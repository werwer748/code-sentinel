# 자연어 매핑표: 깊이, 지적 강도, 심각도 하한, 집중 영역, 보고 상한

`natural-language.md`의 절차로 씁니다. SPEC의 기본 매핑(굵게 표시)에 동의어를 더한 목록이며, 여기와 `nl-scope.md`에 없는 표현은 옵션으로 바꾸지 않습니다.

## 1. 깊이

| 사용자 표현 | 옵션 |
|---|---|
| **"빠르게"**, **"가볍게"**, "빨리", "간단히", "간단하게", "대충", "훑어", "quick", "quickly", "fast", "brief", "briefly" | `--depth quick` |
| "보통으로", "기본 깊이로", "standard", "normal depth" | `--depth standard` |
| **"꼼꼼히"**, **"깊게"**, "꼼꼼하게", "자세히", "자세하게", "철저히", "철저하게", "심층", "깊이 있게", "thorough", "thoroughly", "in depth", "in-depth", "deep", "deeply", "carefully" | `--depth deep` |

## 2. 지적 강도

| 사용자 표현 | 옵션 |
|---|---|
| **"엄격하게"**, **"사소한 것도"**, "사소한 것까지", "작은 것도", "깐깐하게", "빡빡하게", "strict", "strictly", "nitpick", "nitpicky", "pedantic" | `--strictness strict` |
| "적당히", "균형 있게", "balanced" | `--strictness balanced` |

## 3. 심각도 하한

| 사용자 표현 | 옵션 |
|---|---|
| "치명적인 것만", "크리티컬만", "critical only", "only critical" | `--min-severity critical` |
| **"심각한 것만"**, **"큰 문제만"**, "high 이상", "높은 것만", "major issues only", "serious issues only" | `--min-severity high` |
| **"중요한 것만"**, "중요한 것 위주로", "medium 이상", "사소한 건 빼고", "사소한 것 제외", "important only" | `--min-severity medium` |
| "low까지", "모든 심각도", "all severities" | `--min-severity low` |

- "사소한 것도"(포함)는 지적 강도, "사소한 건 빼고"(제외)는 심각도 하한입니다. 서로 다른 항목입니다.

## 4. 집중 영역

영역 키워드:

| slug | 한국어 키워드 | 영어 키워드 |
|---|---|---|
| `security` | 보안, 시큐리티, 취약점, 개인정보 | security, vulnerability, vulnerabilities, privacy |
| `correctness` | 정확성, 버그, 로직 | correctness, bugs, logic |
| `ops` | 운영, 장애 대응, 운영 영향 | ops, operations, reliability |
| `architecture` | 아키텍처, 설계, 구조 | architecture, design |
| `performance` | 성능, 속도 | performance, perf, speed |
| `tests` | 테스트, 테스트 코드 | tests, testing, test coverage |
| `readability` | 가독성, 복잡도 | readability, complexity |
| `style` | 스타일, 컨벤션, 코딩 규칙 | style, conventions |
| `a11y` | 접근성 | a11y, accessibility |

표현 형식:

| 사용자 표현 | 옵션 |
|---|---|
| **"보안 위주로"**, **"보안만"**, "`<키워드>` 위주로", "`<키워드>` 중심으로", "`<키워드>` 관점에서", "`<키워드>`에 집중해서", "`<키워드>`만", "`<키워드>` 리뷰", "`<키워드>` 검토", "`<키워드>` 점검", "focus on `<키워드>`", "`<키워드>` only", "only `<키워드>`", "`<키워드>` review" | `--focus <slug>` |
| **"접근성 봐줘"**, "접근성 확인해줘", "check accessibility" | `--focus a11y` |
| "`<키워드>`이랑/과/와/하고/및/, `<키워드>` 위주로" (한 표현 안의 나열), "focus on `<키워드>` and `<키워드>`" | `--focus <slug>,<slug>` |
| **"스타일 빼고"**, "`<키워드>` 빼고", "`<키워드>` 제외하고", "`<키워드>` 말고", "without `<키워드>`", "except `<키워드>`", "skip `<키워드>`" | 8개 영역에서 해당 영역을 뺀 나머지를 나열 |
| "모든 영역", "all areas" | `--focus all` |

- 키워드만 단독으로 쓰거나 한정어 없이 쓰면("버그 찾아줘", "보안 괜찮아?") 집중 영역으로 바꾸지 않습니다. 단, "접근성 봐줘"는 SPEC 매핑이므로 예외입니다.
- "`a11y` 빼고"는 `--focus all`과 같게 취급하지 않고, a11y가 `correctness`의 일부이므로 해석하지 않은 표현으로 적습니다.
- "테스트 돌려줘", "테스트 실행"은 집중 영역이 아니라 검증 실행 요청입니다(`natural-language.md` 3절).

## 5. 보고 상한

| 사용자 표현 | 옵션 |
|---|---|
| "상위 `<n>`개", "최대 `<n>`개", "`<n>`개까지", "`<n>`개만 보여줘", "`<n>`건만", "`<n>`건까지", "top `<n>`", "at most `<n>` findings", "max `<n>`" | `--max-findings <n>` |
| "전부 보여줘", "다 보여줘", "제한 없이", "개수 제한 없이", "show all findings", "no limit" | `--max-findings all` |
