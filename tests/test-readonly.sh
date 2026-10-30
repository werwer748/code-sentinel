#!/bin/bash
# test-readonly.sh — 스냅샷 정합성과 불변성 (SPEC §16.5)
. "$(dirname "$0")/lib.sh"
setup_sandbox

M="$TEST_ROOT/manifest.txt"
collect() {
	RC=0
	/bin/bash "$COLLECT" "$@" >"$M" 2>"$TEST_ROOT/err.txt" || RC=$?
}

# 저장소 상태 스냅샷: status, HEAD, refs, stash, index 해시, 작업 트리 파일 해시
# (이 함수 자체가 상태를 바꾸지 않도록 optional lock 과 필터를 끈다)
state() {
	local idx
	idx=$(git rev-parse --git-path index)
	{
		GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c filter.crypt.clean= -c filter.crypt.process= -c filter.crypt.required=false \
			status --porcelain=v1 -z -uall | tr '\0' '\n'
		echo "HEAD $(git rev-parse -q --verify HEAD || echo none)"
		git for-each-ref --format='%(refname) %(objectname)'
		git stash list
		if [ -f "$idx" ]; then echo "index $(shasum <"$idx")"; else echo "index none"; fi
		find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
			printf '%s %s\n' "$(shasum <"$f" | cut -c1-40)" "$f"
		done
	}
}

check_invariant() { # <설명> <collect 인자...>
	local desc=$1 a b
	shift
	a=$(state)
	collect "$@"
	b=$(state)
	if [ "$a" = "$b" ]; then pass "불변: $desc (exit $RC)"; else fail "불변: $desc" "상태가 바뀜"; fi
}

# ------------------------------------------------------------ 기본 저장소
R="$TEST_ROOT/repo"
new_repo "$R"
cd "$R"
printf 'a\n' >a.txt
printf 'b\n' >b.txt
gcommit init
git checkout -q -b feature
printf 'a2\n' >>a.txt
gcommit feature
git stash list >/dev/null
printf 'idx\n' >>b.txt
git add b.txt
printf 'wt\n' >>b.txt
printf 'u\n' >u.txt
printf 'ignored\n' >ig.log
printf '*.log\n' >.git/info/exclude

collect --scope changes --base main
assert_eq "스냅샷: changes → worktree" worktree "$(mf_get "$M" snapshot)"
assert_eq "스냅샷: changes head" "$(git rev-parse HEAD)" "$(mf_get "$M" head)"
assert_eq "스냅샷: changes merge_base" "$(git merge-base main HEAD)" "$(mf_get "$M" merge_base)"
assert_contains "스냅샷: collected_at" "$(mf_get "$M" collected_at)" "T"
collect --scope staged
assert_eq "스냅샷: staged → index" index "$(mf_get "$M" snapshot)"
collect --scope commit
assert_eq "스냅샷: commit → sha" "$(git rev-parse HEAD)" "$(mf_get "$M" snapshot)"
assert_eq "스냅샷: commit parent" "$(git rev-parse HEAD^)" "$(mf_get "$M" parent)"

for args in "--scope changes --base main" "--scope staged" "--scope commit" "--scope full" \
	"--scope changes" "--scope commit --ref nope" "--scope staged --include b.txt"; do
	# shellcheck disable=SC2086
	check_invariant "$args" $args
done

# ------------------------------------------------------------ PR head 와 로컬 코드 불일치
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
head_oid=$(git rev-parse feature)
printf '{"baseRefOid":"%s","headRefOid":"%s","baseRefName":"main","headRefName":"feature","title":"t","body":"b","url":"u","commits":[]}\n' \
	"$(git rev-parse main)" "$head_oid" >"$FAKE_GH_JSON"
git diff main feature >"$FAKE_GH_PATCH"
git stash -q -u
git checkout -q main
printf 'local-only\n' >>a.txt # 로컬 작업 트리는 PR head 와 다름
PATH="$FAKEBIN:$PATH" collect --scope pr --pr 7
assert_eq "PR 불일치: 성공" 0 "$RC"
assert_eq "PR 불일치: snapshot 은 PR head" "$head_oid" "$(mf_get "$M" snapshot)"
assert_eq "PR 불일치: local_head_matches no" no "$(mf_get "$M" local_head_matches)"
assert_contains "PR 불일치: 로컬 근거 금지 경고" "$(mf_section "$M" WARNINGS)" "로컬 파일을 확정 근거로 쓰지 마세요"
assert_not_contains "PR 불일치: 로컬 전용 변경은 diff 에 없음" "$(cat "$(mf_get "$M" diff_file)")" "local-only"
PATH="$FAKEBIN:$PATH" check_invariant "pr (로컬 객체)" --scope pr --pr 7

printf '{"baseRefOid":"%s","headRefOid":"%s","baseRefName":"main","headRefName":"feature","title":"t","body":"b","url":"u","commits":[]}\n' \
	"$(git rev-parse main)" 1111111111111111111111111111111111111111 >"$FAKE_GH_JSON"
PATH="$FAKEBIN:$PATH" collect --scope pr --pr 7
assert_eq "PR head 객체 없음: gh-diff" gh-diff "$(mf_get "$M" diff_mode)"
PATH="$FAKEBIN:$PATH" check_invariant "pr (gh-diff)" --scope pr --pr 7
git checkout -q -- a.txt

# ------------------------------------------------------------ linked worktree, 필터·사용자 설정 저장소
git worktree add -q "$TEST_ROOT/wt" -b wt-branch main 2>/dev/null
cd "$TEST_ROOT/wt"
printf 'w\n' >w.txt
git add w.txt
printf 'w2\n' >>w.txt
check_invariant "linked worktree staged" --scope staged
check_invariant "linked worktree changes" --scope changes --base main

R2="$TEST_ROOT/filter"
new_repo "$R2"
cd "$R2"
printf '*.secret filter=crypt\n' >.gitattributes
printf 'aaaa\n' >x.secret
gcommit init
git checkout -q -b feature
git config filter.crypt.clean "false"
git config filter.crypt.required true
git config diff.external "false"
sleep 1
printf 'bbbb\n' >x.secret
printf 'n\n' >n.txt
check_invariant "필터·외부 diff 설정 저장소 changes" --scope changes --base main
check_invariant "필터·외부 diff 설정 저장소 full" --scope full

finish
