#!/bin/bash
# scripts/doctor.sh — code-sentinel 설치 상태와 실행 환경을 점검합니다(읽기 전용).
#
# 사용법: scripts/doctor.sh [--codex | --claude | --all]
#
#   --codex / --claude  해당 설치 경로만 점검(나머지 경로는 SKIP)
#   --all               두 경로 모두 점검(기본값)
#
# - 항목마다 PASS / FAIL / WARN / SKIP 한 줄을 출력하고, 조치가 필요하면 바로 아래에 안내합니다.
# - 어떤 파일도 만들거나 바꾸지 않습니다. 레거시 경로도 읽기만 합니다.
# - codex, claude, gh 는 호출한 셸의 PATH 에서 찾습니다. 없어도 실패로 보지 않습니다.
# - 테스트를 위해 HOME, CLAUDE_CONFIG_DIR, CODEX_HOME 환경변수를 그대로 따릅니다.
#
# 종료 코드: 0 FAIL 없음 · 1 FAIL 있음 · 2 사용법 오류

set -euo pipefail
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

SKILL_NAME=code-sentinel
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SRC="$REPO_ROOT/skills/$SKILL_NAME"

DESC_MAX=1024
GIT_MIN_MAJOR=2
GIT_MIN_MINOR=46
REQUIRED_SKILL_SCRIPTS="collect-context.sh cleanup-context.sh run-verification.sh"

N_PASS=0
N_FAIL=0
N_WARN=0
N_SKIP=0
pass() {
	N_PASS=$((N_PASS + 1))
	printf 'PASS  %s\n' "$1"
}
fail() {
	N_FAIL=$((N_FAIL + 1))
	printf 'FAIL  %s\n' "$1"
}
warn() {
	N_WARN=$((N_WARN + 1))
	printf 'WARN  %s\n' "$1"
}
skip() {
	N_SKIP=$((N_SKIP + 1))
	printf 'SKIP  %s\n' "$1"
}
hint() { printf '      조치: %s\n' "$1"; }
section() { printf '\n== %s\n' "$1"; }

usage() {
	printf '%s\n' \
		'사용법: scripts/doctor.sh [--codex | --claude | --all]' \
		'' \
		'  --codex    Codex 설치 경로만 점검' \
		'  --claude   Claude Code 설치 경로만 점검' \
		'  --all      두 경로 모두 점검(기본값)' \
		'' \
		'FAIL 이 하나라도 있으면 종료 코드 1 로 끝납니다.'
}

WANT_CODEX=0
WANT_CLAUDE=0
while [ $# -gt 0 ]; do
	case "$1" in
	--codex) WANT_CODEX=1 ;;
	--claude) WANT_CLAUDE=1 ;;
	--all)
		WANT_CODEX=1
		WANT_CLAUDE=1
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf '오류: 알 수 없는 옵션: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done
if [ "$WANT_CODEX" -eq 0 ] && [ "$WANT_CLAUDE" -eq 0 ]; then
	WANT_CODEX=1
	WANT_CLAUDE=1
fi

INSTALL_CMD="$REPO_ROOT/scripts/install.sh"

printf 'code-sentinel doctor\n'
printf '저장소: %s\n' "$REPO_ROOT"

# ---------------------------------------------------------------- 저장소
section "저장소"

repo_version() {
	local top v
	command -v git >/dev/null 2>&1 || return 0
	top=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null) || return 0
	[ -n "$top" ] || return 0
	top=$(cd -P "$top" 2>/dev/null && pwd -P) || return 0
	# 상위 디렉터리의 다른 저장소를 이 저장소로 착각하지 않는다.
	[ "$top" = "$REPO_ROOT" ] || return 0
	v=$(git -C "$REPO_ROOT" describe --tags --always 2>/dev/null) || return 0
	printf '%s' "$v"
}
VERSION=$(repo_version || true)
if [ -n "$VERSION" ]; then
	pass "저장소 버전: $VERSION"
else
	warn "저장소 버전: unknown (커밋이 없거나 Git 저장소가 아님)"
