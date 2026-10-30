#!/bin/bash
# tests/test-install.sh — scripts/install.sh, uninstall.sh, doctor.sh (SPEC §15, §16.8)
#
# - 시작 전에 HOME 이 임시 디렉터리(TEST_ROOT) 아래인지 확인하고, 아니면 즉시 중단한다.
#   스크립트를 실행할 때마다 같은 확인을 반복한다.
# - 저장소 레이아웃(scripts/ + skills/code-sentinel/SKILL.md + 더미 스크립트)을 임시 디렉터리에
#   복사해(공백이 든 경로) 그 복사본의 스크립트를 실행한다. 실제 SKILL.md 내용과 무관하다.
# - 실행할 때마다 전후로 "현재 임시 HOME 밖"(TEST_ROOT 전체)의 파일 목록·크기·권한·mtime·링크 대상을
#   비교해, 대상 경로 밖에 아무것도 쓰지 않는지 확인한다. 실제 HOME 의 대상 경로도 전후 비교한다(읽기만 함).

. "$(dirname "$0")/lib.sh"

# ---------------------------------------------------------------- 실제 HOME 대상 경로(읽기만 함)
REAL_HOME=${HOME:-}
REAL_CLAUDE_BASE=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
REAL_CODEX_HOME=${CODEX_HOME:-${HOME:-}/.codex}

path_sig() {
	if [ -L "$1" ]; then
		printf 'link:%s' "$(readlink "$1")"
	elif [ -d "$1" ]; then
		printf 'dir'
	elif [ -e "$1" ]; then
		printf 'file'
	else
		printf 'none'
	fi
}
real_sig() {
	printf '%s|%s|%s|%s' \
		"$(path_sig "$REAL_HOME/.agents/skills/code-sentinel")" \
		"$(path_sig "$REAL_CLAUDE_BASE/skills/code-sentinel")" \
		"$(path_sig "$REAL_HOME/.codex/skills/code-sentinel")" \
		"$(path_sig "$REAL_CODEX_HOME/skills/code-sentinel")"
}
REAL_SIG_BEFORE=$(real_sig)

setup_sandbox

# ---------------------------------------------------------------- 안전장치
abort() {
	fail "중단: $1"
	finish
	exit 1
}

