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

**Branch naming:** worktree branches insert `wt-` after the type prefix — `fix/wt-<topic>`, `feature/wt-NNN-<topic>` (see AGENTS.md Git Workflow). Pass it explicitly (`-BranchName fix/wt-<topic>`) or name the worktree so the derived branch matches.

**Do NOT** run bare `git worktree add` — it checks out files but skips isolation setup, leaving a broken worktree.

### Cleanup of merged worktrees on create

Creating a worktree first checks the other worktrees whose branch is already merged
into `main`. What happens next is governed by one persistent per-repo setting plus
per-run overrides.

**The recommended switch — set it once:**

```bash
git config --local ahkflow.worktreeCleanup true    # always remove merged, clean worktrees
git config --local ahkflow.worktreeCleanup false   # never remove, never ask
git config --local --unset ahkflow.worktreeCleanup # back to ask-once
```

It lives in `.git/config` (never committed), is read at `--local` scope only (a global
value can't enable it here), and governs every context. An invalid or duplicated value
fails closed to report-only with a repair hint.

Precedence, highest first:

1. **`-Cleanup` / `-c` flag** (direct calls) — removes every merged, clean worktree, no prompt.
2. **`AHKFLOW_WORKTREE_CLEANUP`** — hook context only: `1|true|yes|y` enables, `0|false|no|n`
   disables, other values ignored. Per-run; never affects a direct call.
3. **`ahkflow.worktreeCleanup`** config — `true` removes, `false` skips. All contexts.
4. **Unset + interactive console** — asks once: *"Found N merged, clean worktrees. Remove
   them now and enable automatic cleanup for this repository? [y/N]"*. `y` removes now and
   persists `true`; anything else persists `false`. The answer is remembered, so it never
   asks again.
5. **Unset + hook / non-interactive** — report-only; the hook prints the one-liner to enable.

```bash
pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name>            # ask-once if unset
pwsh -NoProfile -File scripts/new-worktree.ps1 -Name <name> -Cleanup   # force removal this run
```

A worktree with uncommitted changes is never removed, even if its branch is merged. The
worktree currently being created or reused is always excluded from the sweep. Removal
reuses `remove-worktree-local-dev.ps1` (`git branch -d`, DB drop, Docker teardown,
lock-safe folder delete) and is logged to `.claude\worktrees\worktree-removal.log`.

#### Claude Code in-conversation native creation: ask once, then remember

Applies when *you* create a brand-new worktree in direct response to a conversation
request via `EnterWorktree` with `name`. Entering an existing worktree with `path` never
triggers this.

`EnterWorktree` fires the `WorktreeCreate` hook, which runs the resolver above: with a
recognized `AHKFLOW_WORKTREE_CLEANUP` env value or the config set (`true`/`false`) it acts
silently and there is nothing to do. Only when neither governs — no env override **and** the
config is **unset** — mirror the console ask-once in the conversation.

First work out the two absolute paths, then substitute them literally into the commands
below — do not paste PowerShell `$variables` into a Bash-tool command line, because the
Bash tool (Git Bash) expands `$newPath`/`$mainRoot` to empty strings before `pwsh` ever
runs, silently breaking the call.

- `<new-worktree-absolute-path>`: the exact path `EnterWorktree` returned.
- `<main-root>`: that path with the trailing worktree segment removed — drop
  `\.claude\worktrees\<name>` (default layout) or `\.worktrees\<name>` (fallback layout).
  Do not use a fixed parent count; the two layouts have different depths. Before running,
  confirm `<main-root>\scripts\cleanup-merged-worktrees.ps1` exists — if it does not, you
  removed the wrong number of segments.

1. Honor a session-wide env override first. If `AHKFLOW_WORKTREE_CLEANUP` holds a recognized
   value, the environment already governs this session (the `WorktreeCreate` hook applied it),
   so do nothing here — do not detect, do not ask, do not write config. Stop.

   ```bash
   printf '%s' "${AHKFLOW_WORKTREE_CLEANUP:-}"
   ```

   `1`/`true`/`yes`/`y` (enable) or `0`/`false`/`no`/`n` (disable), case-insensitive and
   trimmed → env owns the session; stop. Empty or any other value → continue. (This is why
   `AHKFLOW_WORKTREE_CLEANUP=0` set before launching Claude Code suppresses the whole flow.)

2. Check the config with the SAME four-state read the script uses — `--get-all` (not `--get`,
   which silently returns only the last value when the key is duplicated):

   ```bash
   git -C '<main-root>' config --local --bool --get-all ahkflow.worktreeCleanup
   ```

   - Exit 1, no output → **unset** → continue to step 3.
   - Exit 0 with exactly one `true`/`false` line → **set** → act silently, stop.
   - Anything else — exit 128 (bad boolean) or exit 0 with more than one line (duplicated) →
     **invalid** → report-only. Tell the user the value is invalid/duplicated and to repair it
     with `git config --local --unset-all ahkflow.worktreeCleanup`; do NOT ask and do NOT
     overwrite it. Stop.

3. Detect eligible merged worktrees. This is report-only here: step 1 ruled out any env
   override and step 2 guaranteed the config is unset, so `-IsHook` only lists — it removes
   nothing.

   ```bash
   pwsh -NoProfile -Command "& '<main-root>\scripts\cleanup-merged-worktrees.ps1' -RepoRoot '<main-root>' -IsHook -ExcludePath '<new-worktree-absolute-path>'"
   ```

   If that command errors (non-zero exit or an exception), report the error to the user and
   stop; do not ask on the basis of a failed detection run.

   - No `cleanup: eligible merged worktree: ...` line → stay silent, do not ask, do not write config.
   - One or more `cleanup: eligible merged worktree: <path> [<branch>]` lines → ask once via
     `AskUserQuestion`: "Found N merged worktree(s) ready to clean up: `<path>` [`<branch>`], … .
     Clean them up automatically from now on? I'll remember either way." with options
     `Yes, remove them` / `No, leave them`.

4. Persist the answer (mirrors the console ask-once exactly):

   - **Yes** → enable and remove now:

     ```bash
     git -C '<main-root>' config --local ahkflow.worktreeCleanup true
     pwsh -NoProfile -Command "& '<main-root>\scripts\cleanup-merged-worktrees.ps1' -RepoRoot '<main-root>' -Cleanup -ExcludePath '<new-worktree-absolute-path>'"
     ```

   - **No** → remember the choice, remove nothing:

     ```bash
     git -C '<main-root>' config --local ahkflow.worktreeCleanup false
     ```

To suppress this whole flow for a session regardless of config, set
`AHKFLOW_WORKTREE_CLEANUP=0` in the shell *before launching Claude Code*; step 1 stops before
any detection or ask.

## Removing

Claude Code's native `/exit` → "remove worktree" fires the `WorktreeRemove` hook
(`scripts/remove-worktree-local-dev.ps1`). It only auto-removes when the worktree's
branch is **merged into `main` AND** the working tree is **clean**; otherwise the
worktree folder and branch are preserved and the log names the reason (unmerged /
uncommitted changes / detached HEAD) plus manual `git worktree remove` + `prune` +
`branch -d` commands. A detached-HEAD worktree is never auto-removed, even if it is
clean and its commit is already in `main` — this matches the conservatism of the
create-time cleanup (`cleanup-merged-worktrees.ps1`).

To force removal of an unmerged or dirty worktree (folder deleted; branch still only
removed via safe `git branch -d`, so an unmerged branch survives), set
`AHKFLOW_WORKTREE_FORCE_REMOVE=1` before exiting:

```powershell
$env:AHKFLOW_WORKTREE_FORCE_REMOVE = '1'
```

When eligible (or forced), the script removes the worktree and deletes the branch
(`git branch -d`), then drops the DB and removes the Docker Compose project — but only
if that branch delete succeeds. If the branch has unmerged commits, `git branch -d`
fails and DB/Docker cleanup is skipped; the next `new-worktree.ps1` run's orphan prune,
or `scripts\prune-worktree-databases.ps1` / `scripts\prune-worktree-docker.ps1`, reclaim
them later. Without `-WorktreePath` it is a no-op.

Worktrees deleted with plain git skip the `WorktreeRemove` hook; the next `new-worktree.ps1` run sweeps orphaned Docker projects as a safety net.