fi

if [ -d "$SRC" ]; then
	pass "스킬 원본: $SRC"
else
	fail "스킬 원본 디렉터리가 없습니다: $SRC"
fi

# ---------------------------------------------------------------- 설치 경로
section "설치 경로"

# check_target <라벨> <대상> <install 옵션>
check_target() {
	local label=$1 t=$2 opt=$3 lt phys
	if [ -L "$t" ]; then
		lt=$(readlink "$t" 2>/dev/null || true)
		if [ ! -e "$t" ]; then
			fail "$label: 깨진 링크 ($t -> $lt)"
			hint "저장소를 옮겼다면 새 위치에서 다시 연결하세요: '$INSTALL_CMD' --force $opt"
		elif [ ! -d "$t" ]; then
			fail "$label: 디렉터리가 아닌 파일을 가리키는 링크 ($t -> $lt)"
			hint "이 저장소로 바꾸려면: '$INSTALL_CMD' --force $opt"
		else
			phys=$(cd -P "$t" 2>/dev/null && pwd -P) || phys=""
			if [ -z "$phys" ]; then
				warn "$label: 링크 대상에 접근할 수 없음 ($t -> $lt)"
			elif [ "$phys" = "$SRC" ]; then
				pass "$label: 정상 ($t -> $lt)"
			else
				warn "$label: 다른 경로를 가리킴 ($t -> $lt)"
				hint "이 저장소로 바꾸려면: '$INSTALL_CMD' --force $opt"
			fi
		fi
	elif [ -d "$t" ]; then
		warn "$label: 링크가 아닌 실제 디렉터리 ($t)"
		hint "복사로 설치한 것으로 보입니다(git pull 로 갱신되지 않음). 내용을 확인해 직접 정리한 뒤 '$INSTALL_CMD' $opt 를 실행하세요."
	elif [ -e "$t" ]; then
		fail "$label: 링크가 아닌 실제 파일 ($t)"
		hint "스킬로 읽히지 않습니다. 내용을 확인해 직접 정리한 뒤 '$INSTALL_CMD' $opt 를 실행하세요."
	else
		warn "$label: 미설치 ($t)"
		hint "설치: '$INSTALL_CMD' $opt"
	fi
}

