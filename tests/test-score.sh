#!/bin/bash
# tests/test-score.sh — 채점기(score-quality.sh)와 리뷰 품질 픽스처 자체 테스트 (SPEC §16.9)
#
# - 까다로운 경로(공백·한글·개행·역슬래시·큰따옴표·` · `·` → `)를 헤더 문법으로 썼다가 다시 읽어 같은지
# - 문법에 맞지 않는 헤더 → 출력 형식 오류(종료 코드 3)
# - 다른 파일·같은 줄/영역, minSeverity 미만, 영역 불일치 → 탐지 아님
# - mustNotFlag 위치·영역의 Medium 이상 → 위반(함정 영역 밖 지적은 위반 아님)
# - 픽스처: setup.sh 동작, expected-findings.json 형식·위치, collect-context.sh 가 기대 파일을 대상으로 잡는지
# - run-quality.sh --dry-run 이 AI 도구를 실행하지 않고 명령만 출력하는지

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh disable=SC1091
. "$(dirname "$0")/lib.sh"
setup_sandbox

SCORE="$REPO_ROOT/tests/score-quality.sh"
FIX="$REPO_ROOT/tests/fixtures/review-quality"
SETUP="$FIX/setup.sh"
RUNQ="$REPO_ROOT/tests/run-quality.sh"
W="$TEST_ROOT/work"
mkdir -p "$W"

OPTS='해석된 옵션: --changes --base main --depth standard --strictness balanced --min-severity low --focus all --max-findings 20'
SEP=' · '

# ---------------------------------------------------------------- helpers

# C 스타일 이스케이프(따옴표 없이). score-quality.sh 의 기계 판독 출력과 같은 규칙(이 테스트의 경로 범위 안에서).
cesc() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//$'\n'/\\n}
	s=${s//$'\t'/\\t}
	printf '%s' "$s"
}

# 헤더 문법의 경로 표기: 제어문자·역슬래시·큰따옴표·` · `·` → `가 있으면 C 스타일 따옴표.
hpath() {
	case $1 in
	*[[:cntrl:]]* | *\\* | *\"* | *' · '* | *' → '*) printf '"%s"' "$(cesc "$1")" ;;
	*) printf '%s' "$1" ;;
	esac
}

# hdr <id> <severity> <confidence> <area> <location>
hdr() {
	printf '[%s] %s%s확신도 %s%s%s%s%s\n' "$1" "$2" "$SEP" "$3" "$SEP" "$4" "$SEP" "$5"
}

# exp_entry <id> <file> <start> <end> <area> <minSeverity> : mustDetect 항목 JSON
exp_entry() {
	printf '{"id":"%s","file":"%s","lineRange":[%s,%s],"area":"%s","minSeverity":"%s","mustDetect":true}' \
		"$1" "$(cesc "$2")" "$3" "$4" "$5" "$6"
}

# nf_entry <id> <file> <start> <end> : mustNotFlag 항목 JSON
nf_entry() {
	printf '{"id":"%s","file":"%s","lineRange":[%s,%s],"area":"security","mustDetect":false,"mustNotFlag":true}' \
		"$1" "$(cesc "$2")" "$3" "$4"
}

# report <file> <header lines...> : 해석된 옵션 줄과 발견 항목 헤더로 보고서를 만든다.
report() {
	local f=$1
	shift
	{
		printf '## 리뷰 요약\n%s\n상태: complete\n\n## 발견된 문제\n' "$OPTS"
		for l in "$@"; do printf '%s\n  문제: 설명\n  수정: 설명\n' "$l"; done
		printf '\n## 최종 평가\n- 우선 조치: S-01 → S-02\n\n특정 항목을 고치려면 번호로 요청하세요 (예: "S-01 고쳐줘").\n'
	} >"$f"
}

# run_score <args...> : SC_OUT, SC_RC
run_score() {
	SC_RC=0
	SC_OUT=$(/bin/bash "$SCORE" "$@" 2>&1) || SC_RC=$?
}

