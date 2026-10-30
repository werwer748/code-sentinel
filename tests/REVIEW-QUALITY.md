# 리뷰 품질 검증 (SPEC §17)

실제 Claude Code와 Codex에서 code-sentinel을 실행해, 미리 심어 둔 버그를 얼마나 찾는지와 정상 코드를 얼마나
잘못 지적하는지를 잽니다. 채점은 모델이 하지 않고 `tests/score-quality.sh`가 보고서 헤더(SPEC §13.2)를 파싱해서 합니다.

이 검증은 실제 AI 도구를 호출하므로 자동 테스트(`tests/run.sh`)에 넣지 않았습니다. 채점기와 픽스처 자체는
`tests/test-score.sh`가 자동 테스트로 검증합니다.

## 구성

| 파일 | 역할 |
|---|---|
| `fixtures/review-quality/<name>/base/` | `main` 브랜치에 커밋되는 정상 코드 |
| `fixtures/review-quality/<name>/change/` | `feature` 브랜치의 전체 트리. 의도한 버그와 정상 변경이 섞여 있음 |
| `fixtures/review-quality/<name>/expected-findings.json` | 기대 결과. 심은 버그(`mustDetect`)와 오탐 함정(`mustNotFlag`) |
| `fixtures/review-quality/setup.sh` | `setup.sh <name> <dest>`: 임시 Git 저장소 생성(base → main, change → feature) |
| `score-quality.sh` | 보고서 채점기 |
| `run-quality.sh` | 실제 도구 실행·보관·채점·집계 |
| `test-score.sh` | 채점기와 픽스처 자체 테스트(자동 테스트에 포함) |

### 픽스처

모든 위치는 `change/` 트리 기준이며, 정확한 줄 범위와 설명은 각 `expected-findings.json`에 있습니다.

**backend-api** (Express 5 + PostgreSQL, TypeScript) — 버그 8, 함정 2

| ID | 파일 | 영역 | 최소 심각도 | 내용 |
|---|---|---|---|---|
| BE-01 | src/routes/invoices.ts | security | High | IDOR: 송장 상세를 id로만 조회 |
| BE-02 | src/routes/products.ts | security | High | 경로 파라미터를 문자열로 조립한 SQL |
| BE-03 | migrations/002_wallets_invoices_currency.sql | ops | Medium | 기본값 없는 NOT NULL 컬럼 추가 후 새 코드가 즉시 사용 |
| BE-04 | src/routes/orders.ts | performance | Medium | 주문 목록의 N+1 쿼리 |
| BE-05 | src/routes/wallet.ts | correctness | Medium | 트랜잭션·락 없이 잔액 확인 후 차감 |
| BE-06 | src/services/paymentGateway.ts | correctness | Medium | 멱등키 없는 결제 재시도 |
| BE-07 | src/routes/orders.ts | correctness | Medium | 예외를 삼키고 200 반환(주문 취소) |
| BE-08 | src/routes/orders.ts | architecture | Medium | 응답 필드명 변경(totalCents → amountCents) |
| BE-D1 | src/routes/products.ts | (함정) security·correctness | — | 동적으로 조립하지만 값은 모두 바인딩된 쿼리 |
| BE-D2 | src/services/inventory.ts | (함정) correctness·performance | — | 트랜잭션 안의 정상적인 `SELECT ... FOR UPDATE` |

**frontend-web** (Next.js App Router, React) — 버그 9, 함정 2, 규칙 제외 3

| ID | 파일 | 영역 | 최소 심각도 | 내용 |
|---|---|---|---|---|
| FE-01 | src/components/PriceTag.tsx | correctness·architecture | Medium | 클라이언트 컴포넌트가 서버 전용 모듈을 import. `NEXT_PUBLIC_`이 아닌 env가 번들에서 비워져 회원가가 표시되지 않음(토큰 유출 아님) |
| FE-02 | src/components/DealBanner.tsx | correctness | Medium | 렌더 중 `Date.now()` → 하이드레이션 불일치 |
| FE-03 | src/components/ReviewList.tsx | security | High | 정제하지 않은 리뷰 HTML을 `dangerouslySetInnerHTML`로 출력 |
| FE-04 | src/components/StockBadge.tsx | correctness | Medium | `setInterval` 정리 누락 |
| FE-05 | src/components/HelpfulButton.tsx | correctness | Low | 낙관적 업데이트 실패 시 롤백 없음 |
| FE-06 | src/components/AddToCart.tsx | correctness | Medium | `div onClick` 버튼(키보드 조작 불가) |
| FE-07 | src/components/CatalogSearch.tsx | correctness | Low | 라벨 없는 input |
| FE-08 | e2e/checkout.spec.ts | tests | Low | `nth-child`에 의존하는 E2E 셀렉터 |
| FE-09 | src/components/CatalogSearch.tsx | performance | Low | 키 입력마다 전체 카탈로그 검색 인덱스 재생성 |
| FE-D1 | src/app/products/[id]/page.tsx | (함정) security·correctness | — | DOMPurify로 정제한 뒤 넣는 HTML |
| FE-D2 | src/components/ProductGallery.tsx | (함정) style·readability·performance | — | 사유·ADR 링크가 있는 의도적 `eslint-disable` |

규칙 제외 대상: `pnpm-lock.yaml`(lockfile), `src/components/__snapshots__/ProductCard.test.tsx.snap`(스냅샷),
`src/lib/types.generated.ts`(생성 코드). `package.json`의 의존성 추가와 lockfile 변경은 서로 일치합니다.

