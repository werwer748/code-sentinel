#!/bin/bash
# test-gitenv.sh — 사용자 git 설정 간섭, 필터, partial clone, 읽기 전용 .git, worktree (SPEC §16.4)
. "$(dirname "$0")/lib.sh"
setup_sandbox

M="$TEST_ROOT/manifest.txt"
collect() {
	RC=0
	/bin/bash "$COLLECT" "$@" >"$M" 2>"$TEST_ROOT/err.txt" || RC=$?
}
files() { mf_section "$M" FILES; }
diff_of() { cat "$(mf_get "$M" diff_file)"; }

MARK="$TEST_ROOT/marks"
mkdir -p "$MARK"
# 실행되면 표시 파일을 남기는 가짜 외부 명령
mk_marker_cmd() { # <name>
	cat >"$TEST_ROOT/$1.sh" <<EOF
#!/bin/bash
touch "$MARK/$1"
cat
EOF
	chmod +x "$TEST_ROOT/$1.sh"
}

# ------------------------------------------------------------ 사용자 설정 간섭
mk_marker_cmd extdiff
mk_marker_cmd textconv
mk_marker_cmd fsmonitor
UCFG="$TEST_ROOT/user.gitconfig"
cat >"$UCFG" <<EOF
[diff]
	external = $TEST_ROOT/extdiff.sh
	noprefix = true
	relative = true
	mnemonicPrefix = true
[diff "tc"]
	textconv = $TEST_ROOT/textconv.sh
[color]
	ui = always
[core]
	quotePath = true
	fsmonitor = $TEST_ROOT/fsmonitor.sh
[log]
	showSignature = true
EOF

R="$TEST_ROOT/userenv"
new_repo "$R"
cd "$R" || exit 1
mkdir -p src
printf 'a\n' >'src/한글.txt'
printf '*.txt diff=tc\n' >.gitattributes
gcommit init
git checkout -q -b feature
printf 'b\n' >>'src/한글.txt'
gcommit change
printf 'c\n' >>'src/한글.txt'

(cd src && GIT_CONFIG_GLOBAL="$UCFG" /bin/bash "$COLLECT" --scope changes --base main >"$M" 2>"$TEST_ROOT/err.txt") && RC=0 || RC=$?
assert_eq "사용자 설정 간섭: 성공" 0 "$RC"
assert_contains "core.quotePath=true 무시(한글 원문)" "$(files)" "M	src/한글.txt"
d=$(diff_of)
assert_contains "diff.noprefix 무시(a/ 접두어)" "$d" "--- a/src/한글.txt"
assert_not_contains "color.ui=always 무시" "$d" "$(printf '\033[')"
assert_contains "textconv 미적용(원문 diff)" "$d" "+c"
for m in extdiff textconv fsmonitor; do
	if [ -e "$MARK/$m" ]; then fail "외부 명령 미실행: $m" "실행됨"; else pass "외부 명령 미실행: $m"; fi
done
(cd src && GIT_CONFIG_GLOBAL="$UCFG" /bin/bash "$COLLECT" --scope commit >"$M" 2>"$TEST_ROOT/err.txt") && RC=0 || RC=$?
assert_eq "log.showSignature 설정에서 commit 범위 성공" 0 "$RC"

# ------------------------------------------------------------ clean 필터
mk_marker_cmd cleanf
R2="$TEST_ROOT/filter"
new_repo "$R2"
cd "$R2" || exit 1
printf '*.secret filter=crypt\n' >.gitattributes
printf 'aaaa\n' >x.secret
printf 'n\n' >normal.txt
gcommit init
git checkout -q -b feature
git config filter.crypt.clean "$TEST_ROOT/cleanf.sh"
git config filter.crypt.required true
sleep 1
printf 'bbbb\n' >x.secret # 크기가 같은 내용 변경
printf 'm\n' >>normal.txt
collect --scope changes --base main
assert_eq "필터 저장소: 성공" 0 "$RC"
if [ -e "$MARK/cleanf" ]; then fail "clean 필터 미실행" "실행됨"; else pass "clean 필터 미실행(required=true)"; fi
assert_contains "필터 대상 → SKIPPED filter" "$(mf_section "$M" SKIPPED)" "x.secret	filter"
assert_not_contains "필터 대상 내용은 diff 에서 빠짐" "$(diff_of)" "bbbb"
collect --scope full
if [ -e "$MARK/cleanf" ]; then fail "full: clean 필터 미실행" "실행됨"; else pass "full: clean 필터 미실행"; fi

# ------------------------------------------------------------ partial clone
SRC="$TEST_ROOT/pc-src"
new_repo "$SRC"
cd "$SRC" || exit 1
git config uploadpack.allowFilter true
git config uploadpack.allowAnySHA1InWant true
printf 'v1\n' >data.txt
gcommit c1
printf 'v2\n' >data.txt
gcommit c2
printf 'v3\n' >data.txt
gcommit c3
PC="$TEST_ROOT/pc"
git clone -q --filter=blob:none "file://$SRC" "$PC" 2>/dev/null
cd "$PC" || exit 1
before=$(find .git/objects -type f | wc -l)
collect --scope commit --ref HEAD~1
after=$(find .git/objects -type f | wc -l)
assert_eq "partial clone: 누락 객체 → 4" 4 "$RC"
assert_eq "partial clone: fetch 없음(객체 수 동일)" "$((before))" "$((after))"
collect --scope staged
assert_eq "partial clone: 객체가 있는 범위는 성공" 0 "$RC"

# ------------------------------------------------------------ 읽기 전용 .git
R3="$TEST_ROOT/ro"
new_repo "$R3"
cd "$R3" || exit 1
printf 'a\n' >a.txt
gcommit init
git checkout -q -b feature
printf 'b\n' >>a.txt
gcommit b
printf 'c\n' >>a.txt
printf 'u\n' >u.txt
chmod -R a-w .git
collect --scope changes --base main
assert_eq "읽기 전용 .git: changes 성공" 0 "$RC"
collect --scope staged
assert_eq "읽기 전용 .git: staged 성공" 0 "$RC"
collect --scope full
assert_eq "읽기 전용 .git: full 성공" 0 "$RC"
chmod -R u+w .git

# ------------------------------------------------------------ linked worktree
git worktree add -q "$TEST_ROOT/wt" -b wt-branch main 2>/dev/null
cd "$TEST_ROOT/wt" || exit 1
printf 'w\n' >w.txt
git add w.txt
collect --scope staged
assert_eq "linked worktree: 성공" 0 "$RC"
assert_eq "linked worktree: repo 경로" "$TEST_ROOT/wt" "$(mf_get "$M" repo)"
assert_contains "linked worktree: 파일" "$(files)" "A	w.txt"

finish
