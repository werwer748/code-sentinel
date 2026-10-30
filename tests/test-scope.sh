#!/bin/bash
# test-scope.sh — collect-context.sh 범위·파일 처리·기준·옵션·PR (SPEC §16.3)
. "$(dirname "$0")/lib.sh"
setup_sandbox

M="$TEST_ROOT/manifest.txt"

# collect <args...> : RC 와 $M 을 채운다
collect() {
	RC=0
	/bin/bash "$COLLECT" "$@" >"$M" 2>"$TEST_ROOT/err.txt" || RC=$?
}
files() { mf_section "$M" FILES; }
diff_of() { cat "$(mf_get "$M" diff_file)"; }

make_fake_gh() { # <bin dir>
	mkdir -p "$1"
	cat >"$1/gh" <<'GH'
#!/bin/bash
case "$1 $2" in
"pr view")
	if [ -n "${FAKE_GH_FAIL:-}" ]; then echo "gh: To get started with GitHub CLI, please run: gh auth login" >&2; exit 4; fi
	cat "$FAKE_GH_JSON" ;;
"pr diff") cat "$FAKE_GH_PATCH" ;;
*) exit 1 ;;
esac
GH
	chmod +x "$1/gh"
}

# ------------------------------------------------------------ 기본 저장소
R="$TEST_ROOT/repo"
new_repo "$R"
cd "$R" || exit 1
printf 'one\ntwo\nthree\n' >keep.txt
printf 'del\n' >gone.txt
printf 'line1\nline2\nline3\nline4\nline5\n' >old-name.txt
printf 'x\n' >mode.sh
printf '{"name":"x"}\n' >package.json
gcommit init
git checkout -q -b feature

# 커밋된 변경
printf 'four\n' >>keep.txt
git rm -q gone.txt
git mv old-name.txt new-name.txt
printf 'line6\n' >>new-name.txt
chmod +x mode.sh
printf 'bin\000ary\n' >blob.bin
gcommit "feat: 여러 변경"
# 미커밋 변경: staged, unstaged, 부분 스테이징, untracked
printf 'staged-line\n' >staged.txt
git add staged.txt
printf 'idx\n' >>keep.txt
git add keep.txt
printf 'wt\n' >>keep.txt
printf 'u\n' >untracked.txt

collect --scope changes --base main
assert_eq "changes 성공" 0 "$RC"
f=$(files)
assert_contains "changes: 수정" "$f" "M	keep.txt"
assert_contains "changes: 삭제" "$f" "D	gone.txt"
assert_contains "changes: 이름 변경+수정" "$f" "R	old-name.txt	new-name.txt"
assert_contains "changes: mode만 변경" "$f" "mode.sh	mode-only"
assert_contains "changes: binary" "$f" "blob.bin	binary"
assert_contains "changes: staged 신규" "$f" "A	staged.txt"
assert_contains "changes: untracked" "$f" "A	untracked.txt	untracked"
assert_eq "changes: 부분 스테이징 파일은 한 번만" 1 "$(printf '%s\n' "$f" | grep -c 'keep.txt')"
d=$(diff_of)
assert_contains "changes: 작업 트리 버전(unstaged 줄 포함)" "$d" "+wt"
assert_contains "changes: untracked diff 포함" "$d" "+u"
assert_eq "changes: snapshot" worktree "$(mf_get "$M" snapshot)"
assert_eq "changes: merge_base" "$(git merge-base main HEAD)" "$(mf_get "$M" merge_base)"
assert_eq "changes: commit_count" 1 "$(mf_get "$M" commit_count)"
assert_contains "changes: 커밋 메시지 수집" "$(cat "$(mf_get "$M" commits_file)")" "feat: 여러 변경"
assert_contains "changes: status_summary" "$(mf_get "$M" status_summary)" "untracked=1"

collect --scope staged
assert_eq "staged 성공" 0 "$RC"
f=$(files)
assert_contains "staged: staged 파일" "$f" "A	staged.txt"
assert_not_contains "staged: untracked 제외" "$f" "untracked.txt"
d=$(diff_of)
assert_contains "staged: index 버전" "$d" "+idx"
assert_not_contains "staged: unstaged 줄 제외" "$d" "+wt"
assert_eq "staged: snapshot" index "$(mf_get "$M" snapshot)"