metric() {
	printf '%s\n' "$SC_OUT" | awk -F'\t' -v k="$1" '$1 == "metric" && $2 == k { print $3 }'
}

verdict() {
	printf '%s\n' "$SC_OUT" | awk -F'\t' '$1 == "verdict" { v = $2 } END { print v }'
}

expect_score() { # <설명> <기대 종료코드> <기대 hit 또는 -> <기대 위반 또는 ->
	local ok=1 why=""
	[ "$SC_RC" = "$2" ] || { ok=0; why="exit $SC_RC (want $2)"; }
	if [ "$3" != "-" ] && [ "$(metric mustdetect_hit)" != "$3" ]; then ok=0; why="$why hit=$(metric mustdetect_hit) (want $3)"; fi
	if [ "$4" != "-" ] && [ "$(metric mustnotflag_violations)" != "$4" ]; then ok=0; why="$why violations=$(metric mustnotflag_violations) (want $4)"; fi
	if [ $ok -eq 1 ]; then pass "$1"; else fail "$1" "$why | $(printf '%s\n' "$SC_OUT" | grep -E '^(형식 오류|error|판정)' | head -3 | tr '\n' ' ')"; fi
}

# ---------------------------------------------------------------- 1. 경로 왕복

roundtrip() { # <설명> <원래 경로> [<헤더에 쓸 위치 문자열>]
	local desc=$1 p=$2 loc=${3:-}
	[ -n "$loc" ] || loc="$(hpath "$p"):4-9"
	printf '[%s]\n' "$(exp_entry RT "$p" 3 5 security High)" >"$W/rt.json"
	report "$W/rt.md" "$(hdr S-01 High High security "$loc")"
	run_score "$W/rt.json" "$W/rt.md"
	expect_score "왕복: $desc (채점 일치)" 0 1 0
	run_score --parse "$W/rt.md"
	local got
	got=$(printf '%s\n' "$SC_OUT" | awk -F'\t' '$1 == "finding" { print $6; exit }')
	assert_eq "왕복: $desc (파싱 경로)" "$(cesc "$p")" "$got"
}

roundtrip '공백' 'src/my file.ts'
roundtrip '공백(따옴표 표기도 허용)' 'src/my file.ts' '"src/my file.ts":4-9'
roundtrip '한글' 'src/한글 폴더/파일 이름.ts'
roundtrip '개행' $'src/new\nline.ts'
roundtrip '탭' $'src/tab\there.ts'
roundtrip '역슬래시' 'src/back\slash.ts'
roundtrip '큰따옴표' 'src/say "hi".ts'
roundtrip "' · ' 구분자" 'src/a · b.ts'
roundtrip "' → ' 화살표" 'src/a → b.ts'
roundtrip '콜론' 'src/a:b:c.ts'
roundtrip '혼합' $'문서/메모 · "초안" → \\최종\n본문\t끝.md'
roundtrip '8진수 이스케이프(UTF-8 바이트)' 'src/café.ts' '"src/caf\303\251.ts":4-9'
roundtrip '이름 변경(새 경로로 대조)' 'src/new · name.ts' 'src/old name.ts → "src/new · name.ts":4-9'
roundtrip '이름 변경(둘 다 따옴표)' $'src/new\nq.ts' '"src/old\"q.ts" → "src/new\nq.ts":4-9'

# 이름 변경의 이전 경로도 파싱됨
report "$W/ren.md" "$(hdr S-01 Medium High correctness '"old · a.ts" → new a.ts:2')"
run_score --parse "$W/ren.md"
assert_eq "이름 변경: 이전 경로 파싱" 'old · a.ts' "$(printf '%s\n' "$SC_OUT" | awk -F'\t' '$1 == "finding" { print $10; exit }')"

