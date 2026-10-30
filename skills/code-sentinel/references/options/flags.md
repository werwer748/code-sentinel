# 옵션: 플래그 읽기와 정규화

입력이 비어 있지 않으면 항상 읽습니다. 플래그가 아닌 텍스트가 있으면 `natural-language.md`와 매핑표 두 개(`nl-scope.md`, `nl-review.md`)도 함께 읽습니다. 오류 메시지 전문은 `../report/errors.md`에 있습니다. 모델 기반 해석이므로 완전한 결정성을 보장하지는 않지만, 여기 적힌 규칙 밖의 추측은 하지 않습니다.

## 1. 옵션 표

| 항목 | 옵션 | 값 | 기본값 | 비고 |
|---|---|---|---|---|
| 범위 | `--changes` | 없음 | 기본 범위 | merge-base(base, HEAD) → 작업 트리. 미커밋 변경 포함 |
| 범위 | `--staged` | 없음 | | HEAD → index. staged만 |
| 범위 | `--commit [ref]` | 선택. 커밋 하나 | 값 생략 시 `HEAD` | 첫 번째 부모 → ref. `A..B` 같은 범위는 오류 |
| 범위 | `--pr <n>` | 필수. 양의 정수 | | `gh` 필요. merge-base(base tip, head) → head |
| 범위 | `--full` | 없음 | | 추적 파일 + ignore되지 않은 untracked 파일 전체 |
| 기준 브랜치 | `--base <ref>` | 필수 | 자동 결정 | `--changes`에서만 허용 |
| 파일 필터 | `--files <pathspec>` | 필수 | 없음 | 반복 가능. 모든 범위. 기본 제외보다 우선. 스크립트에는 `--include`로 전달 |
| 파일 필터 | `--exclude <pathspec>` | 필수 | 없음 | 반복 가능. 모든 범위 |
| 깊이 | `--depth` | `quick` \| `standard` \| `deep` | `standard` | |
| 지적 강도 | `--strictness` | `balanced` \| `strict` | `balanced` | |
| 심각도 하한 | `--min-severity` | `critical` \| `high` \| `medium` \| `low` | `low` | |
| 집중 영역 | `--focus` | 영역 slug 목록(쉼표 구분), `a11y`, `all` | `all` | slug: `security`, `correctness`, `ops`, `architecture`, `performance`, `tests`, `readability`, `style` |
| 보고 상한 | `--max-findings` | 1 이상의 정수 \| `all` | `20` | |
| 검증 실행 | `--run-tests` | 없음 | 꺼짐 | 플래그로만 켭니다(자연어로 켜지 않음) |

- 범위 옵션은 하나만 씁니다. 범위 플래그가 없으면 `--changes`입니다.
- 깊이, 지적 강도, 심각도 하한은 서로 독립입니다. 예를 들어 `--depth quick --strictness strict`도 유효합니다.
- v1.0에서 옵션 없이 고정된 값: 출력은 터미널, 언어는 한국어, 수정은 read-only, 실행은 single-agent.

## 2. 토큰 나누기

1. 입력을 공백으로 나눠 토큰을 만듭니다. 작은따옴표(`'...'`)나 큰따옴표(`"..."`)로 감싼 부분은 따옴표를 떼고 한 토큰으로 봅니다(공백이 든 경로용).
2. `--`로 시작하는 토큰만 플래그입니다. `-d`처럼 하이픈 하나로 시작하는 토큰은 플래그가 아니고 자연어로 취급합니다.
3. `--이름=값` 형태는 `--이름 값`과 같게 읽습니다.

## 3. 플래그 읽기

1. 플래그를 앞에서부터 순서대로 읽습니다.
2. 값이 필요한 옵션(`--pr`, `--base`, `--files`, `--exclude`, `--depth`, `--strictness`, `--min-severity`, `--focus`, `--max-findings`)은 바로 다음 토큰을 값으로 씁니다. 다음 토큰이 없거나 `--`로 시작하면 "값 누락" 오류입니다.
3. `--commit`은 다음 토큰이 없거나 `--`로 시작하면 값이 `HEAD`입니다. 그렇지 않으면 다음 토큰이 ref입니다.
4. 열거형 값(`--depth`, `--strictness`, `--min-severity`, `--focus`의 slug, `--max-findings all`)은 대소문자를 구분하지 않고 소문자로 정규화합니다. 옵션 이름은 소문자만 인정합니다.
5. 같은 설정 항목의 플래그가 여러 번 나오면:
   - 범위 플래그(`--changes`, `--staged`, `--commit`, `--pr`, `--full`)는 같은 플래그의 반복을 포함해 2개 이상이면 오류입니다.
   - `--files`, `--exclude`는 누적합니다(입력 순서 유지).
   - 그 밖의 값 옵션은 마지막 값이 우선합니다. `--run-tests` 반복은 한 번과 같습니다.