collect --scope commit
assert_eq "commit 성공" 0 "$RC"
assert_eq "commit: snapshot 은 HEAD" "$(git rev-parse HEAD)" "$(mf_get "$M" snapshot)"
assert_eq "commit: parent" "$(git rev-parse HEAD^)" "$(mf_get "$M" parent)"
assert_not_contains "commit: 미커밋 제외" "$(files)" "staged.txt"

collect --scope full
assert_eq "full 성공" 0 "$RC"
f=$(files)
assert_contains "full: 추적 파일" "$f" "F	keep.txt"
assert_contains "full: untracked 포함" "$f" "untracked.txt"
assert_contains "full: binary 표시" "$f" "blob.bin	binary"
assert_eq "full: diff_file none" none "$(mf_get "$M" diff_file)"

# ------------------------------------------------------------ 특수 경로
R2="$TEST_ROOT/paths"
new_repo "$R2"
cd "$R2" || exit 1
printf 'a\n' >a.txt
gcommit init
printf 'x\n' >'공백 있는 한글.ts'
printf 'x\n' >'quote"d.ts'
printf 'x\n' >"$(printf 'new\nline.ts')"
printf 'x\n' >'back\slash.ts'
collect --scope staged
git add -A
collect --scope staged
f=$(files)
assert_contains "경로: 공백·한글 원문 유지" "$f" "A	공백 있는 한글.ts"
assert_contains "경로: 큰따옴표 인용" "$f" 'A	"quote\"d.ts"'
assert_contains "경로: 개행 인용" "$f" 'A	"new\nline.ts"'
assert_contains "경로: 역슬래시 인용" "$f" 'A	"back\\slash.ts"'

# ------------------------------------------------------------ merge-base / 기준 브랜치
R3="$TEST_ROOT/base"
new_repo "$R3"
cd "$R3" || exit 1
printf 'a\n' >a.txt
gcommit init
git checkout -q -b feature
printf 'f\n' >feature.txt
gcommit feature
git checkout -q main
printf 'm\n' >main-only.txt
gcommit "main 진행"
git checkout -q feature
collect --scope changes --base main
f=$(files)
assert_contains "merge-base: feature 변경 포함" "$f" "feature.txt"
assert_not_contains "merge-base: base 쪽 변경 제외" "$f" "main-only.txt"

git config code-sentinel.base main
collect --scope changes
assert_eq "기준: code-sentinel.base 설정" "main" "$(mf_get "$M" base_ref)"
assert_eq "기준: 출처 config" config "$(mf_get "$M" base_source)"
git config --unset code-sentinel.base

git update-ref refs/remotes/origin/main "$(git rev-parse main)"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
collect --scope changes
assert_eq "기준: origin/HEAD" "origin/main" "$(mf_get "$M" base_ref)"
assert_contains "기준: 원격 fetch 시점 경고" "$(mf_section "$M" WARNINGS)" "fetch"
git symbolic-ref -d refs/remotes/origin/HEAD
git update-ref -d refs/remotes/origin/main

collect --scope changes
assert_eq "기준: 결정 불가 → 4" 4 "$RC"
assert_contains "기준: main 추정하지 않음" "$(cat "$TEST_ROOT/err.txt")" "기준 브랜치를 정할 수 없습니다"

git checkout -q main
printf 'dirty\n' >>a.txt
collect --scope changes --base main
assert_eq "현재 브랜치 = 기준: 성공" 0 "$RC"
assert_eq "현재 브랜치 = 기준: same_as_base" yes "$(mf_get "$M" same_as_base)"
assert_contains "현재 브랜치 = 기준: 미커밋만" "$(files)" "M	a.txt"
git checkout -q -- a.txt

# detached HEAD
git checkout -q --detach feature
collect --scope changes --base main
assert_eq "detached HEAD 성공" 0 "$RC"
assert_contains "detached HEAD: feature 변경" "$(files)" "feature.txt"
git checkout -q feature

