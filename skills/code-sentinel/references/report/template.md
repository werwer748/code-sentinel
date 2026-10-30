# 보고서: 전체 템플릿과 최종 평가

standard·deep 보고서를 쓸 때 읽습니다. 요약 줄 규칙은 `summary.md`, 발견 항목 문법은 `findings.md`, 검증 현황 규칙은 `status.md`를 따릅니다.

## 1. 기본 템플릿

    ## 리뷰 요약
    해석된 옵션: --changes --base origin/main --depth standard --strictness balanced --min-severity low --focus all --max-findings 20
    상태: complete
    범위: changes (merge-base a1b2c3d → 작업 트리, 미커밋 포함)
    기준: origin/main @ a1b2c3d (원격 참조는 마지막 fetch 기준)
    스냅샷: worktree @ 9f8e7d6 (2026-10-29 21:00 수집, staged 1 · unstaged 2 · untracked 1)
    파일: 대상 12개 · 실제 검토 12개 · 검토 생략 0개 · 규칙 제외 3개 · 참고로 읽음 7개
    의도: 커밋 메시지 4개
    적용 프로필: backend, frontend
    발견: Critical 0 · High 1 · Medium 2 · Low 1 (생략 2건)

    ## 발견된 문제
    [S-01] High · 확신도 High · security · src/api/orders.ts:42-48
      문제: 주문 조회 시 요청자와 주문 소유자를 비교하지 않음
      조건: 로그인한 사용자가 다른 사용자의 주문 ID로 요청할 때
      영향: 모든 사용자의 주문 정보 노출
      근거: src/api/orders.ts:44
          const order = await db.order.findUnique({ where: { id: req.params.id } });
          return res.json(order);
      수정: where 조건에 ownerId: req.user.id를 추가하고, 없으면 404를 반환
      같은 원인: src/api/invoices.ts:30

    ### 검토 권장 (strict, 확신도 Low)
    ### 범위 밖 관찰

    ## 검증 현황
    - 실행한 검증: 미실행(기본 모드) — 기본 모드는 테스트·빌드·린트를 실행하지 않음
    - 정적으로 확인한 것: 호출부 3곳, 관련 테스트 2개, 타입 정의 1개
    - 영역별: security 발견 1건 · correctness 발견 2건 · ops 검토함·발견 없음 · architecture 검토함·발견 없음 · performance 발견 1건 · tests 검토함·발견 없음 · readability 검토함·발견 없음 · style 검토함·발견 없음
    - 검토 한계: 규칙 제외 3개(pnpm-lock.yaml: lockfile, …), 확인하지 못한 가정(…)

    ## 최종 평가
    - 주요 위험: 다른 사용자의 주문 조회(S-01)와 결제 이중 청구(S-02)
    - 우선 조치: S-01 → S-02 → S-04

    특정 항목을 고치려면 번호로 요청하세요 (예: "S-01 고쳐줘").

- 항목이 없는 하위 섹션(`### 검토 권장`, `### 범위 밖 관찰`)은 제목도 쓰지 않습니다.
- 발견이 없으면 `empty.md`, partial이면 끝에 `partial.md`의 "이어서 검토하기" 블록을 넣습니다.

## 2. 최종 평가

- `- 주요 위험:`에 가장 중요한 위험을 번호와 함께, `- 우선 조치:`에 조치 순서를 `S-01 → S-02`처럼 적고, 빈 줄 다음에 "특정 항목을 고치려면 번호로 요청하세요 (예: "S-01 고쳐줘")." 안내 줄을 둡니다.
- 발견이 없으면 `- 주요 위험: 확인된 문제 없음`만 쓰고 마지막 안내 줄은 생략합니다.
