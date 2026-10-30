#!/bin/bash
# collect-context.sh — code-sentinel 리뷰 대상 수집 (읽기 전용)
#
#   collect-context.sh --scope changes|staged|commit|pr|full
#                      [--base <ref>] [--ref <ref>] [--pr <n>]
#                      [--include <pathspec>]... [--exclude <pathspec>]...
#                      [--repo <path>]
#
# stdout 에 탭 구분 매니페스트(CODE_SENTINEL_CONTEXT 1)를 출력하고,
# diff 와 부가 데이터는 ${TMPDIR:-/tmp}/code-sentinel.XXXXXX 에 쓴다.
# 리뷰가 끝나면 호출자가 cleanup-context.sh <context_dir> 로 정리한다.
#
# 종료 코드: 0 성공, 2 사용법 오류, 3 Git 저장소 아님, 4 기준 결정 불가,
#            5 ref 해석 불가, 6 PR 접근 불가, 1 그 밖의 내부 오류

set -euo pipefail
export LC_ALL=C

readonly MAX_FILE_BYTES=1048576     # 파일당 1 MiB
readonly MAX_TOTAL_BYTES=10485760   # --full 전체 10 MiB
readonly MAX_COMMITS=50
readonly SPLIT_FILES=60
readonly SPLIT_LINES=3000
readonly TRUNC_FILES=300
readonly TRUNC_LINES=20000
readonly MARKER=.code-sentinel-context

# ---------------------------------------------------------------- 공통

die() {
	local code=$1
	shift
	printf 'code-sentinel: %s\n' "$*" >&2
	exit "$code"
}

usage_err() { die 2 "사용법 오류: $*"; }

usage() {
	cat <<'USAGE'
사용법: collect-context.sh --scope changes|staged|commit|pr|full
                          [--base <ref>] [--ref <ref>] [--pr <n>]
                          [--include <pathspec>]... [--exclude <pathspec>]...
                          [--repo <path>]
USAGE
}

WARNINGS=()
warn() { WARNINGS+=("$*"); }

# 경로를 매니페스트 표기로: 제어문자·역슬래시·큰따옴표가 있으면 C 스타일로 인용
cquote() {
	local p=$1
	case "$p" in
	*[[:cntrl:]]* | *\\* | *\"*) ;;
	*)
		printf '%s' "$p"
		return
		;;
	esac
	local out='"' i c n
	for ((i = 0; i < ${#p}; i++)); do
		c=${p:i:1}
		case "$c" in
		$'\n') out="$out\\n" ;;
		$'\t') out="$out\\t" ;;
		\\) out="$out\\\\" ;;
		\") out="$out\\\"" ;;
		[[:cntrl:]])
			n=$(printf '%d' "'$c")
			out="$out$(printf '\\%03o' "$n")"
			;;
		*) out="$out$c" ;;
		esac
	done
	printf '%s"' "$out"
}

# ---------------------------------------------------------------- 인자

scope=""
base=""
base_set=0
ref=""
ref_set=0
prnum=""
pr_set=0
repo=""
includes=()
excludes=()

need_val() {
	[ $# -ge 2 ] || usage_err "$1 에 값이 필요합니다"
	case "$2" in
	"" | --*) usage_err "$1 에 값이 필요합니다" ;;
	esac
}

while [ $# -gt 0 ]; do
	case "$1" in
	--scope)
		need_val "$@"
		[ -z "$scope" ] || usage_err "범위 옵션은 하나만 쓸 수 있습니다 (입력: $scope, $2)"
		scope=$2
		shift 2
		;;
	--base)
		need_val "$@"
		base=$2
		base_set=1
		shift 2
		;;
	--ref)
		need_val "$@"
		ref=$2
		ref_set=1
		shift 2
		;;
	--pr)
		need_val "$@"
		prnum=$2
		pr_set=1
		shift 2
		;;
	--include)
		need_val "$@"
		includes+=("$2")
		shift 2
		;;
	--exclude)
		need_val "$@"
		excludes+=("$2")
		shift 2
		;;
	--repo)
		need_val "$@"
		repo=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) usage_err "알 수 없는 옵션: $1" ;;
	esac
done

case "$scope" in
changes | staged | commit | pr | full) ;;
"") usage_err "--scope 가 필요합니다" ;;
*) usage_err "알 수 없는 범위: $scope" ;;
esac
if [ "$base_set" -eq 1 ] && [ "$scope" != changes ]; then
	usage_err "--base 는 --scope changes 에서만 쓸 수 있습니다"
fi
if [ "$ref_set" -eq 1 ] && [ "$scope" != commit ]; then
	usage_err "--ref 는 --scope commit 에서만 쓸 수 있습니다"
fi
if [ "$pr_set" -eq 1 ] && [ "$scope" != pr ]; then
	usage_err "--pr 는 --scope pr 에서만 쓸 수 있습니다"
fi
if [ "$scope" = pr ]; then
	[ "$pr_set" -eq 1 ] || usage_err "--scope pr 에는 --pr <number> 가 필요합니다"
	case "$prnum" in
	"" | *[!0-9]* | 0*) usage_err "--pr 값은 양의 정수여야 합니다: $prnum" ;;
	esac
fi
if [ "$scope" = commit ]; then
	[ "$ref_set" -eq 1 ] || ref=HEAD
	case "$ref" in
	*..*) usage_err "커밋 범위(A..B)는 지원하지 않습니다: $ref" ;;
	esac
fi

# ---------------------------------------------------------------- 저장소

if [ -n "$repo" ]; then
	cd "$repo" 2>/dev/null || die 3 "Git 저장소가 아닙니다. 저장소 안에서 실행하세요. ($repo)"
fi
top=$(git rev-parse --show-toplevel 2>/dev/null) || die 3 "Git 저장소가 아닙니다. 저장소 안에서 실행하세요."
[ -n "$top" ] || die 3 "Git 저장소가 아닙니다. 저장소 안에서 실행하세요."
cd "$top"
top=$(pwd -P)

export GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_PAGER=cat GIT_TERMINAL_PROMPT=0
# gh: 프롬프트·업데이트 확인·텔레메트리 요청을 끈다(--pr 에서 읽기 요청만 남기기 위해)
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GH_TELEMETRY=0 DO_NOT_TRACK=1 GH_PAGER=cat
unset GIT_EXTERNAL_DIFF GIT_DIFF_OPTS 2>/dev/null || true

