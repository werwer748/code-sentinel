# 검증 실행 결과 읽기와 보고

`--run-tests`로 `run-verification.sh`를 실행한 뒤 출력을 읽을 때 읽습니다. 실행 절차는 `run.md`에 있습니다.

## 1. 출력 형식

stdout에 줄 기반 텍스트를 냅니다. 첫 줄은 `CODE_SENTINEL_VERIFY 1`, 이어서 `키<TAB>값` 줄과 `[섹션]`입니다.

    CODE_SENTINEL_VERIFY 1
    decision          allow|deny
    reasons           거부 사유를 "; "로 이은 한 줄, 없으면 -
    hooks_suppressed  yes|no|unknown
    exit_code         명령 종료 코드, 실행 안 했으면 -
    duration          소요 시간(정수 초), 실행 안 했으면 -
    log_file          출력 로그 경로(stdout·stderr 합침), 실행 안 했으면 -
    mode              check|run
    timed_out         yes|no, 실행 안 했으면 -
    timeout           타임아웃(초)
    repo              저장소 최상위(실제 경로)
    workdir           명령을 실행한 디렉터리(실제 경로)
    command           실행한 명령(표시용)
    kind              npm-script|pnpm-script|yarn-script|make|go|cargo|pytest|tsc|lint|other
    context_dir       로그가 든 임시 디렉터리, 없으면 -
    changes           none|detected|unknown, 실행 안 했으면 -
    tracked_changes   [TRACKED_CHANGES] 줄 수
    new_untracked     [NEW_UNTRACKED] 줄 수
    ignored_dirs      [IGNORED_DIRS] 줄 수
    refs_index        [REFS_INDEX] 줄 수
    isolation         unverified (격리 활성 여부는 확인하지 못함)
    [REASONS]         거부 사유 한 줄에 하나
    [CHECKED]         검사한 대상(script·make-target·makefile·env-file 등)
    [TRACKED_CHANGES]
    [NEW_UNTRACKED]
    [IGNORED_DIRS]
    [REFS_INDEX]
    [WARNINGS]        TMPDIR 대체, 버전 확인 실패 등
    [NOTES]           보장 한계 문구

(위 예시의 열 사이 공백은 실제로는 탭 하나입니다.)

- 로그는 `collect-context.sh`와 같은 방식(`../internals/git-and-temp.md` 1절)으로 만든 `code-sentinel.*` 임시 디렉터리(권한 700, 마커 `.code-sentinel-context`)에 씁니다. 실행한 경우에만 남고, 리뷰가 끝나면 `cleanup-context.sh <context_dir>`로 지웁니다. `--check`와 거부 시에는 임시 디렉터리를 남기지 않습니다.
- 사용법 오류(2)와 저장소 아님(3)은 stdout 대신 stderr에 원인과 다음 행동을 출력합니다.

## 2. 종료 코드

| 코드 | 의미 |
|---|---|
| 0 | 실행했고 명령 성공(`--check`면 허용). 전후 변경이 감지돼도 0이며 `changes detected`로 알림 |
| 2 | 사용법 오류(`--` 없음, 알 수 없는 옵션, 잘못된 `--timeout`) |
| 3 | Git 저장소가 아님(디렉터리 없음 포함) |
| 10 | 실행했고 명령 실패 |
| 11 | 타임아웃(자식 프로세스까지 종료) |
| 12 | 정적 검사에서 거부(실행하지 않음) |
| 1 | 내부 오류(임시 디렉터리 생성 실패, 실행 전 Git 상태 기록 실패 등. 이때는 실행하지 않음) |

## 3. pre/post 훅 억제 (`hooks_suppressed`)

패키지 관리자마다 다릅니다. 훅 내용은 억제 여부와 관계없이 **항상** 검사합니다(`../internals/verification-script.md` 1절).

