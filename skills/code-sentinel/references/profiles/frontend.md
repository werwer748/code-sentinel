# frontend 프로필

웹 프런트엔드(컴포넌트, 클라이언트 상태, 렌더링, 브라우저 보안, 접근성) 변경에서 "특히 확인할 것"을 8개 리뷰 영역에 덧붙이는 프로필입니다. 프로필은 영역을 대체하지 않습니다. 발견 항목은 아래 표시된 영역 slug로 보고하며, 해당 없는 항목은 보고서에 쓰지 않습니다. 심각도는 `../review/severity.md`, 보고 형식은 `../report/findings.md`를 따릅니다.

## 1. 감지 신호

변경 파일(`[FILES]`)의 경로·확장자와 `package.json` 의존성을 보고, 다음 중 하나라도 해당하면 적용합니다. backend·infra 프로필과 동시에 적용될 수 있습니다(예: Next.js의 `app/api/**/route.ts`는 backend도 적용).

| 종류 | 신호 |
|---|---|
| 프레임워크 의존성 | `react`, `react-dom`, `next`, `vue`, `nuxt`, `svelte`, `@sveltejs/kit`, `solid-js`, `preact`, `@angular/core`, `@remix-run/*`, `astro`, `react-native` |
| 컴포넌트 파일 | `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.astro`, `components/`, `pages/`, `app/**/page.*`, `app/**/layout.*` |
| 클라이언트 상태·데이터 | `redux`, `zustand`, `jotai`, `pinia`, `@tanstack/react-query`, `swr`, `apollo-client` |
| 스타일·자산 | `*.css`, `*.scss`, `*.module.css`, Tailwind 설정 (단독으로는 약한 신호. 다른 신호와 함께일 때 적용) |
| E2E·컴포넌트 테스트 | `playwright`, `cypress`, `@testing-library/*`, `*.spec.tsx`, `e2e/` |

신호가 없으면 적용하지 않습니다. 적용 여부는 보고서 요약의 "적용 프로필"에 적습니다.

## 2. 영역별로 특히 확인할 것

### `security`

- **클라이언트 번들의 비밀정보:** `NEXT_PUBLIC_*`, `VITE_*`, `REACT_APP_*`, `NUXT_PUBLIC_*`, `PUBLIC_*` 접두어 환경변수나 클라이언트 코드에 API 비밀 키·서비스 계정 키가 들어감
- **XSS:** `dangerouslySetInnerHTML`, `v-html`, `{@html}`, `innerHTML`에 정제하지 않은 값, `javascript:` 링크(`href`에 사용자 입력), 정제하지 않은 마크다운 렌더링
- **토큰 저장:** 액세스·리프레시 토큰을 `localStorage`·`sessionStorage`에 저장(XSS 시 탈취)
- 오픈 리다이렉트(`?next=` 값을 검증 없이 `location`에 사용), `postMessage` 수신 시 origin 미검증, `target="_blank"`의 opener 노출(구형 브라우저 지원 시)

### `correctness`