# 설정된 모든 필터 드라이버를 무력화한다(clean/smudge/process 실행 방지).
FILTER_NAMES=()
filter_seen="|"
while IFS= read -r -d '' entry; do
	key=${entry%%$'\n'*}
	case "$key" in
	filter.*.clean | filter.*.smudge | filter.*.process | filter.*.required)
		name=${key#filter.}
		name=${name%.*}
		case "$filter_seen" in
		*"|$name|"*) ;;
		*)
			FILTER_NAMES+=("$name")
			filter_seen="$filter_seen$name|"
			;;
		esac
		;;
	esac
done < <(git config -z --get-regexp '^filter\.' 2>/dev/null || true)

FN=()
for name in ${FILTER_NAMES[@]+"${FILTER_NAMES[@]}"}; do
	FN+=(-c "filter.$name.clean=" -c "filter.$name.smudge=" -c "filter.$name.process=" -c "filter.$name.required=false")
done

G() {
	git --no-pager \
		-c core.quotePath=false -c color.ui=never \
		-c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.relative=false \
		-c core.fsmonitor=false -c log.showSignature=false \
		-c diff.submodule=short -c status.submoduleSummary=false \
		${FN[@]+"${FN[@]}"} "$@"
}

EMPTY_TREE=$(git hash-object -t tree /dev/null)

git_version_ge_246() {
	local v major rest minor
	v=$(git version | awk '{ print $3 }')
	major=${v%%.*}
	rest=${v#*.}
	minor=${rest%%.*}
	case "$major$minor" in *[!0-9]*) return 1 ;; esac
	[ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 46 ]; }
}

is_partial_clone() {
	[ -n "$(git config --get extensions.partialClone 2>/dev/null || true)" ] && return 0
	git config --get-regexp '^remote\..*\.promisor$' 2>/dev/null | awk '$2 == "true" { f = 1 } END { exit !f }'
}

PARTIAL=0
LAZY_SAFE=1
if is_partial_clone; then
	PARTIAL=1
	git_version_ge_246 || LAZY_SAFE=0
fi
if [ "$PARTIAL" -eq 1 ] && [ "$LAZY_SAFE" -eq 0 ] && [ "$scope" != pr ]; then
	die 4 "git 2.46 미만에서는 partial clone 저장소의 객체 지연 다운로드를 막을 수 없어 수집하지 않습니다. git을 업데이트하거나 --pr 범위를 쓰세요."
fi

# ---------------------------------------------------------------- 임시 디렉터리