# 하위 디렉터리 실행
mkdir -p sub/dir
printf 's\n' >sub/dir/s.txt
(cd sub/dir && /bin/bash "$COLLECT" --scope changes --base main >"$M" 2>/dev/null)
assert_eq "하위 디렉터리: repo 는 최상위" "$R3" "$(mf_get "$M" repo)"
assert_contains "하위 디렉터리: 최상위 기준 경로" "$(files)" "sub/dir/s.txt"
rm -rf sub

# shallow clone
SH="$TEST_ROOT/shallow"
git clone -q --depth 1 --no-single-branch "file://$R3" "$SH" 2>/dev/null
cd "$SH" || exit 1
git checkout -q feature 2>/dev/null || git checkout -q -b feature origin/feature
collect --scope changes --base origin/main
assert_eq "shallow clone → 4" 4 "$RC"
assert_contains "shallow 안내" "$(cat "$TEST_ROOT/err.txt")" "unshallow"

# ------------------------------------------------------------ 최초 커밋, 빈 저장소, merge commit
R4="$TEST_ROOT/root"
new_repo "$R4"
cd "$R4" || exit 1
printf 'first\n' >first.txt
git add first.txt
collect --scope staged
assert_eq "빈 저장소 staged 성공" 0 "$RC"
assert_eq "빈 저장소 staged: empty tree 기준" empty-tree "$(mf_get "$M" parent)"
assert_contains "빈 저장소 staged: 파일" "$(files)" "A	first.txt"
gcommit first
collect --scope commit
assert_eq "최초 커밋: empty tree 기준" empty-tree "$(mf_get "$M" parent)"
assert_contains "최초 커밋: 파일" "$(files)" "A	first.txt"
git checkout -q -b side
printf 's\n' >side.txt
gcommit side
git checkout -q main
printf 'm\n' >m.txt
gcommit m
git merge -q --no-ff -m merge side
collect --scope commit
assert_eq "merge commit 표시" yes "$(mf_get "$M" merge_commit)"
assert_eq "merge commit: 첫 번째 부모" "$(git rev-parse HEAD^1)" "$(mf_get "$M" parent)"
assert_contains "merge commit: 둘째 부모 쪽 변경" "$(files)" "side.txt"
collect --scope commit --ref 'HEAD~1..HEAD'
assert_eq "커밋 범위 지정 → 2" 2 "$RC"

# ------------------------------------------------------------ 변경 없음, 제외 규칙, 필터, 대형 변경
R5="$TEST_ROOT/rules"
new_repo "$R5"
cd "$R5" || exit 1
printf 'a\n' >a.ts
printf '{"dependencies":{}}\n' >package.json
gcommit init
collect --scope staged
assert_eq "변경 없음: 성공" 0 "$RC"
assert_eq "변경 없음: target_files 0" 0 "$(mf_get "$M" target_files)"

mkdir -p dist src/__snapshots__ gen
printf 'x\n' >pnpm-lock.yaml
printf 'x\n' >dist/out.js
printf 'x\n' >lib.min.js
printf 'x\n' >src/__snapshots__/a.snap
printf 'x\n' >api.generated.ts
printf '// Code generated by tool. DO NOT EDIT.\nx\n' >gen/model.go
printf 'x\n' >gen/marked.ts
printf 'gen/marked.ts linguist-generated\n' >.gitattributes
printf 'real\n' >src/app.ts
git add -A
collect --scope staged
r=$(mf_section "$M" RULE_EXCLUDED)
assert_contains "제외: lockfile" "$r" "pnpm-lock.yaml	lockfile"
assert_contains "제외: dist" "$r" "dist/out.js	build-output"
assert_contains "제외: min" "$r" "lib.min.js	minified"
assert_contains "제외: snapshot" "$r" "src/__snapshots__/a.snap	snapshot"
assert_contains "제외: *.generated.*" "$r" "api.generated.ts	generated"
assert_contains "제외: DO NOT EDIT 헤더" "$r" "gen/model.go	generated"
assert_contains "제외: linguist-generated" "$r" "gen/marked.ts	generated"
assert_contains "제외: 대상은 남음" "$(files)" "src/app.ts"
assert_not_contains "제외: diff 에서 빠짐" "$(diff_of)" "pnpm-lock.yaml"
assert_contains "lockfile만 변경 경고" "$(mf_section "$M" WARNINGS)" "lockfile만 변경"