**infra** (GitHub Actions, Dockerfile, 배포 셸, Terraform) — 버그 4, 함정 3

| ID | 파일 | 영역 | 최소 심각도 | 내용 |
|---|---|---|---|---|
| IN-01 | .github/workflows/preview.yml | security | High | `pull_request_target`에서 PR head를 실행하고 secrets 사용 |
| IN-02 | Dockerfile | security·ops | Low | `node:latest` 태그, root로 실행(USER 없음). 배포 경로에서 쓰이지 않는 이미지 |
| IN-03 | scripts/deploy.sh | ops | Medium | 인용하지 않은 변수 경로의 `rm -rf` |
| IN-04 | .github/workflows/deploy.yml | security | Medium | 해시로 고정하지 않은 서드파티 action(`@main`)에 자격 증명 전달 |
| IN-D1 | infra/docs-site.tf | (함정) security | — | 근거(ADR 0007)가 문서화된 공개 정적 사이트 버킷 |
| IN-D2 | infra/alb.tf | (함정) security | — | 공개 API 로드밸런서의 443 전체 공개(사유 주석) |
| IN-D3 | scripts/deploy.sh | (함정) ops·correctness·security | — | 인용·`--`·`mktemp -d` 경로를 쓰는 안전한 `rm -rf` trap |

**clean-change** (TypeScript 유틸 라이브러리) — 버그 없음. `paginate` 헬퍼와 테스트, README·CHANGELOG 갱신.
Medium 이상 지적이 하나라도 나오면 오탐입니다.

## 채점 규칙 (`score-quality.sh`)

    score-quality.sh <expected-findings.json> <report.md>       # 채점 (0 합격 · 1 불합격 · 2 입력 오류 · 3 형식 오류)
    score-quality.sh --parse <report.md>                        # 헤더 파싱 결과만 출력
    score-quality.sh --list-expected <expected-findings.json>   # 기대 항목 검증·출력
    score-quality.sh --check-expected <json> <fixture-repo>     # file·lineRange·anchor 가 저장소와 맞는지

- 헤더: `[S-NN] <Critical|High|Medium|Low> · 확신도 <High|Medium|Low> · <영역 slug> · <위치>`.
  앞에서부터 ` · ` 3개만 분리하고 나머지 전체가 위치입니다. 영역 slug는 SPEC §9.1의 8개만 허용합니다.
- 위치: `경로:L`, `경로:L-L`, 삭제는 `경로:L-L (삭제)`, 이름 변경은 `이전 → 새:L-L`(새 경로로 대조).
  제어문자·역슬래시·큰따옴표·` · `·` → `가 든 경로는 C 스타일 따옴표(`\n` `\t` `\\` `\"` `\ooo`)로 씁니다.
- 탐지: 경로 일치 + 줄 범위 겹침 + 영역 일치 + 심각도 ≥ `minSeverity`. `같은 원인:` 줄의 위치도 같은 항목의
  위치로 셉니다. `(삭제)` 위치는 변경 전 줄 번호라서 대조하지 않습니다.
- 위반: `mustNotFlag` 항목과 같은 파일·겹치는 줄에, 그 함정의 영역(위 표의 "(함정)" 뒤, JSON의 `area`)으로
  Medium 이상 지적. 함정 영역은 그 함정이 유도하는 잘못된 주장의 영역입니다. 다른 영역의 지적(예: 함정 줄을 덮는
  "테스트 없음")은 위반이 아닙니다. 2라운드부터 적용하며, 1라운드는 영역과 무관하게 셌습니다.
- 출력 형식 오류(실행 실패로 처리, 종료 코드 3):
  - `[S-`로 시작하지만 문법에 맞지 않는 줄
  - 줄 앞에 마크다운 꾸밈(`### `, `**`, `- ` 등)이 붙어 있지만 나머지는 헤더 문법에 맞는 줄 (명세 보강:
    꾸민 헤더가 조용히 빠져 clean-change가 거짓 합격하는 것을 막음)
  - 보고서에 `해석된 옵션:` 줄이 없음 (명세 보강: 빈 출력·중단된 출력을 "발견 0건"으로 세지 않음)
- 합격: `mustDetect`가 있으면 탐지율 80% 이상이고 위반 0건. 없으면(clean-change) Medium 이상 발견 0건.
  8개 중 7개, 9개 중 8개, 4개 중 4개를 찾아야 80%를 넘습니다.

## 실행 절차

### 0. 사전 확인

1. `claude`, `codex`가 설치·인증되어 있는지 확인합니다(`claude --version`, `codex --version`).
2. 프로젝트 스킬 경로를 공식 문서로 다시 확인합니다(Claude Code `<project>/.claude/skills/`, Codex
   `<repo>/.agents/skills/`). 다르면 `run-quality.sh`의 `link_skill`을 고칩니다.
3. 전역에 같은 이름의 스킬(`~/.claude/skills/code-sentinel`, `~/.agents/skills/code-sentinel`,
   `~/.codex/skills/code-sentinel`)이 있는지 봅니다. 있으면 어느 쪽이 로드됐는지 확인할 수 없으므로 결과에 적습니다.
   `run-quality.sh`도 읽기만 해서 경고하고 `environment.tsv`에 기록합니다.
4. 자동 테스트로 채점기와 픽스처를 확인합니다: `/bin/bash tests/run.sh score`

### 1. 명령 미리 보기

    /bin/bash tests/run-quality.sh --dry-run
    /bin/bash tests/run-quality.sh --dry-run --normalization

`--dry-run`은 AI 도구를 실행하지 않고 파일도 만들지 않습니다.

