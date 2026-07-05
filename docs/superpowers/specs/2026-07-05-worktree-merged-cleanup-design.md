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
- No per-worktree removal grain — interactive removal is a single batch confirmation.
- Cleanup is never the default: removal requires an explicit opt-in — either an
  interactive confirmation, or the `-Cleanup` flag. There is no mode that removes
  worktrees on plain creation without one of those.

## Behavior

### CLI surface

`new-worktree.ps1` gains one switch:

- `-Cleanup` (alias `-c`) — request the merged-cleanup sweep for this run.

### Context detection

Two independent signals, resolved in this order:

1. **Hook vs. direct** — a `WorktreeCreate` hook invocation supplies the name via
   JSON on stdin and never passes `-Name`; a direct call always passes `-Name`.
   So the run is hook-driven iff `-Name` is absent **and** hook JSON was read.
   `new-worktree.ps1` already encodes exactly this
   (`$hookInput = if ($Name) { $null } else { Get-HookInput }`); capture it as a
   boolean (`$isHook = (-not $Name) -and ($null -ne $hookInput)`) before name
   resolution and pass it to the cleanup step. **Do not** use
   `[Console]::IsInputRedirected` to detect a hook — it is `True` for any
   redirected stdin, including a direct `pwsh` call made by an agent or a pipe,
   so it cannot tell hook from direct.
2. **Can we prompt?** — only meaningful for a direct run. We can prompt iff stdin
   is a real console (`-not [Console]::IsInputRedirected`). A direct call whose
   stdin is redirected (agent, CI, pipe) is **direct non-interactive**: we cannot
   ask a question, so we must not block on `Read-Host`.

### Decision matrix

| Context | `-Cleanup` | Behavior |
| --- | --- | --- |
| Hook (`WorktreeCreate`) | n/a | Never prompt, never remove. Detection runs; eligible worktrees are logged to stderr for visibility only. |
| Direct, interactive console | no | Ask one gate question: `Clean up merged worktrees? (y/n)`. Yes → list + batch-confirm `Remove these N worktrees? (y/n)`. No → skip. |
| Direct, interactive console | yes | Skip the gate. List + batch-confirm directly. |
| Direct, non-interactive (redirected stdin) | no | Skip cleanup. No opt-in given and we cannot prompt, so nothing is removed. |
| Direct, non-interactive (redirected stdin) | yes | `-Cleanup` **is** the opt-in and the confirmation. Remove all eligible worktrees without prompting; log each removal. |

Notes:

- The gate question is asked **only** on a direct interactive run without `-Cleanup`.
- `-Cleanup` means "the user has decided to clean up." Interactively it still shows
  the eligible list and one batch confirm (a last look); non-interactively there is
  no one to confirm, so the flag itself authorizes removal.
- Without `-Cleanup` and without a console, cleanup is skipped entirely — removal
  never happens without an explicit opt-in.
- If detection finds nothing eligible, no question is asked and nothing is printed
  beyond a diagnostic line.

### Detection — eligibility

A worktree is **eligible** for removal when **both** hold:

1. **Merged** — its branch is merged into `main`, using the local `main` ref
   with no `git fetch`. This matches how `git branch -d` already decides.

   Detect with `git branch --format="%(refname:short)" --merged main`, **not**
   plain `git branch --merged main`. Plain output prefixes each line with a
   two-char marker — `* ` for the current branch and `+ ` for a branch checked
   out in another worktree — and the cleanup candidates are exactly the
   `+`-prefixed ones. A naive line compare against `+ feature/foo` never matches
   `feature/foo` and silently skips every eligible worktree. `--format` emits
   bare short names, avoiding the marker-stripping entirely.
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
- Determine eligibility (merged + clean) per worktree, using the `--format`
  branch query from Detection.
- Own the gate question, the eligible-list display, and the batch confirmation.
- Invoke `remove-worktree-local-dev.ps1` per removed worktree.
- Accept the caller's `$isHook` and `-Cleanup` state and drive the decision matrix:
  hook → detect + stderr report only (no prompt, no removal); direct interactive →
  gate/confirm; direct non-interactive → remove-if-`-Cleanup`, else skip.

`new-worktree.ps1` dot-sources / calls this near the top of its flow, before it
creates the new worktree, passing through:

- whether `-Cleanup` was set,
- `$isHook` — the boolean derived from `-Name` absent + hook JSON present (see
  Context detection), so the cleanup step never re-derives hook-ness from
  redirected stdin.

The cleanup step itself decides prompt-ability from `[Console]::IsInputRedirected`
(a real console vs. redirected stdin), independently of `$isHook`.

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

Two required layers, both in the repo's existing PowerShell test style (assert
helpers, no external Pester dependency):

**Host-resolution (extend `tests/WorktreePowerShellHost.Tests.ps1`).** Assert the
new script exists and uses the shared host resolver (`Resolve-PowerShellExecutable`)
rather than bare `powershell`/`$PSHOME` when spawning `remove-worktree-local-dev.ps1`,
mirroring the assertions already present for `new-worktree.ps1` and
`remove-worktree-local-dev.ps1`. This text check does **not** cover behavior — the
following behavior tests are required, not optional.

**Cleanup behavior (new test file).** Using temporary throwaway branches/worktrees,
cover:

- **Eligibility matrix** — merged+clean → eligible; merged+dirty → excluded;
  unmerged+clean → excluded; the main checkout → always excluded.
- **Formatted branch parsing** — a merged branch that is checked out in another
  worktree (so plain `git branch --merged` prefixes it with `+ `) is still detected
  as eligible. This is the regression guard for the `--format` fix; a test built on
  plain `git branch --merged` parsing must fail.
- **Hook report-only** — in hook context, detection runs but nothing is removed and
  no prompt is issued.
- **Stdout stays clean** — driving the full `new-worktree.ps1` hook path with
  eligible worktrees present, stdout is exactly the new worktree path; all cleanup
  output lands on stderr.

## Documentation

- `scripts/README.md` — add `cleanup-merged-worktrees.ps1` to the
  "Worktree internals — contract" table (the files documented as one set).
- `.agents/worktrees/SKILL.md` (and its plugin + `.claude`/`.github` symlink copies)
  — document the `-Cleanup`/`-c` flag and the `Clean up merged worktrees? (y/n)`
  gate question under Creating.

## Open questions

None.
