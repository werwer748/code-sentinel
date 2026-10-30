# `run-verification.sh` 거부 규칙, 실행 환경, 타임아웃

스크립트 동작 설명입니다. 리뷰 중에는 읽지 않습니다(거부되면 출력의 `reasons`를 그대로 보고). 사용자가 거부 사유나 실행 환경을 물을 때 참고합니다.

## 1. 실행 전 검사 (거부 규칙)

다음 중 하나라도 해당하면 실행하지 않고 `decision deny`와 사유를 출력합니다(종료 코드 12).

**검사 대상 텍스트**

- npm·pnpm·yarn: 대상 스크립트, 그 `pre<이름>`·`post<이름>` 훅, 스크립트가 다시 부르는 스크립트(`npm run x`, `yarn x`, `run-s`·`run-p`·`npm-run-all`의 이름과 glob, `npm:x`)와 그 훅, 설치 수명주기 훅(`preinstall`, `install`, `postinstall`, `preprepare`, `prepare`, `postprepare`).
  - 설치 수명주기 훅은 패키지 관리자 설정(예: pnpm의 실행 전 의존성 확인)에 따라 암묵적으로 실행될 수 있고 code-sentinel이 이를 확인할 수 없으므로 항상 검사합니다.
- Makefile: 대상 타깃과 의존 타깃(변수로 지정한 의존 포함)의 레시피, 레시피가 참조하는 변수, `$(MAKE) <타깃>` 재귀 호출 타깃, include한 저장소 안 Makefile, 해석 시점에 실행되는 `$(shell ...)`·`!=` 할당. 레시피가 npm 스크립트를 부르면 그 스크립트도 검사합니다.
- 명령 인자(`npm test -- --watch` 등)

**거부 사유**

| 분류 | 예 |
|---|---|
| watch 모드 | `--watch`, `--watchAll`(`=false`는 허용), `run` 없는 `vitest`, `nodemon`, `ng test`(`--watch=false` 없이), `tsc -w` |
| 파일 수정·스냅샷 갱신 | `--fix`, `--write`, `-u`, `--update-snapshot`, `--updateSnapshot`, `--update`, `prettier -w`, `--apply`, `--autocorrect` |
| 설치 | `npm/pnpm/yarn install·ci·add`, 인자 없는 `yarn`, `pip install`, `go get`, `cargo install`, `bundle install`, `corepack enable` 등 |
| 다운로드 가능 실행 | 미설치 패키지의 `npx`, `npx -p`, `pnpm dlx`, `yarn dlx`, `bunx`, `npm exec` |
| 마이그레이션 | `migrate`, `db push`, `db:seed`, `db:reset`, `schema:sync`, `alembic upgrade` 등 |
| 코드 생성 | `generate`, `codegen` (`prisma generate`, `go generate` 등) |
| docker | `docker`, `docker-compose`, `podman` |
| 원격 스크립트 실행 | `curl ... \| sh`, `wget ... \| bash`, `bash <(curl ...)`, `sh -c "$(curl ...)"` |
| 재귀 삭제 | `rm -rf`(재귀 옵션이 있는 `rm`), `rimraf`, `find ... -delete` |
| Git 상태 변경 | `git checkout·reset·clean·stash·commit·add·push·fetch` 등 |
| 권한 상승 | `sudo`, `doas`, `su` |
| 실제 DB·큐 접속 설정 | `postgres://`, `mysql://`, `redis://`, `amqp://` 등, `DATABASE_URL`, `REDIS_URL` 같은 접속 변수 |
| `.env` 자격증명 | 스크립트가 `.env*`를 불러옴(`dotenv`, `env-cmd`, `--env-file`, `.env` 경로), 또는 작업 디렉터리·`package.json` 위치·저장소 최상위의 `.env`, `.env.*`(`.example`·`.sample`·`.template` 등 제외)에 비밀값(`*PASSWORD*`, `*SECRET*`, `*TOKEN*`, `*API_KEY*` 등)이나 DB·큐 접속 설정이 있음 |
| testcontainers | manifest(`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements*.txt`, `pom.xml`, `build.gradle` 등)나 스크립트에 `testcontainers` |
| 정적 확인 불가 | `package.json` 해석 실패, 변수·glob이 든 Makefile include, 없는 include 파일, 저장소 밖 include, `-C`·`-f`를 쓰는 재귀 make, 없는 스크립트·타깃 |

