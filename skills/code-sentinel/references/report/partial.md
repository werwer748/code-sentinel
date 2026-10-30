# 보고서: partial과 이어서 검토하기

상태가 partial일 때 읽습니다. 보고서 맨 끝에 다음 블록을 넣습니다.

    ## 이어서 검토하기
    검토 생략 3개: src/legacy/a.ts (분량), src/legacy/b.ts (분량), data/big.json (크기)
    분량 때문에 생략한 파일은 다음처럼 이어서 검토할 수 있습니다.
      Claude Code: /code-sentinel --changes --base origin/main --files src/legacy/a.ts --files src/legacy/b.ts --depth standard --strictness balanced --min-severity low --focus all --max-findings 20
      Codex:       $code-sentinel --changes --base origin/main --files src/legacy/a.ts --files src/legacy/b.ts --depth standard --strictness balanced --min-severity low --focus all --max-findings 20
    data/big.json은 크기 상한(1 MiB) 때문에 다시 실행해도 수집되지 않으므로 직접 확인하세요.

- 호출 예시는 원래의 `해석된 옵션:`에서 `--files`·`--exclude`를 빼고, 생략 파일마다 `--files <경로>`를 넣은 형태입니다(공백·특수문자가 든 경로는 작은따옴표로 감쌈).
- 생략 파일이 10개를 넘으면 상위 디렉터리로 묶어도 되며, 그때는 이미 검토한 파일이 다시 포함될 수 있다고 적습니다.
- 크기(`size`, `total-size`)·필터(`filter`) 때문에 생략한 파일은 다시 실행해도 수집되지 않으므로 호출 예시에 넣지 않고 직접 확인하라고 안내합니다.
- 패턴 검사만 수행한 파일은 사유를 "패턴 검사만 수행"으로 적습니다.
