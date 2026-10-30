#!/bin/bash
# run-verification.sh — code-sentinel --run-tests 의 명령 검사·실행·전후 비교 (SPEC §10.3)
#
# 사용법:
#   run-verification.sh [--repo <path>] [--timeout <sec>] [--check] -- <command> [args...]
#
#   --repo <path>    명령을 실행할 디렉터리(Git 저장소 안). 기본은 현재 디렉터리
#   --timeout <sec>  타임아웃(초, 1~86400). 기본 600
#   --check          정적 검사 결과만 출력하고 실행하지 않음
#
# 출력(stdout): 첫 줄 `CODE_SENTINEL_VERIFY 1`, 이어서 `키<TAB>값` 줄과 [섹션] 목록.
#   decision allow|deny, reasons, hooks_suppressed yes|no|unknown, exit_code, duration,
#   log_file, ... [REASONS] [CHECKED] [TRACKED_CHANGES] [NEW_UNTRACKED] [IGNORED_DIRS]
#   [REFS_INDEX] [WARNINGS] [NOTES]
#
# 종료 코드:
#   0  실행했고 명령 성공(--check 면 허용)
#   2  사용법 오류
#   3  Git 저장소가 아님(디렉터리 없음 포함)
#   10 실행했고 명령 실패
#   11 타임아웃(자식 프로세스까지 종료)
#   12 정적 검사에서 거부
#   1  내부 오류(임시 디렉터리 생성 실패, 실행 전 상태 기록 실패 등)
#
# 정적 검사는 사전 필터일 뿐입니다. 실행 격리는 도구 샌드박스에 의존하며, 이 스크립트는
# 격리 활성 여부를 확인하지 못합니다. 전후 비교는 저장소 안만 봅니다(저장소 밖 부수 효과 감지 불가).
# 사용자 파일을 자동으로 복구하거나 삭제하지 않습니다.

set -euo pipefail

# 자식 명령에는 원래 로캘을 돌려준다.
if [ "${LC_ALL+set}" = set ]; then ORIG_LC_ALL_SET=1; ORIG_LC_ALL=$LC_ALL; else ORIG_LC_ALL_SET=0; ORIG_LC_ALL=""; fi
export LC_ALL=C
IFS=$' \t\n'

PROG=run-verification.sh
DEFAULT_TIMEOUT=600
MAX_TIMEOUT=86400
KILL_GRACE=3            # TERM 후 KILL 까지 기다리는 최대 초
POLL_INTERVAL=0.2       # 실행 감시 주기(초)
PROBE_TIMEOUT=15        # 패키지 관리자 버전 확인 타임아웃(초)
MAX_INCLUDE_ROUNDS=5    # Makefile include 추적 단계
MARKER_NAME=.code-sentinel-context

ORIG_UMASK=$(umask)

# ---------------------------------------------------------------- 공통 유틸

die_usage() {
	printf '%s: %s\n' "$PROG" "$1" >&2
	printf '다음 행동: run-verification.sh [--repo <path>] [--timeout <sec>] [--check] -- <command> [args...] 형식으로 실행하세요.\n' >&2
	exit 2
}

die_internal() {
	printf '%s: 내부 오류: %s\n' "$PROG" "$1" >&2
	exit 1
}

NL='
'
REASONS=""
CHECKED=""
WARNINGS=""
add_reason() { REASONS="$REASONS$1$NL"; }
add_checked() { CHECKED="$CHECKED$1$NL"; }
add_warning() { WARNINGS="$WARNINGS$1$NL"; }

# C 스타일 따옴표(제어문자·역슬래시·큰따옴표가 있을 때만). 결과는 CQ.
CQ=""
cq() {
	local s=$1 out i n c o
	case "$s" in
	*[[:cntrl:]]* | *\\* | *\"*) ;;
	*) CQ=$s; return 0 ;;
	esac
	out='"'
	n=${#s}
	i=0
	while [ "$i" -lt "$n" ]; do
		c=${s:$i:1}
		case "$c" in
		\\) out="$out\\\\" ;;
		\") out="$out\\\"" ;;
		$'\t') out="$out\\t" ;;
		$'\n') out="$out\\n" ;;
		$'\r') out="$out\\r" ;;
		$'\a') out="$out\\a" ;;
		$'\b') out="$out\\b" ;;
		$'\v') out="$out\\v" ;;
		$'\f') out="$out\\f" ;;
		[[:cntrl:]])
			o=$(printf '%03o' "'$c")
			out="$out\\$o"
			;;
		*) out="$out$c" ;;
		esac
		i=$((i + 1))
	done
	CQ="$out\""
}

# 명령 표시용: 안전한 문자만 있으면 그대로, 아니면 C 스타일 따옴표
display_cmd() {
	local a out=""
	for a in "$@"; do
		case "$a" in
		'' | *[!A-Za-z0-9_./:=@%+,-]*)
			cq "$a"
			case "$CQ" in \"*) ;; *) CQ="\"$CQ\"" ;; esac
			out="$out${out:+ }$CQ"
			;;
		*) out="$out${out:+ }$a" ;;
		esac
	done
	printf '%s' "$out"
}

# 표시용 정리: 제어문자를 ? 로
san() { printf '%s' "$1" | tr '[:cntrl:]' '?'; }

# 해시: 내용 비교용(보안 목적 아님)
if [ -x /sbin/md5 ]; then
	hash_stdin() { /sbin/md5 -q; }
elif command -v shasum >/dev/null 2>&1; then
	hash_stdin() { shasum -a 256 | cut -c1-64; }
else
	hash_stdin() { cksum | tr ' \t' '__'; }
fi

# ---------------------------------------------------------------- git 고정 (SPEC §5.3)

FILTER_ARGS=()
FILTER_ENV=()
FILTER_NAMES="$NL"

G() {
	env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_NAMESPACE \
		GIT_PAGER=cat GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 \
		${FILTER_ENV[@]+"${FILTER_ENV[@]}"} \
		git --no-pager -c core.quotePath=false -c color.ui=never -c diff.noprefix=false \
		-c diff.mnemonicPrefix=false -c diff.relative=false -c core.fsmonitor=false \
		-c log.showSignature=false \
		${FILTER_ARGS[@]+"${FILTER_ARGS[@]}"} "$@"
}

# clean/process 필터 드라이버를 찾아 무력화한다(필터는 실행하지 않음).
add_filter_driver() {
	local name=$1 base idx k
	case "$FILTER_NAMES" in *"$NL$name$NL"*) return 0 ;; esac
	FILTER_NAMES="$FILTER_NAMES$name$NL"
	case "$name" in
	*=* | *[[:cntrl:]]*)
		# -c 로 표현할 수 없는 이름은 GIT_CONFIG_COUNT 로 무력화
		base=${GIT_CONFIG_COUNT:-0}
		case "$base" in '' | *[!0-9]*) base=0 ;; esac
		idx=$((base + ${#FILTER_ENV[@]} / 2))
		for k in clean smudge process; do
			FILTER_ENV+=("GIT_CONFIG_KEY_$idx=filter.$name.$k" "GIT_CONFIG_VALUE_$idx=")
			idx=$((idx + 1))
		done
		FILTER_ENV+=("GIT_CONFIG_KEY_$idx=filter.$name.required" "GIT_CONFIG_VALUE_$idx=false")
		idx=$((idx + 1))
		# GIT_CONFIG_COUNT 는 마지막 값이 적용되도록 매번 덧붙인다
		FILTER_ENV+=("GIT_CONFIG_COUNT=$idx")
		;;
	*)
		FILTER_ARGS+=(-c "filter.$name.clean=" -c "filter.$name.smudge=" -c "filter.$name.process=" -c "filter.$name.required=false")
		;;
	esac
}

compute_filters() {
	local out=$CTX/check-attr.z nl v p a
	: >"$out"
	{ G -C "$TOP" ls-files -z --cached --others --exclude-standard 2>/dev/null || true; } |
		{ G -C "$TOP" check-attr -z --stdin filter 2>/dev/null || true; } >"$out"
	[ -s "$out" ] || return 0
	nl=$(tr -cd '\n' <"$out" | wc -c | tr -d ' ')
	if [ "$nl" = 0 ]; then
		while IFS= read -r v; do
			case "$v" in '' | unspecified | unset | set) ;; *) add_filter_driver "$v" ;; esac
		done <<EOF_FILTERS
$(tr '\0' '\n' <"$out" | awk 'NR % 3 == 0' | sort -u)
EOF_FILTERS
	else
		while IFS= read -r -d '' p && IFS= read -r -d '' a && IFS= read -r -d '' v; do
			case "$v" in '' | unspecified | unset | set) ;; *) add_filter_driver "$v" ;; esac
		done <"$out"
	fi
}

# ---------------------------------------------------------------- 임시 디렉터리 (SPEC §6 계약)

CTX=""
KEEP_CTX=0
CHILD=""

make_ctx() {
	local base=${TMPDIR:-/tmp} d="" token
	base=${base%/}
	[ -n "$base" ] || base=/tmp
	umask 077
	d=$(mktemp -d "$base/code-sentinel.XXXXXX" 2>/dev/null) || d=""
	if [ -z "$d" ]; then
		add_warning "TMPDIR($(san "$base"))에 쓸 수 없어 /tmp 를 사용함"
		d=$(mktemp -d /tmp/code-sentinel.XXXXXX 2>/dev/null) || d=""
	fi
	if [ -z "$d" ]; then
		umask "$ORIG_UMASK"
		die_internal "임시 디렉터리를 만들 수 없습니다."
	fi
	CTX=$(cd -P "$d" && pwd -P)
	token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
	printf 'created_at %s\npid %s\ntoken %s\n' "$(date +%s)" "$$" "$token" >"$CTX/$MARKER_NAME"
	umask "$ORIG_UMASK"
}

# ---------------------------------------------------------------- 프로세스 트리 종료