# 삭제 위치: 문법상 유효하지만(변경 전 줄 번호) 탐지로 대조하지 않음
printf '[%s]\n' "$(exp_entry D1 src/gone.ts 1 3 correctness Low)" >"$W/del.json"
report "$W/del.md" "$(hdr S-01 High High correctness 'src/gone.ts:1-3 (삭제)')"
run_score --parse "$W/del.md"
assert_eq "삭제 위치: 파싱 성공" "parsed" "$(verdict)"
assert_eq "삭제 위치: deleted 표시" "deleted" "$(printf '%s\n' "$SC_OUT" | awk -F'\t' '$1 == "finding" { print $9; exit }')"
run_score "$W/del.json" "$W/del.md"
expect_score "삭제 위치: 탐지로 대조하지 않음" 1 0 -

# ---------------------------------------------------------------- 2. 출력 형식 오류

printf '[%s]\n' "$(exp_entry F1 src/a.ts 1 10 security Low)" >"$W/fmt.json"
bad_header() { # <설명> <줄>
	report "$W/fmt.md" "$2"
	run_score "$W/fmt.json" "$W/fmt.md"
	if [ "$SC_RC" = 3 ] && [ "$(verdict)" = format-error ]; then pass "형식 오류: $1"; else fail "형식 오류: $1" "exit $SC_RC verdict $(verdict)"; fi
}
bad_header '심각도 오타' "$(hdr S-01 Hihg High security src/a.ts:3)"
bad_header '줄 범위 없음' "$(hdr S-01 High High security src/a.ts)"
bad_header '확신도 필드 없음' "[S-01] High${SEP}security${SEP}src/a.ts:3"
bad_header '확신도 값 오류' "$(hdr S-01 High Certain security src/a.ts:3)"
bad_header '영역 slug 오류' "$(hdr S-01 High High secure src/a.ts:3)"
bad_header '영역에 a11y 사용' "$(hdr S-01 High High a11y src/a.ts:3)"
bad_header 'ID 한 자리' "$(hdr S-1 High High security src/a.ts:3)"
bad_header 'ID 뒤 공백 없음' "[S-01]High${SEP}확신도 High${SEP}security${SEP}src/a.ts:3"
bad_header '구분자 공백 없음' '[S-01] High·확신도 High·security·src/a.ts:3'
bad_header '역순 줄 범위' "$(hdr S-01 High High security src/a.ts:5-3)"
bad_header '0번 줄' "$(hdr S-01 High High security src/a.ts:0)"
bad_header '닫는 따옴표 없음' "$(hdr S-01 High High security '"src/a.ts:3')"
bad_header '따옴표 없는 큰따옴표' "$(hdr S-01 High High security 'src/a"b.ts:3')"
bad_header '따옴표 없는 역슬래시' "$(hdr S-01 High High security 'src/a\b.ts:3')"
bad_header "따옴표 없는 ' · '" "$(hdr S-01 High High security 'src/a · b.ts:3')"
bad_header "따옴표 없는 두 번째 ' → '" "$(hdr S-01 High High security 'a → b → c.ts:3')"
bad_header '알 수 없는 이스케이프' "$(hdr S-01 High High security '"src/a\qb.ts":3')"
bad_header '잘못된 삭제 표기' "$(hdr S-01 High High security 'src/a.ts:3 (deleted)')"
bad_header '마크다운 제목으로 꾸민 헤더' "### $(hdr S-01 High High security src/a.ts:3)"
bad_header '굵게 꾸민 헤더' "**$(hdr S-01 High High security src/a.ts:3)**"

# 정상 항목과 섞여 있어도 형식 오류가 우선
report "$W/fmt.md" "$(hdr S-01 High High security src/a.ts:3)" "$(hdr S-02 Hgh High security src/a.ts:4)"
run_score "$W/fmt.json" "$W/fmt.md"
assert_eq "형식 오류: 정상 항목과 섞여도 실행 실패(종료 코드 3)" "3" "$SC_RC"
assert_eq "형식 오류: 1건으로 집계" "1" "$(metric format_errors)"

# 해석된 옵션 줄이 없는 출력(빈 출력·중단된 출력)은 형식 오류
printf '%s\n' "$(hdr S-01 High High security src/a.ts:3)" >"$W/noopts.md"
run_score "$W/fmt.json" "$W/noopts.md"
assert_eq "형식 오류: '해석된 옵션:' 줄 없음" "3" "$SC_RC"
: >"$W/empty.md"
run_score "$W/fmt.json" "$W/empty.md"
assert_eq "형식 오류: 빈 보고서" "3" "$SC_RC"

