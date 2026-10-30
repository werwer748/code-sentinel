#!/bin/bash
# tests/run-quality.sh — 실제 Claude Code·Codex 로 code-sentinel 리뷰 품질을 검증한다 (SPEC §17.2, §17.3).
# 자동 테스트(tests/run.sh)에 포함하지 않는다. 실제 AI 도구를 호출하므로 사람이 직접 실행한다.
#
# 사용법:
#   run-quality.sh [--tool claude|codex|both] [--runs N] [--fixtures a,b,...] [--out DIR]
#                  [--max-seconds N] [--dry-run] [--normalization]
#
#   --tool          실행할 도구 (기본 both)
#   --runs          도구×픽스처마다 반복 횟수 (기본 3). 판정은 가장 낮은 결과 기준
#   --fixtures      쉼표로 구분한 픽스처 이름 (기본 backend-api,frontend-web,infra,clean-change)
#   --out           원본 출력·채점 결과를 보관할 디렉터리 (없거나 비어 있어야 함, 기본: 새 임시 디렉터리)
#   --max-seconds   리뷰 1회의 최대 실행 시간(초, 기본 1800, 0 이면 제한 없음). 넘으면 프로세스를 종료하고 미완료로 기록
#   --dry-run       실행할 명령만 출력한다. AI 도구를 실행하지 않고 파일·디렉터리도 만들지 않는다
#   --normalization 리뷰 대신 해석 일치 검증만 한다: 입력 5개(플래그 2, 자연어 3)를 clean-change 에서 두 도구로
#                   실행하고 보고서의 `해석된 옵션:` 줄을 비교한다
#
# 실행 방식 (리뷰 1회):
#   1. fixtures/review-quality/setup.sh <fixture> <임시 디렉터리>/repo 로 저장소를 만든다(main=base, feature=change).
#   2. 저장소 안에 프로젝트 스킬 링크를 만든다: .claude/skills/code-sentinel, .agents/skills/code-sentinel
#      → 이 저장소의 skills/code-sentinel(절대 경로). 두 디렉터리는 .git/info/exclude 에 넣어 리뷰 대상
#      (untracked)에서 뺀다. 사용자 스킬 디렉터리(~/.claude, ~/.agents, ~/.codex)와 설정은 건드리지 않는다.
#   3. Claude: (cd repo && claude -p '/code-sentinel --changes --base main' --allowedTools 'Bash,Read,Grep,Glob')
#      Codex : codex exec -C repo --sandbox workspace-write -o <파일> '$code-sentinel --changes --base main'
#   4. 실행 전후 저장소 상태(status, HEAD, refs, stash, index 내용, 작업 트리 해시)를 비교해 기록한다.
#   5. tests/score-quality.sh 로 채점하고, 원본 출력과 채점 결과를 --out 아래에 보관한다.
#
# 판정: 도구×픽스처마다 완료된 실행이 N 회 미만이면 불합격. 완료된 실행 중 하나라도 불합격(형식 오류 포함)이면
#       불합격(가장 낮은 결과 기준). 모든 조합이 합격이면 종료 코드 0, 아니면 1. 사용법 오류는 2.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$here/.." && pwd -P)
SKILL_SRC="$REPO_ROOT/skills/code-sentinel"
FIX="$here/fixtures/review-quality"
SETUP="$FIX/setup.sh"
SCORE="$here/score-quality.sh"

ALL_FIXTURES="backend-api,frontend-web,infra,clean-change"
REVIEW_INPUT='--changes --base main'
CLAUDE_TOOLS='Bash,Read,Grep,Glob'
OPTIONS_PREFIX='해석된 옵션:'

# 해석 일치 검증 입력: id|입력|참고용 기대 정규화 결과(두 도구 비교가 판정 기준이고, 이 값은 참고로만 기록)
NORMALIZATION_INPUTS='F1|--changes --base main|--changes --base main --depth standard --strictness balanced --min-severity low --focus all --max-findings 20
F2|--changes --base main --depth quick --focus security,a11y --max-findings 5|--changes --base main --depth quick --strictness balanced --min-severity low --focus security,a11y --max-findings 5
N1|main 기준으로 빠르게 꼼꼼히|--changes --base main --depth deep --strictness balanced --min-severity low --focus all --max-findings 20
N2|main 기준으로 보안 위주로 중요한 것만|--changes --base main --depth standard --strictness balanced --min-severity medium --focus security --max-findings 20
N3|main 기준으로 꼼꼼히 빠르게 스타일 빼고 엄격하게|--changes --base main --depth quick --strictness strict --min-severity low --focus security,correctness,ops,architecture,performance,tests,readability --max-findings 20'