### 2. 리뷰 품질 (2도구 × 4픽스처 × 3회 = 24회)

    /bin/bash tests/run-quality.sh --runs 3 --out <결과 디렉터리>

리뷰 1회마다 다음을 합니다.

1. `setup.sh <fixture> <임시>/repo`로 저장소를 만듭니다(`main` = base, `feature` = change, 커밋 시각 고정).
2. 저장소 안에 `.claude/skills/code-sentinel`, `.agents/skills/code-sentinel` 링크를 만들어 이 저장소의
   `skills/code-sentinel`을 가리키게 합니다. 두 디렉터리는 `.git/info/exclude`에 넣어 리뷰 대상(untracked)에서 뺍니다.
3. 실행:
   - Claude Code: `(cd repo && claude -p '/code-sentinel --changes --base main' --allowedTools 'Bash,Read,Grep,Glob')`
   - Codex: `codex exec -C repo --sandbox workspace-write -o <파일> '$code-sentinel --changes --base main'`
     (`collect-context.sh`가 임시 디렉터리를 만들 수 있게 workspace-write 샌드박스를 씁니다. SPEC §17.2의
     "기본 샌드박스"와 다르면 결과에 적습니다.)
4. 실행 전후 저장소 상태(HEAD, refs, stash, `ls-files -s`, status, 작업 트리 해시)를 비교해 `readonly` 열에 기록합니다.
5. 원본 출력(`raw/<tool>/<fixture>/run-N.md`, 로그)과 채점 결과(`run-N.score.txt`)를 보관합니다.

결과 파일: `results.tsv`(실행별), `summary.tsv`·`summary.md`(도구×픽스처, 가장 낮은 결과 기준),
`environment.tsv`(도구 버전, 전역 스킬 여부). 완료한 실행이 3회 미만인 조합은 불합격입니다.
리뷰 1회의 최대 실행 시간은 `--max-seconds`(기본 1800초)이며, 넘으면 미완료(`over-time`)로 기록합니다.

### 3. 해석 일치 (입력 5개, clean-change)

    /bin/bash tests/run-quality.sh --normalization --out <결과 디렉터리>

| ID | 입력 | 참고 기대값(`해석된 옵션:` 뒤) |
|---|---|---|
| F1 | `--changes --base main` | `--changes --base main --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` |
| F2 | `--changes --base main --depth quick --focus security,a11y --max-findings 5` | `--changes --base main --depth quick --strictness balanced --min-severity low --focus security,a11y --max-findings 5` |
| N1 | `main 기준으로 빠르게 꼼꼼히` (같은 항목 충돌) | `--changes --base main --depth deep --strictness balanced --min-severity low --focus all --max-findings 20` |
| N2 | `main 기준으로 보안 위주로 중요한 것만` | `--changes --base main --depth standard --strictness balanced --min-severity medium --focus security --max-findings 20` |
| N3 | `main 기준으로 꼼꼼히 빠르게 스타일 빼고 엄격하게` (같은 항목 충돌) | `--changes --base main --depth quick --strictness strict --min-severity low --focus security,correctness,ops,architecture,performance,tests,readability --max-findings 20` |

판정 기준은 두 도구의 `해석된 옵션:` 줄이 서로 같은지입니다(SPEC §3.2-7). 참고 기대값과의 일치 여부는
`normalization.tsv`에 따로 기록합니다. 자연어 입력에 `main 기준으로`를 넣은 것은 픽스처 저장소에
`origin/HEAD`가 없어 기준 브랜치를 자동으로 정할 수 없기 때문입니다(SPEC §4.2).

### 4. 결과 기록

아래 표를 `summary.md`와 `normalization.tsv`로 채우고, 실행 날짜·도구 버전·전역 스킬 여부·원본 출력 위치를 적습니다.
실행할 수 없었거나 인증이 없으면 값을 만들지 말고 "미검증"과 사유를 적습니다.

## 격리와 주의 사항

- 인증 때문에 실제 HOME을 씁니다. 사용자 스킬 디렉터리와 설정은 바꾸지 않습니다(전역 스킬은 읽기만 함).
- 도구가 남기는 세션·로그 기록(예: `~/.claude/projects/`, `~/.codex/sessions/`)은 예외로 허용하고 결과에 적습니다.
- 픽스처 저장소는 `${TMPDIR}` 아래 임시 디렉터리에 만들고 실행이 끝나면 지웁니다. 원본 출력은 `--out`에 남습니다.
- `expected-findings.json`과 이 문서는 정답을 담고 있습니다. 픽스처 저장소에는 복사되지 않지만, 모델이 스킬 링크를
  거슬러 이 저장소를 읽으면 오염될 수 있습니다. 원본 출력에 이 파일들을 읽은 흔적이 있으면 그 실행은 무효로 봅니다.
- 픽스처의 `change/` 트리에는 의도한 결함이 있습니다(예: `infra/change/scripts/deploy.sh`의 인용 누락).
  정적 검사(shellcheck 등)는 `tests/fixtures/review-quality/*/base`와 `*/change`를 대상에서 빼야 합니다.
  픽스처 파일에 `shellcheck disable` 같은 표시를 넣으면 리뷰어에게 정답을 알려 주게 되므로 넣지 않습니다.
- 픽스처를 고치면 `/bin/bash tests/test-score.sh`를 실행해 줄 범위와 `anchor`가 맞는지 확인합니다.

## 알려진 한계

