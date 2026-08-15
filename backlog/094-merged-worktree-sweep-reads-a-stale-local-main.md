# 094 - Merged worktree sweep reads a stale local main

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

The merged-worktree sweep decides what is merged by reading the local `main` branch, and nothing
fetches first. `gh pr merge` never advances local `main`, so the sweep reports "no merged worktrees
eligible" for work that merged hours earlier, and keeps reporting it until a human pulls.

## User story

As a contributor finishing a branch, I want the automatic sweep to notice my merge, so that a
merged worktree is removed on the next worktree creation instead of waiting for me to pull.

## Detail

The sweep is automatic and enabled. `scripts/new-worktree.ps1:273` runs
`cleanup-merged-worktrees.ps1` before creating any worktree, and this repository has
`ahkflow.worktreeCleanup` set to `true`, so it removes rather than reports.

**The base it compares against is local.** `scripts/cleanup-merged-worktrees.ps1:20` defaults
`$MainRef` to `'main'`. That value reaches `git branch --merged $MainRef` (`:147`) and
`git rev-list --min-parents=2 $MainRef` (`:107`). Neither `new-worktree.ps1` nor
`cleanup-merged-worktrees.ps1` runs `git fetch` anywhere.

So the sweep is behind by exactly one human `git pull`. An agent cannot close that gap: it may not
write to the main checkout, and `gh pr merge` merges on GitHub without touching any local ref.

**Observed twice on 2026-08-14, same command and same config, opposite results.**

1. At 10:56, local `main` was at `eae8eebd`. Pull request #303 had merged into `origin/main` at
   07:31. `new-worktree.ps1` printed `cleanup: no merged worktrees eligible for cleanup.` and left
   `wt-backlog-template-carries-stage-field` in place. Correct, given what it could see.
2. Later the same day, after local `main` reached `fe30c2a9`, the identical command printed
   `cleanup: removing merged worktree: ...\wt-backlog-template-carries-stage-field
   [fix/wt-backlog-template-carries-stage-field]` and removed it.

Nothing changed but the local ref.

**The parameter already supports the fix.** `scripts/cleanup-merged-worktrees.ps1:137` carries a
comment about `$MainRef` not resolving to a local branch, naming `'origin/main'` as the example.
Passing a remote-tracking ref is designed for; nothing passes one, and nothing fetches to make it
current.

**`workflow.md` says this is owned, and it is not.** Three separate claims point at backlog 073:

- `docs/development/workflow.md:545` — a script that tests a merged-pull-request fact rather than
  ancestry
- `docs/development/workflow.md:560` — "Making the script test a freshly fetched remote base
  instead is backlog 073's business"
- `docs/development/workflow.md:601` — "Until backlog 073 scripts this", for the check that finds a
  branch left behind after its worktree is gone

Backlog 073's acceptance criteria are at `backlog/073-process-wave-3-cleanup-ux.md:25-29`: no
terminal window, a readable log, naming the process that holds the folder, a guard against removing
an unimplemented plan, and honouring `git worktree lock`. None of the three claims appears. 073 is
scoped to cleanup experience; this is a correctness defect.

**Cost of leaving it.** Every merged worktree survives until a human pulls, so the folder list grows
and a session reading it cannot tell finished work from live work. It also produced a wrong
instruction: a session told the user to run the sweep by hand, having diagnosed the automation as
absent rather than late.

## Acceptance criteria

- [ ] The sweep decides merged-ness against a base that reflects the remote, and the item states
      where the fetch happens: in `new-worktree.ps1` before the sweep, or inside the sweep itself
- [ ] A stale local `main` no longer hides a merge. A worktree whose branch is merged on the remote
      is eligible even when local `main` predates that merge
- [ ] A fixture proves both directions: a worktree merged on the remote but not into a stale local
      `main` is eligible, and an unmerged worktree is still preserved
- [ ] The fetch cannot make worktree creation fail when the network is down. Offline, the sweep
      falls back to the local base and says so
- [ ] Each of the three `workflow.md` claims at `:545`, `:560`, and `:601` names the item that
      really owns it. Where no item owns one, this item records that or a new one is filed
- [ ] The manual "update local `main` before attempting removal" step at
      `docs/development/workflow.md:548-557` is removed or rewritten to match the new behaviour

## Out of scope

- Backlog 073's cleanup experience work: the terminal window, the log wording, naming the holding
  process, the unimplemented-plan guard, and `git worktree lock`
- Replacing ancestry with a merged-pull-request fact (`workflow.md:545`). Related, larger, and
  independent of where the base comes from
- The branch-left-behind check (`workflow.md:601`). This item only re-points the claim

## Notes / dependencies

- Plan: `docs/superpowers/plans/2026-08-15-merged-worktree-sweep-stale-local-main-plan-094.md`
- Backlog 095 merged in pull request #310 on 2026-08-15, so the shared file
  `scripts/cleanup-merged-worktrees.ps1` is free. This branch is based on that result
- Found while closing backlog 087, when a manual sweep was recommended on a wrong diagnosis
- `scripts/remove-worktree-local-dev.ps1:318-322` has the same decision on the single-worktree
  path: "merged = HEAD is an ancestor of main". Check whether it needs the same fix. The range
  `workflow.md:549` gives for this is off by four lines, which is its own small correction
- Backlog 073 is the neighbouring item. Read its scope before widening this one
