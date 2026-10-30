# 매니페스트 (`collect-context.sh` 출력)

매니페스트 필드, `[FILES]` 표시 열, 섹션의 뜻이 불분명할 때 읽습니다. 범위별 의미는 `scopes.md`, 대형 변경은 `large-changes.md`, `--pr`은 `pr.md`를 따릅니다.

stdout에 줄 기반 텍스트 매니페스트를 냅니다.

- 필드는 탭 하나로 구분합니다.
- 제어문자·역슬래시·큰따옴표가 들어간 경로는 Git과 같은 C 스타일 따옴표 표기(`"..."` 안에 `\n`, `\t`, `\\`, `\"`)로 씁니다. 한글 등 그 밖의 문자는 그대로 씁니다.
- diff 본문과 부가 데이터는 임시 디렉터리(`../internals/git-and-temp.md` 1절)에 쓰고, 그 경로를 매니페스트에 적습니다.

예 (열 사이 공백은 실제로는 탭 하나):

    CODE_SENTINEL_CONTEXT 1
    scope           changes
    repo            /abs/path/to/repo
    context_dir     /private/var/folders/.../T/code-sentinel.Ab12Cd
    snapshot        worktree
    head            <sha>
    collected_at    2026-10-29T12:00:00Z
    status_summary  staged=1 unstaged=2 untracked=1
    base_ref        origin/main
    merge_base      <sha>
    uncommitted     included
    target_files    12
    target_lines    340
    rule_excluded   3
    skipped         0
    split           none|recommended|truncated
    diff_file       /private/var/folders/.../code-sentinel.Ab12Cd/diff.patch
    numbered_diff_file  /private/var/folders/.../code-sentinel.Ab12Cd/diff.numbered.txt
    commits_file    /private/var/folders/.../code-sentinel.Ab12Cd/commits.txt
    commit_count    4
    [FILES]
    M     src/app.ts
    R100  old name.ts   new name.ts
    A     assets/logo.png   binary
    [RULE_EXCLUDED]
    pnpm-lock.yaml  lockfile
    [SKIPPED]
    data/big.json   size
    [WARNINGS]
    ...

**공통 필드**

| 필드 | 의미 |
|---|---|
| `CODE_SENTINEL_CONTEXT 1` | 첫 줄. 매니페스트 형식 버전 |
| `scope` | `changes`, `staged`, `commit`, `pr`, `full` |
| `repo` | 저장소 최상위 절대 경로 |
| `context_dir` | 임시 디렉터리의 실제 경로. 리뷰 후 `cleanup-context.sh`에 그대로 넘김 |
| `snapshot` | 리뷰 대상 스냅샷(`worktree`, `index`, 커밋 SHA) |
| `head` | 수집 시점의 로컬 HEAD SHA(커밋이 없는 저장소는 `none`) |
| `collected_at` | 수집 시각(UTC) |
| `status_summary` | 수집 시점의 작업 트리 상태 요약 `staged=N unstaged=N untracked=N` (스냅샷이 `worktree`·`index`일 때만) |
| `target_files`, `target_lines` | 규칙 제외를 뺀 대상 파일 수와 줄 수 |
| `rule_excluded`, `skipped` | 규칙 제외 수, 검토 생략 수 |
| `split` | `none`, `recommended`, `truncated` (`large-changes.md`) |
| `diff_file` | 리뷰할 diff가 든 파일(원본 patch). `--full`은 `none`이며, 이때는 `[FILES]`의 파일을 작업 트리에서 직접 읽음 |
| `numbered_diff_file` | `diff_file`과 같은 내용에 줄 번호를 붙인 파일. 모델은 이 파일로 diff를 읽음. `--full`은 `none` |
| `commits_file`, `commit_count` | 커밋 메시지 파일과 커밋 수(`--changes`·`--commit`·`--pr`만) |

`status_summary`·`collected_at`은 리뷰 시점을 알려줄 뿐, 그 뒤에 작업 트리가 바뀌지 않았다는 보장은 아닙니다.

**범위별 필드**

| 범위 | 필드 |
|---|---|
| `--changes` | `snapshot worktree`, `base_ref`, `base_source`(결정 경로), `merge_base`, `uncommitted included`, 현재 브랜치가 기준과 같으면 `same_as_base yes` |
| `--staged` | `snapshot index`, `parent <HEAD sha 또는 empty-tree>`, `uncommitted staged-only` |
| `--commit` | `snapshot <sha>`, `ref`, `parent <sha 또는 empty-tree>`, merge commit이면 `merge_commit yes`, `uncommitted excluded` |
| `--pr` | `snapshot <head sha>`, `pr_number`, `pr_url`, `pr_title`, `pr_body_file`, `base_ref`(PR base 브랜치 이름), `head_ref`, `base_tip`, `merge_base`, `diff_mode local\|gh-diff`, `local_head_matches yes\|no`, `uncommitted excluded` |
| `--full` | `snapshot worktree`, `diff_file none`, `numbered_diff_file none` |

범위에 해당하지 않는 필드는 생략될 수 있고, 위에 없는 보조 필드가 더 있을 수 있습니다(모르는 필드는 무시).

**`[FILES]`**

- 형식: `<상태>` 탭 `<경로>` [탭 `<새 경로>`] [탭 `<표시>`]. 규칙 제외 파일은 여기 나오지 않습니다.
- 상태는 Git `--name-status` 표기(A, M, D, R<유사도>, T 등)를 따릅니다. untracked 파일은 신규(A)이고 `untracked` 표시가 붙습니다. 이름 변경은 셋째 열이 이전 경로 다음의 새 경로이고, 표시는 그 뒤에 옵니다.
- 표시 열은 하나이며 여러 표시를 쉼표로 잇습니다(예: `binary,untracked`): `binary`, `submodule`, `symlink`, `mode-only`, `lfs`, `filtered`, `untracked`, `skipped`(같은 파일이 `[SKIPPED]`에 있음).
- `binary`·`submodule`·`lfs`는 내용을 리뷰하지 않는 목록 항목입니다. `symlink`는 링크 대상 문자열만, `mode-only`는 모드 변경만 봅니다.

**`[RULE_EXCLUDED]`**: `<경로>` 탭 `<사유>`. `scopes.md` 4절의 규칙 제외 목록이며 사유는 `build-output`(의존성·산출물 디렉터리), `lockfile`, `snapshot`, `minified`(`*.min.*`, `*.map`), `generated`(생성 코드)입니다.

**`[SKIPPED]`**: `<경로>` 탭 `<사유>`. 사유는 `size`(파일당 1 MiB 초과), `total-size`(`--full` 누적 10 MiB 초과), `filter`(clean/process 필터 대상).

**`[WARNINGS]`**: 사람이 읽을 경고 줄. 예: `$TMPDIR` 대신 `/tmp` 사용, 커밋 메시지 50개 초과로 잘림, git 버전에 따른 제한. 보고서 "검토 한계"에 반영합니다.