# 헤더가 아닌 참조 줄은 오류가 아님
{
	printf '%s\n\n' "$OPTS"
	hdr S-01 High High security src/a.ts:3
	printf '  같은 원인: 없음\n- [S-01] 먼저 고치세요\n[Summary]\n우선 조치: [S-01] → [S-02]\n'
} >"$W/refs.md"
run_score "$W/fmt.json" "$W/refs.md"
expect_score "참조 줄(- [S-01] …, [Summary])은 형식 오류가 아님" 0 1 -

# ---------------------------------------------------------------- 3. 탐지 인정 규칙

printf '[%s]\n' "$(exp_entry T1 src/api/orders.ts 40 48 security High)" >"$W/t.json"

report "$W/t.md" "$(hdr S-01 High High security src/api/invoices.ts:40-48)"
run_score "$W/t.json" "$W/t.md"
expect_score "다른 파일의 같은 줄·같은 영역은 탐지 아님" 1 0 -

report "$W/t.md" "$(hdr S-01 Medium High security src/api/orders.ts:42)"
run_score "$W/t.json" "$W/t.md"
expect_score "minSeverity(High) 미만(Medium)은 탐지 아님" 1 0 -

report "$W/t.md" "$(hdr S-01 Critical Low security src/api/orders.ts:42)"
run_score "$W/t.json" "$W/t.md"
expect_score "minSeverity 이상(Critical)은 탐지" 0 1 -

report "$W/t.md" "$(hdr S-01 High High correctness src/api/orders.ts:42)"
run_score "$W/t.json" "$W/t.md"
expect_score "영역이 다르면 탐지 아님" 1 0 -

report "$W/t.md" "$(hdr S-01 High High security src/api/orders.ts:30-39)"
run_score "$W/t.json" "$W/t.md"
expect_score "겹치지 않는 줄 범위는 탐지 아님" 1 0 -

report "$W/t.md" "$(hdr S-01 High High security src/api/orders.ts:30-40)"
run_score "$W/t.json" "$W/t.md"
expect_score "경계에서 한 줄만 겹쳐도 탐지" 0 1 -

{
	printf '%s\n\n' "$OPTS"
	hdr S-01 High High security src/api/other.ts:1
	printf '  문제: 설명\n  같은 원인: src/api/a.ts:3, src/api/orders.ts:44-45\n'
} >"$W/t.md"
run_score "$W/t.json" "$W/t.md"
expect_score "'같은 원인:' 위치도 탐지로 인정" 0 1 -

# 80% 기준
{
	printf '[%s' "$(exp_entry P1 a.ts 1 1 security Low)"
	for i in 2 3 4 5; do printf ',%s' "$(exp_entry P$i a.ts "$i" "$i" security Low)"; done
	printf ']\n'
} >"$W/p.json"
report "$W/p.md" "$(hdr S-01 Low High security a.ts:1-4)"
run_score "$W/p.json" "$W/p.md"
expect_score "탐지율 4/5(80%)는 합격" 0 4 0
report "$W/p.md" "$(hdr S-01 Low High security a.ts:1-3)"
run_score "$W/p.json" "$W/p.md"
expect_score "탐지율 3/5(60%)는 불합격" 1 3 0

# ---------------------------------------------------------------- 4. mustNotFlag

printf '[%s,%s]\n' "$(exp_entry M1 src/q.ts 1 5 security Medium)" "$(nf_entry N1 src/safe.ts 10 20)" >"$W/n.json"

report "$W/n.md" "$(hdr S-01 High High security src/q.ts:2)" "$(hdr S-02 Medium Low security src/safe.ts:15)"
run_score "$W/n.json" "$W/n.md"
expect_score "mustNotFlag 위치·영역의 Medium 지적은 위반(탐지 100%여도 불합격)" 1 1 1