- 영역은 정확히 일치해야 탐지로 인정합니다(SPEC §17.3). 경계가 모호한 버그(예: FE-01 correctness/architecture,
  IN-03 ops/correctness, BE-03 ops/correctness)는 모델이 다른 영역을 고르면 놓친 것으로 집계됩니다.
  불합격 시 `run-N.score.txt`의 `finding` 줄로 원인을 확인합니다.
- 줄 범위는 겹치기만 하면 인정하므로, 파일 전체를 가리키는 지적도 탐지로 셀 수 있습니다.
- 모델 출력은 비결정적입니다. 3회 중 가장 낮은 결과로 판정하는 것은 이 변동을 보수적으로 다루기 위함입니다.
- `--max-findings 20`(기본값)을 넘는 발견은 보고서에서 잘리므로 탐지율에 반영되지 않습니다.

## 2라운드 기준 (실행 전 확정, 2026-10-30)

1라운드 결과(아래)를 보고 고친 내용입니다. 1라운드 판정은 바꾸지 않고, 2라운드는 아래 기준으로 따로 기록합니다.

| 구분 | 변경 | 이유(1라운드 원인) |
|---|---|---|
| 스킬 | `collect-context.sh`가 줄 번호를 붙인 `numbered_diff_file`을 만들고, SKILL.md·report-format.md에 "위치는 번호 열에서, 출력 전 위치 확인" 규칙 추가 | A: diff 파일 자체의 줄 번호를 위치로 씀 |
| 픽스처 | `infra/change/scripts/deploy.sh`의 `mv` 직전에 `chmod 0755 "$staging_dir"` 추가. 이에 따라 IN-03 범위 26-32 → 27-33 | C: 의도하지 않은 0700 권한 버그 |
| 채점 | 함정 위반은 함정 영역(픽스처 표의 "(함정)" 뒤)의 Medium 이상 지적만 셈 | D: 영역과 무관한 줄 겹침 |

바꾸지 않은 것:

- 모든 `mustDetect` 항목의 허용 영역과 `minSeverity`. FE-01은 `security|architecture`, IN-02는 Medium 이상 그대로입니다.
  IN-02의 Medium은 스킬 `severity.md`의 예시(`latest` 태그는 Low)와 다르지만, 기준을 엄격하게 유지하기로 했습니다.
- 합격 기준(탐지 80% 이상, 위반 0건, clean-change Medium 이상 0건), 3회 중 최저 결과 판정, 해석 일치 입력 5개.
- 실행 명령과 환경(Claude Code 2.1.312, Codex CLI 0.165.0, Codex `workspace-write`).

결과는 `tests/quality-runs/2026-10-30-r2-{claude,codex,normalization}/`에 둡니다.

## 3라운드 기준 (실행 전 확정, 2026-10-30)

2라운드 결과를 보고 고친 내용입니다. 1·2라운드 판정은 바꾸지 않고, 3라운드는 아래 기준으로 따로 기록합니다.

| 구분 | 변경 | 이유 |
|---|---|---|
| 픽스처 | FE-01 허용 영역 `security|architecture` → `correctness|architecture`, 설명 수정 | Next.js 14는 `NEXT_PUBLIC_`이 아닌 env를 클라이언트 번들에서 비웁니다. 토큰은 새지 않고 회원가 표시가 깨지는 회귀입니다. 두 도구 6회 모두 이렇게 설명했습니다 |
| 픽스처 | IN-02 `minSeverity` Medium → Low, 설명 수정 | 이 Dockerfile은 배포 경로에서 쓰이지 않습니다(`deploy.yml`은 tarball을 SSH로 배포). 스킬 기준(`latest` 태그는 Low)이 맞습니다 |
| 스킬 | 지침 문서를 상황별 파일 35개로 분할(파일마다 100줄 이내), 같은 단계의 문서를 한 번에 읽게 함 | 토큰 점검: 매번 읽는 지침이 약 5.7만 토큰이었음 |

- 스킬 파일이 바뀌었으므로 **전체**를 다시 돌립니다: 리뷰 24회(4개 픽스처 × 2개 도구 × 3회)와 해석 일치 10회.
- Claude Code 실행은 사용량 한도 때문에 동시에 돌리지 않고 순서대로 실행합니다.
- 참고용 재채점: 고친 기대값으로 2라운드 출력을 다시 채점하면 8개 조합 중 7개가 합격합니다. Claude Code infra 3회차만 IN-03을 Low로 매겨 불합격이며, 이는 모델 판단 편차입니다.
- 토큰: 실행마다 Claude Code 기록의 캐시 쓰기·읽기·출력과 Codex `tokens used`를 2라운드 평균과 비교해 기록합니다.

바꾸지 않은 것: 그 밖의 `mustDetect` 항목과 함정, 합격 기준, 3회 중 최저 결과 판정, 해석 일치 입력 5개, 채점 스크립트.

**설치 기준(결과를 보기 전에 정함):** 도구 결함(출력 형식 오류, 읽기 전용 위반, 임시 디렉터리 잔존, 위치 범위 오류)이 0건이고, 남은 불합격이 모델 판단 편차(심각도·영역 판단, Low 항목 누락)뿐이면 전역 설치로 진행합니다.

결과는 `tests/quality-runs/2026-10-30-r3-{claude,codex,normalization}/`에 둡니다.

## 결과 — 1라운드 (2026-10-29)

### 실행 환경