case "${HOME:-}" in
/?*)
	CODEX_T="${HOME%/}/.agents/skills/$SKILL_NAME"
	CLAUDE_BASE=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
	CLAUDE_T="${CLAUDE_BASE%/}/skills/$SKILL_NAME"
	if [ "$WANT_CODEX" -eq 1 ]; then
		check_target Codex "$CODEX_T" --codex
	else
		skip "Codex: 점검하지 않음 (--claude)"
	fi
	if [ "$WANT_CLAUDE" -eq 1 ]; then
		case "$CLAUDE_BASE" in
		/*) check_target "Claude Code" "$CLAUDE_T" --claude ;;
		*) fail "Claude Code: CLAUDE_CONFIG_DIR 가 절대 경로가 아닙니다: '$CLAUDE_BASE'" ;;
		esac
	else
		skip "Claude Code: 점검하지 않음 (--codex)"
	fi
	;;
*)
	fail "HOME 이 비어 있거나 절대 경로가 아닙니다: '${HOME:-}'"
	;;
esac

# ---------------------------------------------------------------- 레거시 경로
section "Codex 레거시 경로 (읽기만 함)"

describe_path() {
	if [ -L "$1" ]; then
		printf '링크 -> %s' "$(readlink "$1" 2>/dev/null || true)"
	elif [ -d "$1" ]; then
		printf '디렉터리'
	else
		printf '파일'
	fi
}

check_legacy() {
	local p=$1
	if [ -e "$p" ] || [ -L "$p" ]; then
		warn "레거시 경로에 같은 이름의 스킬이 있습니다: $p ($(describe_path "$p"))"
		hint "Codex 에서 code-sentinel 이 중복으로 보일 수 있습니다. 확인한 뒤 직접 정리하세요(doctor 는 건드리지 않습니다)."
	else
		pass "레거시 경로 중복 없음: $p"
	fi
}

if [ -n "${HOME:-}" ]; then
	LEGACY1="${HOME%/}/.codex/skills/$SKILL_NAME"
	CODEX_HOME_DIR=${CODEX_HOME:-$HOME/.codex}
	LEGACY2="${CODEX_HOME_DIR%/}/skills/$SKILL_NAME"
	check_legacy "$LEGACY1"
	if [ "$LEGACY2" != "$LEGACY1" ]; then
		check_legacy "$LEGACY2"
	fi
else
	skip "레거시 경로: HOME 이 없어 점검하지 않음"
fi

# ---------------------------------------------------------------- SKILL.md
section "SKILL.md frontmatter"

# fm_value <키> <frontmatter 본문> : 최상위 키의 값. 따옴표를 벗기고,
# 들여쓴 연속 줄(블록 스칼라 | > 포함)은 공백 하나로 이어 붙인다.
fm_value() {
	printf '%s\n' "$2" | awk -v want="$1" -v sq="'" -v dq='"' '
		function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
		function unq(s,    a, b) {
			if (length(s) >= 2) {
				a = substr(s, 1, 1); b = substr(s, length(s), 1)
				if ((a == sq && b == sq) || (a == dq && b == dq)) s = substr(s, 2, length(s) - 2)
			}
			return s
		}
		function flush() { if (key == want && !done) { print unq(trim(val)); done = 1 } }
		/^[A-Za-z0-9_-]+[ \t]*:/ {
			flush()
			key = $0; sub(/[ \t]*:.*/, "", key)
			val = $0; sub(/^[^:]*:/, "", val); val = trim(val)
			if (val ~ /^[|>][-+0-9]*$/) val = ""
			next
		}
		/^[ \t]/ || /^$/ {
			if (key != "") { t = trim($0); if (t != "") val = (val == "" ? t : val " " t) }
			next
		}
		{ flush(); key = "" }
		END { flush() }
	'
}

# char_count <문자열> : UTF-8 문자 수(연속 바이트 0x80-0xBF 를 빼고 센다. 로캘과 무관)
char_count() {
	printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' '
}

check_skill_md() {
	local f="$SRC/SKILL.md" fm rc name desc dlen keys k extra="" dir_name
	if [ ! -f "$f" ]; then
		fail "SKILL.md 가 없습니다: $f"
		return 0
	fi
	rc=0
	# 첫 줄의 --- 부터 다음 --- 까지를 frontmatter 로 본다.
	fm=$(awk '
		{ sub(/\r$/, "") }
		NR == 1 { if ($0 != "---") { bad = 1; exit } next }
		$0 == "---" { closed = 1; exit }
		{ print }
		END { if (NR == 0 || bad) exit 3; if (!closed) exit 4 }
	' "$f") || rc=$?
	case "$rc" in
	0) ;;
	3)
		fail "SKILL.md frontmatter: 첫 줄이 '---' 가 아닙니다"
		return 0
		;;
	4)
		fail "SKILL.md frontmatter: 닫는 '---' 줄이 없습니다"
		return 0
		;;
	*)
		fail "SKILL.md 를 읽을 수 없습니다: $f"
		return 0
		;;
	esac

	dir_name=$(basename "$SRC")
	name=$(fm_value name "$fm")
	if [ -z "$name" ]; then
		fail "SKILL.md frontmatter: name 이 없습니다"
	elif [ "$name" != "$SKILL_NAME" ]; then
		fail "SKILL.md frontmatter: name 이 '$SKILL_NAME' 이 아닙니다: '$name'"
	elif [ "$name" != "$dir_name" ]; then
		fail "SKILL.md frontmatter: name('$name')이 디렉터리 이름('$dir_name')과 다릅니다"
	else
		pass "SKILL.md name: $name (디렉터리 이름과 일치)"
	fi

	desc=$(fm_value description "$fm")
	if [ -z "$desc" ]; then
		fail "SKILL.md frontmatter: description 이 없거나 비어 있습니다"
	else
		dlen=$(char_count "$desc")
		if [ "$dlen" -gt "$DESC_MAX" ]; then
			fail "SKILL.md frontmatter: description 이 너무 깁니다 (${dlen}자, 최대 ${DESC_MAX}자)"
		else
			pass "SKILL.md description: ${dlen}자 (최대 ${DESC_MAX}자)"
		fi
	fi

	keys=$(printf '%s\n' "$fm" | awk '/^[A-Za-z0-9_-]+[ \t]*:/ { k = $0; sub(/[ \t]*:.*/, "", k); print k }')
	for k in $keys; do
		case "$k" in
		name | description) ;;
		*) extra="$extra $k" ;;
		esac
	done
	if [ -n "$extra" ]; then
		warn "SKILL.md frontmatter: name, description 외의 키가 있습니다:$extra"
		hint "두 도구가 같은 SKILL.md 를 읽으므로 Codex 가 무시하고 정상 로드하는지 확인하세요."
	fi
}
check_skill_md

