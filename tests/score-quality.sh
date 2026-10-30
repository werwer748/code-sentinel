#!/bin/bash
# tests/score-quality.sh — code-sentinel 리뷰 품질 채점기 (SPEC §13.2, §17.3)
#
# 사용법:
#   score-quality.sh <expected-findings.json> <report.md>   보고서 채점
#   score-quality.sh --parse <report.md>                    헤더 파싱 결과만 출력
#   score-quality.sh --list-expected <expected-findings.json>  기대 항목 검증·출력
#   score-quality.sh --check-expected <expected-findings.json> <fixture-repo>
#                                                           file·lineRange·anchor 가 저장소와 맞는지 확인
#
# 종료 코드: 0 합격(--parse/--list-expected/--check-expected 는 성공) · 1 불합격(--check-expected 는 불일치)
#            · 2 사용법·입력 오류 · 3 출력 형식 오류
#
# expected-findings.json: [{id, file, lineRange: [start, end], area, minSeverity, mustDetect,
#   mustNotFlag?, anchor?, description?}]. file 은 change 트리 기준 상대 경로, lineRange 는 change 트리의
#   줄 번호. mustNotFlag 항목(오탐 함정)은 mustDetect: false. anchor 는 lineRange 안에 있어야 하는 문자열
#   (픽스처 검증용), description 은 사람용 설명이며 채점에 쓰지 않는다.
#
# 채점 규칙
# - `[S-` 로 시작하는 줄은 발견 항목 헤더이며 다음 문법을 따라야 한다(어기면 출력 형식 오류).
#     [S-NN] <Critical|High|Medium|Low> · 확신도 <High|Medium|Low> · <영역 slug> · <위치>
#   앞에서부터 ` · ` 3개만 분리하고 나머지 전체가 위치다. 위치는 `경로:L` 또는 `경로:L-L`,
#   삭제는 끝에 ` (삭제)`, 이름 변경은 `이전경로 → 새경로:L-L`(새 경로로 대조). 제어문자·역슬래시·
#   큰따옴표·` · `·` → `가 든 경로는 C 스타일 따옴표("..." 안에 \n \t \\ \" \ooo)로 쓴다.
# - 추가 형식 검사(명세 §13.1·§17.3의 "형식 오류는 실행 실패" 취지를 지키기 위한 보강):
#   * 줄 앞에 마크다운 꾸밈(`### `, `**`, `- ` 등)이 붙었지만 나머지가 헤더 문법에 맞는 줄은 형식 오류
#     (채점에서 조용히 빠져 clean-change 가 거짓 합격하는 것을 막는다).
#   * `해석된 옵션:` 줄이 없는 출력은 형식 오류(빈 출력·중단된 출력을 "발견 0건"으로 세지 않는다).
# - 헤더 아래 `같은 원인:` 줄의 위치(쉼표+공백으로 여러 개 가능)도 같은 발견 항목의 위치로 센다.
#   해석하지 못한 `같은 원인:` 값은 형식 오류가 아니라 경고로만 출력한다.
# - 탐지: 디코딩한 경로 == file, 줄 범위 겹침, 영역 같음, 심각도 >= minSeverity. ` (삭제)` 위치는
#   변경 전 줄 번호이므로 대조하지 않는다.
# - mustNotFlag 위반: mustNotFlag 항목과 같은 파일·겹치는 줄에, 그 항목의 area(함정이 막으려는 잘못된 주장의
#   영역, 여럿이면 배열) 중 하나로 Medium 이상 지적. 다른 영역의 지적(예: 함정 줄을 덮는 "테스트 없음")은
#   위반이 아니다. `같은 원인:` 위치도 똑같이 센다.
# - 합격: mustDetect 가 있으면 탐지율 80% 이상이고 위반 0건. mustDetect 가 없으면(clean-change)
#   Medium 이상 발견 0건(위반 0건 포함).
#
# 출력: 사람이 읽는 요약 + 탭 구분 기계 판독 줄
#   metric<TAB>이름<TAB>값, expected<TAB>id<TAB>상태<TAB>근거, finding<TAB>..., format_error<TAB>..., verdict<TAB>pass|fail|format-error
# 경로는 기계 판독 줄에서 C 스타일 이스케이프(따옴표 없이) 형태로 출력한다.
#
# 의존성: macOS /bin/bash 3.2, /usr/bin/osascript(JavaScript, JSON.parse). jq·python·node 를 쓰지 않는다.

