# 오류 메시지

옵션 오류, 스크립트를 찾지 못함, `collect-context.sh` 종료 코드가 0이 아닐 때 읽습니다. 오류는 원인 한 줄과 다음 행동 한 줄로만 출력합니다. `## 리뷰 요약`이나 다른 섹션을 쓰지 않고, 오류가 여러 개면 입력 순서상 첫 오류 하나만 적습니다.

## 1. 옵션 오류 (리뷰 시작 전)

| 경우 | 원인 줄 | 다음 행동 줄 |
|---|---|---|
| 알 수 없는 옵션 | 알 수 없는 옵션 `--deph`. `--depth`를 의도했나요? | 지원 옵션: --changes --staged --commit --pr --full --base --files --exclude --depth --strictness --min-severity --focus --max-findings --run-tests |
| 알 수 없는 값 | `--depth`의 값 `fast`를 알 수 없습니다. | quick, standard, deep 중 하나를 쓰세요. |
| 값 누락 | `--files`에 값이 없습니다. | `--files src/api`처럼 값을 지정하세요. |
| 범위 플래그 2개 이상 | 범위 옵션은 하나만 쓸 수 있습니다 (입력: `--staged`, `--pr 42`). | 하나만 남기고 다시 실행하세요. |
| `--changes`가 아닌 범위에서 `--base` | `--base`는 `--changes` 범위에서만 쓸 수 있습니다 (입력: `--staged`, `--base main`). | `--base`를 빼거나 `--changes`로 실행하세요. |
| 정수가 아닌 `--pr` | `--pr` 값은 PR 번호(양의 정수)여야 합니다 (입력: `#42`). | `--pr 42`처럼 번호만 지정하세요. |
| `--commit`에 범위 지정 | `--commit`은 커밋 하나만 받습니다 (입력: `A..B`). 범위 리뷰는 v1.0에서 지원하지 않습니다. | `--commit <ref>`로 커밋을 하나씩 지정하세요. |
| 잘못된 `--max-findings` | `--max-findings` 값 `0`을 쓸 수 없습니다. | 1 이상의 정수나 `all`을 쓰세요. |

- 알 수 없는 옵션은 철자가 가장 가까운 지원 옵션을 제안합니다(가까운 것이 없으면 제안 문장을 뺍니다).
- `--focus`의 알 수 없는 slug도 "알 수 없는 값" 오류입니다. 다음 행동 줄에 `security, correctness, ops, architecture, performance, tests, readability, style, a11y, all`을 나열합니다.

## 2. 실행 오류

| 상황 (`collect-context.sh` 종료 코드) | 원인 줄 | 다음 행동 줄 |
|---|---|---|
| 스크립트를 찾지 못함 | code-sentinel 스크립트를 찾을 수 없습니다. | 설치한 저장소에서 `scripts/doctor.sh`로 설치 상태를 확인하세요. |
| Git 저장소 아님 (3) | Git 저장소가 아닙니다. | 저장소 안에서 실행하세요. |
| 기준 브랜치 미결정 (4) | 기준 브랜치를 정할 수 없습니다. | `--base origin/main`처럼 지정하거나 `git config code-sentinel.base <ref>`로 저장하세요. |
| merge-base 없음 (4) | 기준 `<ref>`와 공통 조상(merge-base)을 찾을 수 없습니다. | 다른 `--base`를 지정하거나 `--staged`, `--commit`으로 범위를 바꾸세요. |
| shallow clone (4) | 히스토리가 얕아 merge-base를 구할 수 없습니다. | 직접 `git fetch --unshallow`를 실행한 뒤 다시 시도하세요. |
| partial clone 객체 누락 (4) | 리뷰에 필요한 Git 객체가 로컬에 없습니다. code-sentinel은 fetch하지 않습니다. | 직접 객체를 받은 뒤 다시 시도하세요. |
| git 2.46 미만의 partial clone (4) | git 2.46 미만에서는 partial clone 저장소의 객체 자동 다운로드를 막을 수 없어 수집하지 않습니다. | git을 업데이트하거나 `--pr` 범위를 쓰세요. |
| 커밋 없는 저장소의 `--changes` (4) | 커밋이 없는 저장소에서는 `--changes`의 기준을 정할 수 없습니다. | `--staged`로 실행하세요. |
| 잘못된 ref (5) | `abc123`을 찾을 수 없습니다. | 커밋 해시나 브랜치 이름을 확인하세요. |
| `gh` 미인증 (6) | GitHub CLI 인증이 필요합니다. | `gh auth login` 후 다시 실행하세요. |
| `gh` 없음 (6) | GitHub CLI(`gh`)가 없습니다. | `gh`를 설치하고 `gh auth login` 후 다시 실행하세요. |
| PR 접근 불가 (6) | PR #42에 접근할 수 없습니다. | 저장소 권한이나 번호를 확인하세요. Codex 샌드박스에서는 네트워크가 막혀 있을 수 있습니다. |
| 사용법 오류 (2) | 1절에서 해당하는 원인 줄(스크립트 stderr 사유 기준) | 1절의 다음 행동 줄 |
| 그 밖의 종료 코드 | 컨텍스트 수집에 실패했습니다 (종료 코드 N: <stderr 첫 줄>). | 원인을 해결한 뒤 다시 실행하세요. 계속되면 `scripts/doctor.sh`로 설치 상태를 확인하세요. |

- 종료 코드 4·6의 하위 원인은 스크립트 stderr로 구분합니다. 구분이 어려우면 표에서 그 코드의 첫 행을 쓰고 원인 줄 끝에 stderr 첫 줄을 괄호로 덧붙입니다.
- `--pr`이 실패해도 다른 범위로 대신 리뷰하지 않습니다.
- 오류 출력 뒤에도 `context_dir`가 출력됐다면 정리 스크립트를 실행하고, 실패하면 세 번째 줄로 `임시 디렉터리 정리 실패: <경로>`를 적습니다.
- 이 메시지와 `codex exec`·`claude -p` 프로세스의 종료 코드는 별개입니다.
