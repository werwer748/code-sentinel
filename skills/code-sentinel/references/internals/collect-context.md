# `collect-context.sh` 입력, 종료 코드, 수치 기본값, 실행 제약

스크립트 동작 설명입니다. 리뷰 중에는 읽지 않습니다(인자 표는 `SKILL.md` 3절, 오류 메시지는 `../report/errors.md`). 사용자가 스크립트 동작을 물을 때 참고합니다.

## 1. 위치와 입력

위치는 스킬 디렉터리의 `scripts/collect-context.sh`입니다(저장소 루트의 `scripts/`는 설치·제거·점검용으로 별개). 자연어를 해석하지 않고 정규화된 인자만 받아 엄격하게 검증합니다.

    collect-context.sh --scope changes|staged|commit|pr|full
                       [--base <ref>] [--ref <ref>] [--pr <n>]
                       [--include <pathspec>]... [--exclude <pathspec>]...
                       [--repo <path>]

| 사용자 옵션(정규화 후) | 스크립트 인자 |
|---|---|
| `--changes` | `--scope changes` |
| `--staged` | `--scope staged` |
| `--commit <ref>` | `--scope commit --ref <ref>` |
| `--pr <n>` | `--scope pr --pr <n>` |
| `--full` | `--scope full` |
| `--base <ref>` | `--base <ref>` (사용자가 지정했을 때만) |
| `--files <p>` | `--include <p>` |
| `--exclude <p>` | `--exclude <p>` |

`--depth`, `--strictness`, `--min-severity`, `--focus`, `--max-findings`, `--run-tests`는 스크립트에 넘기지 않습니다.

## 2. 종료 코드 (`collect-context.sh`)

| 코드 | 의미 | 보고서 대신 출력할 메시지(원인 / 다음 행동) |
|---|---|---|
| 0 | 성공(변경 없음 포함, `target_files 0`) | — (변경 없으면 요약과 "리뷰할 변경사항 없음") |
| 2 | 사용법 오류: 알 수 없는 옵션, 잘못된 값, 범위 충돌, `--base` 오용 | 해당 사유의 오류 메시지 |
| 3 | Git 저장소가 아님 | Git 저장소가 아닙니다. / 저장소 안에서 실행하세요. |
| 4 | 기준을 정할 수 없음: 기준 브랜치 미결정, merge-base 없음, shallow clone, partial clone 객체 누락 | 원인에 맞는 메시지(기준 브랜치 지정 안내, `git fetch --unshallow` 안내, 객체 직접 받기 안내) |
| 5 | ref를 해석할 수 없음 | `<ref>`을 찾을 수 없습니다. / 커밋 해시나 브랜치 이름을 확인하세요. |
| 6 | PR 접근 불가: `gh` 없음, 미인증, 권한 없음, 네트워크 차단 | `gh auth login` 안내 또는 PR 접근 불가 안내(Codex 샌드박스 네트워크 차단 가능성 포함) |

- 이 종료 코드는 `collect-context.sh`에만 적용됩니다. 스킬이 출력하는 오류 메시지, `codex exec`·`claude -p` 프로세스의 종료 코드와는 별개입니다.
- 0이 아니면 스크립트가 임시 디렉터리를 스스로 정리합니다. 그래도 출력에 `context_dir`가 있었다면 모델이 `cleanup-context.sh`를 호출합니다.
- 메시지 전문은 `../report/errors.md`를 따릅니다.

## 3. 수치 기본값

`collect-context.sh`(정리·검증 값은 각 스크립트) 상단에 상수로 정의된 값입니다.

| 항목 | 값 | 넘으면 |
|---|---|---|
| 파일당 수집 상한 | 1 MiB (1,048,576 bytes) | `[SKIPPED] size`, partial |
| `--full` 누적 수집 상한 | 10 MiB (10,485,760 bytes) | 이후 파일 `[SKIPPED] total-size`, partial |
| 커밋 메시지 수집 개수 | 최근 50개 | 잘랐다는 사실을 `[WARNINGS]`에 기록 |
| 분할 권장 기준 | 대상 파일 60개 또는 3,000줄 초과 | `split recommended` |
| 일부만 분석 기준 | 대상 파일 300개 또는 20,000줄 초과 | `split truncated` |
| 오래된 임시 디렉터리 기준 (`cleanup-context.sh --stale`) | 1440분 (24시간) | 검증을 통과한 것만 삭제 |
| 검증 실행 타임아웃 (`run-verification.sh`) | 600초 | 자식 프로세스까지 종료, 종료 코드 11 |

## 4. 실행 제약 (스크립트)

- macOS 기본 `/bin/bash` 3.2 호환, shebang `#!/bin/bash`, `set -euo pipefail`.
- 금지 구문: `mapfile`, `readarray`, `declare -A`, `declare -n`, `local -n`, `${var,,}`, `${var^^}`, `|&`, `;;&`, `coproc`, `globstar`.
- BSD 유틸만 씁니다. `readlink -f`, `realpath`, 확장자 인자 없는 `sed -i`, `grep -P`, `stat -c`, `date -d`, `timeout` 명령에 의존하지 않습니다.