# root 와 그 자손 pid 를 출력한다(ps 한 번으로 부모-자식 관계를 모아 너비 우선 탐색).
tree_pids() {
	ps -A -o pid= -o ppid= 2>/dev/null | awk -v root="$1" '
		{ kids[$2] = kids[$2] " " $1 }
		END {
			q[1] = root; n = 1; h = 1; seen[root] = 1
			while (h <= n) {
				p = q[h++]; print p
				m = split(kids[p], a, " ")
				for (i = 1; i <= m; i++) if (!(a[i] in seen)) { seen[a[i]] = 1; q[++n] = a[i] }
			}
		}' || printf '%s\n' "$1"
}

kill_tree() {
	local root=$1 pids p i alive
	kill -STOP "$root" 2>/dev/null || true
	# 멈춘 뒤 자손을 두 번 모아 그 사이에 생긴 프로세스도 잡는다.
	pids=$(tree_pids "$root")
	for p in $pids; do kill -STOP "$p" 2>/dev/null || true; done
	pids=$( { printf '%s\n' $pids; tree_pids "$root"; } | sort -u)
	for p in $pids; do kill -STOP "$p" 2>/dev/null || true; done
	for p in $pids; do kill -TERM "$p" 2>/dev/null || true; done
	for p in $pids; do kill -CONT "$p" 2>/dev/null || true; done
	i=0
	while [ "$i" -lt $((KILL_GRACE * 5)) ]; do
		alive=0
		for p in $pids; do
			if kill -0 "$p" 2>/dev/null; then alive=1; break; fi
		done
		[ "$alive" = 1 ] || break
		sleep 0.2
		i=$((i + 1))
	done
	for p in $pids; do kill -KILL "$p" 2>/dev/null || true; done
}

# run_limited <secs> <outfile> <cwd> <cmd...> : RL_RC, RL_TIMED_OUT 설정
RL_RC=0
RL_TIMED_OUT=0
run_limited() {
	local secs=$1 out=$2 cwd=$3 start polls=0
	shift 3
	RL_TIMED_OUT=0
	RL_RC=0
	start=$SECONDS
	(cd "$cwd" && exec "$@") </dev/null >"$out" 2>&1 &
	CHILD=$!
	while kill -0 "$CHILD" 2>/dev/null; do
		# SECONDS 는 정수 초이므로 '-gt' 로 비교해 실제 경과가 secs 를 넘은 뒤에만 종료한다.
		if [ $((SECONDS - start)) -gt "$secs" ]; then
			RL_TIMED_OUT=1
			kill_tree "$CHILD"
			break
		fi
		# 짧은 명령을 위해 처음 몇 번은 빠르게 확인
		if [ "$polls" -lt 10 ]; then sleep 0.05; else sleep "$POLL_INTERVAL"; fi
		polls=$((polls + 1))
	done
	wait "$CHILD" 2>/dev/null || RL_RC=$?
	CHILD=""
}

on_exit() {
	if [ -n "$CHILD" ]; then kill_tree "$CHILD"; fi
	if [ "$KEEP_CTX" != 1 ] && [ -n "$CTX" ] && [ -d "$CTX" ]; then rm -rf -- "$CTX"; fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ---------------------------------------------------------------- 인자 해석

REPO_ARG=""
TIMEOUT=$DEFAULT_TIMEOUT
CHECK_ONLY=0
SAW_DD=0
while [ $# -gt 0 ]; do
	case "$1" in
	--repo)
		[ $# -ge 2 ] || die_usage "--repo 값이 필요합니다."
		REPO_ARG=$2
		shift 2
		;;
	--repo=*)
		REPO_ARG=${1#--repo=}
		shift
		;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout 값이 필요합니다."
		TIMEOUT=$2
		shift 2
		;;
	--timeout=*)
		TIMEOUT=${1#--timeout=}
		shift
		;;
	--check)
		CHECK_ONLY=1
		shift
		;;
	--)
		SAW_DD=1
		shift
		break
		;;
	-h | --help)
		printf '사용법: run-verification.sh [--repo <path>] [--timeout <sec>] [--check] -- <command> [args...]\n'
		exit 0
		;;
	*)
		die_usage "알 수 없는 옵션: $(san "$1")"
		;;
	esac
