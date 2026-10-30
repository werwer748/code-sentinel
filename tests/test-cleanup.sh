#!/bin/bash
# tests/test-cleanup.sh — 임시 디렉터리 정리 (SPEC §6, §16.6)
. "$(dirname "$0")/lib.sh"
setup_sandbox

# ---------------------------------------------------------------- 로컬 헬퍼

# mk_ctx <부모> [이름] [created_at] : §6 계약대로 디렉터리와 마커를 만들고 경로를 출력
mk_ctx() {
	local parent=$1 name=${2:-} ts=${3:-} d tok
	[ -n "$ts" ] || ts=$(date +%s)
	if [ -n "$name" ]; then
		d="$parent/$name"
		(umask 077 && mkdir "$d")
	else
		d=$(umask 077 && mktemp -d "$parent/code-sentinel.XXXXXX")
	fi
	tok=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
	printf 'created_at %s\npid %s\ntoken %s\n' "$ts" "$$" "$tok" >"$d/.code-sentinel-context"
	echo data >"$d/diff.patch"
	printf '%s' "$d"
}

phys() { (cd -P "$1" && pwd -P); }

# count_ctx <디렉터리> : 바로 아래 code-sentinel.* 개수
count_ctx() {
	local n=0 d
	for d in "$1"/code-sentinel.*; do
		[ -e "$d" ] || [ -L "$d" ] || continue
		n=$((n + 1))
	done
	printf '%s' "$n"
}

# assert_kept <설명> <경로> : 경로가 남아 있어야 함
assert_kept() {
	if [ -e "$2" ]; then pass "$1"; else fail "$1" "삭제되면 안 되는 경로가 사라짐: $2"; fi
}
assert_gone() {
	if [ ! -e "$2" ] && [ ! -L "$2" ]; then pass "$1"; else fail "$1" "남아 있음: $2"; fi
}

T=$(phys "$TMPDIR")

# ---------------------------------------------------------------- 정상 정리

d=$(mk_ctx "$T")
assert_exit "정상 디렉터리 정리 (exit 0)" 0 /bin/bash "$CLEANUP" "$d"
assert_gone "정상 디렉터리 삭제됨" "$d"
assert_contains "삭제 경로 출력" "$LAST_OUT" "$d"

d=$(mk_ctx "$T")
assert_exit "끝에 / 가 붙은 인자도 정리" 0 /bin/bash "$CLEANUP" "$d/"
assert_gone "끝 / 인자 삭제됨" "$d"

assert_exit "이미 없는 디렉터리는 성공(멱등)" 0 /bin/bash "$CLEANUP" "$d"
assert_contains "이미 없음 메시지" "$LAST_OUT" "이미 없음"

# /var/... 표기(링크를 거친 경로)로 넘겨도 정리됨
VAR_PARENT=""
case "$T" in
/private/var/*) VAR_PARENT=${T#/private} ;;
esac
if [ -n "$VAR_PARENT" ] && [ -d "$VAR_PARENT" ]; then
	d=$(mk_ctx "$T")
	vd="$VAR_PARENT/${d##*/}"
	assert_exit "/var/... 표기 인자 정리" 0 /bin/bash "$CLEANUP" "$vd"
	assert_gone "/var/... 표기로 삭제됨" "$d"
	# TMPDIR 자체를 /var 표기로 설정한 경우
	d=$(mk_ctx "$T")
	vd="$VAR_PARENT/${d##*/}"
	assert_exit "TMPDIR=/var/... 일 때 /var 표기 인자 정리" 0 env TMPDIR="$VAR_PARENT" /bin/bash "$CLEANUP" "$vd"
	assert_gone "TMPDIR=/var/... 삭제됨" "$d"
else
	skip "/var/... 표기 정리" "임시 디렉터리가 /private/var 아래가 아님($T)"
fi

