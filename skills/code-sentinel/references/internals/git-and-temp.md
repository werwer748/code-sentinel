# 임시 디렉터리 정리와 Git 호출 고정

스크립트 동작 설명입니다. 리뷰 중에는 읽지 않습니다(모델이 지킬 규칙은 `SKILL.md` 4절에 요약). 사용자가 스크립트 동작을 물을 때 참고합니다.

## 1. 임시 디렉터리와 정리

**생성 (`collect-context.sh`)**

- `umask 077` 후 `mktemp -d "${TMPDIR:-/tmp}/code-sentinel.XXXXXX"`로 만듭니다. `$TMPDIR`에 쓸 수 없으면 `/tmp`로 대체하고 `[WARNINGS]`에 적습니다.
- 생성 직후 마커 파일 `.code-sentinel-context`를 씁니다. 내용은 `created_at <epoch>`, `pid <pid>`, `token <무작위 hex>` 세 줄입니다.
- `context_dir`는 `cd -P` 후 `pwd -P`로 정규화한 실제 경로입니다(macOS의 `/var/folders/...`는 `/private/var/...`를 가리키는 링크 아래에 있음).
- `trap`을 EXIT·INT·TERM·HUP에 걸어 실패 시 스스로 정리합니다. 정상 종료 시에는 디렉터리를 남기고, 모델이 리뷰를 마친 뒤 `cleanup-context.sh <context_dir>`를 호출합니다.
- 스크립트는 스킬 디렉터리와 그 링크 대상에 어떤 파일도 쓰지 않습니다.

**`cleanup-context.sh`는 다음을 모두 만족할 때만 삭제합니다**

1. 인자가 정확히 1개이고, 비어 있지 않은 절대 경로이며, `..` 경로 요소나 개행 등 제어문자가 없음(공백은 허용)
2. 인자 자체가 심볼릭 링크가 아님
3. `cd -P` 후 `pwd -P`로 얻은 실제 경로가, 같은 방식으로 정규화한 `${TMPDIR:-/tmp}` 또는 `/tmp`의 **바로 아래** 디렉터리임
4. 디렉터리 이름이 `code-sentinel.` 접두어 형식임
5. 마커 파일이 일반 파일로 존재하고 형식이 맞음
6. 소유자가 현재 사용자임

- 삭제는 검증한 실제 경로에 대해 합니다. `realpath`·`readlink -f`는 쓰지 않습니다.
- 정리에 실패하면 0이 아닌 코드로 끝내고 남은 경로를 출력합니다. 모델은 그 경로를 보고서에 적고, 다른 방법으로 지우지 않습니다.
- `--stale <분>`(기본 1440)은 임시 디렉터리 바로 아래의 `code-sentinel.*` 중 위 검증을 통과하고 마커 시각이 기준보다 오래된 것만 삭제합니다.
- 사용자 파일을 자동으로 복구하거나 삭제하지 않습니다.

## 2. Git 호출 고정

사용자 git 설정이 출력 형식을 바꾸거나 외부 명령을 실행하지 못하게 모든 git 호출을 고정합니다. 모델이 직접 git을 호출할 때도 같은 원칙을 따릅니다.

- 환경:
  - `GIT_PAGER=cat`
  - `GIT_OPTIONAL_LOCKS=0`: `git status`가 인덱스를 다시 쓰지 않게
  - `GIT_NO_LAZY_FETCH=1`: partial clone의 자동 객체 다운로드 차단. git 2.45에서 도입, 2.46에서 promisor 경로 검사가 추가됐으므로 2.46 이상에서만 보장으로 취급
- 공통 설정: `git --no-pager -c core.quotePath=false -c color.ui=never -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.relative=false -c core.fsmonitor=false`
- diff 계열: `-z`(목록), `-M`, `--no-color`, `--no-ext-diff`, `--no-textconv`
- 파일 목록은 NUL로 구분해 받고 `while IFS= read -r -d '' f` 형태로 처리합니다.
- worktree에서는 `.git`이 파일일 수 있으므로 `git rev-parse --show-toplevel`, `--git-dir`, `--git-path` 결과만 신뢰합니다.
- **금지 명령:** `stash`, `checkout`, `switch`, `reset`, `restore`, `clean`, `add`(`-N` 포함), `commit`, `fetch`, `pull`, `submodule update`, `gc`, `update-index`, `worktree add`, `gh pr checkout`

### 2.1 clean/process 필터

- 위 옵션으로는 막히지 않고, `git diff`와 `git status`는 크기가 같은 변경을 비교할 때 clean 필터를 실행합니다(로컬 재현으로 확인).
- `git check-attr -z filter`(필터를 실행하지 않음)로 필터 대상 경로와 드라이버 이름을 찾습니다.
- 모든 git 호출에서 해당 드라이버를 `-c filter.<name>.clean= -c filter.<name>.smudge= -c filter.<name>.process= -c filter.<name>.required=false`로 무력화합니다.
- Git LFS 대상은 `lfs`로 표시만 하고 실제 검토로 세지 않습니다.
- 그 밖의 필터 대상은 내용 비교에서 빼고 `[SKIPPED]`에 `filter`로 넣습니다(partial 사유). `[FILES]`에는 `filtered`로 표시될 수 있습니다.

### 2.2 partial clone

- commit과 merge-base가 있어도 diff에 필요한 tree·blob이 없을 수 있습니다. 필요한 객체가 없거나 diff 생성이 실패하면 `--pr`은 `gh pr diff`로 처리하고, 그 밖의 범위는 종료 코드 4로 끝냅니다(shallow clone과 같은 "히스토리·객체 불완전" 범주). "변경 없음"으로 처리하지 않습니다.
- git이 2.46 미만이고 partial clone 저장소이면 객체를 읽지 않습니다. `--pr`은 `gh pr diff`, 그 밖의 범위는 종료 코드 4입니다.
- 모델도 누락 객체를 가져오는 명령을 실행하지 않고, 사용자가 직접 받도록 안내합니다.