CTX=""
KEEP=0
on_exit() {
	local rc=$?
	if [ "$KEEP" -ne 1 ] && [ -n "$CTX" ] && [ -d "$CTX" ]; then
		rm -rf "$CTX"
	fi
	exit "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

umask 077
tmp_parent=${TMPDIR:-/tmp}
if ! d=$(mktemp -d "${tmp_parent%/}/code-sentinel.XXXXXX" 2>/dev/null); then
	d=$(mktemp -d /tmp/code-sentinel.XXXXXX 2>/dev/null) || die 1 "임시 디렉터리를 만들 수 없습니다."
	warn "TMPDIR($tmp_parent)에 쓸 수 없어 /tmp 를 사용했습니다."
fi
CTX=$(cd -P "$d" && pwd -P)
token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
printf 'created_at %s\npid %s\ntoken %s\n' "$(date +%s)" "$$" "$token" >"$CTX/$MARKER"

DIFF_FILE="$CTX/diff.patch"
COMMITS_FILE="$CTX/commits.txt"
: >"$DIFF_FILE"
: >"$COMMITS_FILE"

# ---------------------------------------------------------------- 경로 규칙

# 사용자 pathspec
PS=()
if [ ${#includes[@]} -gt 0 ]; then
	PS=("${includes[@]}")
else
	PS=(.)
fi
for p in ${excludes[@]+"${excludes[@]}"}; do
	PS+=(":(exclude)$p")
done

# shell 수준 pathspec 근사(gh-diff 모드용): 정확히 같거나, 디렉터리 접두어이거나, glob 일치
ps_match() {
	local path=$1 pat=${2%/}
	[ "$path" = "$pat" ] && return 0
	case "$path" in
	"$pat"/*) return 0 ;;
	esac
	# shellcheck disable=SC2254
	case "$path" in
	$pat) return 0 ;;
	esac
	return 1
}

user_selected() {
	local path=$1 p
	if [ ${#includes[@]} -gt 0 ]; then
		local hit=0
		for p in "${includes[@]}"; do
			if ps_match "$path" "$p"; then
				hit=1
				break
			fi
		done
		[ "$hit" -eq 1 ] || return 1
	fi
	for p in ${excludes[@]+"${excludes[@]}"}; do
		ps_match "$path" "$p" && return 1
	done
	return 0
}

# 경로만으로 판단하는 기본 제외 사유. 해당 없으면 빈 문자열.
path_rule_reason() {
	local path=$1 base
	base=${path##*/}
	case "/$path/" in
	*/node_modules/* | */vendor/* | */dist/* | */build/* | */.next/* | */.nuxt/* | */out/* | */coverage/* | */target/*)
		printf 'build-output'
		return
		;;
	*/__snapshots__/*)
		printf 'snapshot'
		return
		;;
	esac
	case "$base" in
	package-lock.json | npm-shrinkwrap.json | pnpm-lock.yaml | yarn.lock | bun.lock | bun.lockb | Cargo.lock | poetry.lock | uv.lock | Pipfile.lock | composer.lock | Gemfile.lock | go.sum)
		printf 'lockfile'
		;;
	*.snap) printf 'snapshot' ;;
	*.min.* | *.map) printf 'minified' ;;
	*.generated.* | *.pb.go | *_pb2.py) printf 'generated' ;;
	esac
}

# --include 가 기본 제외를 덮어쓰는지: include 패턴이 그 경로와 같거나, 패턴 자체가 기본 제외 대상일 때
include_overrides() {
	local path=$1 p
	[ ${#includes[@]} -gt 0 ] || return 1
	for p in "${includes[@]}"; do
		if [ "$path" = "${p%/}" ]; then return 0; fi
		if [ -n "$(path_rule_reason "${p%/}/x")" ] || [ -n "$(path_rule_reason "${p%/}")" ]; then
			ps_match "$path" "$p" && return 0
		fi
	done
	return 1
}

has_generated_header() { # stdin 앞부분에 생성 표시가 있는지
	head -c 2048 | grep -Eq '@generated|DO NOT EDIT' 2>/dev/null
}

is_binary_file() { # 작업 트리 파일 앞 8000바이트에 NUL 이 있으면 binary
	local a b
	a=$(head -c 8000 "$1" | wc -c)
	b=$(head -c 8000 "$1" | tr -d '\000' | wc -c)
	[ "$((a))" -ne "$((b))" ]
}

# ---------------------------------------------------------------- 파일 레코드
# F_ST 상태, F_PATH 경로, F_OLD 이전 경로, F_OM/F_NM 모드, F_OSHA/F_NSHA blob,
# F_ADD/F_DEL 줄 수(binary 는 -), F_FLAGS 표시, F_SKIP 생략 사유, F_RULE 규칙 제외 사유

F_ST=()
F_PATH=()
F_OLD=()
F_OM=()
F_NM=()
F_OSHA=()
F_NSHA=()
F_ADD=()
F_DEL=()
F_FLAGS=()
F_SKIP=()
F_RULE=()

add_record() { # st path old om nm osha nsha add del flags
	F_ST+=("$1")
	F_PATH+=("$2")
	F_OLD+=("$3")
	F_OM+=("$4")
	F_NM+=("$5")
	F_OSHA+=("$6")
	F_NSHA+=("$7")
	F_ADD+=("$8")
	F_DEL+=("$9")
	F_FLAGS+=("${10}")
	F_SKIP+=("")
	F_RULE+=("")
}

# git diff --raw --numstat -z 출력 파일을 레코드로 읽는다.
load_raw_numstat() {
	local file=$1 tok om nm os ns st old new start i add del rest p
	start=${#F_PATH[@]}
	# raw 부분
	{
		while IFS= read -r -d '' tok; do
			case "$tok" in
			:*)
				# shellcheck disable=SC2086
				set -- $tok
				om=${1#:}
				nm=$2
				os=$3
				ns=$4
				st=$5
				case "$st" in
				R* | C*)
					IFS= read -r -d '' old
					IFS= read -r -d '' new
					;;
				*)
					IFS= read -r -d '' new
					old=""
					;;
				esac
				add_record "${st:0:1}" "$new" "$old" "$om" "$nm" "$os" "$ns" 0 0 ""
				;;
			*)
				# numstat 부분 시작: 같은 순서로 줄 수를 채운다
				i=$start
				while :; do
					add=${tok%%$'\t'*}
					rest=${tok#*$'\t'}
					del=${rest%%$'\t'*}
					p=${rest#*$'\t'}
					if [ -z "$p" ]; then
						IFS= read -r -d '' old || true
						IFS= read -r -d '' p || true
					fi
					if [ "$i" -lt "${#F_PATH[@]}" ]; then
						if [ "${F_PATH[$i]}" != "$p" ]; then
							die 1 "diff 출력 순서를 맞출 수 없습니다: $p"
						fi
						F_ADD[$i]=$add
						F_DEL[$i]=$del
					fi
					i=$((i + 1))
					IFS= read -r -d '' tok || break
				done
				;;
			esac
		done
	} <"$file"
}

# untracked 파일 레코드 추가
load_untracked() {
	local listf="$CTX/untracked.lst" p ns add del rest flags mode
	G ls-files --others --exclude-standard -z -- "${PS[@]}" >"$listf"
	while IFS= read -r -d '' p; do
		case "$p" in */) continue ;; esac
		flags=untracked
		mode=100644
		if [ -L "$p" ]; then
			mode=120000
		elif [ -x "$p" ]; then
			mode=100755
		fi
		ns=$(G diff --no-index --numstat -- /dev/null "$p" 2>/dev/null || true)
		add=${ns%%$'\t'*}
		rest=${ns#*$'\t'}
		del=${rest%%$'\t'*}
		[ -n "$add" ] || {
			add=0
			del=0
		}
		add_record A "$p" "" 000000 "$mode" 0000000 0000000 "$add" "$del" "$flags"
	done <"$listf"
}

# check-attr 로 filter / linguist-generated / diff 속성을 붙인다.
apply_attrs() {
	local n=${#F_PATH[@]} i path attr val
	[ "$n" -gt 0 ] || return 0
	local inf="$CTX/attr.in" outf="$CTX/attr.out"
	: >"$inf"
	for ((i = 0; i < n; i++)); do printf '%s\0' "${F_PATH[$i]}" >>"$inf"; done
	G check-attr -z --stdin filter linguist-generated diff <"$inf" >"$outf"
	i=0
	local cnt=0
	while IFS= read -r -d '' path && IFS= read -r -d '' attr && IFS= read -r -d '' val; do
		case "$attr" in
		filter)
			case "$val" in
			unspecified | unset | set) ;;
			lfs) F_FLAGS[$i]="${F_FLAGS[$i]:+${F_FLAGS[$i]},}lfs" ;;
			*) F_FLAGS[$i]="${F_FLAGS[$i]:+${F_FLAGS[$i]},}filtered" ;;
			esac
			;;
		linguist-generated)
			case "$val" in set | true) [ -n "${F_RULE[$i]}" ] || F_RULE[$i]=generated ;; esac
			;;
		diff)
			[ "$val" = unset ] && { [ -n "${F_RULE[$i]}" ] || F_RULE[$i]=generated; }
			;;
		esac
		cnt=$((cnt + 1))
		if [ $((cnt % 3)) -eq 0 ]; then i=$((i + 1)); fi
	done <"$outf"
}

# 스냅샷 기준 파일 내용 앞부분 출력 (생성 표시 검사용)
snapshot_head() { # idx
	local i=$1 path=${F_PATH[$1]}
	case "$SNAPSHOT_KIND" in
	worktree)
		if [ -f "$path" ] && [ ! -L "$path" ]; then head -c 2048 "$path"; fi
		;;
	*)
		case "${F_NSHA[$i]}" in
		0000000* | "") ;;
		*) G cat-file blob "${F_NSHA[$i]}" 2>/dev/null | head -c 2048 || true ;;
		esac
		;;
	esac
}