| 항목 | 값 |
|---|---|
| 실행 날짜 | 2026-10-29 14:31 UTC 시작 (스모크: 14:08 UTC) |
| Claude Code 버전 | 2.1.312 |
| Codex CLI 버전 | codex-cli 0.165.0 |
| 전역 code-sentinel 스킬 | 없음 (`environment.tsv`의 `global_skill none`) |
| 원본 출력 위치 | `tests/quality-runs/2026-10-29-{claude,codex,normalization,smoke}/` (커밋하지 않음) |
| Codex 샌드박스 | `workspace-write` (SPEC §17.2의 "기본 샌드박스"와 다름. `collect-context.sh`가 `TMPDIR`에 임시 디렉터리를 만들어야 하기 때문) |
| 실행 방식 | 시간을 줄이려고 `--tool claude`, `--tool codex`, `--normalization`을 동시에 실행. 서로의 `context_dirs_left` 집계가 섞이지 않게 실행마다 `TMPDIR`를 따로 줌 |
| 오염 확인 | Claude 세션 기록 18개, Codex 실행 로그 17개에서 `expected-findings.json`·이 문서·채점기·SPEC을 읽은 흔적 없음. 무효 실행 0회 |

### 리뷰 품질 (가장 낮은 결과 기준)

| 도구 | 픽스처 | 완료/회 | 최소 탐지 | 최대 위반 | 최대 Medium+ | 형식 오류 실행 | 평균 보고서(줄/바이트) | 저장소 변경 실행 | 판정 |
|---|---|---|---|---|---|---|---|---|---|
| Claude Code | backend-api | 3/3 | 5/8 (62%) | 1 | 12 | 0 | 147 / 16025 | 0 | 불합격 |
| Claude Code | frontend-web | 3/3 | 7/9 (77%) | 0 | 9 | 0 | 153 / 15647 | 0 | 불합격 |
| Claude Code | infra | 3/3 | 3/4 (75%) | 1 | 4 | 0 | 103 / 10028 | 0 | 불합격 |
| Claude Code | clean-change | 3/3 | — | 0 | 0 | 0 | 35 / 3070 | 0 | 합격 |
| Codex | backend-api | 3/3 | 8/8 (100%) | 0 | 11 | 0 | 96 / 8961 | 0 | 합격 |
| Codex | frontend-web | 3/3 | 7/9 (77%) | 0 | 9 | 0 | 87 / 7399 | 0 | 불합격 |
| Codex | infra | 3/3 | 3/4 (75%) | 1 | 5 | 0 | 65 / 5769 | 0 | 불합격 |
| Codex | clean-change | 3/3 | — | 0 | 0 | 0 | 26 / 1591 | 0 | 합격 |

실행별 결과(24회):

| 도구 | 픽스처 | 1회 | 2회 | 3회 | 평균 시간 |
|---|---|---|---|---|---|
| Claude Code | backend-api | 합격 8/8 | 불합격 5/8 | 불합격 7/8 · 위반 1 | 294초 |
| Claude Code | frontend-web | 불합격 7/9 | 합격 8/9 | 합격 8/9 | 350초 |
| Claude Code | infra | 불합격 3/4 · 위반 1 | 불합격 3/4 · 위반 1 | 불합격 3/4 · 위반 1 | 250초 |
| Claude Code | clean-change | 합격 | 합격 | 합격 | 77초 |
| Codex | backend-api | 합격 8/8 | 합격 8/8 | 합격 8/8 | 194초 |
| Codex | frontend-web | 불합격 7/9 | 불합격 7/9 | 불합격 7/9 | 164초 |
| Codex | infra | 불합격 3/4 · 위반 1 | 불합격 3/4 · 위반 1 | 불합격 3/4 | 154초 |
| Codex | clean-change | 합격 | 합격 | 합격 | 63초 |

전체 탐지: Claude Code 52/63(82.5%), Codex 54/63(85.7%). 함정 위반: Claude Code 4건, Codex 2건.
24회 모두 실행 성공(시간 초과·빈 출력 0), 출력 형식 오류 0, 저장소 변경 0, 남은 임시 디렉터리 0.

### 해석 일치

| ID | 입력 | 두 도구의 `해석된 옵션:` (같음) | 일치 | 참고 기대값과 같음 |
|---|---|---|---|---|
| F1 | `--changes --base main` | `--changes --base main --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` | 예 | 예 |
| F2 | `--changes --base main --depth quick --focus security,a11y --max-findings 5` | `--changes --base main --depth quick --strictness balanced --min-severity low --focus security,a11y --max-findings 5` | 예 | 예 |
| N1 | `main 기준으로 빠르게 꼼꼼히` | `--changes --base main --depth deep --strictness balanced --min-severity low --focus all --max-findings 20` | 예 | 예 |
| N2 | `main 기준으로 보안 위주로 중요한 것만` | `--changes --base main --depth standard --strictness balanced --min-severity medium --focus security --max-findings 20` | 예 | 예 |
| N3 | `main 기준으로 꼼꼼히 빠르게 스타일 빼고 엄격하게` | `--changes --base main --depth quick --strictness strict --min-severity low --focus security,correctness,ops,architecture,performance,tests,readability --max-findings 20` | 예 | 예 |

Codex는 `해석된 옵션:` 줄 끝에 공백 2개(마크다운 줄바꿈)를 붙이지만, 비교 전에 줄 끝 공백을 지우므로 판정에 영향이 없습니다.

### 실패 원인 분석

항목별 탐지(각 도구 3회 중):

