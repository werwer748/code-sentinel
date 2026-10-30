#!/bin/bash
# cleanup-context.sh — code-sentinel 임시 디렉터리를 검증한 뒤에만 삭제합니다.
#
# 사용법:
#   cleanup-context.sh <context_dir>
#   cleanup-context.sh --stale [<분>]      (기본 1440분)
#
# 삭제 조건 (SPEC §6, 모두 만족해야 함):
#   1. 인자가 정확히 1개, 비어 있지 않은 절대 경로, `..` 경로 요소·제어문자 없음(공백 허용)
#   2. 인자 자체가 심볼릭 링크가 아님
#   3. `cd -P` + `pwd -P`로 얻은 실제 경로가, 같은 방식으로 정규화한
#      ${TMPDIR:-/tmp} 또는 /tmp 의 바로 아래 디렉터리임
#   4. 디렉터리 이름이 `code-sentinel.` + 영숫자 접미어 형식임
#   5. 마커 `.code-sentinel-context`가 일반 파일(링크 아님)이고 형식이 정확함
#        created_at <epoch 초>
#        pid <pid>
#        token <소문자 hex 32자>
#   6. 디렉터리(와 마커)의 소유자가 현재 사용자임
#
# 종료 코드:
#   0  삭제함(또는 이미 없음), --stale 은 실패 없이 끝남
#   1  검증 거부(아무것도 지우지 않음)
#   2  사용법 오류
#   3  삭제를 시도했지만 일부가 남음(남은 경로 출력)
#
# 경로 정규화는 cd -P 와 pwd -P 로만 합니다. 사용자 파일을 복구하거나 다른 경로를 지우지 않습니다.

set -euo pipefail
export LC_ALL=C

PROG=cleanup-context.sh
MARKER=.code-sentinel-context
PREFIX=code-sentinel.
DEFAULT_STALE_MIN=1440
MAX_MARKER_BYTES=256

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
	err "사용법: $PROG <context_dir> | $PROG --stale [<분>]"
	err "다음 행동: collect-context.sh 매니페스트의 context_dir 값을 그대로 넘기세요."
	exit 2
}

# 디렉터리를 물리 경로로 정규화한다. 실패하면 빈 문자열.
phys_dir() {
	(cd -P -- "$1" 2>/dev/null && pwd -P) 2>/dev/null || true
}

# 허용되는 부모(임시 디렉터리) 목록: ${TMPDIR:-/tmp}, /tmp 를 물리 경로로.
TMP_ROOT_1=$(phys_dir "${TMPDIR:-/tmp}")
TMP_ROOT_2=$(phys_dir /tmp)

is_tmp_root() {
	[ -n "$1" ] || return 1
	if [ -n "$TMP_ROOT_1" ] && [ "$1" = "$TMP_ROOT_1" ]; then return 0; fi
	if [ -n "$TMP_ROOT_2" ] && [ "$1" = "$TMP_ROOT_2" ]; then return 0; fi
	return 1
}

# 이름 형식: code-sentinel.<영숫자 1자 이상>
valid_name() {
	local n=$1 suffix
	case "$n" in
	"$PREFIX"*) ;;
	*) return 1 ;;
	esac
	suffix=${n#"$PREFIX"}
	[ -n "$suffix" ] || return 1
	case "$suffix" in
	*[!A-Za-z0-9]*) return 1 ;;
	esac
	return 0
}

# 인자 문자열 검사(조건 1). 실패 사유는 REASON 에 남긴다.
REASON=""
check_arg_syntax() {
	local a=$1 rest seg
	if [ -z "$a" ]; then REASON="빈 인자"; return 1; fi
	case "$a" in
	/*) ;;
	*) REASON="절대 경로가 아님"; return 1 ;;
	esac
	case "$a" in
	*[[:cntrl:]]*) REASON="제어문자 포함"; return 1 ;;
	esac
	rest=$a
	while [ -n "$rest" ]; do
		seg=${rest%%/*}
		if [ "$seg" = ".." ]; then REASON="'..' 경로 요소 포함"; return 1; fi
		case "$rest" in
		*/*) rest=${rest#*/} ;;
		*) rest="" ;;
		esac
	done
	return 0
}

