#!/bin/bash
# scripts/install.sh — code-sentinel 스킬을 Codex·Claude Code 사용자 스킬 경로에 심볼릭 링크로 설치합니다.
#
# 사용법: scripts/install.sh [--codex | --claude | --all] [--dry-run] [--force]
#
#   --codex    Codex 경로에만 설치        ${HOME}/.agents/skills/code-sentinel
#   --claude   Claude Code 경로에만 설치  ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/code-sentinel
#   --all      두 경로 모두 설치(기본값)
#   --dry-run  아무것도 바꾸지 않고 할 일만 출력
#   --force    다른 경로를 가리키는 링크(깨진 링크 포함)를 이 저장소 링크로 교체.
#              실제 디렉터리나 파일은 --force 여도 건드리지 않습니다.
#
# - 이 저장소의 skills/code-sentinel 디렉터리 하나만 절대 경로 링크로 겁니다.
# - 위 두 대상 경로(와 그 부모 디렉터리) 밖에는 아무것도 쓰지 않습니다.
# - 선택한 대상 중 하나라도 충돌하면 어떤 경로도 바꾸지 않고 중단합니다.
# - 테스트를 위해 HOME, CLAUDE_CONFIG_DIR 환경변수를 그대로 따릅니다.
#
# 종료 코드: 0 성공(이미 설치됨 포함) · 1 충돌·오류로 중단 · 2 사용법·환경 오류

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
		'사용법: scripts/install.sh [--codex | --claude | --all] [--dry-run] [--force]' \
		'' \
		'  --codex    Codex 경로에만 설치        ${HOME}/.agents/skills/code-sentinel' \
		'  --claude   Claude Code 경로에만 설치  ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/code-sentinel' \
		'  --all      두 경로 모두 설치(기본값)' \
		'  --dry-run  아무것도 바꾸지 않고 할 일만 출력' \
		'  --force    다른 경로를 가리키는 링크(깨진 링크 포함)를 이 저장소 링크로 교체' \
		'             (실제 디렉터리나 파일은 --force 여도 건드리지 않음)'
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

if [ ! -d "$SRC" ] || [ ! -f "$SRC/SKILL.md" ]; then
	err "스킬 원본이 없습니다: $SRC/SKILL.md"
	err "  저장소가 온전한지 확인하세요."
	exit 1
fi

# 대상 경로 상태: missing | ours | other | broken | real
target_state() {
	local p=$1 phys
	if [ -L "$p" ]; then
		if [ -e "$p" ]; then
			phys=$(cd -P "$p" 2>/dev/null && pwd -P) || phys=""
			if [ -n "$phys" ] && [ "$phys" = "$SRC" ]; then
				printf 'ours'
			else
				printf 'other'
			fi
		else
			printf 'broken'
		fi
	elif [ -e "$p" ]; then
		printf 'real'
	else
		printf 'missing'
	fi
}