| 항목 | Claude Code | Codex | 비고 |
|---|---|---|---|
| BE-01 | 2/3 | 3/3 | Claude 누락 1회는 줄 번호 결함(아래 A) |
| BE-03 | 1/3 | 3/3 | Claude 누락 2회는 줄 번호 결함(A) |
| BE-05 | 2/3 | 3/3 | Claude 누락 1회는 줄 번호 결함(A) |
| BE-D1 | 2/3 | 3/3 | 위반 1회는 채점 규칙 한계(D) |
| FE-01 | 0/3 | 0/3 | 6회 모두 찾았으나 영역을 `correctness`로 분류(B) |
| FE-07 | 2/3 | 0/3 | 실제 누락(E) |
| IN-02 | 0/3 | 0/3 | 6회 모두 찾았으나 심각도를 Low로 매김(B) |
| IN-D3 | 0/3 | 1/3 | 위반 5회는 픽스처 결함(C) |
| 그 밖 20개 | 모두 3/3 | 모두 3/3 | |

채점 기준은 실행 전에 정한 그대로 두었습니다(SPEC §17.1). 아래는 원인 분류이며 판정을 바꾸지 않습니다.

- **A. 스킬 결함 — Claude Code가 diff 파일의 줄 번호를 위치로 씀.** backend-api 2회에서 5건의 위치가 파일 길이를
  넘었습니다(예: 44줄인 `src/routes/invoices.ts`에 `:81-85`). 같은 픽스처로 `collect-context.sh`를 다시 실행해 보니
  이 번호들은 `diff.patch` 안의 줄 번호와 정확히 맞았습니다. `report-format.md`에는 "줄 번호는 리뷰 스냅샷의 파일
  기준"이라고만 적혀 있고, hunk 헤더(`@@ +N`)로 계산하거나 보고 전에 위치를 확인하라는 안내가 없습니다.
  Codex는 지적 73건의 위치가 모두 파일 범위 안이었습니다. 실제 사용자에게도 틀린 위치를 보여 주는 결함입니다.
- **B. 기대값 판단 차이 — 두 도구가 6회 모두 같은 판단.**
  - FE-01(클라이언트 컴포넌트가 서버 전용 모듈을 import): 두 도구 모두 "브라우저에서 내부 가격 서비스를
    호출해 실패하는 기능 회귀"로 보고 `correctness`로 분류했습니다. 허용 영역은 `security|architecture`입니다.
  - IN-02(`node:latest`, `USER` 없음): 두 도구 모두 지적했지만 Low로 매겼습니다. 기준은 Medium 이상입니다.
  - infra는 4개 중 4개를 찾아야 합격이므로 IN-02 하나로 항상 불합격입니다. frontend-web은 9개 중 8개가 필요해서
    FE-01을 놓치면 다른 항목을 하나도 놓칠 수 없습니다.
- **C. 픽스처 결함 — `infra/change/scripts/deploy.sh`에 의도하지 않은 실제 버그.** 변경에서 릴리스 디렉터리를
  `mkdir -p` 대신 `mktemp -d`로 만든 뒤 `mv`합니다. 그래서 릴리스 디렉터리 권한이 0700이 되고, 서비스가
  `deploy`가 아닌 계정으로 돌면 소스를 읽지 못합니다. 두 도구가 따로 이 문제를 High로 지적했고(6회 중 5회),
  위치(14-20)가 안전한 `rm -rf` trap 함정(IN-D3, 14-15)과 겹쳐 위반으로 집계됐습니다. 함정 코드 자체를 문제로
  지적한 실행은 없습니다.
- **D. 채점 규칙 한계 — 영역과 무관한 줄 겹침.** Claude backend-api 3회차의 "새 엔드포인트에 테스트 없음"
  (tests, Medium)이 `같은 원인: src/routes/products.ts:12-37`로 넓은 범위를 가리켜 BE-D1 함정(14-26)과 겹쳤습니다.
- **E. 실제 누락.** FE-07(라벨 없는 input, Low)을 Codex는 3회 모두, Claude는 1회 놓쳤습니다.

### 종합 판정

**불합격.** 8개 조합 중 3개 합격(Claude Code clean-change, Codex backend-api, Codex clean-change), 5개 불합격.

- 합격한 부분: 해석 일치 5/5, 정상 변경 오탐 0(6회), 출력 형식 오류 0, 읽기 전용 24/24, 임시 디렉터리 정리 24/24.
- 스킬에서 고칠 것: A(줄 번호). 이 결함만 고치면 Claude backend-api 2회차는 8/8이 되지만, 3회차는 D 때문에
  여전히 불합격입니다.
- 다음 검증 전에 정할 것: B·C·D는 픽스처와 채점 기준의 문제입니다. 결과를 본 뒤에 이번 판정을 바꾸지 않고,
  고친다면 새 기준으로 다시 실행해 따로 기록합니다.

## 결과 — 2라운드 (2026-10-30)

### 실행 환경

| 항목 | 값 |
|---|---|
| 실행 시각 | 2026-10-29 15:41 UTC(한국 시간 10-30 00:41) 시작. Claude Code 재실행 17:02·17:18 UTC |
| 도구 버전 | Claude Code 2.1.312, codex-cli 0.165.0 (1라운드와 같음) |
| 전역 code-sentinel 스킬 | 없음 |
| 원본 출력 위치 | `tests/quality-runs/2026-10-30-r2-{claude,claude-b,claude-c,claude-merged,codex,normalization}/` |
| 무효 실행 | Claude Code 8회. frontend-web 2·3회차, infra 1~3회차, clean-change 1~3회차가 Claude 5시간 사용량 한도에 걸려 `You've hit your 5-hour limit`만 출력하고 끝남(`2026-10-30-r2-claude/`). 스킬 실패가 아니므로 무효로 보고, 한도가 풀린 뒤 빠진 8회만 순서대로 다시 실행함(`-b`: infra·clean-change 3회씩, `-c`: frontend-web 2회). 이미 끝난 frontend-web 1회차(불합격)는 그대로 집계에 넣음. 합친 결과는 `2026-10-30-r2-claude-merged/` |
| 오염 확인 | Claude 세션 기록과 Codex 로그에서 정답 파일·채점기·SPEC을 읽은 흔적 없음 |

