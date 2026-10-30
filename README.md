# code-sentinel

macOS에서 **OpenAI Codex**와 **Anthropic Claude Code**가 함께 쓰는 읽기 전용 코드 리뷰 스킬입니다. Git 변경사항을 보안, 정확성, 운영, 아키텍처, 성능, 테스트, 가독성, 컨벤션 8개 영역과 backend·frontend·infra 프로필 기준으로 검토하고, 한국어 보고서를 냅니다.

- 하나의 `skills/code-sentinel/SKILL.md`를 두 도구가 공유합니다.
- 소스 파일과 Git 상태(인덱스, refs, stash, 작업 트리)를 바꾸지 않습니다.
- 수집하기만 한 파일은 검토한 것으로 세지 않습니다. 생략이 있으면 보고서에 `partial`로 표시합니다.

상세 동작은 [SPEC.md](SPEC.md)에 있습니다.

## 설치

    git clone <저장소 URL> ~/code-sentinel
    ~/code-sentinel/scripts/install.sh            # Codex + Claude Code
    ~/code-sentinel/scripts/install.sh --claude   # Claude Code만
    ~/code-sentinel/scripts/install.sh --codex    # Codex만
    ~/code-sentinel/scripts/install.sh --dry-run  # 무엇을 할지만 출력

설치 스크립트는 각 도구의 사용자 스킬 디렉터리에 이 저장소의 `skills/code-sentinel`을 가리키는 심볼릭 링크 하나만 만듭니다.

| 도구 | 링크 위치 |
|---|---|
| Codex | `~/.agents/skills/code-sentinel` |
| Claude Code | `${CLAUDE_CONFIG_DIR:-~/.claude}/skills/code-sentinel` |

- 같은 위치에 실제 디렉터리가 있으면 건드리지 않고 멈춥니다.
- 다른 곳을 가리키는 링크는 `--force`일 때만 교체합니다.
- 실행 중인 세션에는 바로 반영되지 않을 수 있습니다. Claude Code는 skills 디렉터리를 새로 만든 경우 `/reload-skills`를 실행하고, Codex는 재시작하세요.

**점검과 제거**

    ~/code-sentinel/scripts/doctor.sh      # 링크 상태, frontmatter, 버전, 의존 도구 점검
    ~/code-sentinel/scripts/uninstall.sh   # 이 저장소를 가리키는 링크만 제거

**업데이트:** 링크 방식이므로 `git pull`만 하면 반영됩니다. 버전은 git tag와 [CHANGELOG.md](CHANGELOG.md)로 관리합니다.

## 사용법

    Codex                                        Claude Code
    $code-sentinel                               /code-sentinel
    $code-sentinel --staged                      /code-sentinel --staged
    $code-sentinel --pr 42 --depth deep          /code-sentinel --pr 42 --depth deep
    $code-sentinel --focus security,a11y         /code-sentinel --focus security,a11y
    $code-sentinel 보안 위주로 빠르게            /code-sentinel 보안 위주로 빠르게

| 항목 | 옵션 | 기본값 |
|---|---|---|
| 범위 | `--changes` \| `--staged` \| `--commit [ref]` \| `--pr <n>` \| `--full` | `--changes` |
| 기준 브랜치 | `--base <ref>` (`--changes`에서만) | `git config code-sentinel.base` → `origin/HEAD` |
| 파일 필터 | `--files <pathspec>`, `--exclude <pathspec>` | 없음 |
| 깊이 | `--depth quick\|standard\|deep` | `standard` |
| 지적 강도 | `--strictness balanced\|strict` | `balanced` |
| 심각도 하한 | `--min-severity critical\|high\|medium\|low` | `low` |
| 집중 영역 | `--focus <area>[,<area>]` | `all` |
| 보고 상한 | `--max-findings <n>\|all` | `20` |
| 검증 실행 | `--run-tests` | 꺼짐 |

- "빠르게", "꼼꼼히", "스테이징한 것만", "PR 42", "보안 위주로" 같은 자연어도 옵션으로 해석합니다. 해석 결과는 보고서 첫 줄 `해석된 옵션:`에 나옵니다.
- 기준 브랜치를 자동으로 정할 수 없으면 main·master를 추정하지 않고 멈춥니다. `--base origin/main`처럼 지정하거나 `git config code-sentinel.base origin/main`으로 저장하세요.
- 보고서의 특정 항목을 고치려면 번호로 요청하세요(예: "S-01 고쳐줘"). 리뷰 자체는 아무것도 수정하지 않습니다.