snapshot_size() { # idx → 바이트 수
	local i=$1 path=${F_PATH[$1]} sha
	if [ "${F_ST[$i]}" = D ]; then
		sha=${F_OSHA[$i]}
	elif [ "$SNAPSHOT_KIND" = worktree ]; then
		if [ -L "$path" ] || [ ! -e "$path" ]; then
			printf 0
			return
		fi
		stat -f %z "$path"
		return
	else
		sha=${F_NSHA[$i]}
	fi
	case "$sha" in
	0000000* | "") printf 0 ;;
	*) G cat-file -s "$sha" 2>/dev/null || printf 0 ;;
	esac
}

# 레코드별 표시·규칙 제외·크기 생략을 정한다.
classify() {
	local n=${#F_PATH[@]} i path reason fl
	for ((i = 0; i < n; i++)); do
		path=${F_PATH[$i]}
		fl=${F_FLAGS[$i]}
		if [ "${F_NM[$i]}" = 160000 ] || [ "${F_OM[$i]}" = 160000 ]; then
			fl="${fl:+$fl,}submodule"
		fi
		if [ "${F_NM[$i]}" = 120000 ] || { [ "${F_ST[$i]}" = D ] && [ "${F_OM[$i]}" = 120000 ]; }; then
			fl="${fl:+$fl,}symlink"
		fi
		if [ "${F_ADD[$i]}" = "-" ]; then
			fl="${fl:+$fl,}binary"
		elif [ "${F_ST[$i]}" = F ] && [ -f "$path" ] && [ ! -L "$path" ] && is_binary_file "$path"; then
			fl="${fl:+$fl,}binary"
		fi
		if [ "${F_ST[$i]}" = M ] && [ "${F_OM[$i]}" != "${F_NM[$i]}" ] && [ "${F_ADD[$i]}" = 0 ] && [ "${F_DEL[$i]}" = 0 ]; then
			fl="${fl:+$fl,}mode-only"
		fi
		F_FLAGS[$i]=$fl

		# 기본 제외
		reason=${F_RULE[$i]}
		[ -n "$reason" ] || reason=$(path_rule_reason "$path")
		if [ -z "$reason" ] && [ "${F_ST[$i]}" != D ]; then
			case ",$fl," in
			*,binary,* | *,submodule,* | *,symlink,* | *,lfs,*) ;;
			*) if snapshot_head "$i" | has_generated_header; then reason=generated; fi ;;
			esac
		fi
		if [ -n "$reason" ] && include_overrides "$path"; then reason=""; fi
		F_RULE[$i]=$reason
		if [ -n "$reason" ]; then continue; fi

		case ",$fl," in
		*,filtered,*)
			F_SKIP[$i]=filter
			continue
			;;
		esac
		case ",$fl," in
		*,binary,* | *,submodule,* | *,lfs,*) continue ;;
		esac
		if [ "$(snapshot_size "$i")" -gt "$MAX_FILE_BYTES" ]; then
			F_SKIP[$i]=size
		fi
	done
}

# ---------------------------------------------------------------- 범위별 수집

M_EXTRA=() # 범위별 매니페스트 필드 ("key<TAB>value")
mf() { M_EXTRA+=("$1	$2"); }

SNAPSHOT_KIND=worktree
head_sha=$(G rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)
DIFF_MODE=local

status_summary() {
	local staged unstaged untracked against=${head_sha:-$EMPTY_TREE}
	staged=$(G diff --cached --name-only -z "$against" -- 2>/dev/null | tr -cd '\000' | wc -c)
	unstaged=$(G diff --name-only -z -- 2>/dev/null | tr -cd '\000' | wc -c)
	untracked=$(G ls-files --others --exclude-standard -z 2>/dev/null | tr -cd '\000' | wc -c)
	printf 'staged=%d unstaged=%d untracked=%d' "$((staged))" "$((unstaged))" "$((untracked))"
}

write_commits() { # <rev-range> : 최근 MAX_COMMITS 개
	local range=$1 total
	total=$(G rev-list --count "$range" 2>/dev/null || printf 0)
	G log -n "$MAX_COMMITS" --format='commit %H%n%B' "$range" >"$COMMITS_FILE" 2>/dev/null || : >"$COMMITS_FILE"
	COMMIT_COUNT=$total
	if [ "$total" -gt "$MAX_COMMITS" ]; then
		warn "커밋 메시지가 ${total}개라 최근 ${MAX_COMMITS}개만 수집했습니다."
	fi
}
COMMIT_COUNT=0

# 이전 → 이후 비교 대상(after 가 비면 작업 트리)으로 레코드와 diff 를 만든다.
collect_tree_diff() { # before [after|--cached]
	local rawf="$CTX/raw.z"
	if ! G diff --raw --numstat -z -M --no-ext-diff --no-textconv "$@" -- "${PS[@]}" >"$rawf" 2>"$CTX/git.err"; then
		return 1
	fi
	load_raw_numstat "$rawf"
}

excluded_pathspecs() { # 규칙 제외·생략·lfs·필터 파일을 diff 에서 뺀다
	local n=${#F_PATH[@]} i
	EXPS=()
	for ((i = 0; i < n; i++)); do
		if [ -n "${F_RULE[$i]}" ] || [ -n "${F_SKIP[$i]}" ]; then
			EXPS+=(":(exclude,literal)${F_PATH[$i]}")
			[ -n "${F_OLD[$i]}" ] && EXPS+=(":(exclude,literal)${F_OLD[$i]}")
			continue
		fi
		case ",${F_FLAGS[$i]}," in
		*,lfs,* | *,filtered,*) EXPS+=(":(exclude,literal)${F_PATH[$i]}") ;;
		esac
	done
}

write_tree_diff() { # before [after|--cached]
	excluded_pathspecs
	G diff -M --no-ext-diff --no-textconv --no-color "$@" -- "${PS[@]}" ${EXPS[@]+"${EXPS[@]}"} >"$DIFF_FILE" 2>"$CTX/git.err"
}

append_untracked_diffs() {
	local n=${#F_PATH[@]} i rc
	for ((i = 0; i < n; i++)); do
		case ",${F_FLAGS[$i]}," in *,untracked,*) ;; *) continue ;; esac
		[ -z "${F_RULE[$i]}" ] && [ -z "${F_SKIP[$i]}" ] || continue
		case ",${F_FLAGS[$i]}," in *,lfs,* | *,filtered,*) continue ;; esac
		rc=0
		G diff --no-index --no-ext-diff --no-textconv --no-color -- /dev/null "${F_PATH[$i]}" >>"$DIFF_FILE" 2>>"$CTX/git.err" || rc=$?
		if [ "$rc" -gt 1 ]; then
			F_SKIP[$i]=unreadable
		fi
	done
}

