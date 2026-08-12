# 083 - Guard classifies link targets as write targets

## Metadata

- **Epic**: Agent guardrails
- **Type**: Feature
- **Interfaces**: CLI

## Summary

The agent worktree guard reads the path a link is created AT, but never the path the link points
TO. A session in a worktree can create a link inside an allowed location that aims at a file in
the main checkout, then write through it. The write that follows looks allowed, because the
guard only ever sees the allowed path.

## User story

As a developer whose main checkout is protected from agent sessions, I want the guard to refuse a
link that points into the main checkout, so that an agent cannot reach a protected file by writing
through a link it made itself.

## Acceptance criteria

- [ ] `New-Item -ItemType HardLink -Path <allowed>\x.md -Target <main>\README.md` is refused from a
      managed worktree
- [ ] The same holds for `-ItemType SymbolicLink` and `-ItemType Junction`
- [ ] The same holds for the `ln` and `mklink` spellings
- [ ] Creating a link whose target is inside the session's own worktree stays allowed
- [ ] Tests cover each spelling above, in `tests/AgentWorktreeGuard.Tests.ps1`

## Out of scope

- Links that already exist on disk before the session starts. `Resolve-AgentSymlinkPath`
  (`scripts/agents/agent-worktree-guard.common.ps1`) already resolves a path through an existing
  reparse point. This item is about link CREATION.
- Hard links specifically carry no reparse point, so an existing hard link cannot be detected by
  path resolution at all. Refusing creation is the only control available for that shape.

## Notes / dependencies

- Found during review of PR #289 (backlog 076). Verified as **pre-existing**, not introduced by
  that branch: the same command is allowed at merge-base `2cba6963` when the link is created inside
  the session's own worktree, so the plans-repo exception did not open it.
- `new-item` maps only to its `Path` parameter in `$script:AgentGuardWriteCmdlets`
  (`scripts/agents/agent-worktree-guard.common.ps1`). `-Target` is not read anywhere.
- Deferred from PR #289 deliberately: closing it means the write grammar has to understand link
  semantics, which is a new capability in a security-critical hot path rather than a fix to the
  work that branch did.
- Related: [084](084-guard-fails-closed-on-pipeline-bound-move-sources.md), the other deferred
  finding from the same review.