### 리뷰 품질 (가장 낮은 결과 기준)

| 도구 | 픽스처 | 완료/회 | 최소 탐지 | 최대 위반 | 최대 Medium+ | 형식 오류 실행 | 평균 보고서(줄/바이트) | 저장소 변경 실행 | 판정 |
|---|---|---|---|---|---|---|---|---|---|
| Claude Code | backend-api | 3/3 | 8/8 (100%) | 0 | 13 | 0 | 157 / 15729 | 0 | 합격 |
| Claude Code | frontend-web | 3/3 | 7/9 (77%) | 0 | 10 | 0 | 149 / 14192 | 0 | 불합격 |
| Claude Code | infra | 3/3 | 2/4 (50%) | 0 | 3 | 0 | 85 / 8665 | 0 | 불합격 |
| Claude Code | clean-change | 3/3 | — | 0 | 0 | 0 | 32 / 2617 | 0 | 합격 |
| Codex | backend-api | 3/3 | 8/8 (100%) | 0 | 10 | 0 | 92 / 8266 | 0 | 합격 |
| Codex | frontend-web | 3/3 | 7/9 (77%) | 0 | 9 | 0 | 88 / 7708 | 0 | 불합격 |
| Codex | infra | 3/3 | 3/4 (75%) | 0 | 5 | 0 | 64 / 5590 | 0 | 불합격 |
| Codex | clean-change | 3/3 | — | 0 | 0 | 0 | 24 / 1513 | 0 | 합격 |

실행별 결과(유효 24회):

| 도구 | 픽스처 | 1회 | 2회 | 3회 | 평균 시간 |
|---|---|---|---|---|---|
| Claude Code | backend-api | 합격 8/8 | 합격 8/8 | 합격 8/8 | 289초 |
| Claude Code | frontend-web | 불합격 7/9 | 불합격 7/9 | 합격 8/9 | 327초 |
| Claude Code | infra | 불합격 3/4 | 불합격 3/4 | 불합격 2/4 | 256초 |
| Claude Code | clean-change | 합격 | 합격 | 합격 | 75초 |
| Codex | backend-api | 합격 8/8 | 합격 8/8 | 합격 8/8 | 198초 |
| Codex | frontend-web | 불합격 7/9 | 불합격 7/9 | 불합격 7/9 | 161초 |
| Codex | infra | 합격 4/4 | 불합격 3/4 | 불합격 3/4 | 149초 |
| Codex | clean-change | 합격 | 합격 | 합격 | 70초 |

전체 탐지: Claude Code 54/63(85.7%, 1라운드 82.5%), Codex 55/63(87.3%, 1라운드 85.7%). 함정 위반: 두 도구 모두 0건
(1라운드 Claude Code 4건, Codex 2건). 유효 24회 모두 출력 형식 오류 0, 저장소 변경 0, 남은 임시 디렉터리 0.

### 해석 일치

5/5. 두 도구의 `해석된 옵션:` 줄이 입력 5개 모두에서 서로 같고, 참고 기대값과도 같습니다(1라운드와 같은 값).

### 1라운드 대비 변화

- **A(줄 번호) 해결:** 보고된 위치 160개(유효 24회) 중 파일 범위를 벗어난 것 0개(1라운드 Claude Code 5개).
  Claude Code backend-api가 3회 모두 8/8로 합격했습니다(1라운드는 3회 중 2회 불합격).
- **C(픽스처 버그) 해결:** `mktemp` 권한 지적과 IN-D3 위반이 사라졌습니다(1라운드 6회 중 5회).
- **D(함정 영역 조건):** 2라운드에서는 함정 줄과 겹치는 Medium 이상 지적이 영역과 관계없이 하나도 없어서,
  판정에 영향을 준 실행이 없습니다. 같은 검사를 1라운드 결과에 돌리면 위반 6건이 모두 다시 잡힙니다(검사 동작 확인).

### 남은 실패 원인

| 항목 | Claude Code | Codex | 내용 |
|---|---|---|---|
| FE-01 | 0/3 | 0/3 | 6회 모두 찾았으나 `correctness`로 분류(허용 영역 `security|architecture`) |
| FE-07 | 1/3 | 0/3 | 라벨 없는 input을 지적하지 않음(실제 누락) |
| IN-02 | 0/3 | 1/3 | `latest`·root 실행을 Low로 매김. Codex 1회는 root 실행을 Medium security로 지적해 탐지 |
| IN-03 | 2/3 | 3/3 | Claude Code 1회는 위치·내용은 맞지만 Low로 매김(기준 Medium 이상) |
| 그 밖 24개 | 모두 3/3 | 모두 3/3 | |

frontend-web은 9개 중 8개가 필요해서, FE-01을 놓치면 FE-07까지 찾아야 합격합니다(Claude Code 1회만 해당).
infra는 4개를 모두 찾아야 해서 IN-02를 Medium 이상으로 매긴 실행만 합격합니다. 스킬의 `severity.md`가 `latest`
태그를 Low 예시로 들고 있어, 기대값과 스킬 기준이 어긋난 상태입니다(2라운드 기준에서 그대로 두기로 결정).

### 종합 판정