resolve_commit() { # ref → sha 또는 실패
	G rev-parse -q --verify "$1^{commit}" 2>/dev/null
}

case "$scope" in
changes)
	base_src=""
	if [ "$base_set" -eq 1 ]; then
		base_ref=$base
		base_src=option
	elif cfg=$(git config --get code-sentinel.base 2>/dev/null) && [ -n "$cfg" ]; then
		base_ref=$cfg
		base_src=config
	elif sym=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); then
		base_ref=${sym#refs/remotes/}
		base_src=origin-head
	else
		die 4 "기준 브랜치를 정할 수 없습니다. --base origin/main 처럼 지정하거나 git config code-sentinel.base <ref> 로 저장하세요."
	fi
	if ! base_sha=$(resolve_commit "$base_ref"); then
		if [ "$base_src" = option ]; then
			die 5 "'$base_ref'을 찾을 수 없습니다. 커밋 해시나 브랜치 이름을 확인하세요."
		fi
		die 4 "기준 브랜치 '$base_ref'($base_src)을 해석할 수 없습니다. --base 로 지정하세요."
	fi
	[ -n "$head_sha" ] || die 4 "커밋이 없는 저장소에서는 --changes 의 기준을 정할 수 없습니다. --staged 를 쓰세요."
	if ! mb=$(G merge-base "$base_sha" "$head_sha" 2>/dev/null); then
		if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
			die 4 "히스토리가 얕아 merge-base를 구할 수 없습니다. 직접 git fetch --unshallow 를 실행한 뒤 다시 시도하세요."
		fi
		die 4 "'$base_ref'와 HEAD 사이에 공통 조상(merge-base)이 없습니다. --base 를 확인하세요."
	fi
	if git show-ref -q --verify "refs/remotes/$base_ref" 2>/dev/null; then
		warn "기준 $base_ref 은 원격 추적 브랜치이며 마지막 fetch 시점 기준입니다."
	fi
	if [ "$base_sha" = "$head_sha" ]; then
		warn "현재 브랜치가 기준 브랜치와 같아 미커밋 변경만 대상입니다."
		mf same_as_base yes
	fi
	collect_tree_diff "$mb" || die 4 "리뷰에 필요한 Git 객체를 읽을 수 없습니다: $(head -1 "$CTX/git.err"). code-sentinel은 fetch하지 않습니다."
	load_untracked
	mf base_ref "$base_ref"
	mf base_source "$base_src"
	mf merge_base "$mb"
	mf uncommitted included
	write_commits "$mb..$head_sha"
	;;
staged)
	SNAPSHOT_KIND=index
	against=${head_sha:-$EMPTY_TREE}
	collect_tree_diff --cached "$against" || die 4 "리뷰에 필요한 Git 객체를 읽을 수 없습니다: $(head -1 "$CTX/git.err")"
	mf parent "${head_sha:-empty-tree}"
	mf uncommitted staged-only
	;;
commit)
	SNAPSHOT_KIND=commit
	sha=$(resolve_commit "$ref") || die 5 "'$ref'을 찾을 수 없습니다. 커밋 해시나 브랜치 이름을 확인하세요."
	parent=$(G rev-parse -q --verify "$sha^1" 2>/dev/null || true)
	nparents=$(G rev-list --parents -n 1 "$sha" | awk '{ print NF - 1 }')
	if [ "$nparents" -gt 1 ]; then
		warn "merge commit 입니다. 첫 번째 부모 기준으로 비교합니다."
		mf merge_commit yes
	fi
	collect_tree_diff "${parent:-$EMPTY_TREE}" "$sha" || die 4 "리뷰에 필요한 Git 객체를 읽을 수 없습니다: $(head -1 "$CTX/git.err")"
	mf ref "$ref"
	mf parent "${parent:-empty-tree}"
	mf uncommitted excluded
	G log -n 1 --format='commit %H%n%B' "$sha" >"$COMMITS_FILE"
	COMMIT_COUNT=1
	;;
