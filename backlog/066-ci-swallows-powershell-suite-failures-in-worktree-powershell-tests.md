# 066 - CI swallows PowerShell suite failures in worktree-powershell-tests

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — CI only)

## Summary

The `worktree-powershell-tests` job runs sixteen PowerShell suites inside one `run:` block. Only the
last script decides the step's exit code, so every earlier suite can fail and the job still reports
success. A red suite has already been shipping this way.

## Evidence

`.github/workflows/ci.yml:102-125` runs the suites like this:

```yaml
  worktree-powershell-tests:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run worktree PowerShell tests
        shell: pwsh
        run: |
          ./tests/AgentWorktreeGuard.Tests.ps1
          ./tests/AgentPreCommitHook.Tests.ps1
          ...
          ./tests/BacklogNumbering.Tests.ps1
```

Each suite ends with `exit 1` when it has failures. In a `shell: pwsh` block, that exit code only
reaches the step when it belongs to the **last** command. Everything above it is discarded.

Run `31208311085`, branch `fix/wt-058-native-edit-refusal`, job `worktree-powershell-tests`, recorded
2026-08-07. The job conclusion was **success**. Its log contains:

```
  FAIL  Shim: a worktree-session redirect reaches the policy core
FAILED: 1 test(s)
  - Shim: a worktree-session redirect reaches the policy core :: Decision must be reported (expected match 'agent-worktree-main-write', got '')
```

The same failure reproduces locally from the main checkout:

```powershell
pwsh -NoProfile -File .\tests\AgentWorktreeGuard.Tests.ps1
```

That one test is being fixed on `fix/wt-065-edit-write-isolation`, because new tests cannot be added
beside a red neighbour. The CI hole that hid it is this item, and it is untouched by that branch.

## A trap the fix must avoid

The obvious fix is to check `$LASTEXITCODE` after each suite in the same PowerShell process. That
does not work. The suites call `exit 1` when they fail, but on success they simply run off the end
with no `exit 0`. `$LASTEXITCODE` then still holds whatever the last native command inside the
suite returned.

Measured on 2026-08-07 against `fix/wt-065-edit-write-isolation`:
`tests/WorktreeBaseRef.Tests.ps1` prints `Worktree base-ref tests passed.` and leaves
`$LASTEXITCODE` at `1`. The same file run as its own process exits `0`.

So the fix must either give each suite its own step or its own process, or add an explicit `exit 0`
to the success path of every suite. Checking `$LASTEXITCODE` in-process would turn a green suite
red.

## Why this matters

Fifteen of the sixteen suites are unguarded. A regression in any of them merges silently. The suites
cover the agent Git guardrails, the worktree scripts, the pre-commit and pre-push hooks, and the
backlog numbering check, so the blind spot covers most of the repository's own tooling.

## Acceptance criteria

- [ ] A failure in any suite in `worktree-powershell-tests` fails the job
- [ ] Every suite still runs when an earlier one fails, so one run reports every broken suite rather
      than only the first
- [ ] The job's summary names which suites failed
- [ ] A deliberately failing suite is used once to prove the job goes red, and the proof is recorded
      in the PR

## Out of scope

- The content of any individual suite. Fixing a red test is that test's own work.
- The `build-test` job. `dotnet test` already fails its step correctly.

## Notes / dependencies

- Found while planning `backlog/065-native-edit-isolation-misses-worktree-sessions-without-w-flag.md`
- `scripts/test-fast.ps1` does not run these suites, so the local pre-PR gate has the same blind spot
  unless the suites are run by hand