## read-only를 더 확실히 하려면

code-sentinel은 스스로 읽기 전용 규칙을 지키지만, 도구 수준의 제한을 함께 쓰면 더 안전합니다.

- **Codex:** `codex --sandbox read-only`로 실행합니다. 단, `--run-tests`는 테스트가 산출물을 쓸 수 있어 읽기 전용 샌드박스에서 실패할 수 있습니다.
- **Claude Code:** plan 모드나 권한 설정(편집 도구 차단)을 씁니다. `/sandbox`로 샌드박스를 켜면 `--run-tests`의 네트워크·쓰기도 제한됩니다.

## 알려진 한계

- **자연어 해석:** 모델이 해석하므로 완전히 결정적이지 않습니다. 같은 입력이면 같은 결과가 나오도록 규칙을 정해 두었지만 보장은 아닙니다. 중요한 실행은 플래그로 지정하세요.
- **`--run-tests`:** 위험한 스크립트(watch, `--fix`, 설치, 마이그레이션, 코드 생성 등)를 실행 전에 정적으로 걸러내지만, 이것은 사전 필터일 뿐입니다.
  - 테스트 코드가 직접 하는 쓰기·네트워크 요청은 도구 샌드박스로만 막을 수 있습니다.
  - code-sentinel은 샌드박스가 켜져 있는지 확인할 수 없습니다.
  - 실행 전후로 저장소 상태를 비교하지만, 저장소 밖의 부수 효과(로컬 DB, 전역 캐시, 네트워크 요청)는 감지하지 못합니다.
- **`--pr`:** `gh`가 설치·인증되어 있어야 합니다. code-sentinel은 `git fetch`를 하지 않으므로, PR head 커밋이 로컬에 없으면 diff만 보고 리뷰합니다(diff-only).
- **shallow·partial clone:** shallow clone은 merge-base를 구할 수 없으면 멈춥니다. partial clone은 필요한 객체가 없으면 멈추고, git 2.46 미만에서는 객체 지연 다운로드를 막을 수 없어 `--pr` 외 범위를 지원하지 않습니다.
- **크기 상한:** 파일당 1 MiB, `--full` 전체 10 MiB를 넘는 내용은 수집하지 않고 `partial`로 표시합니다.
- **기본 제외:** lockfile, 빌드 산출물, minified, 스냅샷, 생성 코드는 리뷰하지 않습니다(`--files`로 명시하면 포함). lockfile은 manifest와의 일치 여부만 확인합니다.
- **임시 디렉터리:** 리뷰 도중 AI 도구가 비정상 종료되면(사용량 한도, 강제 종료 등) 정리 단계가 실행되지 않아 `${TMPDIR}/code-sentinel.*`가 남을 수 있습니다. `skills/code-sentinel/scripts/cleanup-context.sh --stale`로 하루(1440분)가 지난 것을 지울 수 있습니다.
- **리뷰 품질:** 실제 도구 검증(2라운드)에서 8개 조합 중 4개만 합격했습니다. 불합격 원인은 모델의 심각도·영역 판단이 기대값과 다른 것(서버 전용 모듈 import를 `correctness`로 분류, `latest`·root Dockerfile을 Low로 판단)과 Low 항목 누락입니다. 자세한 내용은 [tests/REVIEW-QUALITY.md](tests/REVIEW-QUALITY.md)에 있습니다.

## 개발

    /bin/bash tests/run.sh          # 전체 자동 테스트 (모델 실행 없음)
    /bin/bash tests/run.sh scope    # 하나만
    /bin/bash tests/run-quality.sh --dry-run   # 실제 도구 품질 검증 명령 미리 보기

- 모든 스크립트는 macOS 기본 `/bin/bash` 3.2와 BSD 유틸로 동작해야 합니다.
- 테스트는 임시 HOME·TMPDIR·git 설정에서 실행되며 실제 사용자 설정을 건드리지 않습니다.
- `shellcheck`가 있으면 정적 검사에 포함하고, 없으면 SKIP합니다.
- 실제 Codex·Claude Code 품질 검증 절차와 결과는 [tests/REVIEW-QUALITY.md](tests/REVIEW-QUALITY.md)에 있습니다.

## 라이선스

MIT ([LICENSE](LICENSE)), Copyright (c) 2026 HugoK. 누구나 복제·수정·재배포(상업적 사용 포함)할 수 있고, 재배포할 때 저작권 표기와 라이선스 문구를 함께 넣으면 됩니다.