# 링크를 거친 TMPDIR 표기(어느 환경에서나 재현)
mkdir -p "$TEST_ROOT/real-tmp"
ln -s "$TEST_ROOT/real-tmp" "$TEST_ROOT/alias-tmp"
d=$(mk_ctx "$TEST_ROOT/real-tmp")
assert_exit "링크를 거친 TMPDIR 표기 인자 정리" 0 env TMPDIR="$TEST_ROOT/alias-tmp" /bin/bash "$CLEANUP" "$TEST_ROOT/alias-tmp/${d##*/}"
assert_gone "링크 TMPDIR 표기로 삭제됨" "$d"

# 공백이 든 TMPDIR
SP="$TEST_ROOT/tmp with space"
mkdir -p "$SP"
d=$(mk_ctx "$SP")
assert_exit "공백 든 TMPDIR 아래 정리" 0 env TMPDIR="$SP" /bin/bash "$CLEANUP" "$d"
assert_gone "공백 든 TMPDIR 아래 삭제됨" "$d"

# /tmp 바로 아래(TMPDIR 이 달라도 허용)
if d=$(mk_ctx /tmp 2>/dev/null) && [ -d "$d" ]; then
	assert_exit "/tmp 바로 아래 정리" 0 /bin/bash "$CLEANUP" "$d"
	assert_gone "/tmp 바로 아래 삭제됨" "$d"
	rm -rf "$d" 2>/dev/null || true
else
	skip "/tmp 바로 아래 정리" "/tmp 에 쓸 수 없음"
fi

# ---------------------------------------------------------------- 거부해야 하는 입력

PROJ="$TEST_ROOT/project"
mkdir -p "$PROJ/src"
echo 'important' >"$PROJ/src/app.ts"
# 프로젝트 안에 마커까지 갖춘 가짜 디렉터리(우회 시도용)
FAKE=$(mk_ctx "$PROJ" code-sentinel.ABC123)
# 프로젝트 자체에도 마커를 둔다
tok=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
printf 'created_at 1\npid 1\ntoken %s\n' "$tok" >"$PROJ/.code-sentinel-context"

ln -s "$PROJ" "$T/code-sentinel.LNK001"
assert_exit "심볼릭 링크 인자 거부" 1 /bin/bash "$CLEANUP" "$T/code-sentinel.LNK001"
assert_exit "심볼릭 링크 인자(끝 /) 거부" 1 /bin/bash "$CLEANUP" "$T/code-sentinel.LNK001/"
assert_kept "링크 대상 프로젝트 보존" "$PROJ/src/app.ts"
assert_kept "링크 자체 보존" "$T/code-sentinel.LNK001"
rm -f "$T/code-sentinel.LNK001"

ln -s "$FAKE" "$T/code-sentinel.LNK002"
assert_exit "마커 있는 디렉터리를 가리키는 링크 거부" 1 /bin/bash "$CLEANUP" "$T/code-sentinel.LNK002"
assert_kept "링크 대상(마커 있음) 보존" "$FAKE/diff.patch"
rm -f "$T/code-sentinel.LNK002"

ln -s "$PROJ" "$T/via"
assert_exit "임시 디렉터리 안 링크를 거쳐 프로젝트를 가리키는 우회 거부" 1 /bin/bash "$CLEANUP" "$T/via/code-sentinel.ABC123"
assert_contains "우회 거부 사유(바로 아래 아님)" "$LAST_OUT" "바로 아래"
assert_kept "우회 대상 보존" "$FAKE/diff.patch"
rm -f "$T/via"

d=$(mk_ctx "$T")
assert_exit "'..' 포함 경로 거부" 1 /bin/bash "$CLEANUP" "$d/../${d##*/}"
assert_exit "'..' 로 끝나는 경로 거부" 1 /bin/bash "$CLEANUP" "$d/sub/.."
assert_kept "'..' 거부 후 보존" "$d"

NLD="$T/code-sentinel.ab"$'\n'"cd"
mkdir "$NLD"
tok=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
printf 'created_at 1\npid 1\ntoken %s\n' "$tok" >"$NLD/.code-sentinel-context"
assert_exit "개행 포함 경로 거부" 1 /bin/bash "$CLEANUP" "$NLD"
assert_kept "개행 경로 보존" "$NLD"
TBD="$T/code-sentinel.ab"$'\t'"cd"
mkdir "$TBD"
assert_exit "탭 포함 경로 거부" 1 /bin/bash "$CLEANUP" "$TBD"
assert_kept "탭 경로 보존" "$TBD"

