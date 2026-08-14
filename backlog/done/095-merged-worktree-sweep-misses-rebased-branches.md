# 095 - Merged-worktree sweep misses rebased branches

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

The merged-worktree sweep never removes a worktree whose branch was rebased before it merged. The
proof it uses reads only reflog entries whose subject starts with `commit`. A rebase writes
`rebase (finish):` instead, so the sweep cannot pair the branch with the merge commit on `main`.

## User story

As a contributor who rebases a branch before merging it, I want the automatic sweep to remove that
worktree, so that finished work does not stay in the worktree list forever.

## Detail

`scripts/cleanup-merged-worktrees.ps1:70-120` defines `Test-BranchOwnWorkWasMerged`. It returns
`$true` only when one single reflog entry supplies both proofs:

1. The entry subject matches `^commit\b` (`:95`).
2. The SHA on that same entry is a non-first parent of a merge commit reachable from `main`
   (`:107-117`).

A rebase breaks the pairing. `git rebase` writes the replayed tip under the subject
`rebase (finish):`, not `commit:`. The only `commit:` entry still carries the pre-rebase SHA, and
that SHA exists nowhere on `main`.

**Observed on 2026-08-14.** Pull request #309 merged branch `chore/wt-microsoft-learn-mcp`. Local
`main` was current at `605fff27`, `ahkflow.worktreeCleanup` was `true`, and the worktree was clean.
`git branch --merged main` listed the branch. The worktree stayed.

Branch reflog:

```
33295201 rebase (finish): refs/heads/chore/wt-microsoft-learn-mcp onto e12666ab
ac6c04d4 rebase (finish): refs/heads/chore/wt-microsoft-learn-mcp onto df577b0a
6fb1b4d9 commit: chore: add Microsoft Learn MCP server
1309d0fe branch: Created from HEAD
```

Merge commit `605fff27` has parents `5012fd59 33295201`. The non-first parent `33295201` sits on a
`rebase (finish):` entry, so proof 1 rejects it. The only `commit:` SHA is `6fb1b4d9`, which is not
a parent of anything on `main`.

Dot-sourcing the script and calling the function directly returns `False`:

```powershell
. ./scripts/cleanup-merged-worktrees.ps1
Test-BranchOwnWorkWasMerged -RepoRoot (Get-Location).Path -Branch 'chore/wt-microsoft-learn-mcp' -MainRef 'main'
# False
```

**Scope of the defect.** Every branch that is rebased and then merged with a merge commit is
affected. Only a branch that never moved passes today.

**Scope of the fix.** It covers a local rebase followed by a normal merge commit, which is the
`--no-ff` shape a GitHub "Merge pull request" leaves behind. GitHub "Rebase and merge" stays
unsupported: it creates no merge commit, so no non-first parent exists for the merge proof to find.

**Why the pairing rule exists.** The comment at `:63-69` explains it. Reflog subjects are
caller-controlled text, so a forged `commit:` subject alone could delete an unstarted worktree. A
`branch: Created from` entry alone could do the same for a branch started at an already-merged tip.
Any fix must keep both attacks closed.

## Acceptance criteria

- [x] A branch that was rebased and then merged is eligible for cleanup
- [x] A branch created from an already-merged tip, with no commit of its own, is still preserved
- [x] A forged `commit:` reflog subject on an unstarted branch still cannot make it eligible
- [x] A branch merged without any rebase is still eligible, as it is today
- [x] A branch whose commit was reset away cannot borrow an unrelated rebase as merge proof
- [x] A forged `commit (finish):` subject, which only `GIT_REFLOG_ACTION` produces, proves nothing
- [x] `tests/WorktreeMergedCleanup.Tests.ps1` covers the rebase-then-merge shape with a real git
      fixture, not a hand-written reflog

## Out of scope

- Backlog 094 (merged-worktree sweep reads a stale local `main`). Same script, different cause.
  This item assumes the base ref is current
- Replacing ancestry proof with a merged-pull-request fact from the GitHub API
- The single-worktree path in `scripts/remove-worktree-local-dev.ps1`

## Notes / dependencies

- Found on 2026-08-14, when the worktree for pull request #309 stayed after the merge
- Candidate fix: widen the subject test at `:95` to `^(commit|rebase \(finish\))\b`. The
  `rebase (finish)` SHA is the post-replay tip, which is real work, and the same-entry rule stays.
  Check this against the two attacks named above before you write it
- Shipped fix: the probe keeps two sets from one reflog walk. The work proof is the closed list git
  writes, `^commit(:| \((amend|merge|initial|cherry-pick)\):)`. A `rebase (finish)` SHA can carry
  the merge proof, but only after `git cherry` shows it holds a patch-equivalent copy of one of the
  branch's own commits
- `\b` cannot follow `)`: that character and the `:` after it are both non-word characters, so
  `^(commit|rebase \(finish\))\b` matches nothing
- A review round caught two unsafe pairings the first draft allowed. Both are pinned by tests: a
  commit reset away and then rebased onto an unrelated merged branch, and a forged
  `commit (finish):` subject. The second one also returned `True` on `main` before this branch
- Backlog 094 touches the same function. Expect a conflict, and read it before you start
- Spec: none — single-function fix, no design needed
- Plan: `docs/superpowers/plans/2026-08-14-merged-worktree-sweep-rebased-branches-plan-095.md`