- `package.json`은 `osascript -l JavaScript`의 `JSON.parse`로 읽습니다. `jq`·`python`·`node`에 의존하지 않으며, `plutil -extract`는 점이 든 키(`test.unit`)를 읽지 못해 쓰지 않습니다.
- Makefile은 `make -n`을 쓰지 않습니다(일부 레시피를 실제로 실행할 수 있음). 조건문(`ifeq` 등)은 양쪽 분기를 모두 검사 대상으로 봅니다.
- 이 규칙은 보수적입니다. 일반 단어(`generate`, `docker`)가 테스트 이름 패턴 등에 들어 있어도 거부할 수 있습니다. 거부되면 사유를 그대로 보고하고 사용자가 직접 실행하도록 안내합니다.
- 스크립트가 호출하는 **별도 파일**(셸 스크립트, JS·설정 파일, 테스트 코드, `conftest.py`, `build.rs`)의 내용은 검사하지 않습니다.

## 2. 실행 환경

| 설정 | 값 |
|---|---|
| 작업 디렉터리 | `--repo` 경로(기본: 현재 디렉터리) |
| 표준입력 | `/dev/null` |
| CI·훅 | `CI=1`, `HUSKY=0` |
| npm 계열 | `npm_config_ignore_scripts=true`, `npm_config_offline=true`, `npm_config_update_notifier=false` |
| Go | `GOPROXY=off`, `GOFLAGS=-mod=readonly`, `GOTOOLCHAIN=local` |
| Rust | `CARGO_NET_OFFLINE=true` |
| Python | `PIP_NO_INDEX=1`, `PYTHONDONTWRITEBYTECODE=1` |
| Corepack | `COREPACK_ENABLE_NETWORK=0` (패키지 관리자 내려받기 차단) |
| make | `MAKEFILES` 해제 |

- 그 밖의 환경변수는 그대로 물려받습니다. 현재 셸에 DB 접속 변수 등이 있으면 테스트가 그것을 쓸 수 있습니다.
- 로캘(`LC_ALL`)은 호출할 때의 값을 그대로 돌려줍니다.

## 3. 타임아웃

- 기본 600초, `--timeout <초>`(1~86400)로 바꿉니다.
- macOS에는 `timeout` 명령이 없으므로 bash로 구현합니다. 명령을 백그라운드로 실행하고 감시하다가, 시간이 지나면 프로세스 트리 전체(`pgrep -P`로 모은 자손)를 멈춘(STOP) 뒤 `TERM`을 보내고, 최대 3초 뒤 남은 프로세스에 `KILL`을 보냅니다.
- 타임아웃이면 종료 코드 11, `timed_out yes`입니다. `exit_code`에는 종료 신호에 따른 값(예: 143)이 남습니다.
- 자손이 스스로 새 세션으로 분리(데몬화)해 트리를 벗어나면 종료하지 못할 수 있습니다.
- 스크립트 자체가 INT·TERM·HUP을 받으면 실행 중인 프로세스 트리를 종료하고 임시 디렉터리를 지운 뒤 끝납니다.

## 4. 전후 비교 기록

`git-and-temp.md` 2절의 git 호출 고정(`GIT_OPTIONAL_LOCKS=0`, `GIT_NO_LAZY_FETCH=1`, `core.fsmonitor=false` 등)과 clean/process 필터 무력화(`git check-attr -z filter`로 찾은 드라이버를 `-c filter.<이름>.clean=` 등으로 비움)를 똑같이 적용합니다. 비교 중 필터·fsmonitor 훅·외부 diff는 실행되지 않습니다.

실행 전후로 다음을 기록해 비교합니다.

- `git status --porcelain=v1 -z -uall` (ignored 제외)
- `HEAD`(SHA와 가리키는 브랜치), `git for-each-ref`, stash 기록(`refs/stash`의 reflog. `git stash` 명령은 쓰지 않음)
- index 파일 체크섬: 경로는 `git rev-parse --git-path index`. index가 없는 저장소도 처리(`index created` 등)
- 저장소 설정 파일(`git rev-parse --git-path config`) 체크섬
- 실행 전에 이미 변경 상태였던 추적 파일과 untracked 파일의 **내용 해시·종류·모드·링크 대상**. 상태가 계속 `M`이면 `git status`만으로는 추가 변경을 잡을 수 없기 때문입니다. 내용 해시는 작업 트리 파일을 직접 읽어 계산하므로 필터를 거치지 않습니다.
- ignored 항목(`--ignored=traditional`, 디렉터리는 `dir/` 단위)의 생성·삭제. **기존 ignored 디렉터리 안의 변화와 개별 ignored 파일의 내용 변경은 감지 범위 밖**입니다.

출력 형식은 `../verification/results.md` 4절에 있습니다.
