# 098 - Worktree removal decides merged by ancestry so a rebase merge is refused

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: complex
- **Stage**: 3-plan

## Summary

Two scripts decide whether a worktree is merged, and they use different rules. Neither rule can
see a rebase merge. The removal script asks whether `HEAD` is an ancestor of the base, which a
rebase merge makes false, so it keeps a worktree whose work already landed. The same ancestry
question is true for a branch nobody has committed on, so the removal script also deletes
unstarted work. The sweep refuses both cases, for the opposite reasons.

## User story

As a contributor whose pull request was merged with a rebase merge, I want the worktree to be
removed, so that the folder list holds live work only.

## Detail

The removal script runs `git merge-base --is-ancestor HEAD <base>`
(`scripts/remove-worktree-local-dev.ps1:368`, "$result = Invoke-GitCapture @('-C', $WorktreeFull, 'merge-base', '--is-ancestor', 'HEAD', $BaseRef)").
The sweep asks a different question: reachability plus a ref-log reading of the branch's own work
(`scripts/cleanup-merged-worktrees.ps1:170`, "function Test-BranchOwnWorkWasMerged {"), after a
first filter of `git branch --merged`
(`scripts/cleanup-merged-worktrees.ps1:281`, "$mergedNames = & git -C $RepoRoot branch --format='%(refname:short)' --merged $MainRef 2>$null").

**Measured, not assumed.** A scratch repository reproduced a GitHub rebase merge: the branch tip
was replayed onto main with a new committer, so main carries a different SHA for the same patch.
Both rules refused it.

| Rule | Verdict on a rebase merge |
|---|---|
| `merge-base --is-ancestor HEAD origin/main` (removal script) | exit 1, not merged |
| `git branch --merged origin/main` (sweep first filter) | branch absent, not merged |
| `Test-BranchOwnWorkWasMerged` (sweep) | `False` |
| `Get-EligibleMergedWorktrees` (sweep) | empty |

So the sweep does not list a rebase-merged worktree and hand it to a removal script that then
refuses. Both keep it. The sweep's merge proof needs the branch SHA to be a non-first parent of a
merge commit on main (`scripts/cleanup-merged-worktrees.ps1:229`, "$parentLines = & git -C $RepoRoot rev-list --min-parents=2 --format='%P' $MainRef 2>$null"),
and a rebase merge writes no merge commit. The sweep's existing rebase case is a **local** rebase
followed by a merge-commit merge (`tests/WorktreeMergedCleanup.Tests.ps1:448`, "Assert-True (Test-BranchOwnWorkWasMerged -RepoRoot $repo -Branch 'feat-rebased') 'A branch rebased before it merged must report merged own work.'").

The two rules also disagree in the destructive direction. A brand-new branch points at a commit
the base already has, so ancestry is true and the removal hook deletes a worktree nobody has
committed in. The sweep refuses that case on purpose, in its first signal.

No local git fact links a rebase-merged branch to the base. The merge is only recorded on GitHub,
so the decision needs GitHub as an extra source: a merged pull request whose head SHA the branch
really pointed at.

This repository has rebase merging enabled (`allow_rebase_merge: true`, `allow_squash_merge: false`,
`delete_branch_on_merge: true`), so this happens for real.

Backlog 094 fixed which base both scripts read; it left the ancestry test alone on purpose.

## Acceptance criteria

- [ ] One decision function answers "was this branch's own work merged", and both scripts call it,
      with no second rule to keep in step
- [ ] A worktree whose pull request was merged with a rebase merge is removed
- [ ] The pull request is bound to this branch by SHA, not by branch name: a branch name that a
      later worktree reuses never inherits an older pull request's merge
- [ ] GitHub is an extra accepting signal only. When `gh` is missing, unauthenticated, offline, or
      rate-limited, the decision falls back to local git and the log says why
- [ ] A worktree whose branch is not merged is still preserved, a worktree with uncommitted
      changes is still preserved, and a worktree whose branch holds no commit of its own is still
      preserved — including on the removal hook path, which removes it today
- [ ] A worktree whose branch was merged and then gained commits no other ref holds is preserved.
      `git branch --merged` gives that protection today by accident, and the fix deletes that filter
- [ ] A fixture proves every direction without calling GitHub, and one fixture parses real `gh`
      output captured from this repository
- [ ] The Cleanup warning
      (`docs/development/workflow.md:549`, "**Merge with a merge commit, not a rebase merge.** The removal script decides a worktree is")
      no longer tells the reader to avoid rebase merges

## Out of scope

- Where the base comes from. Backlog 094 settled that: the fetched remote-tracking branch
- The reflog forgery limit (backlog 096). The shared decision inherits whatever that item leaves
- Squash merges. This repository has `allow_squash_merge: false`, and the GitHub signal covers
  them anyway if that ever changes

## Notes / dependencies

- Found while implementing backlog 094, which needed the removal gate to read the same base
- The Cleanup warning points at this item
  (`docs/development/workflow.md:556`, "(backlog 095), so the two disagree; backlog 098 makes the removal script use the same rule.")
- The shared rule lands in `scripts/worktree-git.common.ps1`, which the removal script already
  dot-sources (`scripts/remove-worktree-local-dev.ps1:75`, "$gitHelperPath = Join-Path $PSScriptRoot 'worktree-git.common.ps1'").
  The watcher runs from a copy in `%TEMP%` where that helper is absent, so it needs a fallback
  stub in the shape the script already uses for `Resolve-MergedBaseRef`
- Grilled 2026-08-19. Difficulty raised from moderate to complex: the fix needs a new source of
  truth, not a shared rule
- Spec: `docs/superpowers/specs/2026-08-19-worktree-merged-rule-design-098.md`
- Terms: `CONTEXT.md` defines **Merge proof**; `docs/adr/0007-merge-proof-may-come-from-github.md` records the decision
- Plan: `docs/superpowers/plans/2026-08-19-worktree-merged-rule-plan-098.md`