# 마커 형식 검사(조건 5)
check_marker() {
	local m=$1/$MARKER size n=0 line ok=1
	if [ -L "$m" ]; then REASON="마커가 심볼릭 링크임"; return 1; fi
	if [ ! -f "$m" ]; then
		if [ -e "$m" ]; then REASON="마커가 일반 파일이 아님"; else REASON="마커 파일 없음"; fi
		return 1
	fi
	size=$(wc -c <"$m" | tr -d ' ')
	case "$size" in '' | *[!0-9]*) REASON="마커 크기 확인 실패"; return 1 ;; esac
	if [ "$size" -gt "$MAX_MARKER_BYTES" ]; then REASON="마커 크기 이상"; return 1; fi
	MARKER_CREATED=""
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		case "$n:$line" in
		1:"created_at "*)
			MARKER_CREATED=${line#created_at }
			case "$MARKER_CREATED" in '' | *[!0-9]*) ok=0 ;; esac
			;;
		2:"pid "*)
			case "${line#pid }" in '' | *[!0-9]*) ok=0 ;; esac
			;;
		3:"token "*)
			local tok=${line#token }
			if [ "${#tok}" -ne 32 ]; then ok=0; fi
			case "$tok" in *[!0-9a-f]*) ok=0 ;; esac
			;;
		*) ok=0 ;;
		esac
	done <"$m"
	if [ "$n" -ne 3 ] || [ "$ok" -ne 1 ]; then REASON="마커 형식이 맞지 않음"; return 1; fi
	return 0
}

# 경로 전체 검증(조건 1~6). 통과하면 VALID_PATH 에 실제 경로를 남긴다.
VALID_PATH=""
MARKER_CREATED=""
validate() {
	local a=$1 trimmed phys parent base uid owner
	VALID_PATH=""
	check_arg_syntax "$a" || return 1
	# 끝의 / 를 떼고 링크 여부를 본다("link/" 는 -L 이 링크를 따라가므로).
	trimmed=$a
	while [ "${#trimmed}" -gt 1 ] && [ "${trimmed%/}" != "$trimmed" ]; do trimmed=${trimmed%/}; done
	if [ -L "$trimmed" ]; then REASON="인자가 심볼릭 링크임"; return 1; fi
	if [ ! -d "$trimmed" ]; then
		if [ -e "$trimmed" ]; then REASON="디렉터리가 아님"; else REASON="경로가 없음"; fi
		return 1
	fi
	phys=$(phys_dir "$trimmed")
	if [ -z "$phys" ]; then REASON="실제 경로를 구할 수 없음"; return 1; fi
	if [ "$phys" = "/" ]; then REASON="루트 디렉터리"; return 1; fi
	parent=${phys%/*}
	[ -n "$parent" ] || parent=/
	base=${phys##*/}
	if ! is_tmp_root "$parent"; then REASON="임시 디렉터리(\${TMPDIR:-/tmp} 또는 /tmp)의 바로 아래가 아님"; return 1; fi
	if ! valid_name "$base"; then REASON="이름이 code-sentinel.XXXXXX 형식이 아님"; return 1; fi
	check_marker "$phys" || return 1
	uid=$(id -u)
	owner=$(stat -f '%u' "$phys" 2>/dev/null || true)
	if [ "$owner" != "$uid" ]; then REASON="현재 사용자 소유가 아님"; return 1; fi
	owner=$(stat -f '%u' "$phys/$MARKER" 2>/dev/null || true)
	if [ "$owner" != "$uid" ]; then REASON="마커가 현재 사용자 소유가 아님"; return 1; fi
	VALID_PATH=$phys
	return 0
}

