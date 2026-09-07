# 147 - Cleanup sweep skips a dirty worktree silently

## Metadata

- **Epic**: Developer workflow
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

`scripts/cleanup-merged-worktrees.ps1` drops a merged worktree that has uncommitted changes
without writing any message. The worktree is missing from the report and from
`worktree-removal.log`, so a reader cannot tell it apart from a worktree the sweep never saw.

## User story

As a developer running the worktree sweep, I want the sweep to say why it kept a merged
worktree, so that I do not have to read the script to find out.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] The sweep writes a stderr line naming a merged worktree it keeps because
      `git status --porcelain` returned output, in the same shape as the locked-worktree line
      it already writes.
- [ ] The sweep writes a `Kept: ...` line to `worktree-removal.log` for that worktree, giving
      the same reason.
- [ ] A test covers the dirty-worktree path and asserts both the stderr line and the log line.
- [ ] The sweep still writes exactly one outcome line per worktree per run.

## Out of scope

- The status-check failure path (`git status` itself exits non-zero). It already writes a
  stderr line, and it never reaches the dirty check.
- Any change to which worktrees the sweep removes. This item only changes what it reports.

## Notes / dependencies

- Found 2026-09-07 while investigating why the sweep never listed
  `wt-non-serializable-theory-data-co-2d31cc2a`. Its branch was merged and the plan guard
  allowed it, so it fell out at the dirty check and produced no output at all.
- The skip is at the `if ($status) { continue }` line in `Get-EligibleMergedWorktrees`, in
  `scripts/cleanup-merged-worktrees.ps1`. The two skip paths above it, locked worktree and
  plan-guard refusal, both write a stderr line and a `Kept:` log line. This one writes
  neither.
- The file that blocked that worktree was not really modified. `git diff` was empty and
  `git hash-object` matched the index blob, but `git status` kept reporting it. `git add`
  cleared it and the sweep removed the worktree on the next run. A stale index stat entry is
  worth naming in the message, because the message would have to be actionable for a reader
  who sees no diff.
- Spec: none — the change is one reporting path, not a design question.
- Plan: docs/superpowers/plans/2026-09-07-dirty-worktree-report-plan-147.md