# ---------------------------------------------------------------- 스크립트
section "스크립트"

check_scripts() {
	local s f n_ok=0 n_bad=0 rel
	for s in $REQUIRED_SKILL_SCRIPTS; do
		if [ ! -f "$SRC/scripts/$s" ]; then
			fail "스킬 스크립트가 없습니다: skills/$SKILL_NAME/scripts/$s"
		fi
	done
	for f in "$REPO_ROOT"/scripts/*.sh "$SRC"/scripts/*.sh; do
		[ -f "$f" ] || continue
		rel=${f#"$REPO_ROOT"/}
		if [ -x "$f" ]; then
			n_ok=$((n_ok + 1))
		else
			n_bad=$((n_bad + 1))
			fail "실행 권한이 없습니다: $rel"
			hint "chmod +x '$f'"
		fi
	done
	if [ "$n_bad" -eq 0 ]; then
		if [ "$n_ok" -gt 0 ]; then
			pass "실행 권한: scripts/, skills/$SKILL_NAME/scripts/ 의 ${n_ok}개 스크립트"
		else
			warn "실행 권한: 점검할 스크립트가 없습니다"
		fi
	fi
}
check_scripts

check_syntax() {
	local out n_ok n_bad bad_list line old_ifs
	out=$(find "$REPO_ROOT" -name .git -prune -o -type f -name '*.sh' -print0 2>/dev/null |
		while IFS= read -r -d '' f; do
			if /bin/bash -n "$f" >/dev/null 2>&1; then
				printf 'OK\n'
			else
				printf 'BAD\t%s\n' "${f#"$REPO_ROOT"/}"
			fi
		done) || true
	n_ok=$(printf '%s\n' "$out" | grep -c '^OK$' || true)
	bad_list=$(printf '%s\n' "$out" | awk '/^BAD\t/ { sub(/^BAD\t/, ""); print }')
	n_bad=0
	if [ -n "$bad_list" ]; then
		old_ifs=$IFS
		IFS='
'
		set -f
		for line in $bad_list; do
			n_bad=$((n_bad + 1))
			fail "/bin/bash -n 실패: $line"
		done
		set +f
		IFS=$old_ifs
		hint "확인: /bin/bash -n '<파일>'"
	fi
	if [ "$n_bad" -eq 0 ]; then
		pass "/bin/bash -n: .sh 파일 ${n_ok}개 통과"
	fi
}
check_syntax

# ---------------------------------------------------------------- 도구
section "도구"

if [ -x /bin/bash ]; then
	BV=$(/bin/bash -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null || true)
	pass "/bin/bash: ${BV:-버전 확인 불가}"
else
	fail "/bin/bash 가 없습니다 (모든 스크립트가 /bin/bash 로 실행됩니다)"
fi

check_git() {
	local gp gl gv major rest minor
	gp=$(command -v git 2>/dev/null || true)
	if [ -z "$gp" ]; then
		fail "git: PATH 에 없습니다 (code-sentinel 은 git 이 필요합니다)"
		return 0
	fi
	gl=$(git --version 2>/dev/null || true)
	if [ -z "$gl" ]; then
		fail "git: 실행에 실패했습니다 ($gp)"
		return 0
	fi
	gv=${gl#git version }
	gv=${gv%% *}
	major=${gv%%.*}
	rest=${gv#*.}
	minor=${rest%%.*}
	case "$major" in '' | *[!0-9]*) major="" ;; esac
	case "$minor" in '' | *[!0-9]*) minor="" ;; esac
	if [ -z "$major" ] || [ -z "$minor" ]; then
		warn "git: 버전을 해석할 수 없습니다 ($gl, $gp)"
		return 0
	fi
	if [ "$major" -gt "$GIT_MIN_MAJOR" ] || { [ "$major" -eq "$GIT_MIN_MAJOR" ] && [ "$minor" -ge "$GIT_MIN_MINOR" ]; }; then
		pass "git: $gv ($gp)"
	else
		warn "git: $gv ($gp) — ${GIT_MIN_MAJOR}.${GIT_MIN_MINOR} 미만이라 partial clone 저장소에서는 객체를 읽지 않습니다"
		hint "partial clone 에서 --pr 은 gh pr diff 로 처리되고, 그 밖의 범위는 종료 코드 4 로 끝납니다. git ${GIT_MIN_MAJOR}.${GIT_MIN_MINOR} 이상을 쓰면 자동 객체 다운로드 차단(GIT_NO_LAZY_FETCH)이 보장됩니다."
	fi
}
check_git

# check_tool <이름> : 있으면 경로와 버전을 출력한다. 없으면 SKIP(실패 아님).
FOUND=0
check_tool() {
	local name=$1 p v
	FOUND=0
	p=$(command -v "$name" 2>/dev/null || true)
	if [ -z "$p" ]; then
		skip "$name: PATH 에 없음 (이 도구를 쓰지 않으면 무시해도 됩니다)"
		return 0
	fi
	FOUND=1
	v=$("$p" --version </dev/null 2>/dev/null || true)
	v=${v%%$'\n'*}
	pass "$name: $p${v:+ ($v)}"
}
check_tool codex
HAVE_CODEX=$FOUND
check_tool claude
HAVE_CLAUDE=$FOUND
if [ "$HAVE_CODEX" -eq 0 ] && [ "$HAVE_CLAUDE" -eq 0 ]; then
	warn "codex 와 claude 를 모두 찾지 못했습니다. 이 PATH 에서는 스킬을 쓸 도구가 없습니다."
fi

GH=$(command -v gh 2>/dev/null || true)
if [ -z "$GH" ]; then
	warn "gh: PATH 에 없음 — --pr 범위를 쓰려면 GitHub CLI(gh)가 필요합니다(다른 범위에는 영향 없음)"
	skip "gh auth status: gh 가 없어 점검하지 않음"
else
	# gh 가 HOME 에 상태 파일(텔레메트리 device-id 등)을 쓰지 않게 한다.
	GHV=$(GH_TELEMETRY=0 DO_NOT_TRACK=1 GH_NO_UPDATE_NOTIFIER=1 "$GH" --version </dev/null 2>/dev/null || true)
	GHV=${GHV%%$'\n'*}
	pass "gh: $GH${GHV:+ ($GHV)}"
	if GH_TELEMETRY=0 DO_NOT_TRACK=1 GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 "$GH" auth status </dev/null >/dev/null 2>&1; then
		pass "gh auth status: 인증됨"
	else
		warn "gh auth status: 인증되지 않았거나 확인에 실패했습니다 — --pr 을 쓰려면 gh auth login"
	fi
fi

# ---------------------------------------------------------------- 요약
printf '\n요약: PASS %d · FAIL %d · WARN %d · SKIP %d\n' "$N_PASS" "$N_FAIL" "$N_WARN" "$N_SKIP"
if [ "$N_FAIL" -gt 0 ]; then
	exit 1
fi
exit 0
