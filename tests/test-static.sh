#!/bin/bash
# test-static.sh — bash 3.2 호환 정적 검사, shellcheck, SKILL.md frontmatter (SPEC §16.2)
. "$(dirname "$0")/lib.sh"
setup_sandbox

cd "$REPO_ROOT" || exit 1

# 검사 대상: 저장소의 모든 .sh (품질 픽스처는 의도적으로 결함을 담고 있어 제외)
list="$TEST_ROOT/sh.lst"
find . -name '*.sh' -not -path './tests/fixtures/review-quality/*/*' -not -path './.git/*' | sort >"$list"
count=$(wc -l <"$list")
if [ "$count" -gt 0 ]; then pass "검사할 셸 스크립트 $((count))개"; else fail "셸 스크립트를 찾지 못함"; fi

while IFS= read -r f; do
	first=$(head -1 "$f")
	assert_eq "shebang $f" '#!/bin/bash' "$first"
	if /bin/bash -n "$f" 2>"$TEST_ROOT/n.err"; then
		pass "bash -n $f"
	else
		fail "bash -n $f" "$(head -1 "$TEST_ROOT/n.err")"
	fi
done <"$list"

# 금지 구문 (주석 줄 제외, 이 파일 자체 제외)
forbidden='\bmapfile\b|\breadarray\b|declare -[a-zA-Z]*[An]|local -n\b|\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,|\^\^)|\|&|;;&|\bcoproc\b|globstar|readlink -f|\brealpath\b|grep -[a-zA-Z]*P|stat -c|date -d|(^|[;&|[:space:]])timeout[[:space:]]+[0-9]|sed -i[[:space:]]+[^-[:space:]'"'"'"]'
while IFS= read -r f; do
	case "$f" in ./tests/test-static.sh) continue ;; esac
	hits=$(grep -nE "$forbidden" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
	if [ -z "$hits" ]; then
		pass "금지 구문 없음 $f"
	else
		fail "금지 구문 $f" "$(printf '%s' "$hits" | head -2 | tr '\n' ' ')"
	fi
done <"$list"

# 정적 분석 도구 shellcheck가 있으면 실행
sc=$(PATH=$ORIG_PATH command -v shellcheck || true)
if [ -n "$sc" ]; then
	while IFS= read -r f; do
		if "$sc" -s bash -S warning "$f" >"$TEST_ROOT/sc.out" 2>&1; then
			pass "shellcheck $f"
		else
			fail "shellcheck $f" "$(head -3 "$TEST_ROOT/sc.out" | tr '\n' ' ')"
		fi
	done <"$list"
else
	skip "shellcheck" "설치되어 있지 않음"
fi

# SKILL.md frontmatter와 금지 치환 구문
skill="$SKILL_DIR/SKILL.md"
if [ -f "$skill" ]; then
	fm=$(awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$skill")
	keys=$(printf '%s\n' "$fm" | awk -F: '/^[A-Za-z_-]+:/ { print $1 }' | sort | tr '\n' ' ')
	assert_eq "frontmatter 키는 name, description 뿐" "description name " "$keys"
	name=$(printf '%s\n' "$fm" | awk -F': *' '$1 == "name" { print $2 }')
	assert_eq "name 은 디렉터리 이름과 같음" "code-sentinel" "$name"
	desc=$(printf '%s\n' "$fm" | awk '/^description:/ { sub(/^description: */, ""); on = 1 } on && !/^description:/ && /^[A-Za-z_-]+:/ { on = 0 } on')
	dlen=$(printf '%s' "$desc" | wc -m)
	if [ "$((dlen))" -gt 0 ] && [ "$((dlen))" -le 1024 ]; then pass "description 길이 $((dlen))자"; else fail "description 길이" "$((dlen))자"; fi
	docs="$TEST_ROOT/docs.lst"
	(cd "$SKILL_DIR" && find . -name '*.md' | sed 's|^\./||' | sort) >"$docs"
	# 지침 문서는 상황별로 나눠 필요한 것만 읽게 하므로 파일마다 100줄을 넘지 않는다
	long=""
	while IFS= read -r d; do
		n=$(wc -l <"$SKILL_DIR/$d")
		[ "$((n))" -le 100 ] || long="$long $d($((n))줄)"
	done <"$docs"
	if [ -z "$long" ]; then pass "지침 문서 $(wc -l <"$docs" | tr -d ' ')개 모두 100줄 이내"; else fail "100줄 초과 문서" "$long"; fi
	bad=""
	while IFS= read -r d; do
		hit=$(grep -nE '\$ARGUMENTS|\$\{CLAUDE_SKILL_DIR\}|\$[0-9]|^!`' "$SKILL_DIR/$d" || true)
		[ -z "$hit" ] || bad="$bad $d:$(printf '%s' "$hit" | head -1)"
	done <"$docs"
	if [ -z "$bad" ]; then pass "도구별 치환 구문 없음"; else fail "도구별 치환 구문" "$bad"; fi
	# SKILL.md 5절 표가 가리키는 문서가 모두 있고, internals/ 밖의 문서는 모두 표에 나온다
	refs="$TEST_ROOT/skill-refs.lst"
	grep -oE '`[a-z]+/[a-z<>-]+\.md`' "$skill" | tr -d '`' | sort -u >"$refs"
	missing=""
	while IFS= read -r r; do
		case "$r" in
		review/\<slug\>.md)
			for s in security correctness ops architecture performance tests readability style; do
				[ -f "$SKILL_DIR/references/review/$s.md" ] || missing="$missing review/$s.md"
			done ;;
		*) [ -f "$SKILL_DIR/references/$r" ] || missing="$missing $r" ;;
		esac
	done <"$refs"
	if [ -z "$missing" ]; then pass "SKILL.md가 가리키는 문서가 모두 있음"; else fail "SKILL.md가 가리키는 문서 없음" "$missing"; fi
	unlisted=""
	while IFS= read -r d; do
		case "$d" in SKILL.md | references/internals/*) continue ;; esac
		r=${d#references/}
		case "$r" in review/security.md | review/correctness.md | review/ops.md | review/architecture.md | review/performance.md | review/tests.md | review/readability.md | review/style.md)
			grep -q 'review/<slug>.md' "$refs" && continue ;;
		esac
		grep -qxF "$r" "$refs" || unlisted="$unlisted $r"
	done <"$docs"
	if [ -z "$unlisted" ]; then pass "internals/ 밖의 문서가 모두 SKILL.md 표에 있음"; else fail "SKILL.md 표에 없는 문서" "$unlisted"; fi
	# 문서 안의 상대 참조(`x.md`, `../dir/x.md`)가 실제 파일을 가리킨다
	broken=""
	while IFS= read -r d; do
		case "$d" in references/*) ;; *) continue ;; esac
		dir=$(dirname "$SKILL_DIR/$d")
		for r in $(grep -oE '`(\.\./)?([a-z]+/)?[a-z-]+\.md`' "$SKILL_DIR/$d" | tr -d '`' | sort -u); do
			[ -f "$dir/$r" ] || broken="$broken ${d}->${r}"
		done
	done <"$docs"
	if [ -z "$broken" ]; then pass "문서 간 상대 참조가 모두 실제 파일을 가리킴"; else fail "깨진 문서 참조" "$broken"; fi
else
	fail "SKILL.md 없음" "$skill"
fi

finish
