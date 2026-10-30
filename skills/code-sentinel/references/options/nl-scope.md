# 자연어 매핑표: 범위, 기준 브랜치, 파일 필터

`natural-language.md`의 절차로 씁니다. SPEC의 기본 매핑(굵게 표시)에 동의어를 더한 목록이며, 여기와 `nl-review.md`에 없는 표현은 옵션으로 바꾸지 않습니다.

## 1. 범위

| 사용자 표현 | 옵션 |
|---|---|
| **"스테이징한 것만"**, **"staged"**, "스테이징된 것", "스테이지한 것", "staged changes", "the index" | `--staged` |
| **"마지막 커밋"**, "최근 커밋", "직전 커밋", "방금 한 커밋", "HEAD 커밋", "last commit", "latest commit", "most recent commit" | `--commit HEAD` |
| **"커밋 abc123"**, "abc123 커밋", "commit abc123" (해시는 4~40자 16진수, 또는 `HEAD`, `HEAD~<n>`, `HEAD^`) | `--commit abc123` |
| **"PR 42"**, **"42번 PR"**, **"#42"**, **PR URL**(`https://github.com/<owner>/<repo>/pull/42`), "PR #42", "PR42", "PR 42번", "풀리퀘 42", "pull request 42" | `--pr 42` |
| **"전체"**, **"프로젝트 전체"**, "저장소 전체", "레포 전체", "코드 전체", "전체 코드", "모든 파일", "whole project", "entire repo", "entire codebase", "full scan" | `--full` |
| "변경사항 전체", "전체 변경사항", "브랜치 변경사항", "이 브랜치에서 바뀐 것", "branch changes", "my branch changes" | `--changes` |

- PR URL에서는 번호만 씁니다. `gh`는 현재 저장소 기준으로 조회하므로, 보고서의 PR URL(매니페스트 `pr_url`)이 입력 URL의 저장소와 다르면 보고서 요약에 그 사실을 적습니다.
- "전체적으로"(부사)는 `--full`이 아닙니다. 리뷰 요청 수식어로 보고 무시합니다.

## 2. 기준 브랜치

| 사용자 표현 | 옵션 |
|---|---|
| **"main 기준으로"**, "`<ref>` 기준으로", "`<ref>` 기준", "`<ref>` 브랜치 기준으로", "`<ref>` 대비", "`<ref>`와 비교해서", "against `<ref>`", "compared to `<ref>`", "relative to `<ref>`" | `--base <ref>` |

- `<ref>`는 공백 없는 한 토큰입니다(예: `main`, `origin/main`, `develop`, `release/1.2`). 뒤의 "브랜치"라는 말은 떼고 씁니다.
- 최종 범위가 `--changes`가 아니면 적용하지 않습니다(`natural-language.md` 2절 3).

## 3. 파일 필터

| 사용자 표현 | 옵션 |
|---|---|
| **"src/api만"**, "`<경로>` 폴더만", "`<경로>` 디렉터리만", "`<경로>` 파일만", "`<경로>` 아래만", "only `<경로>`", "`<경로>` only" | `--files <경로>` |
| "`<경로>` 빼고", "`<경로>` 제외", "`<경로>` 제외하고", "`<경로>` 말고", "except `<경로>`", "excluding `<경로>`", "skip `<경로>`" | `--exclude <경로>` |

- `<경로>`는 `/`를 포함하거나, 파일 확장자가 있거나(`app.ts`), glob 문자(`*`, `?`)가 있는 토큰입니다. 끝에 붙은 조사는 뗍니다(`src/api만` → `src/api`).
- 한 표현에 경로를 여러 개 나열하면 각각 적습니다("src/api랑 src/web만" → `--files src/api --files src/web`).
- 영역 이름(`nl-review.md` 4절의 키워드) 뒤의 "빼고"는 파일 제외가 아니라 집중 영역 제외입니다("스타일 빼고", "테스트 빼고").
- 한정어("만", "빼고" 등) 없이 경로만 쓰면 옵션으로 바꾸지 않습니다(`natural-language.md` 3절).