pr)
	SNAPSHOT_KIND=commit
	command -v gh >/dev/null 2>&1 || die 6 "GitHub CLI(gh)가 없습니다. gh 를 설치하고 gh auth login 후 다시 실행하세요."
	jsonf="$CTX/pr.json"
	if ! gh pr view "$prnum" --json baseRefOid,headRefOid,baseRefName,headRefName,title,body,url,commits >"$jsonf" 2>"$CTX/gh.err"; then
		die 6 "PR #$prnum 에 접근할 수 없습니다: $(head -1 "$CTX/gh.err"). gh auth login, 저장소 권한, 번호를 확인하세요. Codex 샌드박스에서는 네트워크가 막혀 있을 수 있습니다."
	fi
	PR_BODY_FILE="$CTX/pr-body.txt"
	meta=$(osascript -l JavaScript - "$jsonf" "$PR_BODY_FILE" "$COMMITS_FILE" "$MAX_COMMITS" <<'JXA' 2>"$CTX/jxa.err"
ObjC.import('Foundation');
function run(argv) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null).js;
  var d = JSON.parse(s);
  var clean = function (x) { return String(x == null ? '' : x).replace(/[\t\r\n]+/g, ' '); };
  $(d.body == null ? '' : String(d.body)).writeToFileAtomicallyEncodingError(argv[1], true, 4, null);
  var cs = d.commits || [], max = parseInt(argv[3], 10), out = [];
  for (var i = cs.length - 1; i >= 0 && out.length < max; i--) {
    var c = cs[i];
    out.push('commit ' + c.oid + '\n' + (c.messageHeadline || '') + (c.messageBody ? '\n\n' + c.messageBody : '') + '\n');
  }
  $(out.join('\n')).writeToFileAtomicallyEncodingError(argv[2], true, 4, null);
  return [clean(d.baseRefOid), clean(d.headRefOid), clean(d.baseRefName), clean(d.headRefName), clean(d.url), String(cs.length), clean(d.title)].join('\n');
}
JXA
	) || die 6 "PR #$prnum 메타데이터를 해석할 수 없습니다: $(head -1 "$CTX/jxa.err")"
	{
		IFS= read -r base_oid
		IFS= read -r head_oid
		IFS= read -r base_name
		IFS= read -r head_name
		IFS= read -r pr_url
		IFS= read -r pr_ncommits
		IFS= read -r pr_title || true
	} <<<"$meta"
	case "$base_oid$head_oid" in
	*[!0-9a-f]* | "") die 6 "PR #$prnum 의 base/head 커밋을 읽을 수 없습니다." ;;
	esac
	COMMIT_COUNT=${pr_ncommits:-0}
	if [ "$COMMIT_COUNT" -gt "$MAX_COMMITS" ]; then
		warn "커밋 메시지가 ${COMMIT_COUNT}개라 최근 ${MAX_COMMITS}개만 수집했습니다."
	fi

	use_local=1
	[ "$PARTIAL" -eq 1 ] && [ "$LAZY_SAFE" -eq 0 ] && use_local=0
	if [ "$use_local" -eq 1 ]; then
		G cat-file -e "$base_oid^{commit}" 2>/dev/null && G cat-file -e "$head_oid^{commit}" 2>/dev/null || use_local=0
	fi
	if [ "$use_local" -eq 1 ]; then
		mb=$(G merge-base "$base_oid" "$head_oid" 2>/dev/null) || use_local=0
	fi
	if [ "$use_local" -eq 1 ]; then
		if ! collect_tree_diff "$mb" "$head_oid"; then
			use_local=0
			F_ST=()
			F_PATH=()
			F_OLD=()
			F_OM=()
			F_NM=()
			F_OSHA=()
			F_NSHA=()
			F_ADD=()
			F_DEL=()
			F_FLAGS=()
			F_SKIP=()
			F_RULE=()
		fi
	fi
	if [ "$use_local" -eq 0 ]; then
		DIFF_MODE=gh-diff
		mb=""
		rawpatch="$CTX/gh.patch"
		gh pr diff "$prnum" >"$rawpatch" 2>"$CTX/gh.err" || die 6 "PR #$prnum 의 diff를 가져올 수 없습니다: $(head -1 "$CTX/gh.err")"
	fi

	local_match=no
	if [ "$head_sha" = "$head_oid" ] && [ -z "$(G status --porcelain 2>/dev/null)" ]; then
		local_match=yes
	else
		warn "로컬 HEAD·작업 트리가 PR head와 다릅니다. 로컬 파일을 확정 근거로 쓰지 마세요."
	fi
	if [ "$DIFF_MODE" = gh-diff ]; then
		warn "PR head 객체가 로컬에 없어 diff-only로 수집했습니다. 관련 코드 맥락은 확인할 수 없습니다."
	fi
	mf pr_number "$prnum"
	mf pr_url "$pr_url"
	mf pr_title "$pr_title"
	mf pr_body_file "$PR_BODY_FILE"
	mf base_ref "$base_name"
	mf head_ref "$head_name"
	mf base_tip "$base_oid"
	mf merge_base "${mb:-unknown}"
	mf diff_mode "$DIFF_MODE"
	mf local_head_matches "$local_match"
	mf uncommitted excluded
	if [ "$DIFF_MODE" = local ]; then write_commits "$mb..$head_oid"; fi
	;;
full)
	listf="$CTX/full.lst"
	G ls-files -s -z -- "${PS[@]}" >"$listf"
	missing=0
	prev=""
	while IFS= read -r -d '' ent; do
		meta=${ent%%$'\t'*}
		p=${ent#*$'\t'}
		[ "$p" = "$prev" ] && continue # 충돌 stage 중복
		prev=$p
		# shellcheck disable=SC2086
		set -- $meta
		mode=$1
		if [ "$mode" != 160000 ] && [ ! -e "$p" ] && [ ! -L "$p" ]; then
			missing=$((missing + 1))
			continue
		fi
		[ -L "$p" ] && mode=120000
		add_record F "$p" "" "$mode" "$mode" "$2" 0000000 0 0 ""
	done <"$listf"
	if [ "$missing" -gt 0 ]; then
		warn "작업 트리에서 삭제된 추적 파일 ${missing}개는 제외했습니다."
	fi
	load_untracked
	;;
esac

# ---------------------------------------------------------------- gh-diff 모드 파일 목록

if [ "$DIFF_MODE" = gh-diff ]; then
	# 패치 헤더를 파싱: 상태<TAB>경로<TAB>이전경로<TAB>추가<TAB>삭제<TAB>binary
	parsed="$CTX/gh.files"
	awk '
	function unq(s,   out, i, c, n) {
		if (substr(s, 1, 1) != "\"") return s
		s = substr(s, 2, length(s) - 2); out = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c != "\\") { out = out c; continue }
			i++; c = substr(s, i, 1)
			if (c == "n") out = out "\n"; else if (c == "t") out = out "\t"
			else if (c ~ /[0-7]/) { n = (c + 0) * 64 + (substr(s, i + 1, 1) + 0) * 8 + (substr(s, i + 2, 1) + 0); out = out sprintf("%c", n); i += 2 }
			else out = out c
		}
		return out
	}
	function stripab(s) { s = unq(s); sub(/\t$/, "", s); return substr(s, 3) }
	function flush() {
		if (!have) return
		if (path == "") path = hdr
		printf "%s\t%s\to:%s\t%s\t%s\t%s\n", st, path, old, (bin ? "-" : add), (bin ? "-" : del), bin
	}
	/^diff --git / {
		flush(); have = 1; st = "M"; path = ""; old = ""; add = 0; del = 0; bin = 0; inh = 0
		rest = substr($0, 12)
		if (substr(rest, 1, 1) == "\"") { q = index(substr(rest, 2), "\""); hdr = substr(unq(substr(rest, 1, q + 1)), 3) }
		else hdr = substr(rest, 3, (length(rest) - 3) / 2 - 1)
		next
	}
	!have { next }
	/^@@ / { inh = 1; next }
	inh && /^\+/ { add++; next }
	inh && /^-/ { del++; next }
	inh { next }
	/^new file mode / { st = "A"; next }
	/^deleted file mode / { st = "D"; next }
	/^rename from / { st = "R"; old = unq(substr($0, 13)); next }
	/^rename to / { path = unq(substr($0, 11)); next }
	/^Binary files / || /^GIT binary patch/ { bin = 1; next }
	/^--- / { if (substr($0, 5) != "/dev/null" && path == "" && st == "D") path = stripab(substr($0, 5)); next }
	/^\+\+\+ / { if (substr($0, 5) != "/dev/null") path = stripab(substr($0, 5)); next }
	END { flush() }
	' "$rawpatch" >"$parsed"
	# 이전 경로 열은 비어 있을 수 있어 "o:" 접두어를 붙여 둔다(탭 IFS 는 빈 필드를 합치므로)
	while IFS=$'\t' read -r st p old add del bin; do
		old=${old#o:}
		user_selected "$p" || continue
		flags=""
		[ "$bin" = 1 ] && flags=binary
		add_record "$st" "$p" "$old" 100644 100644 0000000 0000000 "$add" "$del" "$flags"
	done <"$parsed"
fi

# ---------------------------------------------------------------- 분류

apply_attrs
classify

# full 범위: 줄 수, binary, 전체 크기 상한
if [ "$scope" = full ]; then
	total_bytes=0
	n=${#F_PATH[@]}
	for ((i = 0; i < n; i++)); do
		[ -z "${F_RULE[$i]}" ] && [ -z "${F_SKIP[$i]}" ] || continue
		p=${F_PATH[$i]}
		case ",${F_FLAGS[$i]}," in *,submodule,* | *,symlink,* | *,lfs,* | *,filtered,* | *,binary,*) continue ;; esac
		sz=$(stat -f %z "$p")
		if [ $((total_bytes + sz)) -gt "$MAX_TOTAL_BYTES" ]; then
			F_SKIP[$i]=total-size
			continue
		fi
		total_bytes=$((total_bytes + sz))
		F_ADD[$i]=$(($(wc -l <"$p")))
	done
fi

# ---------------------------------------------------------------- diff 작성

case "$scope" in
changes)
	write_tree_diff "$mb" || die 4 "diff를 만들 수 없습니다: $(head -1 "$CTX/git.err")"
	append_untracked_diffs
	;;