done
[ "$SAW_DD" = 1 ] || die_usage "'--' 뒤에 실행할 명령을 지정하세요."
[ $# -ge 1 ] || die_usage "'--' 뒤에 실행할 명령이 없습니다."
[ -n "$1" ] || die_usage "명령이 비어 있습니다."
case "$TIMEOUT" in
'' | *[!0-9]*) die_usage "--timeout 값은 1~$MAX_TIMEOUT 사이의 정수(초)여야 합니다: $(san "$TIMEOUT")" ;;
esac
TIMEOUT=$((10#$TIMEOUT))
if [ "$TIMEOUT" -lt 1 ] || [ "$TIMEOUT" -gt "$MAX_TIMEOUT" ]; then
	die_usage "--timeout 값은 1~$MAX_TIMEOUT 사이의 정수(초)여야 합니다: $TIMEOUT"
fi

CMD=("$@")

# ---------------------------------------------------------------- 저장소 확인

[ -n "$REPO_ARG" ] || REPO_ARG=.
not_repo() {
	printf '%s: Git 저장소가 아닙니다: %s\n' "$PROG" "$(san "$REPO_ARG")" >&2
	printf '다음 행동: 저장소 안의 디렉터리를 --repo 로 지정하세요.\n' >&2
	exit 3
}
[ -d "$REPO_ARG" ] || not_repo
WORKDIR=$(cd -P "$REPO_ARG" 2>/dev/null && pwd -P) || not_repo
[ -n "$WORKDIR" ] || not_repo
inside=$(G -C "$WORKDIR" rev-parse --is-inside-work-tree 2>/dev/null) || not_repo
[ "$inside" = true ] || not_repo
TOP=$(G -C "$WORKDIR" rev-parse --show-toplevel 2>/dev/null) || not_repo
[ -n "$TOP" ] || not_repo
TOP=$(cd -P "$TOP" 2>/dev/null && pwd -P) || not_repo

make_ctx

# ---------------------------------------------------------------- 정적 검사: 패턴

Q="'"
OB="(^|[[:space:]\"$Q=])"
OE="([[:space:]\"$Q]|$)"
WB='(^|[^A-Za-z0-9_])'
WE='([^A-Za-z0-9_]|$)'

RE_WATCH="$OB--watch(All)?(=[^[:space:]]*)?$OE"
RE_FIX="$OB(--fix|--write|--update|-update|--update-snapshots?|--updateSnapshots?|--snapshot-update|--force-regen|--regen-all|--apply|--apply-unsafe|--autocorrect|--autocorrect-all|--auto-correct|--auto-correct-all|--fix-dangerously|--fix-suggestions|--add-noqa)(=[^[:space:]]*)?$OE"
RE_MIGRATE="$WB(migrate|migration:run|migrations:run|db[[:space:]:]+push|db:seed|db:reset|db:drop|db:create|db:setup|db:schema:load|schema:sync|schema:drop|alembic[[:space:]]+upgrade|alembic[[:space:]]+downgrade|liquibase[[:space:]]+update|drizzle-kit[[:space:]]+push)$WE"
RE_CODEGEN="$WB(generate|codegen)$WE"
RE_DOCKER="$WB(docker|docker-compose|podman|podman-compose)$WE"
RE_CURL1="$WB(curl|wget)$WE[^|]*[|][[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?([^[:space:]|]*/)?(bash|sh|zsh|dash|ksh|fish|python|python3|node|perl|ruby)$WE"
RE_CURL2='(^|[^A-Za-z0-9_])(bash|sh|zsh|dash|ksh|eval|source)([^A-Za-z0-9_]|$)[^;&|]*([$][(]|<[(]|`)[[:space:]]*(curl|wget)([^A-Za-z0-9_]|$)'
RE_RM='(^|[^A-Za-z0-9_./-])rm[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-[A-Za-z]*[rR]|--recursive)'
RE_RIMRAF="$WB(rimraf|del-cli)$WE"
RE_FIND_DELETE="${WB}find$WE.*[[:space:]]-delete$WE"
RE_DB_URL='(postgres|postgresql|mysql|mariadb|mongodb|mongodb[+]srv|redis|rediss|amqp|amqps|kafka|nats|mssql|sqlserver|cockroachdb)://'
RE_DB_ENV="$WB(DATABASE_URL|DB_URL|DB_HOST|DB_PASSWORD|PGHOST|PGPASSWORD|PGDATABASE|MYSQL_HOST|MYSQL_PWD|MYSQL_PASSWORD|REDIS_URL|REDIS_HOST|MONGO_URL|MONGO_URI|MONGODB_URL|MONGODB_URI|AMQP_URL|RABBITMQ_URL|KAFKA_BROKERS?|KAFKA_BOOTSTRAP_SERVERS)$WE"
RE_ENVFILE='(^|[^A-Za-z0-9_.])[.]env([^A-Za-z0-9_]|$)'
RE_DOTENV="$WB(dotenv|dotenvx|dotenv-cli|env-cmd)$WE|--env-file"
RE_TESTCONTAINERS='[Tt]estcontainers'

# 단어 목록 포함 여부
in_list() {
	local w=$1
	shift
	local x
	for x in "$@"; do [ "$w" = "$x" ] && return 0; done
	return 1
}

# node_modules/.bin/<name> 을 WORKDIR 부터 TOP 까지 위로 찾는다. 결과는 LOCAL_BIN
LOCAL_BIN=""
find_local_bin() {
	local name=$1 d=$WORKDIR
	LOCAL_BIN=""
	case "$name" in '' | */* | .*) return 1 ;; esac
	while :; do
		if [ -x "$d/node_modules/.bin/$name" ] && [ ! -d "$d/node_modules/.bin/$name" ]; then
			LOCAL_BIN="$d/node_modules/.bin/$name"
			return 0
		fi
		[ "$d" = "$TOP" ] && break
		case "$d" in "$TOP"/*) d=${d%/*} ;; *) break ;; esac
		[ -n "$d" ] || break
	done
	return 1
}

# 셸 텍스트를 명령 단위(세그먼트)로 나눠 명령별 규칙을 검사한다.
scan_segments() {
	local label=$1 text=$2 seg w cmd sub rest bin has_run i
	local -a words
	while IFS= read -r seg; do
		# shellcheck disable=SC2206
		set -f
		words=($seg)
		set +f
		[ ${#words[@]} -gt 0 ] || continue
		i=0
		# 앞쪽 환경 할당·래퍼 건너뛰기
		while [ "$i" -lt ${#words[@]} ]; do
			w=${words[$i]}
			w=${w#[\"$Q]}
			w=${w%[\"$Q]}
			case "$w" in
			[A-Za-z_]*=*) i=$((i + 1)); continue ;;
			env | cross-env | cross-env-shell | time | nice | exec | command | then | do | else | if | elif | '!' | '{' | '}' | '$' | nohup) i=$((i + 1)); continue ;;
			-*)
				# env 등의 플래그
				if [ "$i" -gt 0 ]; then i=$((i + 1)); continue; fi
				;;
			esac
			break
		done
		[ "$i" -lt ${#words[@]} ] || continue
		cmd=${words[$i]}
		cmd=${cmd#[\"$Q]}
		cmd=${cmd%[\"$Q]}
		cmd=${cmd##*/}
		sub=""
		if [ $((i + 1)) -lt ${#words[@]} ]; then
			sub=${words[$((i + 1))]}
			sub=${sub#[\"$Q]}
			sub=${sub%[\"$Q]}
		fi
		rest=" ${words[*]:$((i + 1))} "
		case "$cmd" in
		npm | pnpm | yarn | bun | cnpm)
			if [ -z "$sub" ] && [ "$cmd" = yarn ]; then
				add_reason "설치: $label (yarn 인자 없음 = install)"
			elif in_list "$sub" install i in ins inst insta instal isnt isnta isntal isntall add ci it install-test install-ci-test cit clean-install update up upgrade udpate link ln rebuild rb dedupe ddp prune unlink remove rm uninstall un r; then
				add_reason "설치: $label ($cmd $sub)"
			elif [ "$cmd" = npm ] && in_list "$sub" exec x; then
				add_reason "다운로드 가능 실행: $label (npm $sub)"
			elif [ "$cmd" != npm ] && in_list "$sub" dlx create; then
				add_reason "다운로드 가능 실행: $label ($cmd $sub)"
			elif [ "$cmd" = bun ] && [ "$sub" = x ]; then
				add_reason "다운로드 가능 실행: $label (bun x)"
			fi
			;;
		npx)
			bin=""
			local j=$((i + 1)) pflag=0 t
			while [ "$j" -lt ${#words[@]} ]; do
				t=${words[$j]}
				t=${t#[\"$Q]}
				t=${t%[\"$Q]}
				case "$t" in
				-p | --package | --package=* | -c | --call | --call=*) pflag=1 ;;
				-*) ;;
				*) bin=$t; break ;;
				esac
				j=$((j + 1))
			done
			if [ "$pflag" = 1 ]; then
				add_reason "다운로드 가능 실행: $label (npx --package/-c)"
			elif [ -z "$bin" ] || ! find_local_bin "${bin%%@*}"; then
				add_reason "다운로드 가능 실행: $label (npx $(san "$bin"): 로컬에 설치되지 않음)"
			fi
			;;
		pnpx | bunx)
			add_reason "다운로드 가능 실행: $label ($cmd)"
			;;
		pip | pip3)
			in_list "$sub" install download wheel && add_reason "설치: $label ($cmd $sub)"
			;;
		python | python3)
			case "$rest" in *" -m pip "*install* | *" -m ensurepip "*) add_reason "설치: $label ($cmd -m pip)" ;; esac
			;;
		poetry | pipenv | pdm | hatch | rye)
			in_list "$sub" install add update lock sync && add_reason "설치: $label ($cmd $sub)"
			;;
		uv)
			in_list "$sub" sync add lock run tool pip && add_reason "설치: $label (uv $sub)"
			;;
		bundle | bundler)
			in_list "$sub" install update add && add_reason "설치: $label ($cmd $sub)"
			;;
		gem | brew | apt | apt-get | yum | dnf | apk | port)
			in_list "$sub" install update upgrade add && add_reason "설치: $label ($cmd $sub)"
			;;
		go)
			if in_list "$sub" get install generate; then
				add_reason "설치·생성: $label (go $sub)"
			elif [ "$sub" = mod ]; then
				case "$rest" in *" download "* | *" tidy "* | *" vendor "*) add_reason "설치: $label (go mod)" ;; esac
			fi
			;;
		cargo)
			in_list "$sub" install add update fetch fix && add_reason "설치·수정: $label (cargo $sub)"
			;;
		composer)
			in_list "$sub" install require update && add_reason "설치: $label (composer $sub)"
			;;
		corepack)
			in_list "$sub" enable prepare install use up && add_reason "설치: $label (corepack $sub)"
			;;
		vitest)
			case "$sub" in
			run) ;;
			watch | dev) add_reason "watch 모드: $label (vitest $sub)" ;;
			*)
				case "$rest" in *" --run "* | *" --run="*) ;; *) add_reason "watch 모드: $label (run 없는 vitest)" ;; esac
				;;
			esac
			;;
		nodemon | chokidar | onchange | watchexec | entr | ptw | pytest-watch)
			add_reason "watch 모드: $label ($cmd)"
			;;
		tsc)
			case "$rest" in *" -w "* | *" -b "* | *" --build "* | *" --init "*) add_reason "watch·빌드 모드: $label (tsc)" ;; esac
			;;
		ng)
			if [ "$sub" = test ]; then
				case "$rest" in *--watch=false* | *--no-watch*) ;; *) add_reason "watch 모드: $label (ng test)" ;; esac
			fi
			;;
		karma)
			case "$rest" in *--single-run* | *--no-watch*) ;; *) add_reason "watch 모드: $label (karma)" ;; esac
			;;
		prettier)
			case "$rest" in *" -w "*) add_reason "파일 수정: $label (prettier -w)" ;; esac
			;;
		rubocop)
			case "$rest" in *" -a "* | *" -A "* | *" -x "*) add_reason "파일 수정: $label (rubocop 자동 수정)" ;; esac
			;;
		black | isort | gofmt | goimports | autopep8 | yapf | rustfmt | swiftformat | clang-format)
			case "$rest" in
			*--check* | *--diff* | *" -l "* | *" -d "*) ;;
			*) add_reason "파일 수정 가능: $label ($cmd)" ;;
			esac
			;;
		git)
			if in_list "$sub" clean checkout reset stash restore switch commit push pull fetch add rm mv apply am merge rebase cherry-pick revert update-index update-ref gc worktree submodule tag clone init config; then
				add_reason "Git 상태 변경: $label (git $sub)"
			fi
			;;
		sudo | doas | su)
			add_reason "권한 상승: $label ($cmd)"
			;;
		esac
		# -u (스냅샷 갱신) — 의미가 다른 명령은 제외
		case "$rest" in
		*" -u "*)
			if ! in_list "$cmd" python python3 sort uniq set cut git diff ssh env prettier mocha sudo tar zip unzip cp ls ps top xargs date; then
				add_reason "스냅샷 갱신: $label (-u)"
			fi
			;;
		esac
	done <<EOF_SEG
$(printf '%s\n' "$text" | tr ';&|()`{}' '\n\n\n\n\n\n\n\n')
EOF_SEG
}