6. `--focus` 값:
   - 쉼표로 구분하고 공백을 넣지 않습니다. 빈 요소(끝의 쉼표 등)는 무시하고, 중복은 하나로 합칩니다.
   - 값에 `all`이 들어 있으면 결과는 `all`입니다. 8개 영역 slug가 모두 들어 있어도 `all`로 정규화합니다.
   - 출력 순서는 입력 순서와 관계없이 `security, correctness, ops, architecture, performance, tests, readability, style, a11y` 순서입니다.
7. `--pr` 값은 앞의 0을 뗀 양의 정수로 정규화합니다(`042` → `42`). `#42`, URL, `abc`는 정수가 아니므로 오류입니다.
8. `--max-findings` 값은 1 이상의 정수 또는 `all`입니다. 0, 음수, 소수는 오류입니다.
9. 오류(알 수 없는 옵션·값, 값 누락, 범위 플래그 2개 이상, `--changes`가 아닌 범위에서 `--base`, 정수가 아닌 `--pr`, `--commit`에 범위 지정, 잘못된 `--max-findings`)가 하나라도 있으면 리뷰를 시작하지 않고, 입력 순서상 첫 오류 하나를 `../report/errors.md` 1절 형식으로 출력합니다.

## 4. 정규화 출력

순서: 범위 → `--base`(`--changes`일 때만) → `--files`·`--exclude`(지정한 경우만, 입력 순서) → `--depth` → `--strictness` → `--min-severity` → `--focus` → `--max-findings` → `--run-tests`(켰을 때만)

- 값이 있는 항목은 기본값이어도 모두 출력합니다. 줄 형식은 `해석된 옵션: ` 뒤에 옵션을 공백 하나로 구분해 적습니다.
- 범위는 `--changes`, `--staged`, `--commit <ref>`(값 생략 시 `HEAD`를 적음), `--pr <n>`, `--full` 중 하나입니다.
- `--changes`면 항상 `--base <ref>`를 적습니다. 사용자가 지정하지 않았으면 `collect-context.sh`가 결정한 매니페스트 `base_ref` 값을 적습니다.
- `--files`·`--exclude`는 둘을 한 묶음으로 보고, 입력에 나온 순서대로 각각 `--files <p>`, `--exclude <p>`를 반복해 적습니다. 플래그와 자연어 필터가 섞였으면(`natural-language.md` 2절 1에 따라 버려지지 않은 것만) 입력 위치 순서입니다.
- pathspec에 공백, 따옴표, 셸 특수문자(`$`, `` ` ``, `*`, `?`, `[`, `;`, `&`, `|`, `<`, `>`, `(`, `)`)가 있으면 작은따옴표로 감싸 적습니다. 예: `--files 'src/my dir'`, `--files '*.ts'`.

## 5. 예시

기본(입력 없음, origin/HEAD가 origin/main):

    해석된 옵션: --changes --base origin/main --depth standard --strictness balanced --min-severity low --focus all --max-findings 20

| 입력 | 해석된 옵션 (기준 브랜치가 origin/main으로 자동 결정된다고 가정) |
|---|---|
| `--staged --full` | 오류: 범위 옵션은 하나만 쓸 수 있습니다 (입력: `--staged`, `--full`). |
| `--commit` | `--commit HEAD --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` |
| `--commit --depth deep` | `--commit HEAD --depth deep --strictness balanced --min-severity low --focus all --max-findings 20` |
| `--pr 42 --depth deep` | `--pr 42 --depth deep --strictness balanced --min-severity low --focus all --max-findings 20` |
| `--focus a11y,security` | `--changes --base origin/main --depth standard --strictness balanced --min-severity low --focus security,a11y --max-findings 20` |
| `--files 'src/my dir' --files '*.ts'` | `--changes --base origin/main --files 'src/my dir' --files '*.ts' --depth standard --strictness balanced --min-severity low --focus all --max-findings 20` |
| `--depth=deep --run-tests` | `--changes --base origin/main --depth deep --strictness balanced --min-severity low --focus all --max-findings 20 --run-tests` |