d="$T/code-sentinel.NOMARK"
mkdir "$d"
assert_exit "마커 없는 디렉터리 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_contains "마커 없음 사유" "$LAST_OUT" "마커"
assert_kept "마커 없는 디렉터리 보존" "$d"

d="$T/code-sentinel.MLINK1"
mkdir "$d"
tok=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
printf 'created_at 1\npid 1\ntoken %s\n' "$tok" >"$TEST_ROOT/marker-real"
ln -s "$TEST_ROOT/marker-real" "$d/.code-sentinel-context"
assert_exit "마커가 심볼릭 링크면 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_kept "마커 링크 디렉터리 보존" "$d"

d="$T/code-sentinel.MDIR01"
mkdir -p "$d/.code-sentinel-context"
assert_exit "마커가 디렉터리면 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_kept "마커 디렉터리 보존" "$d"

d=$(mk_ctx "$T")
printf 'created_at 1\npid 1\ntoken XYZ\n' >"$d/.code-sentinel-context"
assert_exit "마커 형식 오류(token) 거부" 1 /bin/bash "$CLEANUP" "$d"
tok=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
printf 'created_at 1\npid 1\ntoken %s\nextra line\n' "$tok" >"$d/.code-sentinel-context"
assert_exit "마커 형식 오류(줄 수) 거부" 1 /bin/bash "$CLEANUP" "$d"
printf 'pid 1\ncreated_at 1\ntoken %s\n' "$tok" >"$d/.code-sentinel-context"
assert_exit "마커 형식 오류(순서) 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_kept "형식 오류 디렉터리 보존" "$d"

d=$(mk_ctx "$T" other-prefix.ABC123)
assert_exit "접두어가 다른 이름 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_kept "접두어 다른 디렉터리 보존" "$d"

mkdir -p "$T/nest"
d=$(mk_ctx "$T/nest")
assert_exit "임시 디렉터리 바로 아래가 아닌 경로 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_kept "중첩 디렉터리 보존" "$d"

d=$(mk_ctx "$PROJ")
assert_exit "임시 디렉터리 밖(프로젝트 안) 거부" 1 /bin/bash "$CLEANUP" "$d"
assert_kept "프로젝트 안 디렉터리 보존" "$d"

assert_exit "빈 인자 거부" 1 /bin/bash "$CLEANUP" ""
assert_exit "인자 없음은 사용법 오류" 2 /bin/bash "$CLEANUP"
d=$(mk_ctx "$T")
d2=$(mk_ctx "$T")
assert_exit "인자 2개는 사용법 오류" 2 /bin/bash "$CLEANUP" "$d" "$d2"
assert_kept "인자 2개 거부 후 보존(1)" "$d"
assert_kept "인자 2개 거부 후 보존(2)" "$d2"
assert_exit "상대 경로 거부" 1 /bin/bash -c 'cd "$1" && /bin/bash "$2" "$3"' _ "$T" "$CLEANUP" "${d##*/}"
assert_kept "상대 경로 거부 후 보존" "$d"
assert_exit "'/' 거부" 1 /bin/bash "$CLEANUP" /
assert_exit "\$HOME 거부" 1 /bin/bash "$CLEANUP" "$HOME"
assert_kept "\$HOME 보존" "$HOME"
assert_exit "작업 디렉터리 거부" 1 /bin/bash -c 'cd "$1" && /bin/bash "$2" "$PWD"' _ "$PROJ" "$CLEANUP"
assert_kept "작업 디렉터리 보존" "$PROJ/src/app.ts"
assert_exit "TMPDIR 자체 거부" 1 /bin/bash "$CLEANUP" "$TMPDIR"
assert_exit "/tmp 자체 거부" 1 /bin/bash "$CLEANUP" /tmp
assert_kept "TMPDIR 보존" "$TMPDIR"
# TMPDIR 자체에 마커와 접두어 이름을 붙여도 부모 조건 때문에 거부
CT="$TEST_ROOT/code-sentinel.TMPDIR"
mkdir -p "$CT"
tok=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
printf 'created_at 1\npid 1\ntoken %s\n' "$tok" >"$CT/.code-sentinel-context"
assert_exit "TMPDIR 자체(마커·접두어 갖춤) 거부" 1 env TMPDIR="$CT" /bin/bash "$CLEANUP" "$CT"
assert_kept "TMPDIR 자체(마커) 보존" "$CT"