usage() {
	sed -n '4,15p' "$0" | sed 's/^# \{0,1\}//'
}

die_usage() {
	printf 'run-quality: %s\n' "$1" >&2
	usage >&2
	exit 2
}

tool=both
runs=3
fixtures=$ALL_FIXTURES
out=""
max_seconds=1800
dry=0
norm=0

while [ $# -gt 0 ]; do
	case $1 in
	--tool)
		[ $# -ge 2 ] || die_usage '--tool 값이 필요합니다'
		tool=$2
		shift 2
		;;
	--runs)
		[ $# -ge 2 ] || die_usage '--runs 값이 필요합니다'
		runs=$2
		shift 2
		;;
	--fixtures)
		[ $# -ge 2 ] || die_usage '--fixtures 값이 필요합니다'
		fixtures=$2
		shift 2
		;;
	--out)
		[ $# -ge 2 ] || die_usage '--out 값이 필요합니다'
		out=$2
		shift 2
		;;
	--max-seconds)
		[ $# -ge 2 ] || die_usage '--max-seconds 값이 필요합니다'
		max_seconds=$2
		shift 2
		;;
	--dry-run)
		dry=1
		shift
		;;
	--normalization)
		norm=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die_usage "알 수 없는 인자: $1" ;;
	esac
done

