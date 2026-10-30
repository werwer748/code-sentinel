#!/bin/bash
# tests/lib.sh — 격리 환경 헬퍼. 각 tests/test-*.sh 가 source 합니다.
#
# 사용 예:
#   . "$(dirname "$0")/lib.sh"
#   setup_sandbox
#   new_repo "$TEST_ROOT/r"; cd "$TEST_ROOT/r"
#   ...
#   assert_eq "설명" "기대값" "실제값"
#   finish

set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SKILL_DIR="$REPO_ROOT/skills/code-sentinel"
SCRIPTS_DIR="$SKILL_DIR/scripts"
# shellcheck disable=SC2034 # 이 파일을 source하는 테스트들이 씀
COLLECT="$SCRIPTS_DIR/collect-context.sh"
# shellcheck disable=SC2034
CLEANUP="$SCRIPTS_DIR/cleanup-context.sh"
# shellcheck disable=SC2034
VERIFY="$SCRIPTS_DIR/run-verification.sh"

T_NAME=$(basename "$0" .sh)
T_PASS=0
T_FAIL=0
T_SKIP=0

pass() { T_PASS=$((T_PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { T_FAIL=$((T_FAIL + 1)); printf 'FAIL  %s%s\n' "$1" "${2:+ -- $2}"; }
skip() { T_SKIP=$((T_SKIP + 1)); printf 'SKIP  %s%s\n' "$1" "${2:+ -- $2}"; }

# 격리 환경을 만든다. TEST_ROOT 아래에 HOME, TMPDIR 등을 두고 종료 시 지운다.
# 원래 PATH 는 ORIG_PATH 로 보존한다(shellcheck 등 예외용).
setup_sandbox() {
	# shellcheck disable=SC2034 # test-static.sh 등이 씀
	ORIG_PATH=$PATH
	ORIG_TMPDIR=${TMPDIR:-/tmp}
	TEST_ROOT=$(mktemp -d "${ORIG_TMPDIR%/}/cs-test.XXXXXX")
	TEST_ROOT=$(cd -P "$TEST_ROOT" && pwd -P)
	trap 'cleanup_sandbox' EXIT
	export HOME="$TEST_ROOT/home"
	export CLAUDE_CONFIG_DIR="$HOME/.claude"
	export CODEX_HOME="$HOME/.codex"
	export TMPDIR="$TEST_ROOT/tmp"
	mkdir -p "$HOME" "$TMPDIR"
	export GIT_CONFIG_GLOBAL=/dev/null
	export GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.com
	export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.com
	export PATH=/usr/bin:/bin:/usr/sbin:/sbin
	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
}

cleanup_sandbox() {
	if [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ]; then
		chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
		rm -rf "$TEST_ROOT"
	fi
}

# new_repo <dir> : main 브랜치의 빈 저장소를 만든다.
new_repo() {
	mkdir -p "$1"
	git -C "$1" init -q -b main
	git -C "$1" config commit.gpgsign false
	git -C "$1" config core.hooksPath /dev/null
}

# gcommit <message> : 현재 디렉터리 저장소의 모든 변경을 커밋한다.
gcommit() {
	git add -A >/dev/null
	git commit -q --allow-empty -m "$1"
}

assert_eq() {
	if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}

assert_contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1" "[$3] not found" ;;
	esac
}

assert_not_contains() {
	case "$2" in
	*"$3"*) fail "$1" "[$3] unexpectedly found" ;;
	*) pass "$1" ;;
	esac
}

# assert_exit <설명> <기대 종료코드> <명령...> : 출력은 LAST_OUT 에 남는다.
assert_exit() {
	local desc=$1 want=$2 got
	shift 2
	LAST_OUT=$("$@" 2>&1) && got=0 || got=$?
	if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc" "exit $got (want $want): $(printf '%s' "$LAST_OUT" | head -3)"; fi
}

# mf_get <manifest 파일> <키> : 탭 구분 매니페스트의 값(두 번째 열부터 끝까지)
mf_get() {
	awk -F'\t' -v k="$2" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }' "$1"
}

# mf_section <manifest 파일> <섹션> : [섹션] 다음 줄부터 다음 [ 섹션 전까지
mf_section() {
	awk -v s="[$2]" '$0 == s { on = 1; next } /^\[[A-Z_]+\]$/ { on = 0 } on' "$1"
}

finish() {
	printf 'RESULT\t%s\tpass=%d\tfail=%d\tskip=%d\n' "$T_NAME" "$T_PASS" "$T_FAIL" "$T_SKIP"
	[ "$T_FAIL" -eq 0 ]
}
