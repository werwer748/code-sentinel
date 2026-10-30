# Changelog

이 프로젝트는 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

## [Unreleased]

### 변경

- 지침 문서를 상황별 파일 35개로 나눔(파일마다 100줄 이내). 플래그만 준 입력은 자연어 매핑표를, quick·`--focus`는 다른 영역 기준을, 기본 리뷰는 스크립트 내부 설명을 읽지 않음. 같은 단계의 문서는 한 번에 읽도록 함
  - 영역별 심각도 예시를 각 영역 문서로 옮기고, 두 곳에 있던 옵션 오류 표를 `report/errors.md` 하나로 합침
  - `run-verification.sh` 호출 예시를 `/bin/bash "<SKILL_DIR>/scripts/..."` 형식으로 통일하고, 끊어진 절 번호 참조를 고침
- `test-static.sh`: 문서 줄 수, SKILL.md 표와 실제 파일의 일치, 문서 간 상대 참조 검사 추가
- 품질 픽스처 기대값: FE-01을 `correctness·architecture`로(Next.js가 비공개 env를 클라이언트 번들에서 비워 토큰은 새지 않고 회원가 표시가 깨짐), IN-02 최소 심각도를 Low로(배포 경로에서 쓰이지 않는 Dockerfile)

## [1.0.0] - 2026-10-29

첫 릴리스.

### 추가

- Codex(`$code-sentinel`)와 Claude Code(`/code-sentinel`)가 공유하는 `skills/code-sentinel/SKILL.md`
- 리뷰 범위 `--changes`, `--staged`, `--commit`, `--pr`, `--full`과 깊이·지적 강도·심각도 하한·집중 영역·보고 상한 옵션
- 자연어 옵션 해석(한국어·영어)과 정규화된 `해석된 옵션:` 출력
- 8개 리뷰 영역(security, correctness, ops, architecture, performance, tests, readability, style)과 backend·frontend·infra 프로필 자동 적용
- `collect-context.sh`:
  - 범위별 diff·매니페스트 수집
  - 줄마다 변경 전·후 줄 번호를 붙인 diff(`numbered_diff_file`). 보고서 위치는 이 번호에서 가져오고, 출력 전에 위치를 확인함
  - 기본 제외 규칙, 크기 상한, 대형 변경 분할 표시
  - 커밋 메시지·PR 본문 수집
  - 사용자 git 설정·필터 무력화, partial clone 지연 fetch 차단
- `cleanup-context.sh`: 검증된 code-sentinel 임시 디렉터리만 삭제, `--stale` 정리
- `run-verification.sh`: `--run-tests`의 정적 사전 필터, 오프라인 실행 환경, 타임아웃, 실행 전후 상태 비교
- `scripts/install.sh`, `uninstall.sh`, `doctor.sh`: 심볼릭 링크 설치, 멱등·충돌 안전 규칙, 점검
- 자동 테스트(`tests/run.sh`, macOS `/bin/bash` 3.2)와 리뷰 품질 픽스처·채점기·실행기
  - 오탐 함정은 함정마다 정한 영역의 지적만 위반으로 셈