| 실행 | 값 | 근거 |
|---|---|---|
| npm 7 이상 | `yes` | `ignore-scripts`가 켜지면 명시한 스크립트만 실행하고 pre/post 훅은 실행하지 않음. 버전은 `npm --version`으로 확인(저장소 밖 `/`에서 실행) |
| npm 6 이하, 버전 확인 실패 | `unknown` | `ignore-scripts` 동작이 다름 |
| Yarn Classic(1.x) | `no` | `run`이 훅도 실행함. `packageManager: yarn@1.*` 또는 v1 `yarn.lock`으로 판단 |
| Yarn 2 이상, 판단 불가 | `unknown` | |
| pnpm | `unknown` | 버전·설정(`enable-pre-post-scripts`)에 따라 다름 |
| make·go·cargo·pytest·tsc·린터 | `unknown` | 훅 개념이 없음. make의 의존 타깃은 실행 전 검사에 포함 |

## 4. 전후 비교

실행 전후의 저장소 상태(추적·untracked 파일, refs, index, 설정, ignored 항목 생성·삭제)를 비교합니다. **기존 ignored 디렉터리 안의 변화와 개별 ignored 파일의 내용 변경, 저장소 밖 부수 효과는 감지 범위 밖**입니다. 결과는 넷으로 나눠 출력합니다.

| 섹션 | 내용 | 줄 형식 |
|---|---|---|
| `[TRACKED_CHANGES]` | 추적 파일 변경 | `status<TAB>경로<TAB>전 -> 후`, 또는 `content`·`mode`·`type`·`link`·`deleted`(쉼표로 여럿)`<TAB>경로<TAB>same status <XY>` |
| `[NEW_UNTRACKED]` | 새 untracked 파일, 기존 untracked 파일의 변경 | `new<TAB>경로<TAB>-`, `modified<TAB>경로<TAB>content,mode…`, `deleted<TAB>경로<TAB>-`, `status<TAB>경로<TAB>?? -> A.` |
| `[IGNORED_DIRS]` | ignored 항목 생성·삭제(산출물·캐시일 수 있어 무해할 수 있음) | `created<TAB>경로`, `removed<TAB>경로` |
| `[REFS_INDEX]` | refs·index·설정 변경 | `HEAD<TAB>전 -> 후`, `HEAD_REF<TAB>전 -> 후`, `ref<TAB>refname<TAB>created\|deleted\|moved`, `stash<TAB>changed`, `index<TAB>changed\|created\|deleted`, `config<TAB>changed` |

- 상태 코드 `XY`는 공백을 `.`으로 바꿔 씁니다(예: `.M`). 깨끗한 상태는 `clean`입니다.
- 경로에 제어문자·역슬래시·큰따옴표가 있으면 C 스타일 따옴표 표기(`"..."`)로 씁니다.
- 테스트가 git을 실행해 index의 stat 정보만 갱신해도 `index changed`가 나올 수 있습니다. 보고할 때 "내용 변경이 아닐 수 있음"을 덧붙입니다.

## 5. 보고서 "검증 현황" 작성 예

    ## 검증 현황
    - 실행한 검증: npm test — 성공 (12초, 훅 억제 yes)
      정적 사전 필터 통과, 실행 격리는 도구 샌드박스에 의존, 격리 활성 여부는 확인하지 못함
      전후 비교: 추적 파일 변경 0 · 새 untracked 0 · ignored 생성·삭제 1 (coverage/, 무해할 수 있음) · refs·index 변경 0
      저장소 밖 부수 효과(로컬 DB, 전역 캐시, 네트워크 요청)는 확인하지 못함
    - 실행하지 않은 검증: npm run lint — 거부(파일 수정·스냅샷 갱신: scripts.lint (--fix))

- 테스트 실패는 "검증 현황"에 실패한 테스트 이름과 로그 요약으로 적고, 변경과 관련이 확인될 때만 근거로 인용합니다. 실패 자체를 발견 항목으로 만들지 않습니다.
- `changes detected`면 섹션별 목록을 그대로 옮겨 적고, 사용자에게 확인을 권합니다. 자동으로 되돌리지 않습니다.
