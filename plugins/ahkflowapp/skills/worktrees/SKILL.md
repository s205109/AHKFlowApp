---
name: worktrees
description: Use when creating, removing, or troubleshooting AHKFlowApp git worktrees across Claude Code, Codex, or Copilot.
---

# Worktrees

AHKFlowApp worktrees carry local-dev isolation — per-worktree ports, database, and Docker Compose project — set up by `scripts/new-worktree.ps1`. Skipping that script leaves a worktree that collides with the main checkout on ports, DB, and containers. Always create worktrees through it.

## Creating

**Claude Code:** use the native worktree feature. It fires the `WorktreeCreate` hook (`.claude/settings.json`) which runs `new-worktree.ps1` for you.

**Codex, Copilot, plain git, or any non-hook path:** run the script directly from the main checkout:

```bash
pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name>
```

It creates the branch, places the worktree under `.claude/worktrees/<name>/`, copies `.worktreeinclude` entries, runs local-dev isolation setup, and prints the worktree path on success.

**Do NOT** run bare `git worktree add` — it checks out files but skips isolation setup, leaving a broken worktree.

## Removing

`pwsh -NoProfile -File scripts/remove-worktree-local-dev.ps1 -WorktreePath .claude\worktrees\<name>` removes the worktree and deletes the branch (`git branch -d`), then drops the DB and removes the Docker Compose project — but only if that branch delete succeeds. If the branch has unmerged commits, `git branch -d` fails and DB/Docker cleanup is skipped; the next `new-worktree.ps1` run's orphan prune, or `scripts\prune-worktree-databases.ps1` / `scripts\prune-worktree-docker.ps1`, reclaim them later. Without `-WorktreePath` it is a no-op.

Worktrees deleted with plain git skip the `WorktreeRemove` hook; the next `new-worktree.ps1` run sweeps orphaned Docker projects as a safety net.