# 다른 사용자 소유
if [ "$(id -u)" = 0 ]; then
	d=$(mk_ctx "$T")
	if chown nobody "$d" 2>/dev/null; then
		assert_exit "다른 사용자 소유 디렉터리 거부" 1 /bin/bash "$CLEANUP" "$d"
		assert_kept "다른 사용자 소유 보존" "$d"
	else
		skip "다른 사용자 소유 디렉터리" "chown 실패"
	fi
else
	skip "다른 사용자 소유 디렉터리" "root 가 아니라 다른 사용자 소유 디렉터리를 만들 수 없음"
fi

# ---------------------------------------------------------------- 삭제 실패

d=$(mk_ctx "$T")
mkdir -p "$d/ro"
echo x >"$d/ro/file"
chmod 500 "$d/ro"
assert_exit "삭제 실패 시 0 이 아닌 코드(3)" 3 /bin/bash "$CLEANUP" "$d"
assert_contains "삭제 실패 시 남은 경로 출력" "$LAST_OUT" "남은 경로: $d"
assert_kept "삭제 실패 시 마커 유지(재시도 가능)" "$d/.code-sentinel-context"
assert_gone "삭제 실패 시에도 다른 파일은 지움" "$d/diff.patch"
chmod 700 "$d/ro"
assert_exit "권한 복구 후 정리" 0 /bin/bash "$CLEANUP" "$d"

# ---------------------------------------------------------------- --stale

ST="$TEST_ROOT/stale-tmp"
mkdir -p "$ST"
now=$(date +%s)
old=$((now - 3 * 86400))
OLD_OK=$(mk_ctx "$ST" "" "$old")
NEW_OK=$(mk_ctx "$ST" "" "$now")
OLD_BAD="$ST/code-sentinel.OLDBAD"
mkdir "$OLD_BAD"
printf 'created_at %s\npid 1\ntoken nothex\n' "$old" >"$OLD_BAD/.code-sentinel-context"
OLD_NOMARK="$ST/code-sentinel.NOMRK2"
mkdir "$OLD_NOMARK"
touch -t 202001010000 "$OLD_NOMARK"
OLD_LINK="$ST/code-sentinel.OLDLNK"
OLD_TARGET=$(mk_ctx "$TEST_ROOT" code-sentinel.TARGET "$old")
ln -s "$OLD_TARGET" "$OLD_LINK"
OLD_OTHER=$(mk_ctx "$ST" other.ABCDEF "$old")
OLD_ALT=$(mk_ctx "$ST" "" "$((now - 2 * 3600))")

# --stale 은 ${TMPDIR} 와 /tmp 를 모두 훑는다. 테스트 밖의 실제 /tmp 항목을 건드리지 않도록
# /tmp 에 code-sentinel.* 가 이미 있으면 실행 단계를 건너뛴다.
if [ "$(count_ctx /tmp)" = 0 ]; then
	assert_exit "--stale 기본(1440분) 실행" 0 env TMPDIR="$ST" /bin/bash "$CLEANUP" --stale
	assert_gone "--stale: 오래된 정상 디렉터리 삭제" "$OLD_OK"
	assert_kept "--stale: 최근 디렉터리 유지" "$NEW_OK"
	assert_kept "--stale: 2시간 된 디렉터리 유지(기본 1440분)" "$OLD_ALT"
	assert_kept "--stale: 마커 형식 오류 유지" "$OLD_BAD"
	assert_kept "--stale: 마커 없는 디렉터리 유지" "$OLD_NOMARK"
	assert_kept "--stale: 링크 유지" "$OLD_LINK"
	assert_kept "--stale: 링크 대상 유지" "$OLD_TARGET/diff.patch"
	assert_kept "--stale: 접두어 다른 디렉터리 유지" "$OLD_OTHER"

	assert_exit "--stale 60분 실행" 0 env TMPDIR="$ST" /bin/bash "$CLEANUP" --stale 60
	assert_gone "--stale 60: 2시간 된 디렉터리 삭제" "$OLD_ALT"
	assert_kept "--stale 60: 최근 디렉터리 유지" "$NEW_OK"
