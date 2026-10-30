#!/bin/bash
# scripts/uninstall.sh — install.sh 가 만든 code-sentinel 링크를 제거합니다.
#
# 사용법: scripts/uninstall.sh [--codex | --claude | --all] [--dry-run] [--force]
#
#   --codex    Codex 경로만        ${HOME}/.agents/skills/code-sentinel
#   --claude   Claude Code 경로만  ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/code-sentinel
#   --all      두 경로 모두(기본값)
#   --dry-run  아무것도 바꾸지 않고 할 일만 출력
#   --force    공통 옵션이라 받아들이지만 동작은 바뀌지 않습니다(안전을 위해).
#
# - 대상이 심볼릭 링크이고, 그 실제 경로(cd -P)가 이 저장소의 skills/code-sentinel 일 때만
#   링크 자체를 지웁니다. rm -r/-rf 는 쓰지 않습니다.
# - 그 밖의 경우(다른 경로·깨진 링크, 실제 디렉터리·파일)는 건드리지 않고 이유를 출력합니다.
# - 설치되어 있지 않으면 성공으로 끝납니다. 부모 디렉터리는 지우지 않습니다.
#
# 종료 코드: 0 제거함 또는 설치되어 있지 않음 · 1 건드리지 않고 남겨 둔 항목이 있음 · 2 사용법·환경 오류

set -euo pipefail
unset CDPATH

SKILL_NAME=code-sentinel
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SRC="$REPO_ROOT/skills/$SKILL_NAME"

say() { printf '%s\n' "$*"; }
warn() { printf '경고: %s\n' "$*" >&2; }
err() { printf '오류: %s\n' "$*" >&2; }

usage() {
	printf '%s\n' \
		'사용법: scripts/uninstall.sh [--codex | --claude | --all] [--dry-run] [--force]' \
		'' \
		'  --codex    Codex 경로만        ${HOME}/.agents/skills/code-sentinel' \
		'  --claude   Claude Code 경로만  ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/code-sentinel' \
		'  --all      두 경로 모두(기본값)' \
		'  --dry-run  아무것도 바꾸지 않고 할 일만 출력' \
		'  --force    받아들이지만 동작은 같음(이 저장소를 가리키는 링크만 지움)'
}

WANT_CODEX=0
WANT_CLAUDE=0
DRY_RUN=0
FORCE=0
while [ $# -gt 0 ]; do
	case "$1" in
	--codex) WANT_CODEX=1 ;;
	--claude) WANT_CLAUDE=1 ;;
	--all)
		WANT_CODEX=1
		WANT_CLAUDE=1
		;;
	--dry-run) DRY_RUN=1 ;;
	--force) FORCE=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		err "알 수 없는 옵션: $1"
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
if [ "$FORCE" -eq 1 ]; then
	say "참고: uninstall 의 --force 는 동작을 바꾸지 않습니다. 이 저장소를 가리키는 링크만 지웁니다."
fi

case "${HOME:-}" in
/?*) ;;
*)
	err "HOME 이 비어 있거나 절대 경로가 아닙니다: '${HOME:-}'"
	exit 2
	;;
esac
CLAUDE_BASE=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
if [ "$WANT_CLAUDE" -eq 1 ]; then
	case "$CLAUDE_BASE" in
	/?*) ;;
	*)
		err "CLAUDE_CONFIG_DIR 는 절대 경로여야 합니다: '$CLAUDE_BASE'"
		exit 2
		;;
	esac
fi
CODEX_T="${HOME%/}/.agents/skills/$SKILL_NAME"
CLAUDE_T="${CLAUDE_BASE%/}/skills/$SKILL_NAME"

LEFT=0
REMOVED=0

# remove_one <라벨> <대상>
remove_one() {
	local label=$1 t=$2 lt phys
	if [ -L "$t" ]; then
		lt=$(readlink "$t" 2>/dev/null || true)
		phys=""
		if [ -e "$t" ]; then
			phys=$(cd -P "$t" 2>/dev/null && pwd -P) || phys=""
		fi
		if [ -n "$phys" ] && [ "$phys" = "$SRC" ]; then
			if [ "$DRY_RUN" -eq 1 ]; then
				say "[dry-run] $label: 링크 삭제: $t -> $lt"
				return 0
			fi
			# 링크 자체만 지운다(-r 없음). 링크 대상은 건드리지 않는다.
			if ! rm "$t" || [ -L "$t" ] || [ -e "$t" ]; then
				err "$label: 링크를 지우지 못했습니다: $t"
				LEFT=1
				return 0
			fi
			say "$label: 제거함 ($t)"
			REMOVED=1
		elif [ ! -e "$t" ]; then
			warn "$label: 깨진 링크라 이 저장소의 설치인지 확인할 수 없어 그대로 둡니다: $t -> $lt"
			warn "  확인한 뒤 링크만 직접 지우거나(rm, -r 없이), 새 위치에서 install.sh --force 로 다시 연결하세요."
			LEFT=1
		elif [ -z "$phys" ]; then
			warn "$label: 링크 대상에 접근할 수 없어 그대로 둡니다: $t -> $lt"
			LEFT=1
		else
			warn "$label: 이 저장소가 아닌 경로를 가리키는 링크라 그대로 둡니다: $t -> $lt"
			LEFT=1
		fi
	elif [ -d "$t" ]; then
		warn "$label: 링크가 아닌 실제 디렉터리라 건드리지 않습니다: $t"
		warn "  uninstall 은 install.sh 가 만든 링크만 지웁니다. 필요하면 내용을 확인한 뒤 직접 정리하세요."
		LEFT=1
	elif [ -e "$t" ]; then
		warn "$label: 링크가 아닌 실제 파일이라 건드리지 않습니다: $t"
		LEFT=1
	else
		say "$label: 설치되어 있지 않습니다 ($t)"
	fi
}

if [ "$WANT_CODEX" -eq 1 ] && [ "$WANT_CLAUDE" -eq 1 ] && [ "$CODEX_T" = "$CLAUDE_T" ]; then
	remove_one "Codex·Claude Code" "$CODEX_T"
else
	if [ "$WANT_CODEX" -eq 1 ]; then remove_one Codex "$CODEX_T"; fi
	if [ "$WANT_CLAUDE" -eq 1 ]; then remove_one "Claude Code" "$CLAUDE_T"; fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
	say "--dry-run: 아무것도 바꾸지 않았습니다."
fi
if [ "$REMOVED" -eq 1 ]; then
	say "실행 중인 세션에는 스킬이 남아 있을 수 있습니다. 세션을 재시작하세요."
fi
if [ "$LEFT" -eq 1 ]; then
	exit 1
fi
exit 0