staged) write_tree_diff --cached "$against" || die 4 "diff를 만들 수 없습니다: $(head -1 "$CTX/git.err")" ;;
commit) write_tree_diff "${parent:-$EMPTY_TREE}" "$sha" || die 4 "diff를 만들 수 없습니다: $(head -1 "$CTX/git.err")" ;;
pr)
	if [ "$DIFF_MODE" = local ]; then
		write_tree_diff "$mb" "$head_oid" || die 4 "diff를 만들 수 없습니다: $(head -1 "$CTX/git.err")"
	else
		# 규칙 제외·생략 파일의 섹션을 빼고 저장
		dropf="$CTX/gh.drop"
		: >"$dropf"
		n=${#F_PATH[@]}
		for ((i = 0; i < n; i++)); do
			if [ -n "${F_RULE[$i]}" ] || [ -n "${F_SKIP[$i]}" ]; then printf '%s\n' "${F_PATH[$i]}" >>"$dropf"; fi
		done
		awk -v dropf="$dropf" '
		BEGIN { while ((getline l < dropf) > 0) drop["a/" l " b/" l] = 1 }
		/^diff --git / { keep = !((substr($0, 12)) in drop) }
		keep
		' "$rawpatch" >"$DIFF_FILE"
	fi
	;;
full) : ;;
esac

# ---------------------------------------------------------------- 줄 번호 diff
# diff.patch 의 hunk 본문 줄마다 "<변경 전 줄> <변경 후 줄> | " 를 붙인다. 모델이 diff 파일 자체의 줄 번호를
# 위치로 쓰지 않도록, 보고서 위치에 쓸 번호를 줄 옆에 직접 보여 준다. 남은 줄 수(hunk 헤더의 개수)만큼만
# 본문으로 보므로, 내용이 '--- '·'+++ '·'@@ '로 시작해도 헤더로 오인하지 않는다.
write_numbered_diff() { # <diff> <출력>
	LC_ALL=C awk '
	function num(o, n) { printf "%6s %6s | %s\n", o, n, $0 }
	function cnt(s) { return (index(s, ",") ? substr(s, index(s, ",") + 1) : 1) + 0 }
	function start(s) { return (index(s, ",") ? substr(s, 1, index(s, ",") - 1) : s) + 0 }
	BEGIN {
		print "# code-sentinel numbered diff: <변경 전 줄> <변경 후 줄> | <diff 줄>. 보고서 위치에는 이 두 열의 번호를 씁니다(이 파일 자체의 줄 번호가 아님)."
		ro = 0; rn = 0
	}
	{
		c = substr($0, 1, 1)
		if (c == "\\") { num("", ""); next }
		if (ro > 0 || rn > 0) {
			if (c == " " || $0 == "") { num(o, n); o++; n++; ro--; rn--; next }
			if (c == "-") { num(o, ""); o++; ro--; next }
			if (c == "+") { num("", n); n++; rn--; next }
			ro = 0; rn = 0
		}
		if (match($0, /^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/)) {
			split(substr($0, 4, RLENGTH - 6), h, " ")
			o = start(substr(h[1], 2)); ro = cnt(substr(h[1], 2))
			n = start(substr(h[2], 2)); rn = cnt(substr(h[2], 2))
		}
		print
	}' "$1" >"$2"
}

NUMBERED_FILE="$CTX/diff.numbered.txt"
if [ "$scope" != full ]; then
	write_numbered_diff "$DIFF_FILE" "$NUMBERED_FILE" || die 1 "줄 번호 diff를 만들 수 없습니다."
fi

# ---------------------------------------------------------------- lockfile / manifest 경고