collect --scope staged --include pnpm-lock.yaml
assert_contains "--include 가 기본 제외보다 우선" "$(files)" "pnpm-lock.yaml"
collect --scope staged --include src
assert_eq "--include src: 대상 1개" 1 "$(mf_get "$M" target_files)"
collect --scope staged --exclude src
assert_not_contains "--exclude src" "$(files)" "src/app.ts"
gcommit rules

# 크기 상한
head -c 1100000 /dev/zero | tr '\000' 'a' >big.txt
git add big.txt
collect --scope staged
assert_contains "1 MiB 초과 → SKIPPED size" "$(mf_section "$M" SKIPPED)" "big.txt	size"
assert_eq "크기 초과: skipped 1" 1 "$(mf_get "$M" skipped)"
assert_not_contains "크기 초과: diff 에서 빠짐" "$(diff_of)" "big.txt"
git rm -q --cached big.txt
rm big.txt

# 대형 변경: 락파일 대량 + 코드 소량은 분할 아님 / 코드 70개는 recommended
awk 'BEGIN { for (i = 0; i < 5000; i++) print "dep" i }' >pnpm-lock.yaml
printf 'b\n' >>a.ts
git add -A
collect --scope staged
assert_eq "락파일 대량 변경: split none" none "$(mf_get "$M" split)"
git reset -q
git checkout -q -- .
mkdir -p many
i=0
while [ "$i" -lt 70 ]; do
	printf 'x\n' >"many/f$i.ts"
	i=$((i + 1))
done
git add many
collect --scope staged
assert_eq "코드 70개: split recommended" recommended "$(mf_get "$M" split)"
git reset -q
rm -rf many

# CRLF / autocrlf
git config core.autocrlf true
printf 'a\r\nb\r\n' >crlf.txt
git add crlf.txt
collect --scope staged
assert_eq "autocrlf: 성공" 0 "$RC"
assert_contains "autocrlf: 파일 포함" "$(files)" "crlf.txt"
git reset -q
rm crlf.txt
git config --unset core.autocrlf

# ------------------------------------------------------------ 심볼릭 링크·submodule 항목
R6="$TEST_ROOT/links"
new_repo "$R6"
cd "$R6" || exit 1
printf 'SECRET-OUTSIDE-CONTENT\n' >"$TEST_ROOT/outside.txt"
printf 'a\n' >a.txt
gcommit init
ln -s ../outside.txt link
git add link
subsha=$(git rev-parse HEAD)
git update-index --add --cacheinfo "160000,$subsha,vendored-sub"
collect --scope staged
f=$(files)
assert_contains "심볼릭 링크 표시" "$f" "link	symlink"
assert_contains "submodule 표시" "$f" "vendored-sub	submodule"
assert_not_contains "심볼릭 링크를 따라가지 않음" "$(diff_of)" "SECRET-OUTSIDE-CONTENT"
collect --scope full
assert_contains "full: 심볼릭 링크 표시" "$(files)" "link	symlink"

# ------------------------------------------------------------ 옵션 검증과 환경 오류
cd "$R" || exit 1
collect --scope nope
assert_eq "알 수 없는 범위 → 2" 2 "$RC"
collect --scope staged --wat
assert_eq "알 수 없는 옵션 → 2" 2 "$RC"
collect --scope staged --scope full
assert_eq "범위 충돌 → 2" 2 "$RC"
collect --scope staged --base main
assert_eq "--base 오용 → 2" 2 "$RC"
collect --scope pr --pr abc
assert_eq "정수가 아닌 --pr → 2" 2 "$RC"
collect
assert_eq "--scope 없음 → 2" 2 "$RC"
collect --scope staged --repo "$TEST_ROOT"
assert_eq "Git 저장소 아님 → 3" 3 "$RC"
collect --scope commit --ref does-not-exist
assert_eq "잘못된 ref → 5" 5 "$RC"
collect --scope changes --base does-not-exist
assert_eq "잘못된 --base → 5" 5 "$RC"

