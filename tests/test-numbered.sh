#!/bin/bash
# test-numbered.sh — collect-context.sh 의 줄 번호 diff(numbered_diff_file)
# 보고서 위치는 이 파일의 번호 열에서 가져오므로, 번호가 실제 파일 줄과 맞는지 범위별로 확인한다.
. "$(dirname "$0")/lib.sh"
setup_sandbox

M="$TEST_ROOT/manifest.txt"
FIX="$REPO_ROOT/tests/fixtures/review-quality"

collect() {
	RC=0
	/bin/bash "$COLLECT" "$@" >"$M" 2>"$TEST_ROOT/err.txt" || RC=$?
}
numbered() { cat "$(mf_get "$M" numbered_diff_file)"; }
# row <변경 전> <변경 후> <diff 줄> : 번호 diff 의 한 줄
row() { printf '%6s %6s | %s' "$1" "$2" "$3"; }
has_row() { # <설명> <변경 전> <변경 후> <diff 줄>
	if numbered | grep -qxF -- "$(row "$2" "$3" "$4")"; then pass "$1"; else fail "$1" "[$(row "$2" "$3" "$4")] not found"; fi
}
has_line() { # <설명> <줄> : 번호 없이 그대로 남는 줄(파일 헤더 등)
	if numbered | grep -qxF -- "$2"; then pass "$1"; else fail "$1" "[$2] not found"; fi
}

# 번호 diff 의 +·문맥 줄은 변경 후 트리의 파일과, -·문맥 줄은 변경 전 트리의 파일과 같은지 전부 대조한다.
# 출력: "<대조한 줄 수> <불일치 수>"
verify_numbers() { # <numbered 파일> <변경 후 트리> <변경 전 트리>
	LC_ALL=C awk -v new="$2" -v old="$3" '
	function line_at(path, k,   l, i) {
		if (!(path in loaded)) {
			loaded[path] = 1
			i = 0
			while ((getline l < path) > 0) { i++; L[path, i] = l }
			close(path)
		}
		return ((path, k) in L) ? L[path, k] : "\001(없음)"
	}
	/^--- a\// { of = substr($0, 7); next }
	/^--- \/dev\/null$/ { of = ""; next }
	/^\+\+\+ b\// { nf = substr($0, 7); next }
	/^\+\+\+ \/dev\/null$/ { nf = ""; next }
	substr($0, 15, 2) == "| " {
		o = substr($0, 1, 6) + 0; n = substr($0, 8, 6) + 0; c = substr($0, 17, 1); text = substr($0, 18)
		if (c == "\\") next
		if (n > 0 && nf != "") { total++; if (line_at(new "/" nf, n) != text) bad++ }
		if (o > 0 && of != "") { total++; if (line_at(old "/" of, o) != text) bad++ }
	}
	END { printf "%d %d\n", total, bad + 0 }' "$1"
}

# ------------------------------------------------------------ 기본 저장소
R="$TEST_ROOT/repo"
new_repo "$R"
cd "$R" || exit 1
i=1
: >a.txt
while [ "$i" -le 20 ]; do
	if [ "$i" -eq 3 ]; then printf -- '-- sql comment\n' >>a.txt; else printf 'l%d\n' "$i" >>a.txt; fi
	i=$((i + 1))
done
printf 'x\ny' >b.txt
printf 'd1\nd2\nd3\n' >d.txt
printf 'line1\nline2\nline3\nline4\nline5\n' >old-name.txt
printf 'bin\000ary\n' >blob.bin
gcommit init
git checkout -q -b feature

# a.txt: 3행(-- sql comment) 삭제, l4 뒤에 '++ added'·'@@ -1 +1 @@ fake' 추가, l18 → l18x (두 번째 hunk)
awk 'NR == 3 { next } { print } NR == 4 { print "++ added"; print "@@ -1 +1 @@ fake" } ' a.txt | sed 's/^l18$/l18x/' >a.new
mv a.new a.txt
printf 'x\nz' >b.txt
git rm -q d.txt
git mv old-name.txt new-name.txt
printf 'line6\n' >>new-name.txt
printf 'bin\000ary2\n' >blob.bin
gcommit "feat: 변경"
printf 'c1\nc2\n' >c.txt

collect --scope changes --base main
assert_eq "changes 성공" 0 "$RC"
nf=$(mf_get "$M" numbered_diff_file)
assert_contains "numbered_diff_file 은 컨텍스트 디렉터리 안" "$nf" "$(mf_get "$M" context_dir)/"
assert_eq "numbered_diff_file 존재" yes "$([ -f "$nf" ] && echo yes || echo no)"
assert_contains "첫 줄은 형식 안내" "$(head -1 "$nf")" "# code-sentinel numbered diff:"
assert_contains "형식 안내: 파일 자체 줄 번호가 아님" "$(head -1 "$nf")" "이 파일 자체의 줄 번호가 아님"
assert_eq "diff.patch 와 줄 수가 같음(+안내 1줄)" "$(($(wc -l <"$(mf_get "$M" diff_file)") + 1))" "$(($(wc -l <"$nf")))"

has_line "파일 헤더는 번호 없이 유지" "diff --git a/a.txt b/a.txt"
has_line "--- 헤더는 번호 없이 유지" "--- a/a.txt"
has_line "+++ 헤더는 번호 없이 유지" "+++ b/a.txt"
has_row "문맥 줄: 양쪽 번호" 1 1 " l1"
has_row "본문의 '--- '는 삭제 줄로 번호" 3 "" "--- sql comment"
has_row "삭제 뒤 문맥 줄: 번호 차이 반영" 4 3 " l4"
has_row "본문의 '+++ '는 추가 줄로 번호" "" 4 "+++ added"
has_row "본문의 '@@ '는 추가 줄로 번호" "" 5 "+@@ -1 +1 @@ fake"
has_row "추가 뒤 문맥 줄" 5 6 " l5"
has_row "두 번째 hunk: 삭제" 18 "" "-l18"
has_row "두 번째 hunk: 추가" "" 19 "+l18x"
has_row "두 번째 hunk: 끝 문맥" 20 21 " l20"