- **서버/클라이언트 경계:** 서버 전용 모듈(DB 클라이언트, `fs`, 비밀 키를 읽는 설정, `server-only` 표시 모듈)을 클라이언트 컴포넌트에서 import. `"use client"`·`"use server"` 지시자 누락·오용
- **하이드레이션 불일치:** 렌더 중 `Date.now()`, `new Date()`, `Math.random()`, `window`·`localStorage` 접근, 로케일·타임존 의존 포맷으로 서버와 클라이언트 결과가 다름
- **effect:** 의존성 배열 누락·과다, 구독·타이머·이벤트 리스너·요청의 정리(cleanup) 누락, 언마운트 후 상태 변경
- **stale closure:** 이벤트 핸들러·타이머·effect가 오래된 상태 값을 캡처
- **리스트 key:** 인덱스나 불안정한 값을 key로 사용해 재정렬·삭제 시 상태가 엉킴
- **비동기 요청의 race·stale 응답:** 나중에 보낸 요청의 응답을 먼저 보낸 이전 요청의 늦은 응답이 덮어씀(취소·요청 ID 비교·AbortController 없음)
- **낙관적 업데이트:** 실패 시 롤백·오류 표시 누락, 서버 응답으로 재동기화하지 않음
- **로딩·에러·빈 상태:** 처리 누락으로 빈 화면·무한 로딩·크래시
- **접근성 기능 결함** (`correctness`로 보고, `--focus a11y` 대상):
  - 키보드 조작: `div`·`span`에 `onClick`만 있고 `button`·`role`·`tabIndex`·키 이벤트 없음
  - 포커스: 모달 열림·닫힘, 라우트 전환 시 포커스 이동·복귀·가두기 누락
  - 폼 라벨·aria: `label`·`aria-label`·`aria-labelledby` 없는 입력, 잘못된 aria 속성, 아이콘 버튼의 이름 없음
  - 색상만으로 전달하는 정보(오류를 빨간색으로만 표시), 낮은 대비
  - 이미지 대체 텍스트 누락(의미 있는 이미지)

### `ops`

- 환경별 API 엔드포인트·기능 플래그가 빌드 시점에 고정되는지, 잘못된 기본값
- 에러 경계(error boundary)·클라이언트 오류 수집 누락, 캐시 헤더·서비스 워커 캐시로 배포 후 구버전이 남음

### `architecture`

- 컴포넌트에 데이터 가져오기·비즈니스 규칙·표현이 섞임, 전역 상태 남용
- 디자인 시스템·공용 컴포넌트를 두고 중복 구현
- 서버 컴포넌트로 충분한 부분을 클라이언트로 내림(번들 증가)

### `performance`

- **불필요한 리렌더:** 렌더마다 새 객체·함수를 props로 전달해 메모이제이션 무력화, 상위 상태 변경이 큰 하위 트리를 다시 그림
- **렌더 중 대량 연산:** 렌더마다 큰 배열 정렬·필터·변환(메모이제이션·서버 계산 없음)
- **가상화 없는 대형 리스트:** 수백~수천 행을 한 번에 렌더
- **무거운 의존성의 번들 유입:** 전체 라이브러리 import(`lodash`, 아이콘 세트, 차트·에디터를 초기 번들에 포함), 동적 import 미사용
- **요청 워터폴:** 부모가 데이터를 받은 뒤에야 자식이 요청 시작, 병렬화 가능한 요청의 직렬 실행
- 이미지 크기·지연 로딩, 레이아웃 시프트

### `tests`

- **DOM 구조에 의존하는 E2E 셀렉터:** `nth-child`, 깊은 CSS 경로, 생성된 클래스명. role·label·`data-testid` 기반 셀렉터 권장
- **스냅샷만 있는 테스트:** 동작 검증 없이 스냅샷만 갱신
- 비동기 UI 테스트의 고정 대기(`sleep`), 실패·빈 상태·접근성 시나리오 누락

### `readability` · `style`

- **i18n 프로젝트의 하드코딩 문자열:** 번역 함수를 쓰는 프로젝트에서 새 UI 문구를 직접 씀
- 디자인 토큰 대신 임의 색상·간격, 문구 톤·용어 불일치
- 거대한 컴포넌트(수백 줄의 JSX와 로직 혼재)

## 3. 흔한 오탐 (보고하지 않음)

- DOMPurify 등으로 정제한 뒤 넣는 HTML
- 사유 주석이 있는 의도적 `eslint-disable`(예: `react-hooks/exhaustive-deps`를 근거와 함께 끈 경우)
- 공개되어도 되는 값(공개 분석 키, 공개 지도 키처럼 문서상 클라이언트 노출이 전제인 키)을 공개 접두어 환경변수로 쓴 경우
- `useEffect` 안에서만 쓰는 `Date.now()`(하이드레이션 이후 실행)