# ------------------------------------------------------------ 커밋 메시지 상한
R7="$TEST_ROOT/commits"
new_repo "$R7"
cd "$R7" || exit 1
gcommit init
git checkout -q -b feature
i=0
while [ "$i" -lt 55 ]; do
	printf '%s\n' "$i" >>n.txt
	gcommit "change $i"
	i=$((i + 1))
done
collect --scope changes --base main
assert_eq "커밋 수 55" 55 "$(mf_get "$M" commit_count)"
assert_eq "커밋 메시지는 50개만" 50 "$(grep -c '^commit [0-9a-f]\{40\}$' "$(mf_get "$M" commits_file)")"
assert_contains "커밋 상한 경고" "$(mf_section "$M" WARNINGS)" "최근 50개"

# ------------------------------------------------------------ PR (가짜 gh)
cd "$R3" || exit 1
git checkout -q feature
collect --scope pr --pr 1
assert_eq "gh 없음 → 6" 6 "$RC"

FAKEBIN="$TEST_ROOT/fakebin"
make_fake_gh "$FAKEBIN"
base_tip=$(git rev-parse main)
head_oid=$(git rev-parse feature)
export FAKE_GH_JSON="$TEST_ROOT/pr.json" FAKE_GH_PATCH="$TEST_ROOT/pr.patch"
printf '{"baseRefOid":"%s","headRefOid":"%s","baseRefName":"main","headRefName":"feature","title":"PR 제목","body":"중복 결제 방지\\n본문","url":"https://example.invalid/pull/1","commits":[{"oid":"%s","messageHeadline":"feature","messageBody":""}]}\n' \
	"$base_tip" "$head_oid" "$head_oid" >"$FAKE_GH_JSON"
git diff "$(git merge-base main feature)" feature >"$FAKE_GH_PATCH"

FAKE_GH_FAIL=1 PATH="$FAKEBIN:$PATH" collect --scope pr --pr 1
assert_eq "gh 미인증 → 6" 6 "$RC"

PATH="$FAKEBIN:$PATH" collect --scope pr --pr 1
assert_eq "PR 로컬 객체: 성공" 0 "$RC"
assert_eq "PR: diff_mode local" local "$(mf_get "$M" diff_mode)"
assert_eq "PR: snapshot = head" "$head_oid" "$(mf_get "$M" snapshot)"
assert_eq "PR: base_tip" "$base_tip" "$(mf_get "$M" base_tip)"
assert_eq "PR: merge_base" "$(git merge-base main feature)" "$(mf_get "$M" merge_base)"
assert_contains "PR: head 변경 포함" "$(files)" "feature.txt"
assert_not_contains "PR: base 쪽 변경 제외(merge-base 기준)" "$(files)" "main-only.txt"
assert_eq "PR: 로컬 HEAD 일치" yes "$(mf_get "$M" local_head_matches)"
assert_contains "PR: 본문 수집" "$(cat "$(mf_get "$M" pr_body_file)")" "중복 결제 방지"
assert_eq "PR: 제목" "PR 제목" "$(mf_get "$M" pr_title)"

missing=0000000000000000000000000000000000000abc
printf '{"baseRefOid":"%s","headRefOid":"%s","baseRefName":"main","headRefName":"feature","title":"t","body":"","url":"u","commits":[]}\n' \
	"$base_tip" "$missing" >"$FAKE_GH_JSON"
PATH="$FAKEBIN:$PATH" collect --scope pr --pr 1
assert_eq "PR 객체 없음: 성공" 0 "$RC"
assert_eq "PR 객체 없음: diff_mode gh-diff" gh-diff "$(mf_get "$M" diff_mode)"
assert_contains "PR gh-diff: 패치에서 파일 목록" "$(files)" "A	feature.txt"
assert_eq "PR gh-diff: 로컬 HEAD 불일치" no "$(mf_get "$M" local_head_matches)"
assert_contains "PR gh-diff: diff-only 경고" "$(mf_section "$M" WARNINGS)" "diff-only"

finish
