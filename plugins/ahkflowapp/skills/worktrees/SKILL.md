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

### Cleanup of merged worktrees on create

Creating a worktree first checks the other worktrees whose branch is already merged
into `main`. Nothing is removed without an explicit opt-in:

- **Interactive direct create (a real console, no flag):** it lists the merged, clean
  worktrees and asks once - `Clean up merged worktrees? (y/n)`. `y` removes them all;
  `n` skips.
- **Direct `-Cleanup` / `-c`:** removes every merged, clean worktree with no prompt:

  ```bash
  pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name> -Cleanup
  ```

- **Claude Code CLI bootstrap (`claude --worktree <name>`):** set
  `AHKFLOW_WORKTREE_CLEANUP=1` before launching Claude to request cleanup during
  native worktree creation:

  ```powershell
  $env:AHKFLOW_WORKTREE_CLEANUP = '1'
  claude --worktree <name>
  Remove-Item Env:AHKFLOW_WORKTREE_CLEANUP
  ```

  Or on one self-clearing line: `$env:AHKFLOW_WORKTREE_CLEANUP='1'; claude --worktree <name>; Remove-Item Env:AHKFLOW_WORKTREE_CLEANUP`.
  The env var only takes effect for the `WorktreeCreate` hook; it does not change a
  direct `scripts/new-worktree.ps1` call, which still uses `-Cleanup` or its prompt.

- **WorktreeCreate hook without the env var, or non-interactive direct create without
  `-Cleanup`:** detection is logged to stderr only; nothing is removed.

A worktree with uncommitted changes is never removed, even if its branch is merged.
The worktree currently being created or reused is always excluded from the sweep, so a
same-named recreate can never race its own removal. Removal reuses
`remove-worktree-local-dev.ps1` (`git branch -d`, DB drop, Docker teardown, lock-safe
folder delete).

#### Claude Code in-conversation native creation: ask afterward

Applies only when *you* create a brand-new worktree in direct response to a
conversation request via `EnterWorktree` with `name`. Entering an existing worktree
with `path` never triggers this.

`EnterWorktree` fires the `WorktreeCreate` hook above. The hook stdout must stay
exactly the new worktree path, it cannot prompt, and hook stderr is not usable as a
conversation signal. Right after `EnterWorktree` returns the new worktree absolute
path, run detection yourself as a normal Bash call so the output is visible.

First work out the two absolute paths, then substitute them literally into the command
below - do not paste PowerShell `$variables` into a Bash-tool command line, because the
Bash tool (Git Bash) expands `$newPath`/`$mainRoot` to empty strings before `pwsh` ever
runs, silently breaking the call.

- `<new-worktree-absolute-path>`: the exact path `EnterWorktree` returned.
- `<main-root>`: that path with the trailing worktree segment removed - drop
  `\.claude\worktrees\<name>` (default layout) or `\.worktrees\<name>` (fallback layout).
  Do not use a fixed parent count; the two layouts have different depths. Before running,
  confirm `<main-root>\scripts\cleanup-merged-worktrees.ps1` exists - if it does not, you
  removed the wrong number of segments.

```bash
pwsh -NoProfile -Command "& '<main-root>\scripts\cleanup-merged-worktrees.ps1' -RepoRoot '<main-root>' -IsHook -ExcludePath '<new-worktree-absolute-path>'"
```

If that command errors (non-zero exit or an exception), report the error to the user and
stop; do not ask the cleanup question on the basis of a failed detection run.

- No `cleanup: eligible merged worktree: ...` line: stay silent, do not ask.
- One or more `cleanup: eligible merged worktree: <path> [<branch>]` lines: ask via
  `AskUserQuestion`, listing what was found, for example:
  "Found N merged worktree(s) ready to clean up: `<path>` [`<branch>`], ... . Remove them now?"
  with options `Yes, remove them` / `No, leave them`.
- If the user answers yes, re-run the same command with `-Cleanup` instead of `-IsHook`:

  ```bash
  pwsh -NoProfile -Command "& '<main-root>\scripts\cleanup-merged-worktrees.ps1' -RepoRoot '<main-root>' -Cleanup -ExcludePath '<new-worktree-absolute-path>'"
  ```

- If the user answers no, leave them; do not run the removal command.

## Removing

`pwsh -NoProfile -File scripts/remove-worktree-local-dev.ps1 -WorktreePath .claude\worktrees\<name>` removes the worktree and deletes the branch (`git branch -d`), then drops the DB and removes the Docker Compose project — but only if that branch delete succeeds. If the branch has unmerged commits, `git branch -d` fails and DB/Docker cleanup is skipped; the next `new-worktree.ps1` run's orphan prune, or `scripts\prune-worktree-databases.ps1` / `scripts\prune-worktree-docker.ps1`, reclaim them later. Without `-WorktreePath` it is a no-op.

Worktrees deleted with plain git skip the `WorktreeRemove` hook; the next `new-worktree.ps1` run sweeps orphaned Docker projects as a safety net.