**불합격.** 8개 조합 중 4개 합격(Claude Code backend-api·clean-change, Codex backend-api·clean-change), 4개 불합격
(두 도구의 frontend-web·infra). 1라운드보다 합격이 하나 늘었습니다(Claude Code backend-api).

- 합격한 부분: 해석 일치 5/5, 정상 변경 오탐 0(6회), 함정 위반 0, 출력 형식 오류 0, 읽기 전용 24/24, 위치 범위 오류 0.
- 불합격 원인은 모두 기대값과 모델 판단의 차이(FE-01 영역, IN-02·IN-03 심각도)와 Low 항목 누락(FE-07)입니다.
  스킬의 수집·형식·안전 동작 문제는 2라운드에서 발견되지 않았습니다.
- 알려진 제약: AI 도구가 리뷰 도중 비정상 종료되면(이번에는 사용량 한도) 정리 단계가 실행되지 않아
  `code-sentinel.*` 임시 디렉터리가 남습니다(무효 실행 1회에서 1개). `cleanup-context.sh --stale`로 지울 수 있습니다.

## 결과 — 3라운드 (2026-10-30)

### 실행 환경

| 항목 | 값 |
|---|---|
| 실행 시각 | 2026-10-30 01:23 UTC(한국 시간 10:23) 시작 |
| 도구 버전 | Claude Code 2.1.314, codex-cli 0.165.0 |
| 전역 code-sentinel 스킬 | 없음 |
| 원본 출력 위치 | `tests/quality-runs/2026-10-30-r3-{smoke,claude,codex,normalization}/` |
| 실행 방식 | 먼저 Claude Code clean-change 1회로 분할한 문서가 동작하는지 확인(`-smoke`, 합격). 이어서 Claude Code와 Codex 리뷰를 `TMPDIR`를 나눠 동시에 실행하고, Claude Code 리뷰가 끝난 뒤 해석 일치를 실행. 무효 실행 없음 |
| 오염 확인 | Claude 세션 기록의 도구 호출과 Codex `exec` 기록에서 정답 파일·채점기·SPEC·픽스처 원본을 읽은 흔적 없음 |

### 리뷰 품질 (가장 낮은 결과 기준)

| 도구 | 픽스처 | 완료/회 | 최소 탐지 | 최대 위반 | 최대 Medium+ | 형식 오류 실행 | 평균 보고서(줄/바이트) | 저장소 변경 실행 | 판정 |
|---|---|---|---|---|---|---|---|---|---|
| claude | backend-api | 3/3 | 8/8 (100%) | 0 | 11 | 0 | 126 / 11801 | 0 | 합격 |
| claude | frontend-web | 3/3 | 8/9 (88%) | 0 | 11 | 0 | 128 / 12217 | 0 | 합격 |
| claude | infra | 3/3 | 4/4 (100%) | 0 | 3 | 0 | 78 / 7162 | 0 | 합격 |
| claude | clean-change | 3/3 | - | 0 | 0 | 0 | 30 / 2413 | 0 | 합격 |
| codex | backend-api | 3/3 | 8/8 (100%) | 0 | 12 | 0 | 112 / 9899 | 0 | 합격 |
| codex | frontend-web | 3/3 | 8/9 (88%) | 0 | 10 | 0 | 90 / 7837 | 0 | 합격 |
| codex | infra | 3/3 | 4/4 (100%) | 0 | 5 | 0 | 79 / 5644 | 0 | 합격 |
| codex | clean-change | 3/3 | - | 0 | 0 | 0 | 25 / 1498 | 0 | 합격 |

- 놓친 항목은 FE-07(라벨 없는 input, Low) 하나뿐입니다(Claude Code 1/3회, Codex 3/3회). 9개 중 8개 기준이라 판정에 영향이 없습니다.
- 임시 디렉터리 잔존 0, 읽기 전용 24/24.

### 해석 일치

5/5. 두 도구의 `해석된 옵션:` 줄이 입력 5개 모두 같고, 참고 기대값과도 모두 일치합니다(`2026-10-30-r3-normalization/normalization.tsv`).

### 토큰 (리뷰 1회 평균, 2라운드 → 3라운드)

| 픽스처 | Claude Code 캐시 쓰기 | 캐시 읽기 | 출력 | API 호출 |
|---|---|---|---|---|
| backend-api | 12.1만 → 7.9만 | 79.5만 → 31.9만 | 3.0만 → 1.1만 | 9 → 6.0 |
| frontend-web | 11.7만 → 7.6만 | 81.2만 → 34.0만 | 3.5만 → 1.2만 | 10 → 6.7 |
| infra | 10.4만 → 7.2만 | 59.6만 → 34.6만 | 2.6만 → 1.0만 | 8 → 7.0 |
| clean-change | 8.4만 → 6.0만 | 51.8만 → 23.5만 | 0.7만 → 0.5만 | 8 → 5.3 |

- 2라운드 값은 사용량 한도로 중단된 실행을 뺀 유효 실행 평균입니다.
- Codex(`tokens used`): 평균 6.8만 → 5.5만(약 20% 감소). 12회 모두 2라운드보다 적거나 비슷합니다.
- 출력도 크게 줄었지만 탐지율은 2라운드보다 같거나 높습니다. 출력이 줄어든 원인(지침 감소로 인한 추론 감소인지)은 따로 확인하지 않았습니다.

### 종합 판정

**합격.** 8개 조합 모두 합격, 해석 일치 5/5, 도구 결함(출력 형식 오류, 읽기 전용 위반, 임시 디렉터리 잔존, 위치 범위 오류) 0건. 3라운드 기준의 설치 조건을 만족합니다.
