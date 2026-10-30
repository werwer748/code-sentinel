# infra 프로필

의존성, CI, 컨테이너, IaC, 쿠버네티스, 셸 스크립트 변경에서 "특히 확인할 것"을 8개 리뷰 영역에 덧붙이는 프로필입니다. 프로필은 영역을 대체하지 않습니다. 발견 항목은 아래 표시된 영역 slug로 보고하며, 해당 없는 항목은 보고서에 쓰지 않습니다. 심각도는 `../review/severity.md`, 보고 형식은 `../report/findings.md`를 따릅니다.

## 1. 감지 신호

변경 파일(`[FILES]`)과 규칙 제외 목록(`[RULE_EXCLUDED]`)의 경로를 보고, 다음 중 하나라도 해당하면 적용합니다. backend·frontend 프로필과 동시에 적용될 수 있습니다.

| 종류 | 신호 |
|---|---|
| 컨테이너 | `Dockerfile`, `Dockerfile.*`, `*.dockerfile`, `.dockerignore`, `docker-compose*.yml`, `compose.yaml`·`compose.yml` |
| CI | `.github/workflows/*.yml`·`*.yaml`, `.github/actions/`, `.gitlab-ci.yml`, `.circleci/`, `Jenkinsfile`, `azure-pipelines.yml`, `buildkite` 설정 |
| IaC | `*.tf`, `*.tfvars`, `*.hcl`, `terragrunt.hcl`, CloudFormation·SAM 템플릿, `serverless.yml`, Pulumi 코드, CDK 스택 |
| 쿠버네티스 | `apiVersion`·`kind`가 있는 YAML, `Chart.yaml`, `values*.yaml`, `templates/`, `kustomization.yaml` |
| 권한 정책 | IAM 정책 JSON·YAML, RBAC `Role`·`ClusterRole`·`RoleBinding` |
| 셸 | `*.sh`, `*.bash`, shebang이 셸인 스크립트, `Makefile`의 레시피 |
| 의존성 | lockfile(규칙 제외 목록에 있어도 신호로 씀), 의존성 manifest(`package.json`의 `dependencies`·`scripts`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements*.txt`, `Gemfile`, `composer.json`) 변경 |

신호가 없으면 적용하지 않습니다. 적용 여부는 보고서 요약의 "적용 프로필"에 적습니다.

lockfile은 규칙 제외라 본문을 읽지 않지만, **변경 여부와 manifest와의 일치**는 확인합니다.

## 2. 영역별로 특히 확인할 것

### `security`

- **CI — `pull_request_target`과 secrets 노출:** `pull_request_target`·`workflow_run`에서 PR head 코드를 체크아웃해 실행하면서 secrets나 쓰기 토큰을 쓰는 워크플로. 포크 PR이 비밀을 탈취할 수 있음
- **CI — 해시로 고정하지 않은 action:** 서드파티 action을 태그·브랜치(`@v3`, `@main`)로 참조. 전체 커밋 SHA로 고정 권장(공식 `actions/*`도 정책에 따라)
- **CI — `permissions` 확대:** `permissions: write-all`, 필요 이상의 `contents: write`·`id-token: write`, 기본 토큰 권한 확대
- **CI — 스크립트 주입:** `${{ github.event.* }}`(PR 제목·브랜치 이름 등)을 `run:`에 직접 넣음
- **Dockerfile — 레이어에 남은 비밀정보:** `ARG`·`ENV`·`COPY`로 넣은 키, 나중 레이어에서 지워도 이미지 히스토리에 남음(빌드 시크릿 마운트 권장)
- **Dockerfile — `curl | sh` 형태의 설치:** 원격 스크립트를 검증 없이 셸로 실행
- **권한 — 와일드카드 IAM:** `Action: "*"`, `Resource: "*"`, `iam:PassRole` 남용, 과도한 RBAC(`ClusterRole`에 `*` 동사·리소스, `cluster-admin` 바인딩)
- **K8s·IaC 노출:** `0.0.0.0/0` 인바운드, 공개 버킷·공개 ACL, 상태 파일(`terraform.tfstate`) 커밋·공개 저장, 평문 시크릿 매니페스트
- **K8s 권한:** `privileged: true`, `hostPath`, `hostNetwork`, `hostPID`, `allowPrivilegeEscalation`, root 실행
- **의존성 — postinstall 스크립트:** 새 의존성의 설치 스크립트, 의존성 출처 변경(레지스트리·git URL)

### `correctness`

- **manifest와 lockfile 불일치:** manifest의 의존성 추가·버전 변경에 lockfile 변경이 없음, 또는 lockfile만 바뀜
- **셸 — `set -euo pipefail` 누락:** 실패를 무시하고 진행
- **셸 — 인용 누락:** 공백·글로브 문자가 든 변수의 분리·확장, `[ $var = x ]`의 빈 값 오류
- **셸 — 변수 경로를 쓰는 `rm -rf`:** 인용하지 않았거나, 변수가 비면 `/`나 상위 디렉터리를 지우는 경로(`rm -rf "$DIR/"*`에서 `DIR`이 빈 경우 등). `${DIR:?}` 같은 보호 여부
- **셸 — 대상 환경의 bash 버전 호환:** macOS `/bin/bash` 3.2에서 안 되는 구문(`mapfile`, 연관 배열, `${var,,}`), BSD·GNU 유틸 차이(`sed -i`, `readlink -f`, `date -d`)
- CI 조건식 오류로 단계가 항상·전혀 실행되지 않음, 잘못된 경로 필터

### `ops`

- **K8s·IaC 리소스 교체·삭제:** 이름·불변 속성 변경으로 리소스가 교체되거나 파괴되는 변경. **영향이 in-place 변경인지, 교체(replace)인지, 파괴(destroy)인지 명시**하고, 상태 데이터(DB, 볼륨, 버킷) 유실 가능성을 적습니다
- **`prevent_destroy` 해제**, `deletion_protection` 해제, `lifecycle` 무시 설정 변경
- **리소스 제한 누락:** 컨테이너 `resources.requests`·`limits`, liveness·readiness probe 누락, 레플리카·PDB
- **Dockerfile:** `latest` 태그(재현 불가·예고 없는 변경), 남겨진 빌드 도구로 이미지 비대·공격 면적 증가, `HEALTHCHECK`·시그널 처리(PID 1)
- **CI 캐시 오염:** 신뢰할 수 없는 PR이 쓴 캐시를 기본 브랜치가 복원, 캐시 키에 lockfile 해시 누락
- 배포 순서 의존(인프라 변경과 앱 변경의 선후), 롤백 경로

### `architecture`

- **새 의존성:** 기존 의존성으로 충분한지, 유지보수 상태·라이선스, 크기
- **버전 범위 완화:** 고정 버전을 `^`·`~`·`*`·`latest`로 바꿔 재현성 저하
- 환경별 설정의 중복(복사된 values·tfvars), 모듈화되지 않은 반복 리소스

### `performance`

- 이미지 레이어 순서로 캐시가 무효화돼 빌드가 느려짐, 거대한 빌드 컨텍스트(`.dockerignore` 누락)
- CI의 불필요한 매트릭스·중복 작업

### `tests`

- 인프라 변경에 대한 `terraform plan`·정책 검사·린트 단계 누락, CI에서 테스트 단계 비활성화·`continue-on-error` 추가

### `readability` · `style`

- 셸 스크립트의 shebang·`shellcheck` 규칙, 프로젝트의 IaC 명명 규칙, 태그 규칙

## 3. 흔한 오탐 (보고하지 않음)

- 근거가 문서화된 공개 정적 사이트 버킷·공개 읽기 설정
- `pull_request`(타깃 아님) 트리거에서 secrets를 쓰지 않는 워크플로
- 공식 베이스 이미지를 다이제스트로 고정한 경우의 태그 표기
- `${VAR:?}`로 빈 값을 막은 뒤의 `rm -rf`