# 스크립트·레시피 텍스트 전체 검사
scan_text() {
	local label=$1 text=$2 t
	t=$text
	t=${t//--watchAll=false/ }
	t=${t//--watch=false/ }
	t=${t//--watchAll=0/ }
	t=${t//--watch=0/ }
	if [[ $t =~ $RE_WATCH ]]; then add_reason "watch 모드: $label (--watch)"; fi
	if [[ $t =~ $RE_FIX ]]; then add_reason "파일 수정·스냅샷 갱신: $label (${BASH_REMATCH[2]})"; fi
	if [[ $t =~ $RE_MIGRATE ]]; then add_reason "마이그레이션: $label (${BASH_REMATCH[2]})"; fi
	if [[ $t =~ $RE_CODEGEN ]]; then add_reason "코드 생성: $label (${BASH_REMATCH[2]})"; fi
	if [[ $t =~ $RE_DOCKER ]]; then add_reason "docker: $label"; fi
	if [[ $t =~ $RE_CURL1 ]] || [[ $t =~ $RE_CURL2 ]]; then add_reason "원격 스크립트 실행(curl·wget | sh): $label"; fi
	if [[ $t =~ $RE_RM ]] || [[ $t =~ $RE_RIMRAF ]] || [[ $t =~ $RE_FIND_DELETE ]]; then add_reason "재귀 삭제(rm -rf 등): $label"; fi
	if [[ $t =~ $RE_DB_URL ]] || [[ $t =~ $RE_DB_ENV ]]; then add_reason "실제 DB·큐 접속 설정: $label"; fi
	if [[ $t =~ $RE_ENVFILE ]] || [[ $t =~ $RE_DOTENV ]]; then add_reason ".env 자격증명 로드 흔적: $label"; fi
	if [[ $t =~ $RE_TESTCONTAINERS ]]; then add_reason "testcontainers 사용: $label"; fi
	scan_segments "$label" "$t"
}

# 사용자가 준 인자(플래그·경로)는 옵션 수준 규칙만 적용
scan_args() {
	local label=$1 text=$2 t
	t=" $text "
	t=${t//--watchAll=false/ }
	t=${t//--watch=false/ }
	if [[ $t =~ $RE_WATCH ]]; then add_reason "watch 모드: $label (--watch)"; fi
	if [[ $t =~ $RE_FIX ]]; then add_reason "파일 수정·스냅샷 갱신: $label (${BASH_REMATCH[2]})"; fi
	case "$t" in *" -u "*) add_reason "스냅샷 갱신: $label (-u)" ;; esac
	if [[ $t =~ $RE_ENVFILE ]] || [[ $t =~ $RE_DOTENV ]]; then add_reason ".env 자격증명 로드 흔적: $label"; fi
}

# ---------------------------------------------------------------- 정적 검사: 프로젝트 흔적

uniq_dirs() {
	local d out="$NL"
	for d in "$@"; do
		[ -n "$d" ] || continue
		case "$out" in *"$NL$d$NL"*) continue ;; esac
		out="$out$d$NL"
		printf '%s\n' "$d"
	done
}

rel_to_top() {
	case "$1" in
	"$TOP") printf '.' ;;
	"$TOP"/*) printf '%s' "${1#"$TOP"/}" ;;
	*) printf '%s' "$1" ;;
	esac
}

check_project_hints() {
	local d f base rel
	while IFS= read -r d; do
		[ -n "$d" ] || continue
		# testcontainers
		for f in "$d"/package.json "$d"/go.mod "$d"/Cargo.toml "$d"/pyproject.toml "$d"/requirements*.txt \
			"$d"/Pipfile "$d"/setup.py "$d"/setup.cfg "$d"/pom.xml "$d"/build.gradle "$d"/build.gradle.kts \
			"$d"/Gemfile "$d"/composer.json; do
			[ -f "$f" ] || continue
			if grep -i -q 'testcontainers' "$f" 2>/dev/null; then
				add_reason "testcontainers 사용: $(san "$(rel_to_top "$f")")"
			fi
		done
		# .env* 자격증명·접속 설정
		for f in "$d"/.env "$d"/.env.*; do
			[ -f "$f" ] || continue
			base=${f##*/}
			case "$base" in
			*.example | *.sample | *.template | *.tpl | *.dist | *.defaults | *.schema | *.example.* | *.sample.*) continue ;;
			esac
			rel=$(san "$(rel_to_top "$f")")
			add_checked "env-file	$rel"
			if grep -E -i -q '^[[:space:]]*(export[[:space:]]+)?[A-Za-z0-9_]*(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIALS?|AUTH)[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]#]' "$f" 2>/dev/null; then
				add_reason ".env 자격증명 흔적: $rel"
			fi
			if grep -E -q "$RE_DB_URL" "$f" 2>/dev/null || grep -E -q "^[[:space:]]*(export[[:space:]]+)?(DATABASE_URL|DB_URL|DB_HOST|PGHOST|PGPASSWORD|MYSQL_HOST|REDIS_URL|REDIS_HOST|MONGO_URL|MONGO_URI|MONGODB_URI|AMQP_URL|RABBITMQ_URL|KAFKA_BROKERS)[[:space:]]*=" "$f" 2>/dev/null; then
				add_reason "실제 DB·큐 접속 설정(.env): $rel"
			fi
		done
	done <<EOF_DIRS
$(uniq_dirs "$WORKDIR" "${PKGROOT:-}" "$TOP")
EOF_DIRS
}

# ---------------------------------------------------------------- package.json (osascript JSON.parse)

# argv: <package.json> <seed text> <names...>
# 출력: PM\t값 / DEP\t이름 / MISSING\t이름 / SCRIPT\t이유\t이름\t내용 / ERR\t사유
JXA_PKG='ObjC.import("Foundation");
var CTRL = new RegExp("[\\x00-\\x1f\\x7f" + String.fromCharCode(0x2028, 0x2029) + "]", "g");
function san(s){ return String(s).replace(CTRL, " "); }
function nm(s){ return String(s).replace(CTRL, "?"); }
function run(argv){
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (!s || s.isNil()) return "ERR\tread";
  var j;
  try { j = JSON.parse(ObjC.unwrap(s)); } catch (e) { return "ERR\tparse"; }
  if (!j || typeof j !== "object" || Array.isArray(j)) return "ERR\tshape";
  var sc = (j.scripts && typeof j.scripts === "object" && !Array.isArray(j.scripts)) ? j.scripts : {};
  var has = function(n){ return Object.prototype.hasOwnProperty.call(sc, n); };
  var out = [];
  out.push("PM\t" + (typeof j.packageManager === "string" ? nm(j.packageManager) : "-"));
  ["dependencies","devDependencies","optionalDependencies","peerDependencies"].forEach(function(k){
    var d = j[k];
    if (d && typeof d === "object") Object.keys(d).forEach(function(n){ out.push("DEP\t" + nm(n)); });
  });
  var seen = {}, queue = [], order = [];
  function add(n, why){ if (!has(n)) return false; if (Object.prototype.hasOwnProperty.call(seen, n)) return true; seen[n] = why; queue.push(n); return true; }
  function addWithHooks(n, why){ var ok = add(n, why); if (ok) { add("pre" + n, "hook"); add("post" + n, "hook"); } return ok; }
  function globRe(g){ var r = ""; for (var i = 0; i < g.length; i++) { var c = g.charAt(i); if (c === "*") { if (g.charAt(i+1) === "*") { r += ".*"; i++; } else r += "[^:]*"; } else if (/[.+?^${}()|\[\]\\\/]/.test(c)) r += "\\" + c; else r += c; } return new RegExp("^" + r + "$"); }
  function addRef(n){ if (n.indexOf("*") >= 0) { var re = globRe(n); Object.keys(sc).forEach(function(k){ if (re.test(k)) addWithHooks(k, "ref"); }); } else addWithHooks(n, "ref"); }
  var NONSCRIPT = {install:1,i:1,ci:1,add:1,remove:1,exec:1,dlx:1,x:1,why:1,list:1,ls:1,info:1,init:1,create:1,link:1,unlink:1,publish:1,pack:1,config:1,set:1,cache:1,workspace:1,workspaces:1,up:1,upgrade:1,update:1,outdated:1,audit:1,global:1,bin:1,dedupe:1,prune:1,rebuild:1};
  function refs(text){
    var segs = String(text).split(/&&|\|\||[;&|()`{}\n]/);
    segs.forEach(function(seg){
      var t = seg.trim().split(/\s+/).map(function(w){ return w.replace(/^["\x27]+|["\x27]+$/g, ""); }).filter(function(w){ return w.length > 0; });
      for (var i = 0; i < t.length; i++) {
        var w = t[i], b = w.replace(/^.*\//, "");
        var m = /^(npm|yarn|pnpm|bun):(.+)$/.exec(w);
        if (m) { addRef(m[2]); continue; }
        if (b === "npm" || b === "pnpm" || b === "yarn" || b === "bun") {
          var k = i + 1;
          while (k < t.length && t[k].charAt(0) === "-") k++;
          if (k >= t.length) continue;
          var sub = t[k];
          if (sub === "run" || sub === "run-script" || sub === "rum" || sub === "urn") {
            k++; while (k < t.length && t[k].charAt(0) === "-") k++;
            if (k < t.length) addRef(t[k]);
          } else if (sub === "test" || sub === "t" || sub === "tst") { addWithHooks("test", "ref"); }
          else if (sub === "start" || sub === "stop" || sub === "restart") { addWithHooks(sub, "ref"); }
          else if (b !== "npm" && !NONSCRIPT[sub]) { addWithHooks(sub, "ref"); }
        } else if (b === "npm-run-all" || b === "run-s" || b === "run-p" || b === "npm-run-all2") {
          for (var k2 = i + 1; k2 < t.length; k2++) { if (t[k2].charAt(0) !== "-") addRef(t[k2]); }
        }
      }
    });
  }
  argv.slice(2).forEach(function(n){ if (!addWithHooks(n, "target")) out.push("MISSING\t" + nm(n)); });
  ["preinstall","install","postinstall","preprepare","prepare","postprepare"].forEach(function(n){ add(n, "install-hook"); });
  refs(argv[1] || "");
  var guard = 0;
  while (queue.length && guard < 10000) { var n = queue.shift(); order.push(n); refs(sc[n]); guard++; }
  order.forEach(function(n){ out.push("SCRIPT\t" + seen[n] + "\t" + nm(n) + "\t" + san(sc[n])); });
  return out.join("\n");
}'

PKGROOT=""
PKG_PM="-"
PKG_DEPS=""
find_pkgroot() {
	local d=$WORKDIR
	PKGROOT=""
	while :; do
		if [ -f "$d/package.json" ]; then PKGROOT=$d; return 0; fi
		[ "$d" = "$TOP" ] && break
		case "$d" in "$TOP"/*) d=${d%/*} ;; *) break ;; esac
		[ -n "$d" ] || break
	done
	return 1
}

# analyze_pkg <seed> <names...> : 스크립트 내용을 검사 목록에 넣고 패턴 검사
analyze_pkg() {
	local seed=$1 out kind why name content rel
	shift
	rel=$(san "$(rel_to_top "$PKGROOT/package.json")")
	if ! out=$(osascript -l JavaScript -e "$JXA_PKG" "$PKGROOT/package.json" "$seed" "$@" 2>/dev/null); then
		add_reason "package.json 해석 실패: $rel"
		return 0
	fi
	add_checked "package.json	$rel"
	while IFS=$'\t' read -r kind why name content; do
		case "$kind" in
		ERR) add_reason "package.json 해석 실패($why): $rel" ;;
		PM) PKG_PM=$why ;;
		DEP) PKG_DEPS="$PKG_DEPS$why$NL" ;;
		MISSING) add_reason "스크립트 없음: scripts.$why" ;;
		SCRIPT)
			add_checked "script	$name	$why"
			scan_text "scripts.$name" "$content"
			;;
		esac
	done <<EOF_PKG
$out
EOF_PKG
}

# ---------------------------------------------------------------- Makefile 정적 분석 (make -n 사용 안 함)

AWK_MAKE='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function flat(s) { gsub(/[\t\r]/, " ", s); return s }
BEGIN { cur = ""; indef = 0; parse = "" }
{
  line = $0
  sub(/\r$/, "", line)
  if (indef) {
    if (line ~ /^[ \t]*endef([ \t]|$)/) { indef = 0; next }
    vars[defname] = vars[defname] " ; " line
    next
  }
  while (line ~ /\\$/) {
    if ((getline nxt) <= 0) break
    sub(/\r$/, "", nxt)
    sub(/\\$/, "", line)
    line = line " " nxt
  }
  if (substr(line, 1, 1) == "\t") {
    r = substr(line, 2)
    if (cur != "") { n = split(cur, ts, /[ \t]+/); for (i = 1; i <= n; i++) if (ts[i] != "") recipe[ts[i]] = recipe[ts[i]] " ; " r }
    else parse = parse " ; " r
    next
  }
  s = line
  sub(/#.*/, "", s)
  if (s ~ /^[ \t]*$/) next
  t = trim(s)
  if (t ~ /^(-include|sinclude|include)[ \t]/) {
    d = t; sub(/[ \t].*/, "", d)
    rest = t; sub(/^[^ \t]+[ \t]+/, "", rest)
    n = split(rest, ts, /[ \t]+/)
    for (i = 1; i <= n; i++) if (ts[i] != "") { print "INCLUDE\t" d "\t" ts[i]; incl[ts[i]] = 1 }
    cur = ""
    next
  }
  if (t ~ /^define[ \t]/) {
    defname = t; sub(/^define[ \t]+/, "", defname); sub(/[ \t]*(::?=|:::=|\?=|\+=|!=|=)?[ \t]*$/, "", defname)
    indef = 1; cur = ""
    next
  }
  if (t ~ /^(ifeq|ifneq|ifdef|ifndef|else|endif)([ \t(]|$)/) next
  if (t ~ /^(export|unexport|override|private|vpath)([ \t]|$)/) {
    if (t ~ /^vpath/) next
    sub(/^(export|unexport|override|private)[ \t]*/, "", t)
    if (t !~ /=/) next
  }
  eq = index(t, "="); co = index(t, ":")
  if (eq > 0 && (co == 0 || co > eq || substr(t, co, eq - co + 1) ~ /^::?:?=$/)) {
    nm = substr(t, 1, eq - 1); sub(/[:?+!]+$/, "", nm); nm = trim(nm)
    val = substr(t, eq + 1)
    vars[nm] = vars[nm] " ; " val
    if (substr(t, eq - 1, 1) == "!" || val ~ /\$[({](shell|eval|file)[ \t]/) parse = parse " ; " val
    cur = ""
    next
  }
  if (co > 0) {
    tg = trim(substr(t, 1, co - 1)); rest = substr(t, co + 1)
    if (substr(rest, 1, 1) == ":") rest = substr(rest, 2)
    semi = index(rest, ";")
    pre = (semi > 0) ? substr(rest, 1, semi - 1) : rest
    if (pre ~ /=/) {
      nm = pre; sub(/[:?+!]*=.*/, "", nm); nm = trim(nm)
      v = pre; sub(/^[^=]*=/, "", v)
      vars[nm] = vars[nm] " ; " v
      if (v ~ /\$[({](shell|eval|file)[ \t]/) parse = parse " ; " v
      cur = ""
      next
    }
    cur = tg
    n = split(tg, ts, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (ts[i] == "") continue
      defined[ts[i]] = 1
      deps[ts[i]] = deps[ts[i]] " " pre
      if (semi > 0) recipe[ts[i]] = recipe[ts[i]] " ; " substr(rest, semi + 1)
    }
    next
  }
  parse = parse " ; " t
  cur = ""
}
function enqueue(x) { if (x == "" || x == "|" || (x in seenT)) return; seenT[x] = 1; q[++nq] = x }
function refvars(s,   m, nmv) {
  while (match(s, /\$[({][A-Za-z0-9_.-]+/)) {
    nmv = substr(s, RSTART + 2, RLENGTH - 2)
    s = substr(s, RSTART + RLENGTH)
    if (nmv == "call" && match(s, /^[ \t]+[A-Za-z0-9_.-]+/)) { nmv = trim(substr(s, RSTART, RLENGTH)) }
    if ((nmv in vars) && !(nmv in seenV)) { seenV[nmv] = 1; vq[++nv] = nmv }
  }
}
function makerefs(s,   seg, toks, n, i, x) {
  while (match(s, /(\$\(MAKE\)|\$\{MAKE\}|(^|[ \t;&|(])make)[ \t]+[^;&|]*/)) {
    seg = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    sub(/^[ \t;&|(]*(\$\(MAKE\)|\$\{MAKE\}|make)[ \t]+/, "", seg)
    n = split(seg, toks, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      x = toks[i]
      if (x == "") continue
      if (x ~ /^-(C|f|I|-directory|-file|-makefile|-include-dir)/) { print "EXTMAKE\t" flat(seg); continue }
      if (x ~ /^-/ || x ~ /=/ || x ~ /^[0-9]+$/) continue
      needpat = 1
      enqueue(x)
    }
  }
}
function subst(s, depth,   out, nmv, st, ln) {
  if (depth > 5) return s
  out = ""
  while (match(s, /\$[({][A-Za-z0-9_.-]+[)}]/)) {
    st = RSTART; ln = RLENGTH
    nmv = substr(s, st + 2, ln - 3)
    out = out substr(s, 1, st - 1) " "
    if (nmv in vars) out = out subst(vars[nmv], depth + 1)
    out = out " "
    s = substr(s, st + ln)
  }
  return out s
}
END {
  nq = 0; nv = 0; needpat = 0
  nw = split(want, w, /[ \t]+/)
  for (i = 1; i <= nw; i++) { if (w[i] == "") continue; if (!(w[i] in defined)) print "MISSING\t" w[i]; enqueue(w[i]) }
  # make 는 include 한 파일과 Makefile 자체에 규칙이 있으면 다시 만들려고 실행한다
  for (x in incl) if (x in defined) enqueue(x)
  if ("Makefile" in defined) enqueue("Makefile")
  if ("makefile" in defined) enqueue("makefile")
  if ("GNUmakefile" in defined) enqueue("GNUmakefile")
  head = 1
  while (head <= nq) {
    tg = q[head++]
    if (!(tg in defined)) { needpat = 1; continue }
    print "TARGET\t" tg
    if (recipe[tg] != "") { print "RECIPE\t" tg "\t" flat(recipe[tg]); refvars(recipe[tg]); makerefs(recipe[tg]) }
    d = deps[tg]
    refvars(d)
    d = subst(d, 0)
    n = split(d, ds, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (ds[i] == "" || ds[i] == "|" || ds[i] == ";") continue
      if (ds[i] ~ /[$%*?]/) { needpat = 1; continue }
      enqueue(ds[i])
    }
  }
  if (needpat) {
    for (x in recipe) if (x ~ /%/ || x == ".DEFAULT") { print "RECIPE\t" x "\t" flat(recipe[x]); refvars(recipe[x]) }
  }
  k = 1
  while (k <= nv) { v = vq[k++]; print "VAR\t" v "\t" flat(vars[v]); refvars(vars[v]) }
  if (parse != "") print "PARSE\t-\t" flat(parse)
}'


MAKEFILE=""
analyze_make() {
	local targets=$1 files_nl round out kind a b inc incpath changed all_text="" mf d
	for mf in GNUmakefile makefile Makefile; do
		if [ -f "$WORKDIR/$mf" ]; then MAKEFILE="$WORKDIR/$mf"; break; fi
	done
	if [ -z "$MAKEFILE" ]; then
		add_reason "Makefile 없음: $(san "$(rel_to_top "$WORKDIR")")"
		return 0
	fi
	local -a files
	files=("$MAKEFILE")
	files_nl="$NL$MAKEFILE$NL"
	add_checked "makefile	$(san "$(rel_to_top "$MAKEFILE")")"
	round=0
	while :; do
		round=$((round + 1))
		out=$(awk -v want="$targets" "$AWK_MAKE" "${files[@]}" 2>/dev/null) || {
			add_reason "Makefile 해석 실패: $(san "$(rel_to_top "$MAKEFILE")")"
			return 0
		}
		changed=0
		while IFS=$'\t' read -r kind a b; do
			[ "$kind" = INCLUDE ] || continue
			inc=$b
			case "$inc" in
			*'$'* | *'*'* | *'?'* | *'['*)
				add_reason "Makefile include 를 정적으로 확인할 수 없음: $(san "$inc")"
				continue
				;;
			esac
			case "$inc" in /*) incpath=$inc ;; *) incpath="$WORKDIR/$inc" ;; esac
			if [ -f "$incpath" ]; then
				d=$(cd -P "$(dirname "$incpath")" 2>/dev/null && pwd -P) || d=""
				case "$d" in
				"$TOP" | "$TOP"/*) ;;
				*)
					add_reason "저장소 밖 Makefile include: $(san "$inc")"
					continue
					;;
				esac
				incpath="$d/${incpath##*/}"
				case "$files_nl" in
				*"$NL$incpath$NL"*) ;;
				*)
					files+=("$incpath")
					files_nl="$files_nl$incpath$NL"
					changed=1
					add_checked "makefile	$(san "$(rel_to_top "$incpath")")"
					;;
				esac
			elif [ "$a" = include ]; then
				add_reason "Makefile include 파일 없음(make 가 생성 규칙을 실행할 수 있음): $(san "$inc")"
			fi
		done <<EOF_INC
$out
EOF_INC
		if [ "$changed" = 1 ] && [ "$round" -lt "$MAX_INCLUDE_ROUNDS" ]; then continue; fi
		if [ "$changed" = 1 ]; then add_reason "Makefile include 단계가 너무 깊음(${MAX_INCLUDE_ROUNDS}단계 초과)"; fi
		break
	done
	while IFS=$'\t' read -r kind a b; do
		case "$kind" in
		MISSING) add_reason "Makefile 타깃 없음: $(san "$a")" ;;
		EXTMAKE) add_reason "다른 디렉터리·파일을 쓰는 재귀 make: $(san "$a")" ;;
		TARGET) add_checked "make-target	$(san "$a")" ;;
		RECIPE)
			scan_text "make:$(san "$a")" "$b"
			all_text="$all_text ; $b"
			;;
		VAR)
			scan_text "make-var:$(san "$a")" "$b"
			all_text="$all_text ; $b"
			;;
		PARSE)
			scan_text "make-parse" "$b"
			all_text="$all_text ; $b"
			;;
		esac
	done <<EOF_MK
$out
EOF_MK
	# 레시피가 npm·yarn·pnpm 스크립트를 부르면 package.json 도 검사
	if find_pkgroot; then
		case "$all_text" in
		*npm* | *yarn* | *pnpm* | *bun* | *run-s* | *run-p*) analyze_pkg "$all_text" ;;
		esac
	fi
}

# ---------------------------------------------------------------- 명령 분류

KIND=""
EXEC=()
HOOKS=unknown
EXTRA_ENV_UNSET=()

deny_cmd() { add_reason "허용 목록 밖 명령: $1"; }

npm_major() {
	local f=$CTX/npm-version.txt v
	run_limited "$PROBE_TIMEOUT" "$f" / env npm_config_update_notifier=false CI=1 npm --version
	if [ "$RL_TIMED_OUT" = 1 ] || [ "$RL_RC" != 0 ]; then
		printf ''
		return 0
	fi
	v=$(head -n 1 "$f" | tr -d ' \r')
	case "$v" in
	[0-9]*.*) printf '%s' "${v%%.*}" ;;
	*) printf '' ;;
	esac
}

# 패키지 관리자 스크립트 실행
classify_pm() {
	local pm=$1 script="" i n a rest_args="" after_dd=0
	shift
	n=$#
	local -a av
	av=("$@")
	if [ "$n" -lt 1 ]; then deny_cmd "$pm (하위 명령 없음)"; return; fi
	case "${av[0]}" in
	test | t | tst)
		script=test
		i=1
		;;
	run | run-script | rum | urn)
		if [ "$n" -lt 2 ] || [ -z "${av[1]}" ]; then deny_cmd "$pm run (스크립트 이름 없음)"; return; fi
		case "${av[1]}" in -*) deny_cmd "$pm run ${av[1]} (스크립트 이름 앞 옵션은 지원하지 않음)"; return ;; esac
		script=${av[1]}
		i=2
		;;
	*)
		deny_cmd "$pm $(san "${av[0]}") (허용: $pm test, $pm run <script>)"
		return
		;;
	esac
	while [ "$i" -lt "$n" ]; do
		a=${av[$i]}
		if [ "$after_dd" = 1 ] || [ "$pm" != npm ]; then
			rest_args="$rest_args $a"
		elif [ "$a" = "--" ]; then
			after_dd=1
		else
			case "$a" in
			--silent | -s | -q | --quiet | --if-present | --loglevel=*) ;;
			*) deny_cmd "npm 옵션 $(san "$a") (지원: --silent, --if-present, -- <args>)"; return ;;
			esac
		fi
		i=$((i + 1))
	done
	if [ "$pm" != npm ]; then
		case " $rest_args " in
		*" -r "* | *" --recursive "* | *" --filter"* | *" -F "* | *" --workspace"* | *" -w "* | *" --workspace-root "*)
			add_reason "워크스페이스 전체 실행 옵션은 지원하지 않음: $(san "$rest_args")"
			;;
		esac
	fi
	[ -n "$rest_args" ] && scan_args "명령 인자" "$rest_args"
	if ! find_pkgroot; then
		add_reason "package.json 없음: $(san "$(rel_to_top "$WORKDIR")") 부터 저장소 최상위까지"
		return
	fi
	analyze_pkg "" "$script"
	EXEC=("$pm" "$@")
	case "$pm" in
	npm)
		local major
		major=$(npm_major)
		if [ -n "$major" ] && [ "$major" -ge 7 ] 2>/dev/null; then
			HOOKS=yes
		else
			HOOKS=unknown
			if [ -z "$major" ]; then add_warning "npm 버전을 확인하지 못해 훅 억제 여부를 알 수 없음"; else add_warning "npm $major: ignore-scripts 동작이 npm 7 이상과 다름"; fi
		fi
		;;
	yarn)
		case "$PKG_PM" in
		yarn@1.*) HOOKS=no ;;
		yarn@*) HOOKS=unknown ;;
		*)
			if [ -f "$PKGROOT/.yarnrc.yml" ] || [ -f "$TOP/.yarnrc.yml" ]; then
				HOOKS=unknown
			elif [ -f "$PKGROOT/yarn.lock" ] && head -n 5 "$PKGROOT/yarn.lock" | grep -q 'yarn lockfile v1'; then
				HOOKS=no
			else
				HOOKS=unknown
			fi
			;;
		esac
		if [ "$HOOKS" = no ]; then add_warning "Yarn Classic 의 run 은 pre/post 훅도 실행함(훅 내용은 검사함)"; fi
		;;
	*) HOOKS=unknown ;;
	esac
}

classify_make() {
	local a targets=""
	shift
	if [ $# -lt 1 ]; then deny_cmd "make (타깃 없음: 기본 타깃은 지원하지 않음)"; return; fi
	for a in "$@"; do
		case "$a" in
		'' | -* | *=* | *[!A-Za-z0-9_./+-]*) deny_cmd "make $(san "$a") (타깃 이름만 허용)"; return ;;
		esac
		targets="$targets $a"
	done
	analyze_make "$targets"
	EXEC=(make "$@")
	EXTRA_ENV_UNSET=(-u MAKEFILES)
	HOOKS=unknown
}

classify_go() {
	local sub=${2:-} a prev_val=0 name past_args=0 args_text=""
	if [ "$sub" != test ] && [ "$sub" != vet ]; then deny_cmd "go $(san "$sub") (허용: go test, go vet)"; return; fi
	shift 2
	for a in "$@"; do
		if [ "$past_args" = 1 ]; then args_text="$args_text $a"; continue; fi
		if [ "$prev_val" = 1 ]; then prev_val=0; continue; fi
		case "$a" in
		-args | --args) past_args=1; continue ;;
		-*)
			name=${a#-}
			name=${name#-}
			name=${name%%=*}
			case "$name" in
			exec | toolexec | o | c | i | coverprofile | cpuprofile | memprofile | blockprofile | mutexprofile | trace | outputdir | fuzz | modfile | overlay | pkgdir | C | test.coverprofile | test.outputdir | update | u | golden | test.update)
				add_reason "파일 쓰기·외부 실행 플래그: go $sub -$name"
				;;
			mod)
				case "$a" in *=mod) add_reason "의존성 변경 플래그: go $sub -mod=mod" ;; esac
				;;
			esac
			case "$a" in
			*=*) ;;
			*)
				case "$name" in
				run | bench | benchtime | count | cpu | parallel | timeout | tags | p | skip | shuffle | coverpkg | covermode | list | fuzztime | fuzzminimizetime | vet | ldflags | gcflags | asmflags | mod | buildvcs | compiler | pgo | test.run | test.count | test.timeout) prev_val=1 ;;
				esac
				;;
			esac
			;;
		. | ./* | ../*) ;;
		*) add_reason "로컬 경로가 아닌 패키지 인자: go $sub $(san "$a")" ;;
		esac
	done
	[ -n "$args_text" ] && scan_args "go 테스트 인자" "$args_text"
	EXEC=(go "$sub" "$@")
	HOOKS=unknown
}

classify_cargo() {
	local sub=${2:-} a
	case "$sub" in
	+*) add_reason "툴체인 지정(cargo +toolchain)은 내려받기를 일으킬 수 있음"; return ;;
	test) ;;
	*) deny_cmd "cargo $(san "$sub") (허용: cargo test)"; return ;;
	esac
	shift 2
	for a in "$@"; do
		case "$a" in
		--config | --config=* | -Z* | --manifest-path | --manifest-path=* | --target-dir | --target-dir=*)
			add_reason "지원하지 않는 cargo 옵션: $(san "$a")"
			;;
		esac
	done
	[ $# -gt 0 ] && scan_args "cargo 인자" "$*"
	EXEC=(cargo test "$@")
	HOOKS=unknown
}

classify_pytest() {
	local a
	for a in "$@"; do
		case "$a" in
		--basetemp | --basetemp=*) add_reason "pytest --basetemp 는 지정 디렉터리를 지울 수 있음" ;;
		esac
	done
	if [ $# -gt 0 ]; then scan_args "pytest 인자" "$*"; fi
}

# tsc·node 린터: 로컬 node_modules/.bin 바이너리로만 실행
classify_node_bin() {
	local first=$1 name bin="" i=0 a n
	local -a av rest
	av=("$@")
	n=${#av[@]}
	case "$first" in
	npx)
		i=1
		while [ "$i" -lt "$n" ]; do
			a=${av[$i]}
			case "$a" in
			--no-install | --no | --offline | -q | --quiet) i=$((i + 1)) ;;
			-*) deny_cmd "npx $(san "$a") (지원: npx [--no-install] <로컬 바이너리>)"; return ;;
			*) break ;;
			esac
		done
		if [ "$i" -ge "$n" ]; then deny_cmd "npx (바이너리 없음)"; return; fi
		name=${av[$i]}
		i=$((i + 1))
		;;
	*/*)
		name=${first##*/}
		case "$first" in
		node_modules/.bin/* | ./node_modules/.bin/* | */node_modules/.bin/*) ;;
		*) deny_cmd "$(san "$first") (node_modules/.bin 아래 바이너리만 허용)"; return ;;
		esac
		local dir
		case "$first" in /*) dir=${first%/*} ;; *) dir="$WORKDIR/${first%/*}" ;; esac
		dir=$(cd -P "$dir" 2>/dev/null && pwd -P) || dir=""
		case "$dir" in
		"$TOP"/*) ;;
		*) add_reason "저장소 밖 바이너리: $(san "$first")"; return ;;
		esac
		if [ -x "$dir/$name" ]; then bin="$dir/$name"; fi
		i=1
		;;
	*)
		name=$first
		i=1
		;;
	esac
	if [ -z "$bin" ]; then
		if find_local_bin "$name"; then bin=$LOCAL_BIN; fi
	fi
	if [ -z "$bin" ]; then
		add_reason "로컬에 설치되지 않은 바이너리: $(san "$name") (node_modules/.bin 없음, 내려받지 않음)"
		return
	fi
	rest=()
	while [ "$i" -lt "$n" ]; do rest+=("${av[$i]}"); i=$((i + 1)); done
	local rs=" ${rest[*]:-} "
	case "$name" in
	tsc)
		KIND=tsc
		case "$rs" in *" --noEmit "* | *" --noEmit=true "* | *" --noemit "*) ;; *) add_reason "tsc 는 --noEmit 일 때만 허용" ;; esac
		case "$rs" in
		*" -w "* | *" --watch "* | *" -b "* | *" --build "* | *" --init "* | *" -i "* | *" --incremental "* | *" --generateTrace"* | *" --tsBuildInfoFile"*)
			add_reason "tsc 쓰기·watch 옵션"
			;;
		esac
		;;
	eslint | stylelint | oxlint)
		case "$rs" in *" -o "* | *" --output-file"* | *" --init "*) add_reason "$name 파일 쓰기 옵션" ;; esac
		;;
	prettier)
		case "$rs" in *" -w "* | *" --write "*) add_reason "prettier 쓰기 옵션" ;; esac
		;;
	biome)
		case "${rest[0]:-}" in
		lint | check | ci | format) ;;
		*) add_reason "biome $(san "${rest[0]:-}") (허용: lint, check, ci, format)" ;;
		esac
		;;
	esac
	# -u 는 prettier 에서 --ignore-unknown 이므로 제외
	local args_text="${rest[*]:-}"
	if [ "$name" = prettier ]; then args_text=${args_text//-u/ }; fi
	[ -n "$args_text" ] && scan_args "$name 인자" "$args_text"
	EXEC=("$bin" ${rest[@]+"${rest[@]}"})
	HOOKS=unknown
}

classify_path_linter() {
	local name=$1 sub=${2:-} rs
	rs=" $* "
	case "$name" in
	ruff)
		case "$sub" in
		check) ;;
		format) case "$rs" in *" --check "* | *" --diff "*) ;; *) add_reason "ruff format 은 --check/--diff 일 때만 허용" ;; esac ;;
		*) add_reason "ruff $(san "$sub") (허용: check, format --check)" ;;
		esac
		;;
	golangci-lint)
		[ "$sub" = run ] || add_reason "golangci-lint $(san "$sub") (허용: run)"
		;;
	mypy)
		case "$rs" in *--install-types*) add_reason "mypy --install-types 는 설치를 일으킴" ;; esac
		;;
	rubocop)
		case "$rs" in *" -a "* | *" -A "* | *" -x "* | *--auto-gen-config*) add_reason "rubocop 자동 수정·파일 생성 옵션" ;; esac
		;;
	esac
	shift
	[ $# -gt 0 ] && scan_args "$name 인자" "$*"
	if ! command -v "$name" >/dev/null 2>&1; then
		add_reason "명령을 찾을 수 없음: $name"
	fi
	EXEC=("$name" "$@")
	HOOKS=unknown
}

classify() {
	local c=$1
	case "$c" in
	npm | pnpm | yarn)
		KIND="$c-script"
		classify_pm "$@"
		;;
	make | gmake)
		KIND=make
		classify_make "$@"
		;;
	go)
		KIND=go
		classify_go "$@"
		;;
	cargo)
		KIND=cargo
		classify_cargo "$@"
		;;
	pytest | py.test)
		KIND=pytest
		shift
		classify_pytest "$@"
		EXEC=("$c" "$@")
		;;
	python | python3)
		if [ "${2:-}" = -m ] && [ "${3:-}" = pytest ]; then
			KIND=pytest
			local py=$1
			shift 3
			classify_pytest "$@"
			EXEC=("$py" -m pytest "$@")
		else
			deny_cmd "$c (허용: $c -m pytest)"
		fi
		;;
	npx | tsc | eslint | prettier | stylelint | biome | oxlint | */node_modules/.bin/* | node_modules/.bin/*)
		KIND=node-bin
		classify_node_bin "$@"
		if [ "$KIND" = node-bin ] && [ ${#EXEC[@]} -gt 0 ]; then
			case "${EXEC[0]##*/}" in
			tsc) KIND=tsc ;;
			eslint | prettier | stylelint | biome | oxlint) KIND=lint ;;
			*)
				add_reason "허용 목록 밖 바이너리: $(san "${EXEC[0]##*/}") (허용: tsc, eslint, prettier, stylelint, biome, oxlint)"
				;;
			esac
		fi
		;;
	ruff | flake8 | pylint | mypy | golangci-lint | shellcheck | rubocop)
		KIND=lint
		classify_path_linter "$@"
		;;
	*)
		KIND=other
		deny_cmd "$(san "$c")"
		;;
	esac
}

# ---------------------------------------------------------------- 실행 전후 스냅샷

# porcelain v1 -z → "경로<TAB>XY" (경로는 C 스타일 따옴표)
parse_status() {
	local rec xy p orig
	while IFS= read -r -d '' rec; do
		xy=${rec:0:2}
		p=${rec:3}
		case "$xy" in
		R* | C* | ?R | ?C) IFS= read -r -d '' orig || true ;;
		esac
		cq "$p"
		printf '%s\t%s\n' "$CQ" "$xy"
		printf '%s\0' "$p" >>"$SNAP_PATHS_OUT"
	done
}

parse_ignored() {
	local rec xy p
	while IFS= read -r -d '' rec; do
		xy=${rec:0:2}
		p=${rec:3}
		case "$xy" in
		'!!')
			cq "$p"
			printf '%s\n' "$CQ"
			;;
		R* | C* | ?R | ?C) IFS= read -r -d '' p || true ;;
		esac
	done
}

file_sig() {
	local f=$1 st h
	if [ -L "$f" ]; then
		st=$(stat -f '%Sp' "$f" 2>/dev/null || echo '?')
		cq "$(readlink "$f" 2>/dev/null || true)"
		h="link:$CQ"
	elif [ -f "$f" ]; then
		st=$(stat -f '%Sp' "$f" 2>/dev/null || echo '?')
		h=$(hash_stdin <"$f" 2>/dev/null || echo '?')
	elif [ -d "$f" ]; then
		st=$(stat -f '%Sp' "$f" 2>/dev/null || echo '?')
		h=dir
	elif [ -e "$f" ]; then
		st=$(stat -f '%Sp' "$f" 2>/dev/null || echo '?')
		h=other
	else
		st=missing
		h=-
	fi
	printf '%s\t%s' "$st" "$h"
}

content_records() {
	local pathsfile=$1 p sig
	[ -s "$pathsfile" ] || return 0
	while IFS= read -r -d '' p; do
		sig=$(file_sig "$TOP/$p")
		cq "$p"
		printf '%s\t%s\n' "$CQ" "$sig"
	done <"$pathsfile"
}

hash_file_or() {
	if [ -f "$1" ]; then hash_stdin <"$1"; else printf 'missing'; fi
}

git_path_abs() {
	local p
	p=$(G -C "$TOP" rev-parse --git-path "$1" 2>/dev/null) || return 1
	case "$p" in /*) printf '%s' "$p" ;; *) printf '%s/%s' "$TOP" "$p" ;; esac
}

SNAP_PATHS_OUT=/dev/null
snapshot() {
	local d=$1 pathsfile=$2 ip cp
	mkdir -p "$d"
	compute_filters
	if [ "$pathsfile" = "" ]; then
		SNAP_PATHS_OUT="$d/paths.z"
		: >"$SNAP_PATHS_OUT"
	else
		SNAP_PATHS_OUT=/dev/null
	fi
	G -C "$TOP" status --porcelain=v1 -z -uall >"$d/status.z" 2>"$d/status.err" || return 1
	parse_status <"$d/status.z" >"$d/status.tsv"
	SNAP_PATHS_OUT=/dev/null
	G -C "$TOP" status --porcelain=v1 -z --ignored=traditional --untracked-files=normal >"$d/ignored.z" 2>/dev/null || return 1
	parse_ignored <"$d/ignored.z" | sort >"$d/ignored.txt"
	{
		G -C "$TOP" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || echo -
		G -C "$TOP" symbolic-ref -q HEAD 2>/dev/null || echo -
	} >"$d/head.txt"
	G -C "$TOP" for-each-ref --format='%(refname)%09%(objectname)' 2>/dev/null | sort >"$d/refs.txt" || return 1
	if G -C "$TOP" rev-parse -q --verify refs/stash >/dev/null 2>&1; then
		G -C "$TOP" log -g --no-decorate --format='%H%x09%gs' refs/stash -- 2>/dev/null >"$d/stash.txt" || true
	else
		: >"$d/stash.txt"
	fi
	ip=$(git_path_abs index) || return 1
	hash_file_or "$ip" >"$d/index.txt"
	cp=$(git_path_abs config) || return 1
	hash_file_or "$cp" >"$d/config.txt"
	if [ "$pathsfile" = "" ]; then
		content_records "$d/paths.z" >"$d/content.tsv"
	else
		content_records "$pathsfile" >"$d/content.tsv"
	fi
	return 0
}

AWK_COMPARE='
BEGIN { FS = "\t" }
FILENAME == F1 { bs[$1] = $2; all[$1] = 1; next }
FILENAME == F2 { as[$1] = $2; all[$1] = 1; next }
FILENAME == F3 { bst[$1] = $2; bh[$1] = $3; next }
FILENAME == F4 { ast[$1] = $2; ah[$1] = $3; next }
function xy(s) { if (s == "") return "clean"; gsub(/ /, ".", s); return s }
function diffkind(p,   k) {
  k = ""
  if (ast[p] == "missing") return "deleted"
  if (bst[p] == "missing") return "created"
  if (substr(bst[p], 1, 1) != substr(ast[p], 1, 1)) k = k (k == "" ? "" : ",") "type"
  else if (bst[p] != ast[p]) k = k (k == "" ? "" : ",") "mode"
  if (bh[p] != ah[p]) {
    if (substr(ah[p], 1, 5) == "link:" || substr(bh[p], 1, 5) == "link:") k = k (k == "" ? "" : ",") "link"
    else k = k (k == "" ? "" : ",") "content"
  }
  return k
}
END {
  for (p in all) {
    b = (p in bs) ? bs[p] : ""
    a = (p in as) ? as[p] : ""
    if (b == "") {
      if (a == "??") print "U\tnew\t" p "\t-"
      else print "T\tstatus\t" p "\tclean -> " xy(a)
      continue
    }
    if (b == "??") {
      if ((p in bst) && (bst[p] != ast[p] || bh[p] != ah[p])) {
        k = diffkind(p)
        if (k == "deleted") print "U\tdeleted\t" p "\t-"
        else print "U\tmodified\t" p "\t" k
      } else if (a != "??") print "U\tstatus\t" p "\t?? -> " xy(a)
      continue
    }
    if (a != b) { print "T\tstatus\t" p "\t" xy(b) " -> " xy(a); continue }
    if ((p in bst) && (bst[p] != ast[p] || bh[p] != ah[p])) print "T\t" diffkind(p) "\t" p "\tsame status " xy(b)
  }
}'

compare_snapshots() {
	local b=$1 a=$2 out=$3
	: >"$out.files"
	awk -v F1="$b/status.tsv" -v F2="$a/status.tsv" -v F3="$b/content.tsv" -v F4="$a/content.tsv" \
		"$AWK_COMPARE" "$b/status.tsv" "$a/status.tsv" "$b/content.tsv" "$a/content.tsv" |
		sort -t "$(printf '\t')" -k3 >"$out.files"
	{
		comm -13 "$b/ignored.txt" "$a/ignored.txt" | sed 's/^/created	/'
		comm -23 "$b/ignored.txt" "$a/ignored.txt" | sed 's/^/removed	/'
	} >"$out.ignored"
	{
		local bh ah bsym asym
		bh=$(sed -n 1p "$b/head.txt")
		ah=$(sed -n 1p "$a/head.txt")
		bsym=$(sed -n 2p "$b/head.txt")
		asym=$(sed -n 2p "$a/head.txt")
		[ "$bh" = "$ah" ] || printf 'HEAD\t%s -> %s\n' "$bh" "$ah"
		[ "$bsym" = "$asym" ] || printf 'HEAD_REF\t%s -> %s\n' "$bsym" "$asym"
		awk -F '\t' -v F1="$b/refs.txt" '
			FILENAME == F1 { br[$1] = $2; next }
			{ ar[$1] = $2 }
			END {
				for (r in ar) { if (!(r in br)) print "ref\t" r "\tcreated"; else if (br[r] != ar[r]) print "ref\t" r "\tmoved" }
				for (r in br) if (!(r in ar)) print "ref\t" r "\tdeleted"
			}' "$b/refs.txt" "$a/refs.txt" | sort
		if ! cmp -s "$b/stash.txt" "$a/stash.txt"; then printf 'stash\tchanged\n'; fi
		local bi ai
		bi=$(cat "$b/index.txt")
		ai=$(cat "$a/index.txt")
		if [ "$bi" != "$ai" ]; then
			if [ "$bi" = missing ]; then
				printf 'index\tcreated\n'
			elif [ "$ai" = missing ]; then
				printf 'index\tdeleted\n'
			else
				printf 'index\tchanged\n'
			fi
		fi
		if ! cmp -s "$b/config.txt" "$a/config.txt"; then printf 'config\tchanged\n'; fi
	} >"$out.refs"
}

# ---------------------------------------------------------------- 출력

DECISION=allow
EXIT_CODE=-
DURATION=-
LOG_FILE=-
TIMED_OUT=-
CHANGES=-
N_TRACKED=0
N_UNTRACKED=0
N_IGNORED=0
N_REFS=0
CMP_BASE=""

count_lines() { if [ -s "$1" ]; then wc -l <"$1" | tr -d ' '; else printf '0'; fi; }

emit() {
	local joined
	printf 'CODE_SENTINEL_VERIFY 1\n'
	printf 'decision\t%s\n' "$DECISION"
	joined=$(printf '%s' "$REASONS" | awk 'NF && !seen[$0]++' | awk 'BEGIN { ORS = "" } { if (NR > 1) print "; "; print }')
	printf 'reasons\t%s\n' "${joined:--}"
	printf 'hooks_suppressed\t%s\n' "$HOOKS"
	printf 'exit_code\t%s\n' "$EXIT_CODE"
	printf 'duration\t%s\n' "$DURATION"
	cq "$LOG_FILE"
	printf 'log_file\t%s\n' "$CQ"
	if [ "$CHECK_ONLY" = 1 ]; then printf 'mode\tcheck\n'; else printf 'mode\trun\n'; fi
	printf 'timed_out\t%s\n' "$TIMED_OUT"
	printf 'timeout\t%s\n' "$TIMEOUT"
	cq "$TOP"
	printf 'repo\t%s\n' "$CQ"
	cq "$WORKDIR"
	printf 'workdir\t%s\n' "$CQ"
	printf 'command\t%s\n' "$(display_cmd "${CMD[@]}" | tr '\t\n' '  ')"
	printf 'kind\t%s\n' "${KIND:--}"
	if [ "$KEEP_CTX" = 1 ]; then cq "$CTX"; printf 'context_dir\t%s\n' "$CQ"; else printf 'context_dir\t-\n'; fi
	printf 'changes\t%s\n' "$CHANGES"
	printf 'tracked_changes\t%s\n' "$N_TRACKED"
	printf 'new_untracked\t%s\n' "$N_UNTRACKED"
	printf 'ignored_dirs\t%s\n' "$N_IGNORED"
	printf 'refs_index\t%s\n' "$N_REFS"
	printf 'isolation\tunverified\n'
	printf '[REASONS]\n'
	printf '%s' "$REASONS" | awk 'NF && !seen[$0]++'
	printf '[CHECKED]\n'
	printf '%s' "$CHECKED" | awk 'NF && !seen[$0]++'
	printf '[TRACKED_CHANGES]\n'
	if [ -n "$CMP_BASE" ] && [ -s "$CMP_BASE.files" ]; then
		awk -F '\t' '$1 == "T" { print $2 "\t" $3 "\t" $4 }' "$CMP_BASE.files"
	fi
	printf '[NEW_UNTRACKED]\n'
	if [ -n "$CMP_BASE" ] && [ -s "$CMP_BASE.files" ]; then
		awk -F '\t' '$1 == "U" { print $2 "\t" $3 "\t" $4 }' "$CMP_BASE.files"
	fi
	printf '[IGNORED_DIRS]\n'
	if [ -n "$CMP_BASE" ] && [ -s "$CMP_BASE.ignored" ]; then cat "$CMP_BASE.ignored"; fi
	printf '[REFS_INDEX]\n'
	if [ -n "$CMP_BASE" ] && [ -s "$CMP_BASE.refs" ]; then cat "$CMP_BASE.refs"; fi
	printf '[WARNINGS]\n'
	printf '%s' "$WARNINGS" | awk 'NF && !seen[$0]++'
	printf '[NOTES]\n'
	if [ "$DECISION" = allow ]; then
		printf '정적 사전 필터 통과, 실행 격리는 도구 샌드박스에 의존, 격리 활성 여부는 확인하지 못함\n'
	fi
	printf '전후 비교는 저장소 안만 봄. "전후 변경 없음"은 저장소 밖 부수 효과(로컬 DB, 전역 캐시, 네트워크 요청)가 없었다는 뜻이 아님\n'
	printf 'ignored 항목은 생성·삭제만 비교함. 기존 ignored 디렉터리 안과 개별 ignored 파일의 내용 변경은 감지 범위 밖\n'
	printf '스크립트가 호출하는 별도 파일(셸 스크립트, 설정, 테스트 코드)의 내용은 정적 검사 범위 밖\n'
}

# ---------------------------------------------------------------- 본 흐름

classify "${CMD[@]}"
check_project_hints

if [ -n "$(printf '%s' "$REASONS" | tr -d '\n')" ]; then
	DECISION=deny
	emit
	exit 12
fi

if [ "$CHECK_ONLY" = 1 ]; then
	emit
	exit 0
fi

if [ ${#EXEC[@]} -eq 0 ]; then die_internal "실행할 명령을 정하지 못했습니다."; fi

# 실행 환경 (SPEC §10.3)
CHILD_ENV=(
	CI=1 HUSKY=0
	npm_config_ignore_scripts=true npm_config_offline=true npm_config_update_notifier=false
	GOPROXY=off GOFLAGS=-mod=readonly GOTOOLCHAIN=local
	CARGO_NET_OFFLINE=true PIP_NO_INDEX=1 PYTHONDONTWRITEBYTECODE=1
	COREPACK_ENABLE_NETWORK=0
)
ENV_UNSET=()
if [ "$ORIG_LC_ALL_SET" = 1 ]; then CHILD_ENV+=("LC_ALL=$ORIG_LC_ALL"); else ENV_UNSET+=(-u LC_ALL); fi
ENV_UNSET+=(${EXTRA_ENV_UNSET[@]+"${EXTRA_ENV_UNSET[@]}"})

if ! snapshot "$CTX/before" ""; then
	die_internal "실행 전 Git 상태를 기록하지 못해 실행하지 않았습니다: $(head -n 1 "$CTX/before/status.err" 2>/dev/null | tr -d '\r' || true)"
fi

LOG_FILE="$CTX/output.log"
start_s=$SECONDS
run_limited "$TIMEOUT" "$LOG_FILE" "$WORKDIR" env ${ENV_UNSET[@]+"${ENV_UNSET[@]}"} "${CHILD_ENV[@]}" "${EXEC[@]}"
DURATION=$((SECONDS - start_s))
KEEP_CTX=1
EXIT_CODE=$RL_RC
if [ "$RL_TIMED_OUT" = 1 ]; then TIMED_OUT=yes; else TIMED_OUT=no; fi

if snapshot "$CTX/after" "$CTX/before/paths.z"; then
	CMP_BASE="$CTX/compare"
	compare_snapshots "$CTX/before" "$CTX/after" "$CMP_BASE"
	N_TRACKED=$(awk -F '\t' '$1 == "T"' "$CMP_BASE.files" | wc -l | tr -d ' ')
	N_UNTRACKED=$(awk -F '\t' '$1 == "U"' "$CMP_BASE.files" | wc -l | tr -d ' ')
	N_IGNORED=$(count_lines "$CMP_BASE.ignored")
	N_REFS=$(count_lines "$CMP_BASE.refs")
	if [ $((N_TRACKED + N_UNTRACKED + N_IGNORED + N_REFS)) -gt 0 ]; then CHANGES=detected; else CHANGES=none; fi
else
	CHANGES=unknown
	add_warning "실행 후 Git 상태를 기록하지 못해 전후 비교를 하지 못함"
fi

emit
if [ "$RL_TIMED_OUT" = 1 ]; then exit 11; fi
if [ "$RL_RC" != 0 ]; then exit 10; fi
exit 0