# plan <라벨> <대상> : 아무것도 바꾸지 않고 할 일을 정한다.
#   R_ACTION: skip(이미 설치됨) | create | replace | block
#   R_MKDIR : 새로 만들어야 하는 부모 디렉터리(없으면 빈 값)
LINK_CONFLICT=0
plan() {
	local label=$1 t=$2 st lt parent anc
	R_ACTION=block
	R_MKDIR=""
	st=$(target_state "$t")
	case "$st" in
	ours)
		say "$label: 이미 설치됨 ($t -> $(readlink "$t" 2>/dev/null || true))"
		R_ACTION=skip
		;;
	missing)
		R_ACTION=create
		;;
	other | broken)
		lt=$(readlink "$t" 2>/dev/null || true)
		if [ "$FORCE" -eq 1 ]; then
			if [ "$st" = broken ]; then
				warn "$label: 깨진 링크를 이 저장소 링크로 교체합니다(--force): $t -> $lt"
			else
				warn "$label: 다른 경로를 가리키는 링크를 이 저장소 링크로 교체합니다(--force): $t -> $lt"
			fi
			R_ACTION=replace
		else
			if [ "$st" = broken ]; then
				warn "$label: 깨진 링크가 있습니다: $t -> $lt"
				warn "  저장소를 옮겼다면 --force 로 새 위치에 다시 연결할 수 있습니다."
			else
				warn "$label: 다른 경로를 가리키는 링크가 있습니다: $t -> $lt"
				warn "  이 저장소로 바꾸려면 --force 를 붙여 다시 실행하세요."
			fi
			LINK_CONFLICT=1
		fi
		;;
	real)
		if [ -d "$t" ]; then
			warn "$label: 링크가 아닌 실제 디렉터리가 있어 설치하지 않습니다: $t"
		else
			warn "$label: 링크가 아닌 실제 파일이 있어 설치하지 않습니다: $t"
		fi
		warn "  --force 여도 건드리지 않습니다. 내용을 확인한 뒤 직접 옮기거나 지우고 다시 실행하세요."
		;;
	esac

	if [ "$R_ACTION" = create ] || [ "$R_ACTION" = replace ]; then
		parent=$(dirname "$t")
		anc=$parent
		while [ ! -e "$anc" ] && [ ! -L "$anc" ]; do
			anc=$(dirname "$anc")
		done
		if [ ! -d "$anc" ]; then
			warn "$label: 상위 경로가 디렉터리가 아니라 설치할 수 없습니다: $anc"
			R_ACTION=block
		elif [ ! -w "$anc" ]; then
			warn "$label: 쓰기 권한이 없어 설치할 수 없습니다: $anc"
			R_ACTION=block
		elif [ "$anc" != "$parent" ]; then
			R_MKDIR=$parent
		fi
	fi
}

# apply <라벨> <대상> <동작> <만들 부모 디렉터리>
apply() {
	local label=$1 t=$2 action=$3 mk=$4
	if [ "$DRY_RUN" -eq 1 ]; then
		if [ -n "$mk" ]; then say "[dry-run] $label: 디렉터리 생성: $mk"; fi
		if [ "$action" = replace ]; then say "[dry-run] $label: 기존 링크 삭제: $t -> $(readlink "$t" 2>/dev/null || true)"; fi
		say "[dry-run] $label: 링크 생성: $t -> $SRC"
		return 0
	fi
	if [ -n "$mk" ]; then
		if ! mkdir -p "$mk"; then
			err "$label: 디렉터리를 만들 수 없습니다: $mk"
			exit 1
		fi
	fi
	if [ "$action" = replace ]; then
		# 링크 자체만 지운다(-r 없음). 그사이 링크가 아닌 것으로 바뀌었으면 중단.
		if [ ! -L "$t" ] || ! rm "$t"; then
			err "$label: 기존 링크를 지울 수 없습니다: $t"
			exit 1
		fi
	fi
	# 대상이 디렉터리면 ln -s 가 그 안에 링크를 만들므로 직전에 다시 확인한다.
	if [ -e "$t" ] || [ -L "$t" ]; then
		err "$label: 설치 중에 대상 경로가 생겼습니다. 다시 실행하세요: $t"
		exit 1
	fi
	if ! ln -s "$SRC" "$t"; then
		err "$label: 링크를 만들 수 없습니다: $t"
		exit 1
	fi
	if [ "$(target_state "$t")" != ours ]; then
		err "$label: 링크를 만들었지만 확인에 실패했습니다: $t"
		exit 1
	fi
	say "$label: 설치함 ($t -> $SRC)"
}

# 대상 목록. CLAUDE_CONFIG_DIR 설정으로 두 경로가 같아지면 한 번만 처리한다.
DO_CODEX=$WANT_CODEX
DO_CLAUDE=$WANT_CLAUDE
CODEX_LABEL=Codex
if [ "$DO_CODEX" -eq 1 ] && [ "$DO_CLAUDE" -eq 1 ] && [ "$CODEX_T" = "$CLAUDE_T" ]; then
	DO_CLAUDE=0
	CODEX_LABEL="Codex·Claude Code"