set -euo pipefail

usage() {
	cat <<'USAGE'
사용법:
  score-quality.sh <expected-findings.json> <report.md>
  score-quality.sh --parse <report.md>
  score-quality.sh --list-expected <expected-findings.json>
  score-quality.sh --check-expected <expected-findings.json> <fixture-repo>
종료 코드: 0 합격 · 1 불합격 · 2 사용법/입력 오류 · 3 출력 형식 오류
USAGE
}

abs_path() {
	case $1 in
	/*) printf '%s' "$1" ;;
	*) printf '%s/%s' "$(pwd -P)" "$1" ;;
	esac
}

need_file() {
	if [ ! -f "$1" ] || [ ! -r "$1" ]; then
		printf 'score-quality: 파일을 읽을 수 없습니다: %s\n' "$1" >&2
		exit 2
	fi
}

js_source() {
	cat <<'JS_EOF'
ObjC.import("Foundation");

var SEVS = ["Low", "Medium", "High", "Critical"];
var CONFS = ["Low", "Medium", "High"];
var AREAS = ["security", "correctness", "ops", "architecture", "performance", "tests", "readability", "style"];
var SEP = " \u00b7 ";
var ARROW = " \u2192 ";
var DEL_TEXT = " (\uc0ad\uc81c)";
var DEL_RE = " \\(\uc0ad\uc81c\\)";
var CONF_PREFIX = "\ud655\uc2e0\ub3c4 ";
var OPTIONS_LINE_RE = /^[\s>*_#`-]*\ud574\uc11d\ub41c \uc635\uc158:/;
var SAME_CAUSE_RE = /^[\s>*_#`-]*\uac19\uc740 \uc6d0\uc778:\**\s*(.*)$/;
var NONE_VALUES = ["", "-", "\u2014", "\uc5c6\uc74c", "N/A", "n/a"];

function readText(path) {
	var data = $.NSData.dataWithContentsOfFile(path);
	if (data.isNil()) { throw new Error("cannot read file: " + path); }
	var str = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
	if (str.isNil()) { throw new Error("file is not valid UTF-8: " + path); }
	return str.js;
}

function sevRank(s) { return SEVS.indexOf(s); }

function normSev(s) {
	if (typeof s !== "string") { return null; }
	var lower = s.toLowerCase();
	for (var i = 0; i < SEVS.length; i++) {
		if (SEVS[i].toLowerCase() === lower) { return SEVS[i]; }
	}
	return null;
}

function cesc(s) {
	var out = "";
	for (var i = 0; i < s.length; i++) {
		var c = s.charAt(i);
		var code = s.charCodeAt(i);
		if (c === "\\") { out += "\\\\"; }
		else if (c === "\"") { out += "\\\""; }
		else if (c === "\n") { out += "\\n"; }
		else if (c === "\t") { out += "\\t"; }
		else if (c === "\r") { out += "\\r"; }
		else if (code < 0x20 || code === 0x7f) { out += "\\" + ("00" + code.toString(8)).slice(-3); }
		else { out += c; }
	}
	return out;
}

function utf8Decode(bin) {
	try { return decodeURIComponent(escape(bin)); } catch (e) { return null; }
}

function utf8Encode(ch) {
	try { return unescape(encodeURIComponent(ch)); } catch (e) { return null; }
}

// s.charAt(i) === '"'. Git 과 같은 C 스타일 따옴표 경로를 해석한다.
function parseQuoted(s, i) {
	var simple = { "n": "\n", "t": "\t", "\\": "\\", "\"": "\"", "a": "\x07", "b": "\b", "f": "\f", "v": "\x0b", "r": "\r" };
	var bin = "";
	i++;
	while (i < s.length) {
		var c = s.charAt(i);
		if (c === "\"") {
			var value = utf8Decode(bin);
			if (value === null) { return { error: "따옴표 경로의 바이트열이 올바른 UTF-8 이 아님" }; }
			if (value === "") { return { error: "빈 경로" }; }
			return { value: value, next: i + 1 };
		}
		if (c === "\\") {
			var n = s.charAt(i + 1);
			if (Object.prototype.hasOwnProperty.call(simple, n)) {
				bin += simple[n];
				i += 2;
				continue;
			}
			var oct = s.substr(i + 1, 3);
			if (/^[0-3][0-7][0-7]$/.test(oct)) {
				bin += String.fromCharCode(parseInt(oct, 8));
				i += 4;
				continue;
			}
			return { error: "알 수 없는 이스케이프 \\" + n };
		}
		var code = s.charCodeAt(i);
		if (code < 0x20 || code === 0x7f) { return { error: "따옴표 경로 안에 이스케이프하지 않은 제어문자" }; }
		var ch = c;
		if (code >= 0xd800 && code <= 0xdbff && i + 1 < s.length) { ch = s.substr(i, 2); }
		var enc = utf8Encode(ch);
		if (enc === null) { return { error: "잘못된 문자" }; }
		bin += enc;
		i += ch.length;
	}
	return { error: "닫는 큰따옴표가 없음" };
}

function checkUnquoted(p) {
	if (p === "") { return "빈 경로"; }
	if (p.indexOf("\"") >= 0 || p.indexOf("\\") >= 0) { return "큰따옴표·역슬래시가 든 경로는 C 스타일 따옴표로 써야 함"; }
	if (p.indexOf(SEP) >= 0 || p.indexOf(ARROW) >= 0) { return "' \u00b7 '·' \u2192 '가 든 경로는 C 스타일 따옴표로 써야 함"; }
	if (/[\x00-\x1f\x7f]/.test(p)) { return "제어문자가 든 경로는 C 스타일 따옴표로 써야 함"; }
	return null;
}

// s[i..] 에서 경로 하나를 읽는다. 따옴표 없는 경로는 ` → `(allowArrow) 또는 `:줄범위`+종결자 앞에서 끝난다.
function parsePathAt(s, i, allowArrow, term) {
	if (s.charAt(i) === "\"") { return parseQuoted(s, i); }
	var ahead = ":[0-9]+(?:-[0-9]+)?(?:" + DEL_RE + ")?" + term;
	var re = new RegExp("^([\\s\\S]+?)(?=" + (allowArrow ? ARROW + "|" : "") + ahead + ")");
	var m = re.exec(s.slice(i));
	if (!m) { return { error: "위치에서 '경로:줄' 형식을 찾지 못함" }; }
	var bad = checkUnquoted(m[1]);
	if (bad) { return { error: bad }; }
	return { value: m[1], next: i + m[1].length };
}

// 위치 하나를 읽는다. listMode 이면 ", " 또는 끝에서 멈추고, 아니면 문자열 끝까지 소비해야 한다.
function parseLoc(s, i, listMode) {
	var term = listMode ? "(?:, |$)" : "$";
	var p1 = parsePathAt(s, i, true, term);
	if (p1.error) { return p1; }
	var oldPath = null;
	var path = p1.value;
	var j = p1.next;
	if (s.substr(j, ARROW.length) === ARROW) {
		oldPath = path;
		var p2 = parsePathAt(s, j + ARROW.length, false, term);
		if (p2.error) { return p2; }
		path = p2.value;
		j = p2.next;
	}
	var re = new RegExp("^:([0-9]+)(?:-([0-9]+))?(" + DEL_RE + ")?" + (listMode ? "(?:, |$)" : "$"));
	var m = re.exec(s.slice(j));
	if (!m) { return { error: "줄 범위 형식 오류(':L' 또는 ':L-L' 필요)" }; }
	var start = parseInt(m[1], 10);
	var end = m[2] === undefined ? start : parseInt(m[2], 10);
	if (start < 1 || end < start) { return { error: "줄 범위 값 오류(" + m[1] + (m[2] === undefined ? "" : "-" + m[2]) + ")" }; }
	return { path: path, oldPath: oldPath, start: start, end: end, deleted: m[3] !== undefined, next: j + m[0].length };
}

function parseHeader(line) {
	var m = /^\[S-([0-9]{2,})\] ([\s\S]*)$/.exec(line);
	if (!m) { return { error: "'[S-NN] ' 접두어 형식 오류" }; }
	var rest = m[2];
	var parts = [];
	for (var k = 0; k < 3; k++) {
		var idx = rest.indexOf(SEP);
		if (idx < 0) { return { error: "' \u00b7 ' 구분자가 3개 미만" }; }
		parts.push(rest.slice(0, idx));
		rest = rest.slice(idx + SEP.length);
	}
	if (SEVS.indexOf(parts[0]) < 0) { return { error: "심각도 값 오류: " + parts[0] }; }
	if (parts[1].indexOf(CONF_PREFIX) !== 0 || CONFS.indexOf(parts[1].slice(CONF_PREFIX.length)) < 0) {
		return { error: "확신도 형식 오류: " + parts[1] };
	}
	if (AREAS.indexOf(parts[2]) < 0) { return { error: "영역 slug 오류: " + parts[2] }; }
	var loc = parseLoc(rest, 0, false);
	if (loc.error) { return { error: loc.error }; }
	return {
		id: "S-" + m[1],
		severity: parts[0],
		confidence: parts[1].slice(CONF_PREFIX.length),
		area: parts[2],
		locs: [loc]
	};
}

function stripDecoration(line) {
	var s = line.replace(/^(?:[\s>*_#`+-]|[0-9]+[.)] )+/, "");
	s = s.replace(/[*_`]+$/, "");
	return s;
}

function parseReport(text) {
	var lines = text.split("\n");
	var findings = [];
	var errors = [];
	var warnings = [];
	var current = null;
	var hasOptions = false;
	for (var n = 0; n < lines.length; n++) {
		var line = lines[n].replace(/\r$/, "").replace(/[ \t]+$/, "");
		if (OPTIONS_LINE_RE.test(line)) { hasOptions = true; }
		if (line.indexOf("[S-") === 0) {
			var h = parseHeader(line);
			if (h.error) {
				errors.push({ line: n + 1, reason: h.error, text: line });
				current = null;
			} else {
				h.line = n + 1;
				findings.push(h);
				current = h;
			}
			continue;
		}
		var stripped = stripDecoration(line);
		if (stripped !== line && stripped.indexOf("[S-") === 0 && !parseHeader(stripped).error) {
			errors.push({ line: n + 1, reason: "헤더 앞뒤에 마크다운 꾸밈이 붙음(줄 맨 앞이 '[S-' 여야 함)", text: line });
			current = null;
			continue;
		}
		if (/^#{1,6} /.test(line)) { current = null; continue; }
		var sc = SAME_CAUSE_RE.exec(line);
		if (sc && current) {
			var value = sc[1].replace(/\*+$/, "");
			if (NONE_VALUES.indexOf(value) >= 0) { continue; }
			var pos = 0;
			while (pos < value.length) {
				var loc = parseLoc(value, pos, true);
				if (loc.error) {
					warnings.push({ line: n + 1, reason: "같은 원인 위치를 해석하지 못함: " + loc.error, text: line });
					break;
				}
				current.locs.push(loc);
				if (loc.next <= pos) { break; }
				pos = loc.next;
			}
		}
	}
	if (!hasOptions) {
		errors.push({ line: 0, reason: "'\ud574\uc11d\ub41c \uc635\uc158:' 줄이 없음(보고서가 아니거나 중단된 출력)", text: "" });
	}
	return { findings: findings, errors: errors, warnings: warnings };
}

function validateExpected(data) {
	if (Object.prototype.toString.call(data) !== "[object Array]") { throw new Error("expected-findings 최상위는 배열이어야 함"); }
	var seen = {};
	var out = [];
	for (var i = 0; i < data.length; i++) {
		var e = data[i];
		var where = "항목 #" + (i + 1);
		if (e === null || typeof e !== "object" || Object.prototype.toString.call(e) === "[object Array]") { throw new Error(where + ": 객체가 아님"); }
		if (typeof e.id !== "string" || e.id === "") { throw new Error(where + ": id 누락"); }
		where = "항목 " + e.id;
		if (seen[e.id]) { throw new Error(where + ": id 중복"); }
		seen[e.id] = true;
		if (typeof e.file !== "string" || e.file === "") { throw new Error(where + ": file 누락"); }
		var lr = e.lineRange;
		if (Object.prototype.toString.call(lr) !== "[object Array]" || lr.length !== 2 ||
			typeof lr[0] !== "number" || typeof lr[1] !== "number" ||
			Math.floor(lr[0]) !== lr[0] || Math.floor(lr[1]) !== lr[1] || lr[0] < 1 || lr[1] < lr[0]) {
			throw new Error(where + ": lineRange 는 [start, end] 양의 정수(start <= end)여야 함");
		}
		// area 는 문자열, 또는 §9.1 정의상 둘 이상이 정당한 경우 허용 영역 배열
		var areas = Object.prototype.toString.call(e.area) === "[object Array]" ? e.area : [e.area];
		if (areas.length < 1) { throw new Error(where + ": area 가 비어 있음"); }
		for (var ai = 0; ai < areas.length; ai++) {
			if (AREAS.indexOf(areas[ai]) < 0) { throw new Error(where + ": area 값 오류: " + areas[ai]); }
		}
		if (typeof e.mustDetect !== "boolean") { throw new Error(where + ": mustDetect 는 boolean 이어야 함"); }
		if (e.mustNotFlag !== undefined && typeof e.mustNotFlag !== "boolean") { throw new Error(where + ": mustNotFlag 는 boolean 이어야 함"); }
		var mnf = e.mustNotFlag === true;
		if (mnf && e.mustDetect) { throw new Error(where + ": mustDetect 와 mustNotFlag 를 함께 켤 수 없음"); }
		var sev = null;
		if (e.minSeverity !== undefined) {
			sev = normSev(e.minSeverity);
			if (sev === null) { throw new Error(where + ": minSeverity 값 오류: " + e.minSeverity); }
		} else if (e.mustDetect) {
			throw new Error(where + ": mustDetect 항목에는 minSeverity 가 필요함");
		}
		if (e.anchor !== undefined && typeof e.anchor !== "string") { throw new Error(where + ": anchor 는 문자열이어야 함"); }
		out.push({ id: e.id, file: e.file, start: lr[0], end: lr[1], area: areas.join("|"), areas: areas, minSeverity: sev,
			mustDetect: e.mustDetect, mustNotFlag: mnf, anchor: e.anchor === undefined ? "" : e.anchor });
	}
	return out;
}

function findingLines(findings) {
	var out = [];
	for (var i = 0; i < findings.length; i++) {
		var f = findings[i];
		for (var k = 0; k < f.locs.length; k++) {
			var l = f.locs[k];
			out.push(["finding", f.id, f.severity, f.confidence, f.area, cesc(l.path), l.start, l.end,
				l.deleted ? "deleted" : "-", l.oldPath === null ? "-" : cesc(l.oldPath), k === 0 ? "header" : "same-cause"].join("\t"));
		}
	}
	return out;
}

function errorLines(res) {
	var out = [];
	for (var i = 0; i < res.errors.length; i++) {
		var e = res.errors[i];
		out.push(["format_error", e.line, e.reason, cesc(e.text)].join("\t"));
	}
	for (var w = 0; w < res.warnings.length; w++) {
		var x = res.warnings[w];
		out.push(["warning", x.line, x.reason, cesc(x.text)].join("\t"));
	}
	return out;
}

function overlaps(l, e) { return l.path === e.file && !l.deleted && l.start <= e.end && e.start <= l.end; }

function score(expected, res) {
	var out = [];
	var mdTotal = 0, mdHit = 0, mnfTotal = 0, violations = 0, mediumPlus = 0, optHit = 0;
	for (var f = 0; f < res.findings.length; f++) {
		if (sevRank(res.findings[f].severity) >= sevRank("Medium")) { mediumPlus++; }
	}
	var human = [];
	var machine = [];
	for (var i = 0; i < expected.length; i++) {
		var e = expected[i];
		var by = [];
		for (var j = 0; j < res.findings.length; j++) {
			var fd = res.findings[j];
			var match = false;
			for (var k = 0; k < fd.locs.length; k++) {
				if (!overlaps(fd.locs[k], e)) { continue; }
				if (e.mustNotFlag) {
					if (e.areas.indexOf(fd.area) >= 0 && sevRank(fd.severity) >= sevRank("Medium")) { match = true; }
				} else if (e.areas.indexOf(fd.area) >= 0 && sevRank(fd.severity) >= sevRank(e.minSeverity === null ? "Low" : e.minSeverity)) {
					match = true;
				}
			}
			if (match) { by.push(fd.id + "(" + fd.severity + "/" + fd.area + ")"); }
		}
		var loc = cesc(e.file) + ":" + e.start + "-" + e.end;
		var state;
		if (e.mustNotFlag) {
			mnfTotal++;
			violations += by.length;
			state = by.length > 0 ? "violation" : "ok";
			human.push((by.length > 0 ? "[VIOL] " : "[OK  ] ") + e.id + " mustNotFlag " + e.area + " " + loc + (by.length > 0 ? " <- " + by.join(", ") : ""));
		} else if (e.mustDetect) {
			mdTotal++;
			if (by.length > 0) { mdHit++; }
			state = by.length > 0 ? "hit" : "miss";
			human.push((by.length > 0 ? "[HIT ] " : "[MISS] ") + e.id + " " + e.area + " >=" + e.minSeverity + " " + loc + (by.length > 0 ? " <- " + by.join(", ") : ""));
		} else {
			if (by.length > 0) { optHit++; }
			state = by.length > 0 ? "optional-hit" : "optional-miss";
			human.push("[OPT ] " + e.id + " " + e.area + " " + loc + (by.length > 0 ? " <- " + by.join(", ") : ""));
		}
		machine.push(["expected", e.id, state, by.length > 0 ? by.join(",") : "-"].join("\t"));
	}
	var verdict;
	if (res.errors.length > 0) {
		verdict = "format-error";
	} else if (mdTotal > 0) {
		verdict = (mdHit * 5 >= mdTotal * 4 && violations === 0) ? "pass" : "fail";
	} else {
		verdict = (mediumPlus === 0 && violations === 0) ? "pass" : "fail";
	}
	out.push("== code-sentinel 리뷰 품질 채점");
	out.push("발견 항목: " + res.findings.length + "건 (Medium 이상 " + mediumPlus + "건) · 출력 형식 오류 " + res.errors.length + "건 · 경고 " + res.warnings.length + "건");
	for (var h = 0; h < human.length; h++) { out.push(human[h]); }
	if (mdTotal > 0) {
		out.push("탐지: " + mdHit + "/" + mdTotal + " (" + Math.floor(mdHit * 1000 / mdTotal) / 10 + "%, 기준 80%) · mustNotFlag 위반 " + violations + "건");
	} else {
		out.push("mustDetect 없음(오탐 측정): Medium 이상 발견 " + mediumPlus + "건 · mustNotFlag 위반 " + violations + "건 (기준 0건)");
	}
	for (var r = 0; r < res.errors.length; r++) {
		var er = res.errors[r];
		out.push("형식 오류: " + (er.line > 0 ? er.line + "행: " : "") + er.reason + (er.text ? " | " + cesc(er.text) : ""));
	}
	out.push("판정: " + verdict);
	out.push(["metric", "mustdetect_total", mdTotal].join("\t"));
	out.push(["metric", "mustdetect_hit", mdHit].join("\t"));
	out.push(["metric", "detect_rate_pct", mdTotal > 0 ? Math.floor(mdHit * 100 / mdTotal) : 100].join("\t"));
	out.push(["metric", "mustnotflag_total", mnfTotal].join("\t"));
	out.push(["metric", "mustnotflag_violations", violations].join("\t"));
	out.push(["metric", "optional_hit", optHit].join("\t"));
	out.push(["metric", "findings", res.findings.length].join("\t"));
	out.push(["metric", "medium_plus", mediumPlus].join("\t"));
	out.push(["metric", "format_errors", res.errors.length].join("\t"));
	out.push(["metric", "warnings", res.warnings.length].join("\t"));
	out = out.concat(machine, findingLines(res.findings), errorLines(res));
	out.push(["verdict", verdict].join("\t"));
	return out.join("\n");
}

// 기대 항목의 file·lineRange·anchor 가 픽스처 저장소(change 트리)와 맞는지 확인한다.
function checkExpected(list, repo) {
	var out = [];
	var bad = 0;
	for (var i = 0; i < list.length; i++) {
		var e = list[i];
		var reason = null;
		var data = $.NSData.dataWithContentsOfFile(repo + "/" + e.file);
		var str = data.isNil() ? null : $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
		if (str === null || str.isNil()) {
			reason = "파일을 UTF-8 텍스트로 읽을 수 없음";
		} else {
			var lines = str.js.split("\n");
			if (lines.length > 0 && lines[lines.length - 1] === "") { lines.pop(); }
			if (e.end > lines.length) {
				reason = "lineRange 끝(" + e.end + ")이 파일 줄 수(" + lines.length + ")보다 큼";
			} else if (e.anchor !== "") {
				var found = false;
				for (var n = e.start - 1; n < e.end; n++) {
					if (lines[n].indexOf(e.anchor) >= 0) { found = true; }
				}
				if (!found) { reason = "anchor 가 lineRange 안에 없음"; }
			}
		}
		if (reason !== null) { bad++; }
		out.push(["check", e.id, reason === null ? "ok" : "error", reason === null ? "-" : reason, cesc(e.file), e.start, e.end].join("\t"));
	}
	out.push(["metric", "checked", list.length].join("\t"));
	out.push(["metric", "check_errors", bad].join("\t"));
	out.push(["verdict", bad === 0 ? "checked" : "check-failed"].join("\t"));
	return out.join("\n");
}

function run(argv) {
	var mode = argv[0];
	try {
		if (mode === "score") {
			var expected = validateExpected(JSON.parse(readText(argv[1])));
			return score(expected, parseReport(readText(argv[2])));
		}
		if (mode === "parse") {
			var res = parseReport(readText(argv[1]));
			var out = findingLines(res.findings).concat(errorLines(res));
			out.push(["metric", "findings", res.findings.length].join("\t"));
			out.push(["metric", "format_errors", res.errors.length].join("\t"));
			out.push(["verdict", res.errors.length > 0 ? "format-error" : "parsed"].join("\t"));
			return out.join("\n");
		}
		if (mode === "check") {
			return checkExpected(validateExpected(JSON.parse(readText(argv[1]))), argv[2]);
		}
		if (mode === "list") {
			var list = validateExpected(JSON.parse(readText(argv[1])));
			var lines = [];
			for (var i = 0; i < list.length; i++) {
				var e = list[i];
				lines.push(["expected", e.id, cesc(e.file), e.start, e.end, e.area, e.minSeverity === null ? "-" : e.minSeverity,
					e.mustDetect ? "mustDetect" : "-", e.mustNotFlag ? "mustNotFlag" : "-", cesc(e.anchor)].join("\t"));
			}
			lines.push(["verdict", "listed"].join("\t"));
			return lines.join("\n");
		}
		return ["error\t알 수 없는 모드", "verdict\tusage-error"].join("\n");
	} catch (err) {
		return ["error\t" + cesc(String(err && err.message ? err.message : err)), "verdict\tusage-error"].join("\n");
	}
}
JS_EOF
}

mode=score
case ${1:-} in
-h | --help)
	usage
	exit 0
	;;
--parse)
	[ $# -eq 2 ] || { usage >&2; exit 2; }
	mode=parse
	a=$(abs_path "$2")
	need_file "$a"
	set -- "$a"
	;;
--list-expected)
	[ $# -eq 2 ] || { usage >&2; exit 2; }
	mode=list
	a=$(abs_path "$2")
	need_file "$a"
	set -- "$a"
	;;
--check-expected)
	[ $# -eq 3 ] || { usage >&2; exit 2; }
	mode=check
	a=$(abs_path "$2")
	need_file "$a"
	if [ ! -d "$3" ]; then
		printf 'score-quality: 저장소 디렉터리가 아닙니다: %s\n' "$3" >&2
		exit 2
	fi
	b=$(cd -P "$3" && pwd -P)
	set -- "$a" "$b"
	;;
*)
	[ $# -eq 2 ] || { usage >&2; exit 2; }
	case $1 in -*) usage >&2; exit 2 ;; esac
	a=$(abs_path "$1")
	b=$(abs_path "$2")
	need_file "$a"
	need_file "$b"
	set -- "$a" "$b"
	;;
esac

if [ ! -x /usr/bin/osascript ]; then
	printf 'score-quality: /usr/bin/osascript 가 필요합니다(macOS 전용).\n' >&2
	exit 2
fi

js=$(js_source)
rc=0
out=$(/usr/bin/osascript -l JavaScript -e "$js" "$mode" "$@" 2>&1) || rc=$?
if [ "$rc" -ne 0 ]; then
	printf 'score-quality: osascript 실행 실패(exit %d): %s\n' "$rc" "$out" >&2
	exit 2
fi
printf '%s\n' "$out"

verdict=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "verdict" { v = $2 } END { print v }')
case $verdict in
pass | parsed | listed | checked) exit 0 ;;
fail | check-failed) exit 1 ;;
format-error) exit 3 ;;
*)
	printf '%s\n' "$out" | awk -F'\t' '$1 == "error" { print "score-quality: " $2 }' >&2
	exit 2
	;;
esac