case $tool in
claude | codex) tools=$tool ;;
both) tools='claude codex' ;;
*) die_usage "--tool 은 claude, codex, both 중 하나여야 합니다: $tool" ;;
esac
case $runs in
'' | *[!0-9]*) die_usage "--runs 는 1 이상의 정수여야 합니다: $runs" ;;
esac
[ "$runs" -ge 1 ] || die_usage "--runs 는 1 이상의 정수여야 합니다: $runs"
case $max_seconds in
'' | *[!0-9]*) die_usage "--max-seconds 는 0 이상의 정수여야 합니다: $max_seconds" ;;
esac
fixture_list=$(printf '%s' "$fixtures" | tr ',' ' ')
[ -n "$(printf '%s' "$fixture_list" | tr -d ' ')" ] || die_usage '--fixtures 가 비어 있습니다'
for f in $fixture_list; do
	case $f in */* | .*) die_usage "잘못된 픽스처 이름: $f" ;; esac
	if [ ! -d "$FIX/$f/base" ] || [ ! -d "$FIX/$f/change" ] || [ ! -f "$FIX/$f/expected-findings.json" ]; then
		die_usage "알 수 없는 픽스처: $f"
	fi
done
[ -f "$SKILL_SRC/SKILL.md" ] || [ "$dry" -eq 1 ] || {
	printf 'run-quality: %s/SKILL.md 가 없습니다.\n' "$SKILL_SRC" >&2
	exit 2
}

# ---------------------------------------------------------------- helpers

shq() {
	case $1 in
	'') printf "''" ;;
	*[!A-Za-z0-9_./:=@%+-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
	*) printf '%s' "$1" ;;
	esac
}

cmdline() {
	local first=1 a
	for a in "$@"; do
		[ $first -eq 1 ] || printf ' '
		shq "$a"
		first=0
	done
}

say() { printf '%s\n' "$*" >&2; }

# 저장소 상태 스냅샷(실행 전후 비교용). index 는 stat 갱신에 흔들리지 않게 ls-files -s 로 비교한다.
repo_state() {
	(
		cd "$1"
		export GIT_OPTIONAL_LOCKS=0
		git rev-parse HEAD
		git symbolic-ref -q HEAD || true
		git for-each-ref
		git stash list
		git ls-files -s
		git status --porcelain=v1 -uall
		find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r p; do
			printf '%s  %s\n' "$(shasum -a 256 "$p" | awk '{ print $1 }')" "$p"
		done
	)
}

context_dir_count() {
	local d=${TMPDIR:-/tmp} n=0 x
	for x in "${d%/}"/code-sentinel.*; do
		[ -e "$x" ] && n=$((n + 1))
	done
	printf '%d' "$n"
}

link_skill() {
	local repo=$1
	mkdir -p "$repo/.claude/skills" "$repo/.agents/skills" "$repo/.git/info"
	ln -s "$SKILL_SRC" "$repo/.claude/skills/code-sentinel"
	ln -s "$SKILL_SRC" "$repo/.agents/skills/code-sentinel"
	printf '.claude/\n.agents/\n' >>"$repo/.git/info/exclude"
}

# run_limited <초> <명령...> : 백그라운드로 실행하고 제한 시간을 넘으면 자식까지 종료한다(종료 코드 124).
run_limited() {
	local limit=$1 pid waited=0 rc=0
	shift
	"$@" &
	pid=$!
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$limit" -gt 0 ] && [ "$waited" -ge "$limit" ]; then
			pkill -TERM -P "$pid" 2>/dev/null || true
			kill -TERM "$pid" 2>/dev/null || true
			sleep 5
			pkill -KILL -P "$pid" 2>/dev/null || true
			kill -KILL "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			return 124
		fi
		sleep 2
		waited=$((waited + 2))
	done
	wait "$pid" || rc=$?
	return $rc
}

invoke_claude() { # <repo> <prompt> <out> <err>
	(cd "$1" && exec claude -p "$2" --allowedTools "$CLAUDE_TOOLS") </dev/null >"$3" 2>"$4"
}

invoke_codex() { # <repo> <prompt> <out> <log>
	codex exec -C "$1" --sandbox workspace-write -o "$3" "$2" </dev/null >"$4" 2>&1
}

# shellcheck disable=SC2016 # Codex 호출 표식 $code-sentinel 을 그대로 써야 한다
prompt_for() { # <tool> <input>
	if [ "$1" = claude ]; then printf '/code-sentinel %s' "$2"; else printf '$code-sentinel %s' "$2"; fi
}

show_tool_cmd() { # <tool> <repo> <prompt> <out> <err>
	if [ "$1" = claude ]; then
		printf '(cd %s && %s) </dev/null >%s 2>%s\n' "$(shq "$2")" \
			"$(cmdline claude -p "$3" --allowedTools "$CLAUDE_TOOLS")" "$(shq "$4")" "$(shq "$5")"
	else
		printf '%s </dev/null >%s 2>&1\n' \
			"$(cmdline codex exec -C "$2" --sandbox workspace-write -o "$4" "$3")" "$(shq "$5")"
	fi
}

tool_available() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 준비

if [ "$dry" -eq 1 ]; then
	work_root='<임시 작업 디렉터리>'
	[ -n "$out" ] || out='<임시 결과 디렉터리>'
	say "== dry-run: AI 도구를 실행하지 않고 파일도 만들지 않습니다."
else
	if [ -n "$out" ]; then
		if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
			printf 'run-quality: --out 디렉터리가 비어 있지 않습니다: %s\n' "$out" >&2
			exit 2
		fi
		mkdir -p "$out"
		out=$(cd -P "$out" && pwd -P)
	else
		out=$(mktemp -d "${TMPDIR:-/tmp}/cs-quality.XXXXXX")
		out=$(cd -P "$out" && pwd -P)
	fi
	work_root=$(mktemp -d "${TMPDIR:-/tmp}/cs-quality-work.XXXXXX")
	work_root=$(cd -P "$work_root" && pwd -P)
	trap 'rm -rf "$work_root"' EXIT
	trap 'exit 130' INT TERM HUP
fi

say "== code-sentinel 리뷰 품질 검증"
say "skill:  $SKILL_SRC"
say "out:    $out"
for t in $tools; do
	if tool_available "$t"; then
		say "tool:   $t ($(command -v "$t"))"
	else
		say "tool:   $t (없음 — 이 도구의 실행은 미완료로 기록)"
	fi
done
global_notes=""
for g in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/code-sentinel" "$HOME/.agents/skills/code-sentinel" "${CODEX_HOME:-$HOME/.codex}/skills/code-sentinel"; do
	if [ -e "$g" ] || [ -L "$g" ]; then
		say "WARN   전역 스킬이 이미 있음: $g (프로젝트 스킬과 어느 쪽이 로드됐는지 확인할 수 없음)"
		global_notes="$global_notes $g"
	fi
done
if [ "$dry" -eq 0 ]; then
	{
		printf 'started_at\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'skill\t%s\n' "$SKILL_SRC"
		for t in $tools; do
			if tool_available "$t"; then
				printf 'tool\t%s\t%s\t%s\n' "$t" "$(command -v "$t")" "$("$t" --version 2>/dev/null | head -1 || true)"
			else
				printf 'tool\t%s\tmissing\t-\n' "$t"
			fi
		done
		printf 'global_skill\t%s\n' "${global_notes:-none}"
		printf 'runs\t%s\nfixtures\t%s\nmax_seconds\t%s\n' "$runs" "$fixtures" "$max_seconds"
	} >"$out/environment.tsv"
fi

# ---------------------------------------------------------------- 해석 일치 검증

extract_options_line() { # <파일> : 첫 `해석된 옵션:` 줄(마크다운 꾸밈·앞뒤 공백 제거)
	[ -f "$1" ] || return 0
	awk -v p="$OPTIONS_PREFIX" '
		{ line = $0; sub(/\r$/, "", line); gsub(/^[ \t>*_`#-]+/, "", line); gsub(/[ \t*_`]+$/, "", line) }
		index(line, p) == 1 { print line; exit }' "$1"
}

if [ "$norm" -eq 1 ]; then
	say "== 해석 일치 검증 (clean-change, 입력 5개)"
	[ "$dry" -eq 1 ] || printf 'id\tinput\tclaude\tcodex\tsame\tclaude_matches_reference\tcodex_matches_reference\n' >"$out/normalization.tsv"
	all_same=1
	while IFS='|' read -r nid ninput nref; do
		[ -n "$nid" ] || continue
		line_claude=""
		line_codex=""
		for t in $tools; do
			dir="$work_root/norm-$t-$nid"
			repo="$dir/repo"
			raw="$out/normalization/$t/$nid.md"
			err="$out/normalization/$t/$nid.log"
			prompt=$(prompt_for "$t" "$ninput")
			if [ "$dry" -eq 1 ]; then
				printf '# 해석 일치 %s · %s · 입력: %s\n' "$nid" "$t" "$ninput"
				printf '%s\n' "$(cmdline /bin/bash "$SETUP" clean-change "$repo")"
				printf 'ln -s %s %s\n' "$(shq "$SKILL_SRC")" "$(shq "$repo/.claude/skills/code-sentinel")"
				printf 'ln -s %s %s\n' "$(shq "$SKILL_SRC")" "$(shq "$repo/.agents/skills/code-sentinel")"
				show_tool_cmd "$t" "$repo" "$prompt" "$raw" "$err"
				printf '# 참고 기대값: %s %s\n' "$OPTIONS_PREFIX" "$nref"
				continue
			fi
			mkdir -p "$dir" "$out/normalization/$t"
			if ! tool_available "$t"; then
				say "[$nid $t] 도구 없음"
				continue
			fi
			/bin/bash "$SETUP" clean-change "$repo" </dev/null >"$dir/setup.log" 2>&1
			link_skill "$repo"
			rc=0
			if [ "$t" = claude ]; then
				run_limited "$max_seconds" invoke_claude "$repo" "$prompt" "$raw" "$err" || rc=$?
			else
				run_limited "$max_seconds" invoke_codex "$repo" "$prompt" "$raw" "$err" || rc=$?
			fi
			l=$(extract_options_line "$raw")
			say "[$nid $t] exit $rc · ${l:-(해석된 옵션 줄 없음)}"
			if [ "$t" = claude ]; then line_claude=$l; else line_codex=$l; fi
			rm -rf "$dir"
		done
		[ "$dry" -eq 0 ] || continue
		same=no
		if [ -n "$line_claude" ] && [ "$line_claude" = "$line_codex" ]; then same=yes; else all_same=0; fi
		refm_claude=no
		refm_codex=no
		[ "$line_claude" = "$OPTIONS_PREFIX $nref" ] && refm_claude=yes
		[ "$line_codex" = "$OPTIONS_PREFIX $nref" ] && refm_codex=yes
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$nid" "$ninput" "${line_claude:--}" "${line_codex:--}" "$same" "$refm_claude" "$refm_codex" >>"$out/normalization.tsv"
	done <<EOF
$NORMALIZATION_INPUTS
EOF
	if [ "$dry" -eq 1 ]; then
		exit 0
	fi
	say "결과: $out/normalization.tsv"
	if [ "$all_same" -eq 1 ]; then
		say "판정: 해석 일치 5/5"
		exit 0
	fi
	say "판정: 해석 불일치 또는 미실행 항목 있음 (두 도구가 모두 있어야 비교 가능)"
	exit 1
fi

# ---------------------------------------------------------------- 리뷰 실행

[ "$dry" -eq 1 ] || printf 'tool\tfixture\trun\tstatus\ttool_exit\tseconds\treport_bytes\treport_lines\tverdict\thit\ttotal\tviolations\tmedium_plus\tformat_errors\treadonly\tcontext_dirs_left\n' >"$out/results.tsv"

for t in $tools; do
	for f in $fixture_list; do
		expected="$FIX/$f/expected-findings.json"
		i=1
		while [ "$i" -le "$runs" ]; do
			dir="$work_root/$t-$f-$i"
			repo="$dir/repo"
			rawdir="$out/raw/$t/$f"
			raw="$rawdir/run-$i.md"
			err="$rawdir/run-$i.log"
			scorefile="$rawdir/run-$i.score.txt"
			prompt=$(prompt_for "$t" "$REVIEW_INPUT")
			if [ "$dry" -eq 1 ]; then
				printf '# %s · %s · %d/%d\n' "$t" "$f" "$i" "$runs"
				printf '%s\n' "$(cmdline /bin/bash "$SETUP" "$f" "$repo")"
				printf 'ln -s %s %s\n' "$(shq "$SKILL_SRC")" "$(shq "$repo/.claude/skills/code-sentinel")"
				printf 'ln -s %s %s\n' "$(shq "$SKILL_SRC")" "$(shq "$repo/.agents/skills/code-sentinel")"
				printf "printf '.claude/\\\\n.agents/\\\\n' >>%s\n" "$(shq "$repo/.git/info/exclude")"
				show_tool_cmd "$t" "$repo" "$prompt" "$raw" "$err"
				printf '%s >%s\n' "$(cmdline /bin/bash "$SCORE" "$expected" "$raw")" "$(shq "$scorefile")"
				i=$((i + 1))
				continue
			fi

			mkdir -p "$dir" "$rawdir"
			status=completed
			trc=-
			secs=0
			bytes=0
			lines=0
			verdict=-
			hit=-
			total=-
			viol=-
			medp=-
			fmt=-
			ro=-
			left=-
			if ! tool_available "$t"; then
				status='tool-missing'
			elif ! /bin/bash "$SETUP" "$f" "$repo" </dev/null >"$dir/setup.log" 2>&1; then
				status='setup-failed'
				cp "$dir/setup.log" "$rawdir/run-$i.setup.log"
			else
				link_skill "$repo"
				repo_state "$repo" >"$dir/state.before"
				ctx_before=$(context_dir_count)
				t0=$(date +%s)
				trc=0
				if [ "$t" = claude ]; then
					run_limited "$max_seconds" invoke_claude "$repo" "$prompt" "$raw" "$err" || trc=$?
				else
					run_limited "$max_seconds" invoke_codex "$repo" "$prompt" "$raw" "$err" || trc=$?
				fi
				secs=$(($(date +%s) - t0))
				ctx_after=$(context_dir_count)
				left=$((ctx_after - ctx_before))
				[ "$left" -ge 0 ] || left=0
				repo_state "$repo" >"$dir/state.after"
				if cmp -s "$dir/state.before" "$dir/state.after"; then
					ro=unchanged
				else
					ro=changed
					diff "$dir/state.before" "$dir/state.after" >"$rawdir/run-$i.state-diff.txt" 2>&1 || true
				fi
				[ -f "$raw" ] || : >"$raw"
				bytes=$(wc -c <"$raw" | tr -d ' ')
				lines=$(wc -l <"$raw" | tr -d ' ')
				if [ "$trc" -eq 124 ]; then
					status='over-time'
				elif [ "$trc" -ne 0 ]; then
					status='tool-failed'
				elif [ "$bytes" -eq 0 ]; then
					status='empty-output'
				fi
				if [ "$status" = completed ]; then
					src=0
					/bin/bash "$SCORE" "$expected" "$raw" >"$scorefile" 2>&1 || src=$?
					verdict=$(awk -F'\t' '$1 == "verdict" { v = $2 } END { print v }' "$scorefile")
					[ -n "$verdict" ] || verdict="score-error($src)"
					hit=$(awk -F'\t' '$1 == "metric" && $2 == "mustdetect_hit" { print $3 }' "$scorefile")
					total=$(awk -F'\t' '$1 == "metric" && $2 == "mustdetect_total" { print $3 }' "$scorefile")
					viol=$(awk -F'\t' '$1 == "metric" && $2 == "mustnotflag_violations" { print $3 }' "$scorefile")
					medp=$(awk -F'\t' '$1 == "metric" && $2 == "medium_plus" { print $3 }' "$scorefile")
					fmt=$(awk -F'\t' '$1 == "metric" && $2 == "format_errors" { print $3 }' "$scorefile")
				fi
			fi
			printf '%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
				"$t" "$f" "$i" "$status" "$trc" "$secs" "$bytes" "$lines" "$verdict" "${hit:--}" "${total:--}" \
				"${viol:--}" "${medp:--}" "${fmt:--}" "$ro" "$left" >>"$out/results.tsv"
			say "[$t $f $i/$runs] $status · ${secs}s · verdict $verdict · 탐지 ${hit:--}/${total:--} · 위반 ${viol:--} · Medium+ ${medp:--} · 저장소 $ro"
			rm -rf "$dir"
			i=$((i + 1))
		done
	done
done

[ "$dry" -eq 0 ] || exit 0

# ---------------------------------------------------------------- 집계 (가장 낮은 결과 기준)

awk -F'\t' -v runs="$runs" '
	NR == 1 { next }
	{
		k = $1 "\t" $2
		if (!(k in seen)) { seen[k] = 1; order[++n] = k }
		if ($4 == "completed") {
			done[k]++
			if ($9 != "pass") bad[k]++
			if ($9 == "format-error") fe[k]++
			if ($10 != "-" && (!(k in minhit) || $10 + 0 < minhit[k])) minhit[k] = $10 + 0
			if ($11 != "-") total[k] = $11
			if ($12 != "-" && $12 + 0 > maxv[k]) maxv[k] = $12 + 0
			if ($13 != "-" && $13 + 0 > maxm[k]) maxm[k] = $13 + 0
			bytes[k] += $7; lines[k] += $8; secs[k] += $6
		}
		if ($15 == "changed") ro[k]++
	}
	END {
		print "tool\tfixture\tcompleted\truns\tmin_hit\ttotal\tmin_rate_pct\tmax_violations\tmax_medium_plus\tformat_error_runs\tavg_report_bytes\tavg_report_lines\tavg_seconds\trepo_changed_runs\tverdict"
		for (j = 1; j <= n; j++) {
			k = order[j]
			c = done[k] + 0
			mh = (k in minhit) ? minhit[k] : "-"
			tt = (k in total) ? total[k] : "-"
			rate = (tt != "-" && tt + 0 > 0 && mh != "-") ? int(mh * 100 / tt) : "-"
			v = (c == runs && bad[k] + 0 == 0) ? "pass" : "fail"
			printf "%s\t%d\t%d\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n", k, c, runs, mh, tt, rate, maxv[k] + 0, maxm[k] + 0, fe[k] + 0,
				c ? int(bytes[k] / c) : 0, c ? int(lines[k] / c) : 0, c ? int(secs[k] / c) : 0, ro[k] + 0, v
		}
	}' "$out/results.tsv" >"$out/summary.tsv"

{
	printf '| 도구 | 픽스처 | 완료/회 | 최소 탐지 | 최대 위반 | 최대 Medium+ | 형식 오류 실행 | 평균 보고서(줄/바이트) | 저장소 변경 실행 | 판정 |\n'
	printf '|---|---|---|---|---|---|---|---|---|---|\n'
	awk -F'\t' 'NR > 1 {
		hit = ($6 == "-" || $6 == 0) ? "-" : $5 "/" $6 " (" $7 "%)"
		printf "| %s | %s | %s/%s | %s | %s | %s | %s | %s / %s | %s | %s |\n", $1, $2, $3, $4, hit, $8, $9, $10, $12, $11, $14, ($15 == "pass" ? "합격" : "불합격")
	}' "$out/summary.tsv"
} >"$out/summary.md"

cat "$out/summary.md"
say ""
say "원본 출력: $out/raw  ·  실행별 결과: $out/results.tsv  ·  집계: $out/summary.tsv"
if awk -F'\t' 'NR > 1 && $15 != "pass" { bad = 1 } END { exit bad ? 0 : 1 }' "$out/summary.tsv"; then
	say "판정: 불합격 조합 있음"
	exit 1
fi
say "판정: 모든 조합 합격"
exit 0