fi

BLOCKED=0
CODEX_ACTION=none
CODEX_MKDIR=""
CLAUDE_ACTION=none
CLAUDE_MKDIR=""
if [ "$DO_CODEX" -eq 1 ]; then
	plan "$CODEX_LABEL" "$CODEX_T"
	CODEX_ACTION=$R_ACTION
	CODEX_MKDIR=$R_MKDIR
	if [ "$R_ACTION" = block ]; then BLOCKED=1; fi
fi
if [ "$DO_CLAUDE" -eq 1 ]; then
	plan "Claude Code" "$CLAUDE_T"
	CLAUDE_ACTION=$R_ACTION
	CLAUDE_MKDIR=$R_MKDIR
	if [ "$R_ACTION" = block ]; then BLOCKED=1; fi
fi

if [ "$BLOCKED" -eq 1 ]; then
	err "충돌이 있어 아무것도 바꾸지 않고 중단합니다."
	if [ "$LINK_CONFLICT" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
		err "  링크 충돌만 있다면 --force 로 교체할 수 있습니다."
	fi
	if [ "$WANT_CODEX" -eq 1 ] && [ "$WANT_CLAUDE" -eq 1 ]; then
		err "  한쪽만 설치하려면 --codex 또는 --claude 를 지정하세요."
	fi
	exit 1
fi

INSTALLED_CODEX=0
INSTALLED_CLAUDE=0
case "$CODEX_ACTION" in
create | replace)
	apply "$CODEX_LABEL" "$CODEX_T" "$CODEX_ACTION" "$CODEX_MKDIR"
	INSTALLED_CODEX=1
	;;
esac
case "$CLAUDE_ACTION" in
create | replace)
	apply "Claude Code" "$CLAUDE_T" "$CLAUDE_ACTION" "$CLAUDE_MKDIR"
	INSTALLED_CLAUDE=1
	;;
esac
if [ "$CODEX_LABEL" != Codex ] && [ "$INSTALLED_CODEX" -eq 1 ]; then
	INSTALLED_CLAUDE=1
	CLAUDE_MKDIR=$CODEX_MKDIR
fi

if [ "$DRY_RUN" -eq 1 ]; then
	say "--dry-run: 아무것도 바꾸지 않았습니다."
	exit 0
fi

if [ "$INSTALLED_CODEX" -eq 0 ] && [ "$INSTALLED_CLAUDE" -eq 0 ]; then
	say "변경 없음: 이미 설치되어 있습니다."
	exit 0
fi

say ""
say "설치 완료."
say "- 실행 중인 세션은 재시작해야 반영될 수 있습니다."
if [ "$INSTALLED_CLAUDE" -eq 1 ]; then
	if [ -n "$CLAUDE_MKDIR" ]; then
		say "- Claude Code: 이번 설치에서 최상위 skills 디렉터리를 새로 만들었습니다($CLAUDE_MKDIR)."
		say "  그 전에 시작한 세션에서는 /reload-skills 를 실행해야 스킬이 보입니다(또는 세션 재시작)."
	else
		say "- Claude Code: 세션 시작 뒤에 최상위 skills 디렉터리가 새로 생겼다면 /reload-skills 를 실행하세요."
		say "  그래도 보이지 않으면 세션을 재시작하세요."
	fi
fi
if [ "$INSTALLED_CODEX" -eq 1 ]; then
	say "- Codex: 실행 중인 Codex 는 재시작해야 새 스킬을 읽습니다."
fi
say "- 업데이트는 저장소에서 git pull 만 하면 반영됩니다."
say "- 점검: $REPO_ROOT/scripts/doctor.sh"
