# Backlog 098 — plan progress

Plan: `docs/superpowers/plans/2026-08-19-worktree-merged-rule-plan-098.md`
Execution: inline, checkpoints after Tasks 3, 5, 7.

- [x] Task 1 — decision functions moved to `scripts/worktree-git.common.ps1`; both worktree suites green.
- [x] Task 2 — `Get-BranchRefLogFacts` + `Get-LocalMergeProofShas` split out; signal 2 now returns its proof SHAs.
- [x] Task 3 — signal 4 (`Get-WorkAfterMergeProof`) refuses work made after the merge proof.
- [x] Task 4 — `ConvertFrom-GhMergedPrJson`, `Get-MergedPullRequestRecords`, `Resolve-BaseBranchName` added.
- [x] Task 5 — GitHub signal wired in, bound by SHA; rebase-merge fixture added.
- [x] Task 6 — sweep pre-filter deleted; one cached GitHub lookup per run.
- [x] Task 7 — hook gate calls the shared decision; hook fixture now commits and merges.
- [x] Task 8 — Stage 10 warning replaced; every citation re-pointed; parity check green.
