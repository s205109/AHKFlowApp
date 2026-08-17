# 098 - Worktree removal decides merged by ancestry so a rebase merge is refused

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The removal script decides that a worktree is merged when its `HEAD` is an ancestor of the base.
A rebase merge rewrites the commits, so the branch head is not an ancestor of the base and the
worktree is preserved even though the work landed.

## User story

As a contributor whose pull request was merged with a rebase merge, I want the worktree to be
removed, so that the folder list holds live work only.

## Detail

The removal script runs `git merge-base --is-ancestor HEAD <base>`
(`scripts/remove-worktree-local-dev.ps1:368`, "'merge-base', '--is-ancestor', 'HEAD', $BaseRef"),
called from the hook path
(`scripts/remove-worktree-local-dev.ps1:688`, "Test-WorktreeMergedIntoMain -WorktreeFull $worktreeFull -BaseRef $baseRef").

The sweep no longer works that way. Backlog 095 replaced patch likeness and ancestry with
reachability plus a ref-log reading of the branch's own work
(`scripts/cleanup-merged-worktrees.ps1:170`, "function Test-BranchOwnWorkWasMerged {"). So the two
scripts now disagree, and the disagreement is visible: the sweep lists a rebase-merged worktree as
eligible, calls the removal script, and the removal script preserves it.

This repository has rebase merging enabled (`allow_rebase_merge: true`), so it happens for real.
The "Merge with a merge commit, not a rebase merge" warning in Stage 10 — Cleanup
(`docs/development/workflow.md:548`, "Merge with a merge commit, not a rebase merge.") describes
the trap and tells the reader to merge with a merge commit for any worktree Cleanup should
remove. That warning is the workaround this item removes.

Backlog 094 fixed which base both scripts read; it left the ancestry test alone on purpose.

## Acceptance criteria

- [ ] The removal script decides merged-ness the way the sweep does, with no second rule to keep
      in step
- [ ] A worktree whose branch was rebased and then merged is removed
- [ ] A worktree whose branch is not merged is still preserved, and a worktree with uncommitted
      changes is still preserved
- [ ] A fixture proves both directions, in `tests/WorktreeRemoveHook.Tests.ps1` or a new suite
- [ ] The Cleanup warning
      (`docs/development/workflow.md:548`, "Merge with a merge commit, not a rebase merge.")
      no longer tells the reader to avoid rebase merges

## Out of scope

- Where the base comes from. Backlog 094 settled that: the fetched remote-tracking branch
- The reflog forgery limit (backlog 096). The shared decision inherits whatever that item leaves

## Notes / dependencies

- Found while implementing backlog 094, which needed the removal gate to read the same base
- The Cleanup warning points at this item
  (`docs/development/workflow.md:555`, "backlog 098 makes the removal script use the same rule.")
- The shared rule lives in `scripts/cleanup-merged-worktrees.ps1`. Moving it into
  `scripts/worktree-git.common.ps1` is one option; the watcher runs from a copy in `%TEMP%`, so
  check what a shared helper does to that copy first
  (`scripts/remove-worktree-local-dev.ps1:75`, "$gitHelperPath = Join-Path $PSScriptRoot 'worktree-git.common.ps1'")
- Spec: none — the defect and the fix are one rule
- Plan: none — not planned yet; Stage 0-intake