report "$W/n.md" "$(hdr S-01 High High security src/q.ts:2)" "$(hdr S-02 High High tests src/safe.ts:12-18)"
run_score "$W/n.json" "$W/n.md"
expect_score "mustNotFlag 위치라도 함정 영역 밖 지적은 위반 아님" 0 1 0

{
	printf '%s\n\n## 발견된 문제\n' "$OPTS"
	printf '%s\n  문제: 설명\n' "$(hdr S-01 High High security src/q.ts:2)"
	printf '%s\n  문제: 설명\n  같은 원인: src/other.ts:1, src/safe.ts:11-12\n' "$(hdr S-02 Medium High security src/other.ts:1)"
} >"$W/n.md"
run_score "$W/n.json" "$W/n.md"
expect_score "같은 원인 위치가 함정 영역·줄에 걸리면 위반" 1 1 1

printf '[%s,%s]\n' "$(exp_entry M1 src/q.ts 1 5 security Medium)" \
	'{"id":"N2","file":"src/safe.ts","lineRange":[10,20],"area":["security","correctness"],"mustDetect":false,"mustNotFlag":true}' >"$W/n2.json"
report "$W/n.md" "$(hdr S-01 High High security src/q.ts:2)" "$(hdr S-02 Medium High correctness src/safe.ts:15)"
run_score "$W/n2.json" "$W/n.md"
expect_score "영역이 여럿인 함정: 그중 하나면 위반" 1 1 1
assert_contains "위반 줄에 함정 영역 표시" "$SC_OUT" "[VIOL] N2 mustNotFlag security|correctness src/safe.ts:10-20"
report "$W/n.md" "$(hdr S-01 High High security src/q.ts:2)" "$(hdr S-02 Medium High performance src/safe.ts:15)"
run_score "$W/n2.json" "$W/n.md"
expect_score "영역이 여럿인 함정: 목록 밖 영역은 위반 아님" 0 1 0

report "$W/n.md" "$(hdr S-01 High High security src/q.ts:2)" "$(hdr S-02 Low High style src/safe.ts:15)"
run_score "$W/n.json" "$W/n.md"
expect_score "mustNotFlag 위치의 Low 지적은 위반 아님" 0 1 0

report "$W/n.md" "$(hdr S-01 High High security src/q.ts:2)" "$(hdr S-02 High High security src/other.ts:15)"
run_score "$W/n.json" "$W/n.md"
expect_score "다른 파일의 같은 줄은 mustNotFlag 위반 아님" 0 1 0

# clean-change 규칙: mustDetect 가 없으면 Medium 이상 0건이어야 합격
printf '[]\n' >"$W/clean.json"
report "$W/c.md"
run_score "$W/clean.json" "$W/c.md"
expect_score "clean: 발견 없음은 합격" 0 - -
report "$W/c.md" "$(hdr S-01 Low Medium readability src/x.ts:3)"
run_score "$W/clean.json" "$W/c.md"
expect_score "clean: Low 만 있으면 합격" 0 - -
report "$W/c.md" "$(hdr S-01 Medium High correctness src/x.ts:3)"
run_score "$W/clean.json" "$W/c.md"
expect_score "clean: Medium 1건이면 불합격" 1 - -
assert_eq "clean: medium_plus 집계" "1" "$(metric medium_plus)"

# ---------------------------------------------------------------- 5. 사용법·입력 오류

run_score
assert_eq "사용법: 인자 없음 → 2" "2" "$SC_RC"
run_score "$W/clean.json"
assert_eq "사용법: 인자 1개 → 2" "2" "$SC_RC"
run_score "$W/clean.json" "$W/missing.md"
assert_eq "사용법: 없는 보고서 → 2" "2" "$SC_RC"
printf '[{"id": ' >"$W/broken.json"
run_score "$W/broken.json" "$W/c.md"
assert_eq "입력 오류: 깨진 JSON → 2" "2" "$SC_RC"
printf '[{"id":"X","file":"a.ts","lineRange":[5,3],"area":"security","minSeverity":"Low","mustDetect":true}]\n' >"$W/badrange.json"
run_score "$W/badrange.json" "$W/c.md"
assert_eq "입력 오류: 역순 lineRange → 2" "2" "$SC_RC"
printf '[{"id":"X","file":"a.ts","lineRange":[1,3],"area":"a11y","minSeverity":"Low","mustDetect":true}]\n' >"$W/badarea.json"
run_score "$W/badarea.json" "$W/c.md"
assert_eq "입력 오류: 알 수 없는 area → 2" "2" "$SC_RC"