has_row "개행 없는 파일: 문맥" 1 1 " x"
has_row "개행 없는 파일: 삭제" 2 "" "-y"
has_row "No newline 표시는 번호 없음" "" "" "\\ No newline at end of file"
has_row "No newline 뒤 추가 줄 번호 유지" "" 2 "+z"

has_row "삭제된 파일: 변경 전 번호" 1 "" "-d1"
has_row "삭제된 파일: 마지막 줄" 3 "" "-d3"
has_line "이름 변경 헤더 유지" "rename from old-name.txt"
has_row "이름 변경 + 수정: 새 파일 번호" "" 6 "+line6"
has_row "untracked 파일: 1부터" "" 1 "+c1"
has_row "untracked 파일: 2" "" 2 "+c2"
assert_contains "바이너리 표시는 그대로" "$(numbered)" "Binary files a/blob.bin and b/blob.bin differ"

BASE_TREE="$TEST_ROOT/base-tree"
mkdir -p "$BASE_TREE"
git archive main | tar -x -C "$BASE_TREE"
res=$(verify_numbers "$nf" "$R" "$BASE_TREE")
if [ "${res%% *}" -gt 30 ] && [ "${res#* }" -eq 0 ]; then
	pass "changes: 번호 ${res%% *}개 모두 실제 파일과 일치"
else
	fail "changes: 번호 대조" "검사 ${res%% *}개, 불일치 ${res#* }개"
fi

# ------------------------------------------------------------ staged · commit · full
git checkout -q -- . 2>/dev/null
rm -f c.txt
printf 'staged1\n' >s.txt
git add s.txt
collect --scope staged
assert_eq "staged 성공" 0 "$RC"
has_row "staged: 새 파일 번호" "" 1 "+staged1"
git reset -q
rm -f s.txt

collect --scope commit --ref HEAD
assert_eq "commit 성공" 0 "$RC"
has_row "commit: 삭제 줄" 3 "" "--- sql comment"
has_row "commit: 추가 줄" "" 19 "+l18x"

collect --scope full
assert_eq "full 성공" 0 "$RC"
assert_eq "full: numbered_diff_file none" none "$(mf_get "$M" numbered_diff_file)"
assert_eq "full: 번호 diff 파일 없음" 0 "$(find "$(mf_get "$M" context_dir)" -name 'diff.numbered.txt' | wc -l | tr -d ' ')"

# ------------------------------------------------------------ 변경 없음
R2="$TEST_ROOT/empty"
new_repo "$R2"
cd "$R2" || exit 1
printf 'a\n' >a.txt
gcommit init
collect --scope staged
assert_eq "변경 없음: 성공" 0 "$RC"
assert_eq "변경 없음: 안내 줄만" 1 "$(($(wc -l <"$(mf_get "$M" numbered_diff_file)")))"

# ------------------------------------------------------------ PR gh-diff 모드(가짜 gh)
cd "$R" || exit 1
FAKEBIN="$TEST_ROOT/fakebin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/gh" <<'GH'
#!/bin/bash
case "$1 $2" in
"pr view") cat "$FAKE_GH_JSON" ;;
"pr diff") cat "$FAKE_GH_PATCH" ;;
*) exit 1 ;;
esac
GH
chmod +x "$FAKEBIN/gh"
export FAKE_GH_JSON="$TEST_ROOT/pr.json" FAKE_GH_PATCH="$TEST_ROOT/pr.patch"
printf '{"baseRefOid":"%s","headRefOid":"%s","baseRefName":"main","headRefName":"feature","title":"t","body":"","url":"u","commits":[]}\n' \
	"$(git rev-parse main)" 0000000000000000000000000000000000000abc >"$FAKE_GH_JSON"
git diff main feature >"$FAKE_GH_PATCH"
PATH="$FAKEBIN:$PATH" collect --scope pr --pr 3
assert_eq "PR gh-diff: 성공" 0 "$RC"
assert_eq "PR gh-diff: diff_mode" gh-diff "$(mf_get "$M" diff_mode)"
has_row "PR gh-diff: 삭제 줄 번호" 3 "" "--- sql comment"
has_row "PR gh-diff: 추가 줄 번호" "" 19 "+l18x"

# ------------------------------------------------------------ 품질 픽스처 전체 대조
for fx in backend-api frontend-web infra clean-change; do
	FR="$TEST_ROOT/fx-$fx"
	if ! /bin/bash "$FIX/setup.sh" "$fx" "$FR" >/dev/null 2>&1; then
		fail "픽스처 $fx 준비" "setup.sh 실패"
		continue
	fi
	cd "$FR" || exit 1
	collect --scope changes --base main
	res=$(verify_numbers "$(mf_get "$M" numbered_diff_file)" "$FR" "$FIX/$fx/base")
	if [ "${res%% *}" -gt 0 ] && [ "${res#* }" -eq 0 ]; then
		pass "픽스처 $fx: 번호 ${res%% *}개 모두 일치"
	else
		fail "픽스처 $fx: 번호 대조" "검사 ${res%% *}개, 불일치 ${res#* }개"
	fi
done

finish