guard_home() {
	case "${TEST_ROOT:-}" in
	/?*/*) ;;
	*) abort "TEST_ROOT 가 올바르지 않습니다: '${TEST_ROOT:-}'" ;;
	esac
	[ -d "$TEST_ROOT" ] || abort "TEST_ROOT 가 없습니다: $TEST_ROOT"
	case "${HOME:-}" in
	"$TEST_ROOT"/*) ;;
	*) abort "HOME 이 임시 디렉터리 밖입니다: '${HOME:-}'" ;;
	esac
	[ "$HOME" != "$REAL_HOME" ] || abort "HOME 이 실제 HOME 과 같습니다: $HOME"
	case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in
	"$TEST_ROOT"/*) ;;
	*) abort "CLAUDE_CONFIG_DIR 가 임시 디렉터리 밖입니다: '${CLAUDE_CONFIG_DIR:-}'" ;;
	esac
	case "${CODEX_HOME:-$HOME/.codex}" in
	"$TEST_ROOT"/*) ;;
	*) abort "CODEX_HOME 이 임시 디렉터리 밖입니다: '${CODEX_HOME:-}'" ;;
	esac
}
guard_home
pass "HOME·CLAUDE_CONFIG_DIR·CODEX_HOME 이 임시 디렉터리 아래에 있음"

HOME_N=0
# new_home : 시나리오마다 새 임시 HOME 을 쓴다.
new_home() {
	HOME_N=$((HOME_N + 1))
	export HOME="$TEST_ROOT/homes/h$HOME_N"
	export CLAUDE_CONFIG_DIR="$HOME/.claude"
	export CODEX_HOME="$HOME/.codex"
	mkdir -p "$HOME"
	guard_home
}

# 현재 HOME 을 뺀 TEST_ROOT 전체의 상태
snap_outside() {
	find "$TEST_ROOT" -path "$HOME" -prune -o -exec stat -f '%m %z %p %N%SY' {} + 2>/dev/null
}
home_tree() { (cd "$HOME" && find . -exec stat -f '%m %z %p %N%SY' {} + | sort); }
home_names() { (cd "$HOME" && find . | sort); }

OUTSIDE_BAD=""
N_RUNS=0
# rx <설명> <기대 종료코드> <명령...> : assert_exit + 실행 전후 임시 HOME 밖 변경 감시
rx() {
	local before after
	guard_home
	before=$(snap_outside)
	assert_exit "$@"
	after=$(snap_outside)
	N_RUNS=$((N_RUNS + 1))
	if [ "$before" != "$after" ]; then OUTSIDE_BAD="$OUTSIDE_BAD [$1]"; fi
}
# rx_any <설명> <명령...> : 종료 코드는 보지 않고 출력만 LAST_OUT 에 남긴다(외부 변경 감시는 함).
rx_any() {
	local desc=$1 before after
	shift
	guard_home
	before=$(snap_outside)
	LAST_OUT=$("$@" 2>&1) || true
	after=$(snap_outside)
	N_RUNS=$((N_RUNS + 1))
	if [ "$before" != "$after" ]; then OUTSIDE_BAD="$OUTSIDE_BAD [$desc]"; fi
}

in_dir() {
	local d=$1
	shift
	cd "$d" && "$@"
}

lnk() { readlink "$1" 2>/dev/null || printf '<none>'; }
kind() {
	if [ -L "$1" ]; then
		printf 'link'
	elif [ -d "$1" ]; then
		printf 'dir'
	elif [ -e "$1" ]; then
		printf 'file'
	else
		printf 'none'
	fi
}
CX() { printf '%s' "$HOME/.agents/skills/code-sentinel"; }
CL() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/code-sentinel"; }
yes_if() { if "$@"; then printf yes; else printf no; fi; }

# ---------------------------------------------------------------- 임시 저장소 레이아웃
SKILL_OK=$(printf '%s\n' '---' 'name: code-sentinel' 'description: 테스트용 코드 리뷰 스킬. Use for code review.' '---' '' '# code-sentinel (test)')

make_repo() {
	local d=$1 s
	mkdir -p "$d/scripts" "$d/skills/code-sentinel/scripts" "$d/skills/code-sentinel/references"
	for s in install.sh uninstall.sh doctor.sh; do
		cp "$REPO_ROOT/scripts/$s" "$d/scripts/$s"
		chmod 755 "$d/scripts/$s"
	done
	printf '%s\n' "$SKILL_OK" >"$d/skills/code-sentinel/SKILL.md"
	for s in collect-context.sh cleanup-context.sh run-verification.sh; do
		printf '#!/bin/bash\nexit 0\n' >"$d/skills/code-sentinel/scripts/$s"
		chmod 755 "$d/skills/code-sentinel/scripts/$s"
	done
}

mkdir -p "$TEST_ROOT/work" "$TEST_ROOT/elsewhere" "$TEST_ROOT/other/code-sentinel"
printf 'other\n' >"$TEST_ROOT/other/code-sentinel/SKILL.md"
OTHER="$TEST_ROOT/other/code-sentinel"
GONE="$TEST_ROOT/gone/code-sentinel"

A="$TEST_ROOT/work/repo A"
make_repo "$A"
A_SRC="$A/skills/code-sentinel"
INS="$A/scripts/install.sh"
UNI="$A/scripts/uninstall.sh"
DOC="$A/scripts/doctor.sh"

# ---------------------------------------------------------------- 사용법
new_home
rx "install: 알 수 없는 옵션은 종료 코드 2" 2 "$INS" --bogus
rx "uninstall: 알 수 없는 옵션은 종료 코드 2" 2 "$UNI" --bogus
rx "doctor: 알 수 없는 옵션은 종료 코드 2" 2 "$DOC" --bogus
rx "install --help 는 성공" 0 "$INS" --help
assert_contains "install --help 에 옵션 설명" "$LAST_OUT" "--dry-run"
rx "상대 경로 CLAUDE_CONFIG_DIR 는 거부(종료 코드 2)" 2 in_dir "$HOME" env CLAUDE_CONFIG_DIR=rel/claude "$INS" --claude
assert_eq "상대 경로 CLAUDE_CONFIG_DIR 로 아무것도 만들지 않음" "." "$(home_names)"
rx "상대 경로 CLAUDE_CONFIG_DIR 여도 --codex 설치는 가능" 0 in_dir "$HOME" env CLAUDE_CONFIG_DIR=rel/claude "$INS" --codex
assert_eq "--codex: 상대 경로 CLAUDE_CONFIG_DIR 를 쓰지 않음" none "$(kind "$HOME/rel")"
rx "상대 경로 CLAUDE_CONFIG_DIR 여도 --codex 제거는 가능" 0 in_dir "$HOME" env CLAUDE_CONFIG_DIR=rel/claude "$UNI" --codex

# ---------------------------------------------------------------- Codex·Claude 개별 설치
new_home
rx "Codex 설치(--codex)" 0 "$INS" --codex
assert_eq "Codex 링크가 저장소 skills/code-sentinel 을 절대 경로로 가리킴" "$A_SRC" "$(lnk "$(CX)")"
assert_eq "--codex 는 Claude 경로를 만들지 않음" none "$(kind "$(CL)")"
assert_contains "완료 메시지: 재시작 안내" "$LAST_OUT" "실행 중인 세션은 재시작해야 반영될 수 있습니다"
assert_contains "완료 메시지: Codex 재시작" "$LAST_OUT" "Codex 는 재시작해야"
assert_eq "HOME 에는 Codex 대상 경로와 그 부모만 생김" \
	"$(printf '%s\n' . ./.agents ./.agents/skills ./.agents/skills/code-sentinel | sort)" "$(home_names)"

rx "Claude Code 설치(--claude)" 0 "$INS" --claude
assert_eq "Claude 링크가 저장소 skills/code-sentinel 을 가리킴" "$A_SRC" "$(lnk "$(CL)")"
assert_eq "--claude 는 Codex 링크를 바꾸지 않음" "$A_SRC" "$(lnk "$(CX)")"
assert_contains "새 skills 디렉터리를 만들면 /reload-skills 안내" "$LAST_OUT" "/reload-skills"
assert_not_contains "--claude 완료 메시지에 Codex 재시작 없음" "$LAST_OUT" "Codex 는 재시작해야"

# 재설치(멱등)
before=$(home_tree)
rx "재설치 성공(멱등)" 0 "$INS"
assert_contains "재설치: 이미 설치됨 출력" "$LAST_OUT" "이미 설치됨"
assert_eq "재설치가 HOME 을 바꾸지 않음" "$before" "$(home_tree)"
rx "이미 설치된 상태에서 --force 도 멱등" 0 "$INS" --force
assert_eq "--force 재설치가 HOME 을 바꾸지 않음" "$before" "$(home_tree)"

# 제거
rx "제거 성공" 0 "$UNI"
assert_eq "제거 후 Codex 경로 없음" none "$(kind "$(CX)")"
assert_eq "제거 후 Claude 경로 없음" none "$(kind "$(CL)")"
assert_eq "제거가 원본 SKILL.md 를 건드리지 않음" yes "$(yes_if [ -f "$A_SRC/SKILL.md" ])"
assert_contains "제거 후 재시작 안내" "$LAST_OUT" "재시작"
rx "미설치 상태에서 제거도 성공" 0 "$UNI"
assert_contains "미설치 안내" "$LAST_OUT" "설치되어 있지 않습니다"
rx "미설치 상태에서 --claude 제거도 성공" 0 "$UNI" --claude

# ---------------------------------------------------------------- 전체 설치
new_home
rx "기본값(전체) 설치" 0 "$INS"
assert_eq "전체 설치: Codex 링크" "$A_SRC" "$(lnk "$(CX)")"
assert_eq "전체 설치: Claude 링크" "$A_SRC" "$(lnk "$(CL)")"
assert_eq "전체 설치: HOME 에는 두 대상 경로와 그 부모만 생김" \
	"$(printf '%s\n' . ./.agents ./.agents/skills ./.agents/skills/code-sentinel ./.claude ./.claude/skills ./.claude/skills/code-sentinel | sort)" \
	"$(home_names)"
rx "전체 설치 후 doctor 통과" 0 "$DOC"
assert_contains "doctor: Codex 정상" "$LAST_OUT" "PASS  Codex: 정상"
assert_contains "doctor: Claude Code 정상" "$LAST_OUT" "PASS  Claude Code: 정상"

new_home
rx "--all 설치" 0 "$INS" --all
assert_eq "--all: Codex 링크" "$A_SRC" "$(lnk "$(CX)")"
assert_eq "--all: Claude 링크" "$A_SRC" "$(lnk "$(CL)")"
rx "--codex --claude 함께 지정도 재설치 멱등" 0 "$INS" --codex --claude
assert_contains "--codex --claude: 이미 설치됨" "$LAST_OUT" "이미 설치됨"
rx "--all 제거" 0 "$UNI" --all
assert_eq "--all 제거: 두 경로 모두 없음" "none none" "$(kind "$(CX)") $(kind "$(CL)")"

# ---------------------------------------------------------------- 충돌: 실제 디렉터리·파일
new_home
mkdir -p "$(CX)"
printf 'keep\n' >"$(CX)/SKILL.md"
rx "실제 디렉터리 충돌: 중단(종료 코드 1)" 1 "$INS"
assert_contains "실제 디렉터리: 수동 조치 안내" "$LAST_OUT" "직접 옮기거나 지우고"
assert_eq "충돌이 있으면 다른 대상(Claude)도 설치하지 않음" none "$(kind "$(CL)")"
rx "실제 디렉터리: --force 도 거부" 1 "$INS" --codex --force
assert_eq "실제 디렉터리 유지" dir "$(kind "$(CX)")"
assert_eq "실제 디렉터리 내용 유지" keep "$(cat "$(CX)/SKILL.md")"
rx "실제 디렉터리: uninstall 은 건드리지 않음(종료 코드 1)" 1 "$UNI" --codex
assert_contains "uninstall: 실제 디렉터리 이유 출력" "$LAST_OUT" "실제 디렉터리라 건드리지 않습니다"
assert_eq "uninstall 뒤에도 실제 디렉터리 내용 유지" keep "$(cat "$(CX)/SKILL.md")"
rx "실제 디렉터리가 있어도 --claude 설치는 가능" 0 "$INS" --claude
rx "doctor: 실제 디렉터리는 경고(실패 아님)" 0 "$DOC"
assert_contains "doctor: 실제 디렉터리 상태" "$LAST_OUT" "WARN  Codex: 링크가 아닌 실제 디렉터리"

new_home
mkdir -p "$(dirname "$(CL)")"
printf 'file\n' >"$(CL)"
rx "실제 파일 충돌: 중단" 1 "$INS" --claude
rx "실제 파일: --force 도 거부" 1 "$INS" --claude --force
assert_eq "실제 파일 유지" "file:file" "$(kind "$(CL)"):$(cat "$(CL)")"

# ---------------------------------------------------------------- 충돌: 다른 경로 링크
new_home
mkdir -p "$(dirname "$(CX)")"
ln -s "$OTHER" "$(CX)"
rx "다른 경로 링크 충돌: 중단(종료 코드 1)" 1 "$INS" --codex
assert_contains "다른 경로 링크: --force 안내" "$LAST_OUT" "--force"
assert_eq "다른 경로 링크 유지" "$OTHER" "$(lnk "$(CX)")"
rx "doctor: 다른 경로 링크는 경고" 0 "$DOC" --codex
assert_contains "doctor: 다른 경로 상태" "$LAST_OUT" "WARN  Codex: 다른 경로를 가리킴"
assert_contains "doctor --codex: Claude 는 SKIP" "$LAST_OUT" "SKIP  Claude Code"
rx "다른 경로 링크: uninstall 은 그대로 둠(종료 코드 1)" 1 "$UNI" --codex
assert_contains "uninstall: 다른 경로 이유 출력" "$LAST_OUT" "이 저장소가 아닌 경로를 가리키는 링크라 그대로 둡니다"
assert_eq "uninstall 뒤에도 다른 경로 링크 유지" "$OTHER" "$(lnk "$(CX)")"
rx "uninstall --force 도 다른 경로 링크는 그대로 둠" 1 "$UNI" --codex --force
assert_eq "uninstall --force 뒤에도 다른 경로 링크 유지" "$OTHER" "$(lnk "$(CX)")"
rx "다른 경로 링크: --force 로 교체" 0 "$INS" --codex --force
assert_eq "--force 교체 후 이 저장소를 가리킴" "$A_SRC" "$(lnk "$(CX)")"
assert_eq "--force 교체가 기존 링크 대상 내용을 건드리지 않음" other "$(cat "$OTHER/SKILL.md")"

# 파일을 가리키는 링크도 다른 경로로 취급
new_home
mkdir -p "$(dirname "$(CL)")"
ln -s "$OTHER/SKILL.md" "$(CL)"
rx "파일을 가리키는 링크: 중단" 1 "$INS" --claude
rx "doctor: 파일을 가리키는 링크는 실패" 1 "$DOC" --claude
rx "파일을 가리키는 링크: --force 로 교체" 0 "$INS" --claude --force
assert_eq "파일 링크 교체 후 이 저장소를 가리킴" "$A_SRC" "$(lnk "$(CL)")"

# ---------------------------------------------------------------- 충돌: 깨진 링크
new_home
mkdir -p "$(dirname "$(CL)")"
ln -s "$GONE" "$(CL)"
rx "깨진 링크 충돌: 중단(종료 코드 1)" 1 "$INS" --claude
assert_contains "깨진 링크 경고" "$LAST_OUT" "깨진 링크"
assert_eq "깨진 링크 유지" "$GONE" "$(lnk "$(CL)")"
rx "doctor: 깨진 링크 감지(종료 코드 1)" 1 "$DOC"
assert_contains "doctor: 깨진 링크 FAIL" "$LAST_OUT" "FAIL  Claude Code: 깨진 링크"
assert_contains "doctor: install.sh --force 안내" "$LAST_OUT" "scripts/install.sh' --force --claude"
rx "깨진 링크: uninstall 은 그대로 둠(종료 코드 1)" 1 "$UNI" --claude
assert_eq "uninstall 뒤에도 깨진 링크 유지" "$GONE" "$(lnk "$(CL)")"
rx "깨진 링크: --force 로 교체" 0 "$INS" --claude --force
assert_eq "깨진 링크 교체 후 이 저장소를 가리킴" "$A_SRC" "$(lnk "$(CL)")"
assert_eq "깨진 링크 교체가 원래 대상 경로를 만들지 않음" none "$(kind "$GONE")"

# ---------------------------------------------------------------- 저장소 이동
new_home
M1="$TEST_ROOT/work/move src"
M2="$TEST_ROOT/work/move dst"
make_repo "$M1"
rx "이동 전 설치" 0 "$M1/scripts/install.sh"
mv "$M1" "$M2"
rx "저장소 이동 후 doctor: 깨진 링크로 실패" 1 "$M2/scripts/doctor.sh"
assert_contains "이동 후 doctor: Codex 깨진 링크" "$LAST_OUT" "FAIL  Codex: 깨진 링크"
assert_contains "이동 후 doctor: 새 위치의 install.sh --force 안내" "$LAST_OUT" "$M2/scripts/install.sh' --force --codex"
rx "이동 후 --force 없이 install 은 중단" 1 "$M2/scripts/install.sh"
rx "이동 후 install --force 로 재연결" 0 "$M2/scripts/install.sh" --force
assert_eq "재연결: Codex 링크" "$M2/skills/code-sentinel" "$(lnk "$(CX)")"
assert_eq "재연결: Claude 링크" "$M2/skills/code-sentinel" "$(lnk "$(CL)")"
rx "재연결 후 doctor 통과" 0 "$M2/scripts/doctor.sh"
assert_not_contains "재연결 후 doctor 에 FAIL 없음" "$LAST_OUT" "FAIL  "

# ---------------------------------------------------------------- CLAUDE_CONFIG_DIR
new_home
export CLAUDE_CONFIG_DIR="$HOME/alt claude dir"
rx "CLAUDE_CONFIG_DIR 변경 후 Claude 설치" 0 "$INS" --claude
assert_eq "CLAUDE_CONFIG_DIR 아래에 링크 생성" "$A_SRC" "$(lnk "$CLAUDE_CONFIG_DIR/skills/code-sentinel")"
assert_eq "CLAUDE_CONFIG_DIR 를 쓰면 ~/.claude 를 만들지 않음" none "$(kind "$HOME/.claude")"
rx "doctor 가 CLAUDE_CONFIG_DIR 경로를 점검" 0 "$DOC" --claude
assert_contains "doctor: CLAUDE_CONFIG_DIR 경로 정상" "$LAST_OUT" "PASS  Claude Code: 정상 ($CLAUDE_CONFIG_DIR/skills/code-sentinel"
rx "CLAUDE_CONFIG_DIR 경로에서 제거" 0 "$UNI" --claude
assert_eq "CLAUDE_CONFIG_DIR 경로 링크 제거됨" none "$(kind "$CLAUDE_CONFIG_DIR/skills/code-sentinel")"
unset CLAUDE_CONFIG_DIR
rx "CLAUDE_CONFIG_DIR 미설정이면 ~/.claude 에 설치" 0 "$INS" --claude
assert_eq "미설정: ~/.claude/skills/code-sentinel" "$A_SRC" "$(lnk "$HOME/.claude/skills/code-sentinel")"
export CLAUDE_CONFIG_DIR="$HOME/.claude"

# ---------------------------------------------------------------- --dry-run
new_home
before=$(home_tree)
rx "--dry-run 설치 성공" 0 "$INS" --dry-run
assert_contains "--dry-run: 할 일 출력" "$LAST_OUT" "[dry-run]"
assert_eq "--dry-run 설치가 HOME 을 바꾸지 않음" "$before" "$(home_tree)"
mkdir -p "$(dirname "$(CX)")"
ln -s "$OTHER" "$(CX)"
before=$(home_tree)
rx "--dry-run --force (다른 경로 링크) 성공" 0 "$INS" --codex --force --dry-run
assert_contains "--dry-run --force: 교체 예정 출력" "$LAST_OUT" "기존 링크 삭제"
assert_eq "--dry-run --force 가 HOME 을 바꾸지 않음" "$before" "$(home_tree)"
assert_eq "--dry-run --force 뒤에도 다른 경로 링크 유지" "$OTHER" "$(lnk "$(CX)")"
rx "--dry-run 도 충돌이면 종료 코드 1" 1 "$INS" --codex --dry-run
assert_eq "--dry-run 충돌이 HOME 을 바꾸지 않음" "$before" "$(home_tree)"
rx "Claude 설치(dry-run 제거 준비)" 0 "$INS" --claude
before=$(home_tree)
rx "--dry-run 제거 성공" 0 "$UNI" --claude --dry-run
assert_contains "--dry-run 제거: 할 일 출력" "$LAST_OUT" "[dry-run]"
assert_eq "--dry-run 제거가 HOME 을 바꾸지 않음" "$before" "$(home_tree)"
assert_eq "--dry-run 제거 뒤에도 링크 유지" "$A_SRC" "$(lnk "$(CL)")"

# ---------------------------------------------------------------- 다른 위치에서 실행
new_home
rx "다른 cwd 에서 절대 경로로 설치" 0 in_dir "$TEST_ROOT/elsewhere" "$INS" --codex
assert_eq "다른 cwd: Codex 링크" "$A_SRC" "$(lnk "$(CX)")"
rx "다른 cwd 에서 상대 경로로 설치" 0 in_dir "$TEST_ROOT/work" "./repo A/scripts/install.sh" --claude
assert_eq "상대 경로 실행도 절대 경로 링크" "$A_SRC" "$(lnk "$(CL)")"
rx "scripts 디렉터리 안에서 /bin/bash install.sh" 0 in_dir "$A/scripts" /bin/bash install.sh
assert_contains "scripts 안 실행: 이미 설치됨" "$LAST_OUT" "이미 설치됨"
rx "다른 cwd 에서 doctor" 0 in_dir "$TEST_ROOT/elsewhere" "$DOC"
rx "다른 cwd 에서 제거" 0 in_dir "$TEST_ROOT/elsewhere" "$UNI"
assert_eq "다른 cwd 제거: 두 경로 모두 없음" "none none" "$(kind "$(CX)") $(kind "$(CL)")"
assert_eq "다른 cwd 실행이 cwd 에 아무것도 만들지 않음" "" "$(ls -A "$TEST_ROOT/elsewhere")"

# ---------------------------------------------------------------- doctor: frontmatter
new_home
F="$TEST_ROOT/work/fm repo"
make_repo "$F"
FMD="$F/skills/code-sentinel/SKILL.md"
FDOC="$F/scripts/doctor.sh"
set_skill() { printf '%s\n' "$@" >"$FMD"; }

rx "frontmatter 정상: doctor 통과(미설치는 경고)" 0 "$FDOC"
assert_contains "frontmatter 정상: name PASS" "$LAST_OUT" "PASS  SKILL.md name: code-sentinel"
assert_contains "frontmatter 정상: description PASS" "$LAST_OUT" "PASS  SKILL.md description:"
assert_contains "미설치 상태 표시" "$LAST_OUT" "WARN  Codex: 미설치"

set_skill '---' 'name: code-sentinal' 'description: x' '---'
rx "frontmatter: name 불일치 → 실패" 1 "$FDOC"
assert_contains "name 불일치 FAIL" "$LAST_OUT" "FAIL  SKILL.md frontmatter: name 이 'code-sentinel' 이 아닙니다: 'code-sentinal'"

set_skill '---' 'description: x' '---'
rx "frontmatter: name 없음 → 실패" 1 "$FDOC"
assert_contains "name 없음 FAIL" "$LAST_OUT" "FAIL  SKILL.md frontmatter: name 이 없습니다"

set_skill '---' 'name: code-sentinel' '---'
rx "frontmatter: description 없음 → 실패" 1 "$FDOC"
assert_contains "description 없음 FAIL" "$LAST_OUT" "FAIL  SKILL.md frontmatter: description 이 없거나 비어 있습니다"

set_skill '---' 'name: code-sentinel' 'description: ""' '---'
rx "frontmatter: description 빈 문자열 → 실패" 1 "$FDOC"
assert_contains "description 빈 문자열 FAIL" "$LAST_OUT" "description 이 없거나 비어 있습니다"

LONG1025=$(printf '%*s' 1025 '' | tr ' ' 'a')
set_skill '---' 'name: code-sentinel' "description: $LONG1025" '---'
rx "frontmatter: description 1025자 → 실패" 1 "$FDOC"
assert_contains "description 1025자 FAIL" "$LAST_OUT" "FAIL  SKILL.md frontmatter: description 이 너무 깁니다 (1025자"

set_skill '---' 'name: code-sentinel' "description: ${LONG1025%a}" '---'
rx "frontmatter: description 1024자 → 통과" 0 "$FDOC"
assert_contains "description 1024자 PASS" "$LAST_OUT" "PASS  SKILL.md description: 1024자"

KO=""
i=0
while [ "$i" -lt 100 ]; do
	KO="${KO}가나다라마바"
	i=$((i + 1))
done
set_skill '---' 'name: code-sentinel' "description: $KO" '---'
rx "frontmatter: 한글 600자(1800바이트) → 통과(문자 수로 셈)" 0 "$FDOC"
assert_contains "한글 description 600자" "$LAST_OUT" "PASS  SKILL.md description: 600자"

set_skill '---' 'name: "code-sentinel"' 'description: >' '  Line one' '  line two' '---'
rx "frontmatter: 따옴표 name, 블록 스칼라 description → 통과" 0 "$FDOC"
assert_contains "블록 스칼라 description 길이" "$LAST_OUT" "PASS  SKILL.md description: 17자"

printf -- '---\r\nname: code-sentinel\r\ndescription: crlf\r\n---\r\n' >"$FMD"
rx "frontmatter: CRLF 줄바꿈 → 통과" 0 "$FDOC"
assert_contains "CRLF name PASS" "$LAST_OUT" "PASS  SKILL.md name: code-sentinel"

set_skill '# code-sentinel' '---' 'name: code-sentinel' 'description: x' '---'
rx "frontmatter: 첫 줄이 --- 가 아님 → 실패" 1 "$FDOC"
assert_contains "frontmatter 시작 없음 FAIL" "$LAST_OUT" "FAIL  SKILL.md frontmatter: 첫 줄이 '---' 가 아닙니다"

set_skill '---' 'name: code-sentinel' 'description: x' '' '# body'
rx "frontmatter: 닫는 --- 없음 → 실패" 1 "$FDOC"
assert_contains "frontmatter 닫힘 없음 FAIL" "$LAST_OUT" "FAIL  SKILL.md frontmatter: 닫는 '---' 줄이 없습니다"

set_skill '---' 'name: code-sentinel' 'description: x' 'allowed-tools: Bash' '---'
rx "frontmatter: 추가 키는 경고(실패 아님)" 0 "$FDOC"
assert_contains "추가 키 WARN" "$LAST_OUT" "WARN  SKILL.md frontmatter: name, description 외의 키가 있습니다: allowed-tools"

rm -f "$FMD"
rx "SKILL.md 없음 → 실패" 1 "$FDOC"
assert_contains "SKILL.md 없음 FAIL" "$LAST_OUT" "FAIL  SKILL.md 가 없습니다"
rx "SKILL.md 없으면 install 도 중단" 1 "$F/scripts/install.sh"
assert_eq "SKILL.md 없을 때 아무것도 설치하지 않음" "." "$(home_names)"
set_skill "$SKILL_OK"

# ---------------------------------------------------------------- doctor: 스크립트 점검
chmod 644 "$F/skills/code-sentinel/scripts/cleanup-context.sh"
rx "실행 권한 없는 스킬 스크립트 → 실패" 1 "$FDOC"
assert_contains "실행 권한 FAIL" "$LAST_OUT" "FAIL  실행 권한이 없습니다: skills/code-sentinel/scripts/cleanup-context.sh"
chmod 755 "$F/skills/code-sentinel/scripts/cleanup-context.sh"

mv "$F/skills/code-sentinel/scripts/run-verification.sh" "$F/run-verification.sh.bak"
rx "필수 스킬 스크립트 없음 → 실패" 1 "$FDOC"
assert_contains "필수 스크립트 FAIL" "$LAST_OUT" "FAIL  스킬 스크립트가 없습니다: skills/code-sentinel/scripts/run-verification.sh"
mv "$F/run-verification.sh.bak" "$F/skills/code-sentinel/scripts/run-verification.sh"

mkdir -p "$F/tests/sub dir"
printf '#!/bin/bash\nif then fi (\n' >"$F/tests/sub dir/broken.sh"
rx "문법 오류 .sh → 실패" 1 "$FDOC"
assert_contains "bash -n FAIL" "$LAST_OUT" "FAIL  /bin/bash -n 실패: tests/sub dir/broken.sh"
rm -f "$F/tests/sub dir/broken.sh"
rx "문법 오류 제거 후 통과" 0 "$FDOC"
assert_contains "bash -n PASS" "$LAST_OUT" "PASS  /bin/bash -n: .sh 파일"

# ---------------------------------------------------------------- doctor: 버전·도구
assert_contains "Git 저장소가 아니면 버전 unknown" "$LAST_OUT" "저장소 버전: unknown"
assert_contains "/bin/bash 버전 표시" "$LAST_OUT" "PASS  /bin/bash: "
case "$LAST_OUT" in
*"PASS  git: "* | *"WARN  git: "*) pass "git 버전 표시" ;;
*) fail "git 버전 표시" "git 줄 없음" ;;
esac

new_repo "$F"
rx "커밋 없는 저장소: doctor 통과" 0 "$FDOC"
assert_contains "커밋 없으면 버전 unknown" "$LAST_OUT" "저장소 버전: unknown"
(cd "$F" && gcommit init && git tag v9.8.7)
rx "태그 있는 저장소: doctor 통과" 0 "$FDOC"
assert_contains "git describe 버전 표시" "$LAST_OUT" "PASS  저장소 버전: v9.8.7"

P="$TEST_ROOT/work/parent repo"
new_repo "$P"
(cd "$P" && gcommit parent && git tag v0.0.1)
make_repo "$P/nested"
rx "상위 저장소 안에 놓인 복사본: doctor 통과" 0 "$P/nested/scripts/doctor.sh"
assert_contains "상위 저장소의 버전을 쓰지 않음" "$LAST_OUT" "저장소 버전: unknown"

FAKEBIN="$TEST_ROOT/fakebin"
mkdir -p "$FAKEBIN"
# 실제 gh 처럼 텔레메트리가 켜져 있으면 HOME 에 상태 파일을 쓴다(doctor 는 이를 꺼야 함).
printf '%s\n' '#!/bin/bash' \
	'case "${GH_TELEMETRY:-}" in 0 | false) ;; *) mkdir -p "$HOME/.local/state/gh" && echo x >"$HOME/.local/state/gh/device-id" ;; esac' \
	'case "$1" in' '--version) echo "gh version 9.9.9 (fake)" ;;' \
	'auth) [ "${FAKE_GH_AUTH:-ok}" = ok ] && exit 0; echo "not logged in" >&2; exit 1 ;;' 'esac' 'exit 0' >"$FAKEBIN/gh"
printf '%s\n' '#!/bin/bash' 'echo "codex-cli 0.0.0-fake"' >"$FAKEBIN/codex"
chmod 755 "$FAKEBIN/gh" "$FAKEBIN/codex"

rx "PATH 에 codex·claude·gh 가 없어도 실패 아님" 0 "$DOC"
assert_contains "codex 없음 SKIP" "$LAST_OUT" "SKIP  codex: PATH 에 없음"
assert_contains "claude 없음 SKIP" "$LAST_OUT" "SKIP  claude: PATH 에 없음"
assert_contains "gh 없음 WARN" "$LAST_OUT" "WARN  gh: PATH 에 없음"
assert_contains "gh 없으면 auth SKIP" "$LAST_OUT" "SKIP  gh auth status"
before=$(home_tree)
rx "호출한 PATH 의 가짜 gh(인증됨)·codex 사용" 0 env PATH="$FAKEBIN:$PATH" FAKE_GH_AUTH=ok "$DOC"
assert_eq "doctor 가 gh 를 실행해도 HOME 을 바꾸지 않음" "$before" "$(home_tree)"
assert_contains "가짜 gh 감지" "$LAST_OUT" "PASS  gh: $FAKEBIN/gh (gh version 9.9.9 (fake))"
assert_contains "gh auth status 인증됨" "$LAST_OUT" "PASS  gh auth status: 인증됨"
assert_contains "가짜 codex 감지" "$LAST_OUT" "PASS  codex: $FAKEBIN/codex (codex-cli 0.0.0-fake)"
rx "gh 미인증도 실패 아님" 0 env PATH="$FAKEBIN:$PATH" FAKE_GH_AUTH=no "$DOC"
assert_contains "gh 미인증 WARN" "$LAST_OUT" "WARN  gh auth status"

# ---------------------------------------------------------------- doctor: 레거시 경로
new_home
rx "레거시 경로 없음" 0 "$DOC"
assert_contains "레거시 중복 없음 PASS" "$LAST_OUT" "PASS  레거시 경로 중복 없음: $HOME/.codex/skills/code-sentinel"
mkdir -p "$HOME/.codex/skills/code-sentinel"
printf 'legacy\n' >"$HOME/.codex/skills/code-sentinel/SKILL.md"
before=$(home_tree)
rx "레거시 중복은 경고(실패 아님)" 0 "$DOC"
# shellcheck disable=SC2088 # 테스트 이름의 ~는 표시용 문자열
assert_contains "~/.codex/skills 중복 WARN" "$LAST_OUT" "WARN  레거시 경로에 같은 이름의 스킬이 있습니다: $HOME/.codex/skills/code-sentinel (디렉터리)"
assert_eq "doctor 가 레거시 경로를 건드리지 않음" "$before" "$(home_tree)"
export CODEX_HOME="$HOME/codex home"
mkdir -p "$CODEX_HOME/skills"
ln -s "$OTHER" "$CODEX_HOME/skills/code-sentinel"
rx "CODEX_HOME 레거시 중복도 경고" 0 "$DOC"
assert_contains "\$CODEX_HOME/skills 중복 WARN" "$LAST_OUT" "WARN  레거시 경로에 같은 이름의 스킬이 있습니다: $CODEX_HOME/skills/code-sentinel (링크 -> $OTHER)"
# shellcheck disable=SC2088 # 테스트 이름의 ~는 표시용 문자열
assert_contains "~/.codex/skills 도 함께 점검" "$LAST_OUT" "$HOME/.codex/skills/code-sentinel (디렉터리)"
rx "레거시 중복이 있어도 install 은 ~/.agents 에만 설치" 0 "$INS" --codex
assert_eq "레거시 경로 유지" "legacy" "$(cat "$HOME/.codex/skills/code-sentinel/SKILL.md")"
assert_eq "CODEX_HOME 레거시 링크 유지" "$OTHER" "$(lnk "$CODEX_HOME/skills/code-sentinel")"
export CODEX_HOME="$HOME/.codex"

# ---------------------------------------------------------------- 실제 저장소 스크립트(임시 HOME)
if [ -f "$SKILL_DIR/SKILL.md" ]; then
	new_home
	rx "실제 저장소의 install.sh 로 임시 HOME 에 설치" 0 "$REPO_ROOT/scripts/install.sh"
	assert_eq "실제 저장소: Codex 링크" "$SKILL_DIR" "$(lnk "$(CX)")"
	assert_eq "실제 저장소: Claude 링크" "$SKILL_DIR" "$(lnk "$(CL)")"
	assert_eq "실제 저장소: 원본 안에 링크를 만들지 않음" none "$(kind "$SKILL_DIR/code-sentinel")"
	rx_any "실제 저장소의 doctor" "$REPO_ROOT/scripts/doctor.sh"
	assert_contains "실제 저장소 doctor: Codex 정상" "$LAST_OUT" "PASS  Codex: 정상"
	assert_contains "실제 저장소 doctor: Claude Code 정상" "$LAST_OUT" "PASS  Claude Code: 정상"
	rx "실제 저장소의 uninstall.sh 로 제거" 0 "$REPO_ROOT/scripts/uninstall.sh"
	assert_eq "실제 저장소: 제거 후 두 경로 없음" "none none" "$(kind "$(CX)") $(kind "$(CL)")"
else
	skip "실제 저장소 스크립트로 설치" "skills/code-sentinel/SKILL.md 가 아직 없음"
fi

# ---------------------------------------------------------------- 임시 HOME 밖 쓰기 없음
assert_eq "임시 HOME 밖(임시 디렉터리 전체)에 아무것도 쓰지 않음 (실행 ${N_RUNS}회)" "" "$OUTSIDE_BAD"
assert_eq "실제 HOME 의 대상·레거시 경로가 바뀌지 않음" "$REAL_SIG_BEFORE" "$(real_sig)"

finish