# 허용 영역 배열: 목록 안의 영역이면 탐지, 밖이면 미탐
printf '[{"id":"X","file":"a.ts","lineRange":[1,3],"area":["ops","correctness"],"minSeverity":"Low","mustDetect":true}]\n' >"$W/multi.json"
{
	printf '%s\n\n' "$OPTS"
	printf '[S-01] Medium%s확신도 High%scorrectness%sa.ts:2-2\n' "$SEP" "$SEP" "$SEP"
} >"$W/multi-hit.md"
run_score "$W/multi.json" "$W/multi-hit.md"
assert_eq "허용 영역 배열: 두 번째 영역도 탐지" "0" "$SC_RC"
{
	printf '%s\n\n' "$OPTS"
	printf '[S-01] Medium%s확신도 High%ssecurity%sa.ts:2-2\n' "$SEP" "$SEP" "$SEP"
} >"$W/multi-miss.md"
run_score "$W/multi.json" "$W/multi-miss.md"
assert_eq "허용 영역 배열: 목록 밖 영역은 미탐" "1" "$SC_RC"

# ---------------------------------------------------------------- 6. 품질 픽스처

count_field() { # <list 출력> <열 번호> <값>
	printf '%s\n' "$1" | awk -F'\t' -v c="$2" -v v="$3" '$1 == "expected" && $c == v { n++ } END { print n + 0 }'
}

