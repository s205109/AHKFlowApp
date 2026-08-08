# 067 - Make the powershell-suites CI check required and runnable from test-fast

## Metadata

- **Epic**: Agent tooling
- **Type**: Feature
- **Interfaces**: UI | API | CLI (none — CI and local tooling only)

## Summary

The `powershell-suites` job now fails when any suite fails, but nothing makes anyone act on it. The
job is not a required status check, so a red run still merges. And no local command runs the suites,
so a break is only found after a push.

## Evidence

Only `build-test` is required on `main`. Read on 2026-08-08:

```
gh api repos/s205109/AHKFlowApp/branches/main/protection --jq '.required_status_checks'
{"checks":[{"app_id":15368,"context":"build-test"}],"contexts":["build-test"],"strict":false,...}
```

The `Protect main` ruleset (id `14590314`) defines no `required_status_checks` rule at all, so the
classic protection above is the whole picture.

On the local side, `scripts/pre-push-quick-checks.ps1:23-40` runs a build and the `Fast` test slice.
`scripts/test-fast.ps1:12-13` offers `Fast`, `Integration`, `E2E`, and `Coverage`. None of them
touch `tests/*.Tests.ps1`.

## Acceptance criteria

- [ ] `powershell-suites` is a required status check on `main`, so a red run blocks the merge
- [x] `scripts/test-fast.ps1` gains a mode that runs `scripts/run-powershell-suites.ps1`
- [x] The new mode appears in `scripts/README.md` and in `docs/development/testing-workflow.md`
- [x] The canonical pre-PR gate in `docs/development/testing-workflow.md` names the new mode

## Status

The local half is done. `pwsh .\scripts\test-fast.ps1 -Mode PowerShell` runs the suites, and the
canonical pre-PR gate names it.

One criterion is left, and an agent cannot do it. Making `powershell-suites` a required status check
is a repository settings change on `s205109/AHKFlowApp`, so it needs a human with admin rights.

## Out of scope

- **Wiring the suites into `scripts/pre-push-quick-checks.ps1`.** The full run took 3m 2s on
  2026-08-08, and two suites are 54s and 60s of that. `scripts/pre-push-quick-checks.ps1:5-7` says
  it deliberately skips slow work to stay fast. Running only a subset there would rebuild the blind
  spot that backlog 066 closed.
- The content of any individual suite.

## Notes / dependencies

- Depends on `backlog/done/066-ci-swallows-powershell-suite-failures-in-worktree-powershell-tests.md`,
  which built `scripts/run-powershell-suites.ps1` and renamed the job to `powershell-suites`
- Making a check required is a repository settings change, so it needs a human with admin rights on
  `s205109/AHKFlowApp`. The `test-fast.ps1` half is ordinary code work and can land first.