else
	skip "--stale 실행" "실제 /tmp 에 code-sentinel.* 가 있어 테스트 밖 항목을 건드리지 않으려고 건너뜀"
fi
assert_exit "--stale 값 오류는 사용법 오류" 2 /bin/bash "$CLEANUP" --stale abc
assert_exit "--stale 인자 과다는 사용법 오류" 2 /bin/bash "$CLEANUP" --stale 1 2

# ---------------------------------------------------------------- collect-context.sh 연동

if [ ! -f "$COLLECT" ]; then
	skip "collect-context.sh context_dir 실제 경로" "collect-context.sh 가 아직 없음"
	skip "collect-context.sh 실패 시 자체 정리" "collect-context.sh 가 아직 없음"
	skip "collect-context.sh INT 시 자체 정리" "collect-context.sh 가 아직 없음"
	skip "collect-context.sh TERM 시 자체 정리" "collect-context.sh 가 아직 없음"
else
	REPO="$TEST_ROOT/repo"
	new_repo "$REPO"
	(
		cd "$REPO" || exit 1
		echo one >a.txt
		gcommit init
		echo two >>a.txt
		git add a.txt
	)

	# context_dir 실제 경로 + 링크 표기로 정리
	CT1="$TEST_ROOT/ctx-real"
	mkdir -p "$CT1"
	ln -s "$CT1" "$TEST_ROOT/ctx-alias"
	ALIAS_TMP="$TEST_ROOT/ctx-alias"
	if [ -n "$VAR_PARENT" ]; then ALIAS_TMP="$VAR_PARENT"; CT1=$T; fi
	MF="$TEST_ROOT/manifest.txt"
	if TMPDIR="$ALIAS_TMP" /bin/bash "$COLLECT" --scope staged --repo "$REPO" >"$MF" 2>"$TEST_ROOT/collect.err"; then
		cdir=$(mf_get "$MF" context_dir)
		if [ -n "$cdir" ] && [ -d "$cdir" ]; then
			assert_eq "context_dir 가 실제 경로(pwd -P)" "$(phys "$cdir")" "$cdir"
			assert_eq "context_dir 가 실제 TMPDIR 바로 아래" "$(phys "$CT1")" "${cdir%/*}"
			case "$cdir" in
			/var/*) fail "context_dir 가 /var 표기가 아님" "$cdir" ;;
			*) pass "context_dir 가 /var 표기가 아님" ;;
			esac
			assert_kept "collect 정상 종료 후 context_dir 유지" "$cdir"
			alias_path="$ALIAS_TMP/${cdir##*/}"
			assert_exit "링크 표기(/var 등) context_dir 정리" 0 env TMPDIR="$ALIAS_TMP" /bin/bash "$CLEANUP" "$alias_path"
			assert_gone "collect context_dir 삭제됨" "$cdir"
		else
			fail "collect-context.sh context_dir 출력" "context_dir 없음: $(head -3 "$MF")"
		fi
	else
		fail "collect-context.sh --scope staged 실행" "$(head -3 "$TEST_ROOT/collect.err")"
	fi

	# 공백 든 TMPDIR 에서 collect → cleanup
	SPC="$TEST_ROOT/collect tmp space"
	mkdir -p "$SPC"
	if TMPDIR="$SPC" /bin/bash "$COLLECT" --scope staged --repo "$REPO" >"$MF" 2>/dev/null; then
		cdir=$(mf_get "$MF" context_dir)
		assert_exit "공백 TMPDIR 의 collect context_dir 정리" 0 env TMPDIR="$SPC" /bin/bash "$CLEANUP" "$cdir"
		assert_gone "공백 TMPDIR collect context_dir 삭제됨" "$cdir"
	else
		fail "공백 TMPDIR 에서 collect-context.sh 실행"
	fi

	# 실패 경로에서 자체 정리
	FT="$TEST_ROOT/fail-tmp"
	mkdir -p "$FT"
	rc=0
	TMPDIR="$FT" /bin/bash "$COLLECT" --scope commit --ref no-such-ref-xyz --repo "$REPO" >/dev/null 2>&1 || rc=$?
	assert_eq "잘못된 ref 는 종료 코드 5" 5 "$rc"
	assert_eq "잘못된 ref 실패 후 임시 디렉터리 남지 않음" 0 "$(count_ctx "$FT")"
	rc=0
	TMPDIR="$FT" /bin/bash "$COLLECT" --scope changes --repo "$REPO" >/dev/null 2>&1 || rc=$?
	assert_eq "기준 브랜치 미결정은 종료 코드 4" 4 "$rc"
	assert_eq "기준 미결정 실패 후 임시 디렉터리 남지 않음" 0 "$(count_ctx "$FT")"
	rc=0
	TMPDIR="$FT" /bin/bash "$COLLECT" --scope staged --repo "$TEST_ROOT/project" >/dev/null 2>&1 || rc=$?
	assert_eq "Git 저장소 아님은 종료 코드 3" 3 "$rc"
	assert_eq "저장소 아님 실패 후 임시 디렉터리 남지 않음" 0 "$(count_ctx "$FT")"

	# INT·TERM 신호에서 자체 정리: git 호출을 느리게 만들어 실행 중에 신호를 보낸다.
	REAL_GIT=$(command -v git)
	SLOW="$TEST_ROOT/slowbin"
	mkdir -p "$SLOW"
	cat >"$SLOW/git" <<EOF