for name in backend-api frontend-web infra clean-change; do
	case $name in
	backend-api) want_md=8 ;;
	frontend-web) want_md=9 ;;
	infra) want_md=4 ;;
	clean-change) want_md=0 ;;
	esac
	fx="$FIX/$name"
	json="$fx/expected-findings.json"
	repo="$W/fx-$name"

	if [ ! -d "$fx/base" ] || [ ! -d "$fx/change" ] || [ ! -f "$json" ]; then
		fail "$name: 픽스처 구성(base/, change/, expected-findings.json)"
		continue
	fi

	assert_exit "$name: setup.sh 성공" 0 /bin/bash "$SETUP" "$name" "$repo"
	[ -d "$repo/.git" ] || continue
	assert_eq "$name: feature 브랜치 체크아웃" "feature" "$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>&1)"
	assert_eq "$name: main 다음 커밋 1개" "1" "$(git -C "$repo" rev-list --count main..feature 2>&1)"
	assert_eq "$name: 작업 트리 깨끗함" "" "$(git -C "$repo" status --porcelain 2>&1)"
	if diff -r -x .git "$fx/change" "$repo" >/dev/null 2>&1; then pass "$name: 작업 트리 == change/"; else fail "$name: 작업 트리 == change/"; fi
	git -C "$repo" ls-tree -r --name-only main >"$W/main-files" 2>&1
	(cd "$fx/base" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) >"$W/base-files"
	if [ "$(LC_ALL=C sort "$W/main-files")" = "$(cat "$W/base-files")" ]; then pass "$name: main == base/"; else fail "$name: main == base/"; fi

	head_before=$(git -C "$repo" rev-parse HEAD)
	assert_exit "$name: 비어 있지 않은 대상은 거부" 1 /bin/bash "$SETUP" "$name" "$repo"
	assert_eq "$name: 거부 후 저장소 그대로" "$head_before" "$(git -C "$repo" rev-parse HEAD)"

	run_score --list-expected "$json"
	if [ "$SC_RC" != 0 ]; then
		fail "$name: expected-findings.json 형식" "$(printf '%s' "$SC_OUT" | head -2)"
		continue
	fi
	pass "$name: expected-findings.json 형식"
	list=$SC_OUT
	assert_eq "$name: mustDetect 항목 수" "$want_md" "$(count_field "$list" 8 mustDetect)"
	nf=$(count_field "$list" 9 mustNotFlag)
	if [ "$want_md" -eq 0 ]; then
		assert_eq "$name: mustNotFlag 없음(clean)" "0" "$nf"
	elif [ "$nf" -ge 2 ]; then
		pass "$name: 오탐 함정(mustNotFlag) 2개 이상 ($nf)"
	else
		fail "$name: 오탐 함정(mustNotFlag) 2개 이상" "got $nf"
	fi

	run_score --check-expected "$json" "$repo"
	if [ "$SC_RC" = 0 ]; then
		pass "$name: file·lineRange·anchor 가 change 트리와 일치"
	else
		fail "$name: file·lineRange·anchor 가 change 트리와 일치" "$(printf '%s\n' "$SC_OUT" | awk -F'\t' '$3 == "error" { print $2 ": " $4 }' | head -3 | tr '\n' ' ')"
	fi

	git -C "$repo" diff --name-only main...feature >"$W/changed" 2>&1
	missing=$(printf '%s\n' "$list" | awk -F'\t' '$1 == "expected" { print $3 }' | while IFS= read -r f; do
		grep -Fqx -- "$f" "$W/changed" || printf '%s ' "$f"
	done)
	assert_eq "$name: 기대 항목 파일이 모두 변경 파일" "" "$missing"

	# 정답 보고서(모든 mustDetect 를 정확히 지적) → 합격, 함정까지 Medium 으로 지적 → 위반
	{
		printf '%s\n\n## 발견된 문제\n' "$OPTS"
		printf '%s\n' "$list" | awk -F'\t' -v sep="$SEP" '
			$1 == "expected" && $8 == "mustDetect" {
				n++
				area = $6; sub(/\|.*/, "", area)   # 허용 영역이 여럿이면 첫 번째로 지적
				printf "[S-%02d] %s%s확신도 High%s%s%s%s:%d-%d\n  문제: 정답\n", n, $7, sep, sep, area, sep, $3, $4, $5
			}'
	} >"$W/oracle-$name.md"
	run_score "$json" "$W/oracle-$name.md"
	expect_score "$name: 정답 보고서는 합격(탐지 $want_md/$want_md)" 0 "$want_md" 0
	cp "$W/oracle-$name.md" "$W/decoy-$name.md"
	printf '%s\n' "$list" | awk -F'\t' -v sep="$SEP" '
		$1 == "expected" && $9 == "mustNotFlag" {
			n++
			area = $6; sub(/\|.*/, "", area)   # 함정 영역이 여럿이면 첫 번째로 지적
			printf "[S-%02d] Medium%s확신도 Medium%s%s%s%s:%d-%d\n", 90 + n, sep, sep, area, sep, $3, $4, $5
		}' >>"$W/decoy-$name.md"
	run_score "$json" "$W/decoy-$name.md"
	if [ "$want_md" -gt 0 ]; then
		expect_score "$name: 함정을 Medium 으로 지적하면 위반 ${nf}건" 1 "$want_md" "$nf"
	fi

	# collect-context.sh 가 기대 파일을 리뷰 대상으로 잡는지
	if [ ! -f "$COLLECT" ]; then
		skip "$name: collect-context.sh 대상 파일" "collect-context.sh 가 아직 없음"
		continue
	fi
	mf="$W/manifest-$name.txt"
	crc=0
	/bin/bash "$COLLECT" --scope changes --base main --repo "$repo" >"$mf" 2>"$W/collect-$name.err" || crc=$?
	assert_eq "$name: collect-context.sh 종료 코드 0" "0" "$crc"
	mf_section "$mf" FILES | awk -F'\t' '{ if ($1 ~ /^[RC]/) print $3; else print $2 }' >"$W/targets-$name"
	missing=$(printf '%s\n' "$list" | awk -F'\t' '$1 == "expected" { print $3 }' | while IFS= read -r f; do
		grep -Fqx -- "$f" "$W/targets-$name" || printf '%s ' "$f"
	done)
	assert_eq "$name: [FILES] 에 기대 파일이 모두 포함" "" "$missing"
	if [ "$name" = frontend-web ]; then
		mf_section "$mf" RULE_EXCLUDED | awk -F'\t' '{ print $1 }' >"$W/excluded-$name"
		for f in pnpm-lock.yaml src/components/__snapshots__/ProductCard.test.tsx.snap src/lib/types.generated.ts; do
			if grep -Fqx -- "$f" "$W/excluded-$name"; then pass "$name: 규칙 제외 $f"; else fail "$name: 규칙 제외 $f"; fi
			if grep -Fqx -- "$f" "$W/targets-$name"; then fail "$name: 규칙 제외 파일이 [FILES] 에 없음 ($f)"; else pass "$name: 규칙 제외 파일이 [FILES] 에 없음 ($f)"; fi
		done
		assert_eq "$name: rule_excluded 3" "3" "$(mf_get "$mf" rule_excluded)"
	fi
