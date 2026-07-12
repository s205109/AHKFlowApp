# Worktree Cleanup: Opt-In with Persistent Ask-Once Config

**Date:** 2026-07-12
**Branch:** `fix/worktree-cleanup-default-on`
**Status:** Approved design, pending implementation plan

## Problem

Commit `8410a5b` flipped merged-worktree cleanup from opt-in to opt-out (default-on in
hook context). The sweep only removes merged + clean worktrees, so it is technically
safe — but on a shared repo it violates least surprise: a new developer launching
`claude --worktree` watches an unrelated worktree vanish silently, suspects data loss,
and wastes time investigating. The original opt-in (`AHKFLOW_WORKTREE_CLEANUP=1` per
process) was too clunky: it had to be re-set before every launch, which is exactly why
the default got flipped.

Goal: return to opt-in, but make opting in a **set-once, well-documented, actively
encouraged** choice. Keep `8410a5b` in history; new commits on this branch change the
default back.

## Mechanism

Persistent tri-state setting in git config:

```
git config ahkflow.worktreeCleanup true   # always sweep merged, clean worktrees
git config ahkflow.worktreeCleanup false  # never sweep, never ask
git config --unset ahkflow.worktreeCleanup  # back to ask-once default
```

- Per-repo, lives in `.git/config` (never committed), one command to set or change.
- Works identically for CLI bootstrap (`claude --worktree`), in-conversation
  `EnterWorktree`, and direct `new-worktree.ps1` / `cleanup-merged-worktrees.ps1` calls.
- Governs **all contexts** (unlike the old hook-only env var).

## Decision precedence

Resolved in one function inside `cleanup-merged-worktrees.ps1`:

1. **`-Cleanup` flag** → clean. Per-run override for direct calls.
2. **`AHKFLOW_WORKTREE_CLEANUP` env var** → `1` clean / `0` report-only. Per-run,
   **hook-only** — a leftover `=1` in a shell must never silently delete on a direct
   call; direct calls already have `-Cleanup` as their per-run override.
3. **`git config ahkflow.worktreeCleanup`** → `true` clean / `false` skip. All contexts.
4. **Unset + interactive console** → ask once:
   `Clean up merged worktrees automatically from now on? (y/n)` — `y` cleans now and
   writes config `true`; `n` writes config `false`. Either way the answer is persisted,
   so the prompt never repeats.
5. **Unset + hook or non-interactive** → report-only. The hook stderr hint prints the
   exact `git config ahkflow.worktreeCleanup true` one-liner, and only while unset —
   once someone answers `n` (config `false`), the hint stops too.

### Behavior matrix

| Context | config unset | config `true` | config `false` |
|---|---|---|---|
| Hook (CLI bootstrap / EnterWorktree) | report-only + config hint | clean | report-only, no hint |
| Interactive direct call | ask once → persist answer | clean, no prompt | skip, no prompt |
| Non-interactive direct call | report-only | clean | skip |
| `-Cleanup` flag (direct) | clean | clean | clean |
| Env `1` / `0` (hook only) | overrides for that run | overrides | overrides |

Unchanged safety rules: worktrees with uncommitted changes are never removed; the
worktree being created/reused is always excluded from the sweep; removals are logged to
`.claude\worktrees\worktree-removal.log`.

## Encouragement

- **Console:** the ask-once prompt itself — it fires exactly when the developer is
  looking at a list of stale merged worktrees, and one keypress makes the choice
  permanent.
- **Claude Code (in-conversation):** `.agents/worktrees/SKILL.md` instructs Claude,
  after `EnterWorktree` creates a brand-new worktree, to run detection; if eligible
  merged worktrees exist **and** the config is unset, ask the user once in the
  conversation ("Found N merged worktrees — clean them up automatically from now on?
  I'll remember either way") and write the git config `true`/`false` accordingly.
  Mirrors the console ask-once semantics exactly.
- **Docs:** the tri-state config is the headline mechanism in `scripts/README.md` and
  the worktrees skill, framed as the recommended ease-of-use setting.

## Manual execution

`scripts/cleanup-merged-worktrees.ps1` keeps its name and standalone entrypoint.
Direct runs behave as today (`-Cleanup` forces, interactive prompt otherwise), plus
config awareness: `true` cleans without prompting, `false` skips, unset asks once.

## Refactors (behavior-preserving)

1. **Rename `-IsHook` → `-ReportOnly`** on `cleanup-merged-worktrees.ps1`.
   `new-worktree.ps1` already passes `$isHook -and -not $cleanupRequested`, so the
   parameter means report-only; the name should say so.
2. **Centralize the decision matrix.** The env-var check currently lives in
   `new-worktree.ps1` and the flag/prompt/non-interactive logic in
   `cleanup-merged-worktrees.ps1`. The full precedence chain moves into one function in
   the cleanup script with one comment block explaining it. `new-worktree.ps1` only
   tells the cleanup script which context it is in (hook vs direct) and forwards
   `-Cleanup`.
3. **Dedupe `Write-Stderr`** into `worktree-powershell.common.ps1` (currently defined
   identically in both scripts, which already dot-source that file).

## Skill-file sync (restore + guard)

`plugins/ahkflowapp/skills/worktrees/SKILL.md` is meant to be a **hard link** to
canonical `.agents/worktrees/SKILL.md` (Codex plugin install ignores symlinks;
`setup-cross-agent-skills.ps1` creates the links). The link is currently broken — the
files are independent copies that happen to match.

- Edit only the canonical `.agents/worktrees/SKILL.md`.
- Re-run `scripts/agents/setup-cross-agent-skills.ps1` to restore the hard links.
- Add a Pester guard test: every `plugins/ahkflowapp/skills/*/SKILL.md` must match its
  `.agents/<skill>/SKILL.md` source byte-for-byte, so future drift fails loudly.

## Tests

Update `tests/WorktreeMergedCleanup.Tests.ps1`:

- Hook default (no env, no config) → report-only, stderr includes the config hint.
- Hook + env `1` → cleans; hook + env `0` → report-only.
- Hook + config `true` → cleans; hook + config `false` → report-only without hint.
- Non-interactive direct + config `true` → cleans; `false` → skips.
- Ask-once persistence is covered via the config-write path (interactive `Read-Host`
  itself is not automatable; test the function that maps an answer to a config write).
- New skill-parity guard test (byte-for-byte plugin vs `.agents`).

## Docs to update

- `.agents/worktrees/SKILL.md` (canonical; plugin copy follows via hard link) — rewrite
  the cleanup section around the tri-state config, including the in-conversation
  ask-once instruction for Claude.
- `scripts/README.md` — one-line description of `cleanup-merged-worktrees.ps1` updated
  to name the config as the primary switch.
- Script synopsis/comments in `cleanup-merged-worktrees.ps1` and `new-worktree.ps1`.

## Out of scope

- Renaming `cleanup-merged-worktrees.ps1` — the name already says what it does.
- Changing the plugin packaging model (e.g. CI-generated copies).
- Any change to removal mechanics (`remove-worktree-local-dev.ps1`), eligibility rules,
  or the removal log.
