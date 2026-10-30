# 보고서: quick 축약형

`--depth quick` 보고서를 쓸 때 읽습니다. 발견 항목마다 헤더 줄과 `문제`, `수정` 두 줄만 씁니다. 헤더 문법(`findings.md`)과 요약 줄 규칙(`summary.md`)은 같고, 검증 현황 규칙은 `status.md`를 따릅니다.

    ## 리뷰 요약
    해석된 옵션: --changes --base origin/main --depth quick --strictness balanced --min-severity low --focus all --max-findings 20
    상태: complete
    범위: changes (merge-base a1b2c3d → 작업 트리, 미커밋 포함)
    기준: origin/main @ a1b2c3d (원격 참조는 마지막 fetch 기준)
    스냅샷: worktree @ 9f8e7d6 (2026-10-29 21:00 수집, staged 0 · unstaged 1 · untracked 0)
    파일: 대상 3개 · 실제 검토 3개 · 검토 생략 0개 · 규칙 제외 0개 · 참고로 읽음 2개
    의도: 커밋 메시지 1개
    적용 프로필: backend
    발견: Critical 0 · High 1 · Medium 0 · Low 0

    ## 발견된 문제
    [S-01] High · 확신도 High · security · src/api/orders.ts:42-48
      문제: 주문 조회 시 요청자와 주문 소유자를 비교하지 않음
      수정: 조회 조건에 ownerId를 추가하고 불일치 시 404 반환

    ## 검증 현황
    - 실행한 검증: 미실행(기본 모드)
    - 영역별: security 발견 1건 · correctness 검토함·발견 없음 · ops 미검토(quick) · architecture 미검토(quick) · performance 미검토(quick) · tests 미검토(quick) · readability 미검토(quick) · style 미검토(quick)
    - 검토 한계: 변경 주변과 직접 호출부만 확인(quick)

    ## 최종 평가
    - 우선 조치: S-01

- 요약 줄과 영역별 결과는 줄이지 않습니다. 상태 정보는 축약형에서도 모두 필요합니다.
- 발견이 없으면 `empty.md` 1절의 "발견된 문제" 문구를 쓰고, partial이면 끝에 `partial.md`의 블록을 넣습니다.