# 검증된 실제 경로를 삭제한다. 실패하면 남은 경로를 출력한다.
# 마커는 마지막에 지운다. 일부만 지워진 경우에도 마커가 남아 있어 다시 정리할 수 있다.
remove_validated() {
	local p=$1 e
	for e in "$p"/* "$p"/.[!.]* "$p"/..?*; do
		[ -e "$e" ] || [ -L "$e" ] || continue
		[ "$e" = "$p/$MARKER" ] && continue
		rm -rf -- "$e" 2>/dev/null || true
	done
	for e in "$p"/* "$p"/.[!.]* "$p"/..?*; do
		[ -e "$e" ] || [ -L "$e" ] || continue
		[ "$e" = "$p/$MARKER" ] && continue
		err "정리 실패: 일부 파일을 지우지 못했습니다(마커는 남겨 다시 정리할 수 있음)."
		printf '남은 경로: %s\n' "$p"
		return 1
	done
	rm -f -- "$p/$MARKER" 2>/dev/null || true
	rmdir -- "$p" 2>/dev/null || true
	if [ -e "$p" ] || [ -L "$p" ]; then
		err "정리 실패: 일부 파일을 지우지 못했습니다."
		printf '남은 경로: %s\n' "$p"
		return 1
	fi
	printf '삭제함: %s\n' "$p"
	return 0
}

# 존재하지 않는 경로가 '이미 정리된 code-sentinel 디렉터리'인지 확인(부모·이름 검증)
already_gone() {
	local a=$1 trimmed parent_arg parent base
	trimmed=$a
	while [ "${#trimmed}" -gt 1 ] && [ "${trimmed%/}" != "$trimmed" ]; do trimmed=${trimmed%/}; done
	[ -e "$trimmed" ] && return 1
	[ -L "$trimmed" ] && return 1
	base=${trimmed##*/}
	parent_arg=${trimmed%/*}
	[ -n "$parent_arg" ] || parent_arg=/
	parent=$(phys_dir "$parent_arg")
	is_tmp_root "$parent" || return 1
	valid_name "$base" || return 1
	return 0
}

cleanup_one() {
	local a=$1
	if validate "$a"; then
		remove_validated "$VALID_PATH" || return 3
		return 0
	fi
	if check_arg_syntax "$a" && already_gone "$a"; then
		printf '이미 없음: %s\n' "$a"
		return 0
	fi
	err "삭제 거부: $REASON"
	err "다음 행동: collect-context.sh 가 출력한 context_dir 경로인지 확인하세요. 다른 경로는 지우지 않습니다."
	return 1
}

cleanup_stale() {
	local minutes=$1 now cutoff root seen="" d failed=0 removed=0 kept=0
	now=$(date +%s)
	cutoff=$((now - minutes * 60))
	for root in "$TMP_ROOT_1" "$TMP_ROOT_2"; do
		[ -n "$root" ] || continue
		[ "$root" = "$seen" ] && continue
		seen=$root
		for d in "$root"/"$PREFIX"*; do
			[ -e "$d" ] || [ -L "$d" ] || continue
			if ! validate "$d"; then
				err "건너뜀: $d ($REASON)"
				kept=$((kept + 1))
				continue
			fi
			if [ "$MARKER_CREATED" -lt "$cutoff" ]; then
				if remove_validated "$VALID_PATH"; then removed=$((removed + 1)); else failed=$((failed + 1)); fi
			else
				kept=$((kept + 1))
			fi
		done
	done
	printf '정리 결과: 삭제 %d · 유지 %d · 실패 %d (기준 %d분)\n' "$removed" "$kept" "$failed" "$minutes"
	[ "$failed" -eq 0 ] || return 3
	return 0
}

main() {
	if [ $# -eq 0 ]; then usage; fi
	case "$1" in
	--stale)
		local minutes=$DEFAULT_STALE_MIN
		if [ $# -ge 2 ]; then minutes=$2; fi
		if [ $# -gt 2 ]; then usage; fi
		case "$minutes" in '' | *[!0-9]*) err "--stale 값은 0 이상의 정수(분)여야 합니다: $minutes"; exit 2 ;; esac
		# 앞자리 0 제거(8진수 해석 방지)
		minutes=$((10#$minutes))
		cleanup_stale "$minutes"
		;;
	-h | --help)
		usage
		;;
	*)
		if [ $# -ne 1 ]; then
			err "인자는 정확히 1개여야 합니다(받은 개수: $#)."
			usage
		fi
		cleanup_one "$1"
		;;
	esac
}

main "$@"
