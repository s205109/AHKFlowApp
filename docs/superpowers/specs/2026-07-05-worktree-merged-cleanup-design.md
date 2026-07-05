# Worktree merged-cleanup on creation — design

## Problem

Creating a new worktree leaves old, already-merged worktrees lying around. They
keep consuming per-worktree ports, databases, and Docker Compose projects, and
clutter `git worktree list`. Today cleanup is fully manual
(`remove-worktree-local-dev.ps1`, or the prune scripts as a safety net).

We want worktree creation to optionally sweep other worktrees whose branch is
already merged into `main`, removing the finished ones.

## Goals

- On worktree creation, detect other worktrees whose branch is merged into `main`.
- Remove the finished ones **only** when the user opts in — never silently.
- Reuse the existing, lock-safe removal path (`remove-worktree-local-dev.ps1`).
- Protect in-progress work: never remove a worktree with a dirty working tree.
- Keep the Claude Code `WorktreeCreate` hook contract intact (stdout = the new
  worktree path, nothing else).

## Non-goals

- No `git fetch` before the merge check — local `main` is used as-is.
- No remote/GitHub (`gh`) merge detection — local `git branch --merged` only.
- No per-worktree removal grain — removal is a single batch confirmation.
- Auto-cleanup is not the default. There is no "auto-remove without asking" mode.

## Behavior

### CLI surface

`new-worktree.ps1` gains one switch:

- `-Cleanup` (alias `-c`) — request the merged-cleanup sweep for this run.

### Decision matrix

| Context | `-Cleanup` passed | Behavior |
| --- | --- | --- |
| Manual/direct, interactive console | no | Ask one gate question: `Clean up merged worktrees? (y/n)`. Yes → detect + batch-confirm. No → skip. |
| Manual/direct, interactive console | yes | Skip the gate question. Detect + batch-confirm directly. |
| Claude Code `WorktreeCreate` hook (non-interactive) | n/a | Never prompt, never remove. Detection runs; eligible worktrees are logged to stderr for visibility only. |

Notes:

- The gate question is asked **only** when a console is interactive and `-Cleanup`
  was not passed. `-Cleanup` is the explicit opt-in that skips the gate.
- If detection finds nothing eligible, no question is asked and nothing is printed
  beyond a diagnostic line.

### Detection — eligibility

A worktree is **eligible** for removal when **both** hold:

1. **Merged** — its branch is merged into `main`
   (`git branch --merged main` lists the branch), using the local `main` ref
   with no `git fetch`. This matches how `git branch -d` already decides.
2. **Clean** — its working tree has no uncommitted changes
   (`git -C <worktree> status --porcelain` is empty).

The current (main) checkout is always excluded. A dirty worktree is never
eligible, even if its branch is merged — this protects in-progress edits.

### Removal

After the user confirms, each eligible worktree is removed by shelling out to the
existing `scripts/remove-worktree-local-dev.ps1 -WorktreePath <path>`. That path
already handles:

- `git branch -d` (refuses unmerged branches as a second safety net),
- per-worktree database drop and Docker Compose project teardown,
- the Windows lock-safe detached-watcher removal (a worktree still open in another
  session/editor is removed once its lock releases).

Batch confirmation wording: `Remove these N worktrees? (y/n)`, after listing the
eligible worktree names/paths.

## Architecture

New file: `scripts/cleanup-merged-worktrees.ps1`.

Responsibilities:

- Enumerate worktrees via `git worktree list --porcelain`, excluding the main
  checkout.
- Determine eligibility (merged + clean) per worktree.
- Own the gate question, the eligible-list display, and the batch confirmation.
- Invoke `remove-worktree-local-dev.ps1` per confirmed worktree.
- Expose a switch to run non-interactively (detection + stderr report only, no
  prompt, no removal) for the hook path.

`new-worktree.ps1` dot-sources / calls this near the top of its flow, before it
creates the new worktree, passing through:

- whether `-Cleanup` was set,
- whether the run is interactive vs. hook-driven (reuse the existing
  `Get-HookInput` / `[Console]::IsInputRedirected` signal the script already uses
  to distinguish hook from direct invocation).

Rationale for a standalone script (vs. inlining): `new-worktree.ps1` is already
substantial; a separate file keeps creation logic focused, lets the sweep be run
on its own, and is testable in isolation. It also fits the documented
"Worktree internals — contract" file set.

### Shared helpers reused

- `worktree-git.common.ps1` — `Resolve-GitPath`, `Test-LinkedWorktree`.
- `worktree-log.common.ps1` — `Write-WorktreeLog` for the human-readable log line.
- `worktree-powershell.common.ps1` — `Resolve-PowerShellExecutable` when spawning
  `remove-worktree-local-dev.ps1`, so the new script obeys the same host-resolution
  contract the existing tests enforce.

## Error handling

- Detection failures (e.g. a `git` error for one worktree) are non-fatal: log to
  stderr, skip that worktree, continue. Cleanup must never block worktree creation.
- A removal failure for one worktree does not abort the others; each is logged.
- In hook (non-interactive) context, all cleanup output goes to stderr so stdout
  stays the single worktree path the hook contract requires.

## Testing

Extend `tests/WorktreePowerShellHost.Tests.ps1` to assert the new script:

- exists,
- uses the shared PowerShell host resolver (`Resolve-PowerShellExecutable`) rather
  than bare `powershell`/`$PSHOME` when spawning `remove-worktree-local-dev.ps1`,

mirroring the assertions already present for `new-worktree.ps1` and
`remove-worktree-local-dev.ps1`.

Where practical, add focused logic tests for eligibility (merged+clean matrix)
using temporary throwaway branches/worktrees, consistent with the repo's existing
PowerShell test style (assert helpers, no external Pester dependency).

## Documentation

- `scripts/README.md` — add `cleanup-merged-worktrees.ps1` to the
  "Worktree internals — contract" table (the files documented as one set).
- `.agents/worktrees/SKILL.md` (and its plugin + `.claude`/`.github` symlink copies)
  — document the `-Cleanup`/`-c` flag and the `Clean up merged worktrees? (y/n)`
  gate question under Creating.

## Open questions

None.