#!/bin/bash
sleep 0.2
exec "$REAL_GIT" "\$@"
EOF
	chmod +x "$SLOW/git"

	signal_case() {
		local sig=$1 st="$TEST_ROOT/sig-$1" pid i rc found=0
		mkdir -p "$st"
		set -m
		PATH="$SLOW:$PATH" TMPDIR="$st" /bin/bash "$COLLECT" --scope staged --repo "$REPO" >/dev/null 2>&1 &
		pid=$!
		set +m
		i=0
		while [ "$i" -lt 150 ]; do
			if [ "$(count_ctx "$st")" != 0 ]; then found=1; break; fi
			kill -0 "$pid" 2>/dev/null || break
			sleep 0.05
			i=$((i + 1))
		done
		if [ "$found" != 1 ] || ! kill -0 "$pid" 2>/dev/null; then
			wait "$pid" 2>/dev/null || true
			if [ "$(count_ctx "$st")" != 0 ]; then
				skip "collect-context.sh $sig 시 자체 정리" "신호를 보내기 전에 수집이 끝남"
			else
				skip "collect-context.sh $sig 시 자체 정리" "실행 중 임시 디렉터리를 관찰하지 못함"
			fi
			return 0
		fi
		kill -"$sig" "$pid" 2>/dev/null || true
		rc=0
		wait "$pid" 2>/dev/null || rc=$?
		i=0
		while [ "$i" -lt 40 ] && [ "$(count_ctx "$st")" != 0 ]; do
			sleep 0.05
			i=$((i + 1))
		done
		if [ "$rc" = 0 ]; then
			fail "collect-context.sh $sig 시 0 이 아닌 종료" "rc=0"
		else
			pass "collect-context.sh $sig 시 0 이 아닌 종료"
		fi
		assert_eq "collect-context.sh $sig 시 임시 디렉터리 자체 정리" 0 "$(count_ctx "$st")"
	}
	signal_case INT
	signal_case TERM
fi

finish