done

# ---------------------------------------------------------------- 7. run-quality.sh --dry-run

if [ ! -f "$RUNQ" ]; then
	skip "run-quality.sh --dry-run" "run-quality.sh 가 없음"
else
	fake="$W/fakebin"
	mkdir -p "$fake"
	for t in claude codex; do
		printf '#!/bin/bash\n: >"%s/invoked-%s"\nexit 0\n' "$W" "$t" >"$fake/$t"
		chmod +x "$fake/$t"
	done
	rc=0
	out=$(PATH="$fake:$PATH" /bin/bash "$RUNQ" --dry-run --tool both --runs 2 --fixtures backend-api,clean-change --out "$W/rq" 2>&1) || rc=$?
	assert_eq "run-quality --dry-run 종료 코드 0" "0" "$rc"
	assert_contains "run-quality --dry-run: claude 명령" "$out" "claude -p '/code-sentinel --changes --base main' --allowedTools 'Bash,Read,Grep,Glob'"
	assert_contains "run-quality --dry-run: codex 명령" "$out" "codex exec -C"
	assert_contains "run-quality --dry-run: codex 입력" "$out" "'\$code-sentinel --changes --base main'"
	assert_contains "run-quality --dry-run: 스킬 링크" "$out" ".claude/skills/code-sentinel"
	assert_contains "run-quality --dry-run: 채점 명령" "$out" "score-quality.sh"
	if [ -e "$W/invoked-claude" ] || [ -e "$W/invoked-codex" ]; then
		fail "run-quality --dry-run 은 AI 도구를 실행하지 않음"
	else
		pass "run-quality --dry-run 은 AI 도구를 실행하지 않음"
	fi
	if [ -e "$W/rq" ]; then fail "run-quality --dry-run 은 출력 디렉터리를 만들지 않음"; else pass "run-quality --dry-run 은 출력 디렉터리를 만들지 않음"; fi
	rc=0
	out=$(PATH="$fake:$PATH" /bin/bash "$RUNQ" --dry-run --normalization 2>&1) || rc=$?
	assert_eq "run-quality --dry-run --normalization 종료 코드 0" "0" "$rc"
	assert_contains "run-quality --normalization: 같은 항목 충돌 입력" "$out" "빠르게 꼼꼼히"
	if [ -e "$W/invoked-claude" ] || [ -e "$W/invoked-codex" ]; then
		fail "run-quality --dry-run --normalization 은 AI 도구를 실행하지 않음"
	else
		pass "run-quality --dry-run --normalization 은 AI 도구를 실행하지 않음"
	fi
	assert_exit "run-quality: 알 수 없는 --tool → 2" 2 /bin/bash "$RUNQ" --dry-run --tool gpt
	assert_exit "run-quality: 알 수 없는 픽스처 → 2" 2 /bin/bash "$RUNQ" --dry-run --fixtures nope
	assert_exit "run-quality: 잘못된 --runs → 2" 2 /bin/bash "$RUNQ" --dry-run --runs 0
fi

finish
