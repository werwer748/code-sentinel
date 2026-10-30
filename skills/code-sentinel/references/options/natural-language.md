# 옵션: 자연어 해석

입력에 플래그와 그 값이 아닌 텍스트가 있을 때 읽습니다. 매핑표는 `nl-scope.md`(범위, 기준 브랜치, 파일 필터)와 `nl-review.md`(깊이, 지적 강도, 심각도 하한, 집중 영역, 보고 상한)에 있고, 둘 다 함께 읽습니다. 플래그 규칙과 정규화 순서는 `flags.md`를 따릅니다.

## 1. 매핑 절차

1. 플래그와 그 값이 아닌 나머지 텍스트를 매핑표로 옵션에 대응시킵니다. 표현은 예시가 아니라 목록이며, 표에 없는 표현은 3절에 따라 처리합니다.
2. 겹치는 표현은 **가장 긴 표현을 먼저** 매칭하고, 텍스트의 한 부분은 한 번만 씁니다(예: "변경사항 전체"는 "전체"보다 먼저 매칭).
3. 한국어 조사·어미(은/는/이/가/을/를/만/으로/로/에서/해줘/봐줘 등)는 매칭에서 무시합니다. 단, "만", "빼고", "기준으로"처럼 매핑표가 의미를 두는 말은 그대로 씁니다.
4. 영어 표현은 대소문자를 구분하지 않습니다.
5. 매핑표가 정의하지 않은 일반 표현은 옵션으로 바꾸지 않습니다(3절).

## 2. 충돌 해결

1. **플래그 > 자연어:** 플래그로 정한 설정 항목에 대한 자연어 표현은 조용히 버립니다. 예: `--staged 전체 봐줘` → `--staged`.
   - `--files`나 `--exclude` 플래그가 하나라도 있으면, 같은 종류의 자연어 파일 필터는 버립니다.
   - `--base` 플래그는 범위가 `--changes`임을 전제하므로, 범위 플래그가 없을 때 자연어 범위 표현을 버리고 범위를 `--changes`로 확정합니다.
2. **자연어끼리:** 같은 설정 항목 안에서는 마지막 표현이 우선합니다. 예: `빠르게 꼼꼼히` → `--depth deep`, `꼼꼼히 빠르게` → `--depth quick`.
   - 설정 항목 단위: 범위, 기준 브랜치, 깊이, 지적 강도, 심각도 하한, 집중 영역, 보고 상한.
   - 다른 항목끼리는 충돌하지 않습니다. 예: `빠르게 엄격하게` → `--depth quick --strictness strict`.
   - 자연어 범위 표현끼리는 오류가 아니라 마지막 표현이 우선합니다(오류는 범위 **플래그** 2개 이상일 때만).
   - 자연어 파일 필터("src/api만", "docs 빼고")는 누적합니다.
   - 집중 영역은 한 표현 안에서 여러 영역을 나열하면 합칩니다("보안이랑 성능 위주로" → `security,performance`). 따로 떨어진 두 표현이면 마지막 표현이 우선합니다.
3. **자연어로 정한 기준 브랜치**는 최종 범위가 `--changes`일 때만 적용합니다. 다른 범위면 버리고 그 표현을 `해석하지 않은 표현`에 적습니다(오류로 만들지 않음).
4. 자연어는 오류를 만들지 않습니다. 오류는 플래그와 그 값에서만 생깁니다.

## 3. 해석하지 않은 표현

- 되묻지 않습니다. 해석한 결과로 진행합니다.
- 옵션처럼 보이지만 매핑표에 없는 표현은 옵션으로 바꾸지 않고, 보고서 요약의 `해석된 옵션:` 바로 다음 줄에 `해석하지 않은 표현: ...`으로 적습니다. 해당하는 것:
  - 단독 숫자("1234", "42번")
  - 브랜치·ref 이름("feature/login 브랜치", "develop")과 한정어 없는 경로("src/api 봐줘")
  - 지원하지 않는 범위 요청("커밋 안 한 것만", "최근 커밋 3개", "어제 이후")
  - 자연어로 정했지만 적용할 수 없어 버린 기준 브랜치(2절 3)
  - 검증 실행 요청("테스트 돌려줘", "run the tests"). 보고서에서 `--run-tests` 플래그를 쓰라고 안내합니다.
  - v1.0 고정값에 대한 요청("영어로", "고쳐줘", "JSON으로"). 출력 형식, 보고 언어, 수정 여부, 병렬 실행은 옵션이 없습니다.
- 여러 개면 입력 순서대로 `, `로 구분합니다. 원문 그대로 적습니다.
- 적지 않는 것: 리뷰 요청 문구("리뷰해줘", "봐줘", "검토 부탁", "please review", "코드 좀"), 인사·감탄, 변경 내용 설명("결제 재시도 로직 추가했어"). 변경 설명은 옵션이 아니라 **변경 의도**(사용자 설명)로 씁니다.
- `--run-tests`는 명령 실행이 따르므로 플래그로만 켭니다.

## 4. 예시

| 입력 | 해석된 옵션 (기준 브랜치가 origin/main으로 자동 결정된다고 가정) |
|---|---|
| `빠르게 꼼꼼히` | `--changes --base origin/main --depth deep --strictness balanced --min-severity low --focus all --max-findings 20` |
| `꼼꼼히 빠르게` | `--changes --base origin/main --depth quick --strictness balanced --min-severity low --focus all --max-findings 20` |
| `--depth quick 꼼꼼히` | `--changes --base origin/main --depth quick --strictness balanced --min-severity low --focus all --max-findings 20` |
| `--staged 전체 봐줘` | `--staged --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` |
| `보안 위주로 빠르게` | `--changes --base origin/main --depth quick --strictness balanced --min-severity low --focus security --max-findings 20` |
| `스타일 빼고` | `--changes --base origin/main --depth standard --strictness balanced --min-severity low --focus security,correctness,ops,architecture,performance,tests,readability --max-findings 20` |
| `main 기준으로 src/api만 엄격하게` | `--changes --base main --files src/api --depth standard --strictness strict --min-severity low --focus all --max-findings 20` |
| `--exclude docs --files src lib/util만` | `--changes --base origin/main --exclude docs --files src --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` (자연어 필터 `lib/util만`은 `--files` 플래그가 있으므로 버림) |
| `PR 42 main 기준으로` | `--pr 42 --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` + `해석하지 않은 표현: main 기준으로` |
| `1234 리뷰해줘` | 기본값 + `해석하지 않은 표현: 1234` |
| `--base develop 스테이징한 것만` | `--changes --base develop --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` (`--base` 플래그가 범위를 `--changes`로 확정) |
| `커밋 abc1234 말고 마지막 커밋을 엄격하게, 접근성 봐줘` | `--commit HEAD --depth standard --strictness strict --min-severity low --focus a11y --max-findings 20` (자연어 범위끼리는 마지막 표현 우선. "말고"는 경로나 영역 키워드 뒤가 아니므로 필터가 아님) |
