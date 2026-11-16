# Plan progress: backlog 212

Plan: `docs/superpowers/plans/2026-11-16-measure-harness-zero-runs-plan-212.md`

- Task 1 (test-fast stub floor of 20 ms): done at 983768d2. Tests: `MeasureTestModes.Tests.ps1` passes on Windows once and in `mcr.microsoft.com/dotnet/sdk:10.0` three times, with the worktree mounted read-only at `/repo`. Mutation proof: with the median taken over warm-up plus counted runs, and with the zero-median throw removed, exactly the two expected cases fail (slow head: median 0.63; spread: no throw). Both mutations reverted; `git diff --stat -- scripts` is empty. Deferrals: none.

## Closing steps

- Simplify: nothing to simplify. The diff is one clamp, one assertion, and comment edits.
- Verify: no exemption needed. The changed suite is the artifact: green on Windows and three times on Linux, and the mutation proof is red for exactly the two guarded cases.
- Document: all four acceptance boxes ticked. Nothing to document beyond the item.
