#!/bin/bash
# tests/run.sh — 전체 자동 테스트. macOS /bin/bash 3.2 로 실행한다.
#   /bin/bash tests/run.sh            전체 실행
#   /bin/bash tests/run.sh scope      test-scope.sh 만 실행
# 실패가 하나라도 있으면 0이 아닌 코드로 종료한다.

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
total_pass=0
total_fail=0
total_skip=0
failed_files=""

printf 'bash: %s (%s)\n' "$BASH_VERSION" "$BASH"
case "$BASH_VERSION" in
3.2.*) ;;
*) printf 'WARN  /bin/bash 3.2 가 아닌 셸에서 실행 중입니다: %s\n' "$BASH" ;;
esac

for f in "$here"/test-*.sh; do
	name=$(basename "$f" .sh)
	if [ $# -gt 0 ]; then
		want=0
		for a in "$@"; do [ "$name" = "test-$a" ] && want=1; done
		[ "$want" -eq 1 ] || continue
	fi
	printf '\n=== %s\n' "$name"
	out=$(/bin/bash "$f" 2>&1)
	rc=$?
	printf '%s\n' "$out"
	line=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "RESULT"' | tail -1)
	if [ -z "$line" ]; then
		printf 'FAIL  %s 가 결과 줄 없이 종료됨 (exit %d)\n' "$name" "$rc"
		total_fail=$((total_fail + 1))
		failed_files="$failed_files $name"
		continue
	fi
	p=$(printf '%s' "$line" | awk -F'\t' '{ sub("pass=", "", $3); print $3 }')
	x=$(printf '%s' "$line" | awk -F'\t' '{ sub("fail=", "", $4); print $4 }')
	s=$(printf '%s' "$line" | awk -F'\t' '{ sub("skip=", "", $5); print $5 }')
	total_pass=$((total_pass + p))
	total_fail=$((total_fail + x))
	total_skip=$((total_skip + s))
	if [ "$x" -gt 0 ] || [ "$rc" -ne 0 ]; then failed_files="$failed_files $name"; fi
done

printf '\n=== 합계: PASS %d · FAIL %d · SKIP %d\n' "$total_pass" "$total_fail" "$total_skip"
if [ -n "$failed_files" ]; then
	printf '실패한 테스트 파일:%s\n' "$failed_files"
	exit 1
fi
exit 0