lock_for_manifest() {
	case "$1" in
	package.json) printf '%s\n' package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb ;;
	Cargo.toml) printf '%s\n' Cargo.lock ;;
	pyproject.toml) printf '%s\n' poetry.lock uv.lock ;;
	Pipfile) printf '%s\n' Pipfile.lock ;;
	composer.json) printf '%s\n' composer.lock ;;
	Gemfile) printf '%s\n' Gemfile.lock ;;
	go.mod) printf '%s\n' go.sum ;;
	esac
}
if [ "$scope" != full ]; then
	changed_list="$CTX/changed.lst"
	: >"$changed_list"
	n=${#F_PATH[@]}
	for ((i = 0; i < n; i++)); do printf '%s\n' "${F_PATH[$i]}" >>"$changed_list"; done
	for ((i = 0; i < n; i++)); do
		p=${F_PATH[$i]}
		dir=${p%/*}
		[ "$dir" = "$p" ] && dir="" || dir="$dir/"
		b=${p##*/}
		if [ "${F_RULE[$i]}" = lockfile ]; then
			has_manifest=0
			for m in package.json Cargo.toml pyproject.toml Pipfile composer.json Gemfile go.mod; do
				if lock_for_manifest "$m" | grep -qxF "$b" && grep -qxF "$dir$m" "$changed_list"; then has_manifest=1; fi
			done
			if [ "$has_manifest" -eq 0 ]; then
				warn "lockfile만 변경됐습니다: $(cquote "$p") (manifest 변경 없음, 의존성 변경 내용을 확인하세요)"
			fi
		fi
		locks=$(lock_for_manifest "$b")
		if [ -n "$locks" ] && [ "${F_ST[$i]}" != D ]; then
			lock_changed=0
			while IFS= read -r l; do
				if grep -qxF "$dir$l" "$changed_list"; then lock_changed=1; fi
			done <<<"$locks"
			if [ "$lock_changed" -eq 0 ]; then
				lock_exists=0
				snap_rev=${sha:-${head_oid:-}}
				while IFS= read -r l; do
					case "$SNAPSHOT_KIND" in
					worktree) if [ -e "$dir$l" ]; then lock_exists=1; fi ;;
					index) if G cat-file -e ":$dir$l" 2>/dev/null; then lock_exists=1; fi ;;
					commit) if [ -n "$snap_rev" ] && G cat-file -e "$snap_rev:$dir$l" 2>/dev/null; then lock_exists=1; fi ;;
					esac
				done <<<"$locks"
				if [ "$lock_exists" -eq 1 ]; then
					warn "manifest가 변경됐지만 lockfile은 그대로입니다: $(cquote "$p")"
				fi
			fi
		fi
	done
fi

# ---------------------------------------------------------------- 집계

n=${#F_PATH[@]}
target=0
lines=0
nrule=0
nskip=0
for ((i = 0; i < n; i++)); do
	if [ -n "${F_RULE[$i]}" ]; then
		nrule=$((nrule + 1))
		continue
	fi
	target=$((target + 1))
	[ -n "${F_SKIP[$i]}" ] && nskip=$((nskip + 1))
	a=${F_ADD[$i]}
	dl=${F_DEL[$i]}
	[ "$a" = "-" ] && a=0
	[ "$dl" = "-" ] && dl=0
	lines=$((lines + a + dl))
done
split=none
if [ "$target" -gt "$TRUNC_FILES" ] || [ "$lines" -gt "$TRUNC_LINES" ]; then
	split=truncated
elif [ "$target" -gt "$SPLIT_FILES" ] || [ "$lines" -gt "$SPLIT_LINES" ]; then
	split=recommended
fi

case "$SNAPSHOT_KIND" in
worktree) snapshot=worktree ;;
index) snapshot=index ;;
commit)
	if [ "$scope" = pr ]; then snapshot=$head_oid; else snapshot=$sha; fi
	;;
esac

# ---------------------------------------------------------------- 매니페스트

MF="$CTX/manifest.txt"
{
	printf 'CODE_SENTINEL_CONTEXT 1\n'
	printf 'scope\t%s\n' "$scope"
	printf 'repo\t%s\n' "$(cquote "$top")"
	printf 'context_dir\t%s\n' "$(cquote "$CTX")"
	printf 'snapshot\t%s\n' "$snapshot"
	printf 'head\t%s\n' "${head_sha:-none}"
	printf 'collected_at\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	if [ "$SNAPSHOT_KIND" != commit ]; then
		printf 'status_summary\t%s\n' "$(status_summary)"
	fi
	for kv in ${M_EXTRA[@]+"${M_EXTRA[@]}"}; do printf '%s\n' "$kv"; done
	printf 'target_files\t%d\n' "$target"
	printf 'target_lines\t%d\n' "$lines"
	printf 'rule_excluded\t%d\n' "$nrule"
	printf 'skipped\t%d\n' "$nskip"
	printf 'split\t%s\n' "$split"
	if [ "$scope" = full ]; then
		printf 'diff_file\tnone\n'
		printf 'numbered_diff_file\tnone\n'
	else
		printf 'diff_file\t%s\n' "$(cquote "$DIFF_FILE")"
		printf 'numbered_diff_file\t%s\n' "$(cquote "$NUMBERED_FILE")"
	fi
	if [ "$scope" != staged ] && [ "$scope" != full ]; then
		printf 'commits_file\t%s\n' "$(cquote "$COMMITS_FILE")"
		printf 'commit_count\t%d\n' "$COMMIT_COUNT"
	fi
	printf '[FILES]\n'
	for ((i = 0; i < n; i++)); do
		[ -z "${F_RULE[$i]}" ] || continue
		st=${F_ST[$i]}
		fl=${F_FLAGS[$i]}
		[ -n "${F_SKIP[$i]}" ] && fl="${fl:+$fl,}skipped"
		if [ -n "${F_OLD[$i]}" ]; then
			printf '%s\t%s\t%s' "$st" "$(cquote "${F_OLD[$i]}")" "$(cquote "${F_PATH[$i]}")"
		else
			printf '%s\t%s' "$st" "$(cquote "${F_PATH[$i]}")"
		fi
		[ -n "$fl" ] && printf '\t%s' "$fl"
		printf '\n'
	done
	printf '[RULE_EXCLUDED]\n'
	for ((i = 0; i < n; i++)); do
		if [ -n "${F_RULE[$i]}" ]; then printf '%s\t%s\n' "$(cquote "${F_PATH[$i]}")" "${F_RULE[$i]}"; fi
	done
	printf '[SKIPPED]\n'
	for ((i = 0; i < n; i++)); do
		[ -n "${F_RULE[$i]}" ] && continue
		if [ -n "${F_SKIP[$i]}" ]; then printf '%s\t%s\n' "$(cquote "${F_PATH[$i]}")" "${F_SKIP[$i]}"; fi
	done
	printf '[WARNINGS]\n'
	for w in ${WARNINGS[@]+"${WARNINGS[@]}"}; do printf '%s\n' "$w"; done
} >"$MF"

# 작업용 중간 파일 정리(매니페스트·diff·줄 번호 diff·커밋·PR 본문만 남긴다)
rm -f "$CTX/raw.z" "$CTX/untracked.lst" "$CTX/attr.in" "$CTX/attr.out" "$CTX/full.lst" "$CTX/changed.lst" \
	"$CTX/gh.files" "$CTX/gh.drop" "$CTX/git.err" "$CTX/gh.err" "$CTX/jxa.err"

cat "$MF"
KEEP=1
exit 0
