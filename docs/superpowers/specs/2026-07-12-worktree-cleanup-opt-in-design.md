# Worktree Cleanup: Opt-In with Persistent Ask-Once Config

**Date:** 2026-07-12
**Branch:** `fix/worktree-cleanup-default-on`
**Status:** Implemented on `fix/worktree-cleanup-default-on` (plan: `docs/superpowers/plans/2026-07-12-worktree-cleanup-opt-in-plan.md`)

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
git config --local ahkflow.worktreeCleanup true   # always sweep merged, clean worktrees
git config --local ahkflow.worktreeCleanup false  # never sweep, never ask
git config --local --unset ahkflow.worktreeCleanup  # back to ask-once default
```

- Per-repo, lives in `.git/config` (never committed), one command to set or change.
- **Scope is `--local` on every read, write, and unset.** Reads use
  `git -C $RepoRoot config --local --bool --get-all ahkflow.worktreeCleanup` so a global or
  system-level value can never enable cleanup for this repo (`--get-all` so a duplicated key
  surfaces as multiple lines and fails closed), and `--bool` normalizes
  `true/false/1/0/yes/no`. **Fail closed:** an invalid, duplicated, or unreadable value
  is treated as report-only, with a stderr warning that includes the repair command
  (`git config --local --unset-all ahkflow.worktreeCleanup`).
- Works identically for CLI bootstrap (`claude --worktree`), in-conversation
  `EnterWorktree`, and direct `new-worktree.ps1` / `cleanup-merged-worktrees.ps1` calls.
- Governs **all contexts** (unlike the old hook-only env var).

## Decision precedence

Resolved in one function inside `cleanup-merged-worktrees.ps1`:

1. **`-Cleanup` flag** → clean. Per-run override for direct calls.
2. **`AHKFLOW_WORKTREE_CLEANUP` env var** → enable (`1|true|yes|y`) cleans / disable
   (`0|false|no|n`) report-only; other values ignored. Per-run, **hook-only** — a
   leftover `=1` in a shell must never silently delete on a direct call; direct calls
   already have `-Cleanup` as their per-run override.
3. **`git config ahkflow.worktreeCleanup`** → `true` clean / `false` skip. All contexts.
4. **Unset + interactive console** → ask once:
   `Found N merged, clean worktrees. Remove them now and enable automatic cleanup for this repository? [y/N]`
   — `y` cleans now and writes config `true`; `n` (the default) writes config `false`.
   Either way the answer is persisted, so the prompt never repeats. The prompt only
   fires when eligible worktrees exist — no eligible worktrees means no prompt and no
   preference is persisted. If the config write fails, the current answer is still
   honored for this run, with a stderr warning that it was not remembered.
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
  I'll remember either way") and write the git config `true`/`false` accordingly
  (`--local`). Mirrors the console ask-once semantics exactly. Detection reuses the
  skill's **existing** procedure unchanged — locating the main checkout, excluding the
  just-created worktree via `-ExcludePath`, literal path substitution (no `$variables`
  through the Bash tool), and detection-failure handling — only the follow-up action
  changes. The `cleanup: eligible merged worktree:` stderr lines remain the detection
  interface for now; a structured dry-run output is deferred (see Out of scope).
- **Docs:** the tri-state config is the headline mechanism in `scripts/README.md` and
  the worktrees skill, framed as the recommended ease-of-use setting.

## Manual execution

`scripts/cleanup-merged-worktrees.ps1` keeps its name and standalone entrypoint.
Direct runs behave as today (`-Cleanup` forces, interactive prompt otherwise), plus
config awareness: `true` cleans without prompting, `false` skips, unset asks once.

## Refactors (behavior-preserving)

1. **Make `-IsHook` honest instead of renaming it.** Today `new-worktree.ps1` collapses
   hook context and authorization into `$cleanupIsReportOnly` and passes *that* as
   `-IsHook`, so the name lies. With the decision matrix centralized (below), the
   caller passes the **raw** hook context and the collapsing disappears — `-IsHook`
   then means exactly what it says. The resolver needs true context (not a
   pre-collapsed outcome) to apply the hook-only env override and the hook-only hint,
   so a rename to `-ReportOnly` would destroy information the resolver requires.
2. **Centralize the decision matrix.** The env-var check currently lives in
   `new-worktree.ps1` and the flag/prompt/non-interactive logic in
   `cleanup-merged-worktrees.ps1`. The full precedence chain moves into one function in
   the cleanup script with one comment block explaining it. `new-worktree.ps1` only
   tells the cleanup script which context it is in (`-IsHook`, raw) and forwards
   `-Cleanup`.
3. **Dedupe `Write-Stderr`** into `worktree-powershell.common.ps1` (currently defined
   identically in both scripts, which already dot-source that file).

## Skill-file sync (restore + guard)

`plugins/ahkflowapp/skills/worktrees/SKILL.md` is meant to be a **hard link** to
canonical `.agents/worktrees/SKILL.md` (Codex plugin install ignores symlinks;
`setup-cross-agent-skills.ps1` creates the links). The link is currently broken — the
files are independent copies that happen to match.

- Edit only the canonical `.agents/worktrees/SKILL.md`.
- Re-run `scripts/agents/setup-cross-agent-skills.ps1` to restore the hard links
  (one-time manual step during this work; git checkouts cannot preserve hard-link
  identity, so restoration itself is not regression-tested).
- Add a guard test — a **self-running assertion script in the existing
  `tests/*.Tests.ps1` harness style** (CI executes these directly; the repo does not
  use Pester): every `plugins/ahkflowapp/skills/*/SKILL.md` must match its
  `.agents/<skill>/SKILL.md` source byte-for-byte. This guards committed-copy drift —
  the harmful consequence of a broken link — not link identity itself.

## Tests

Update `tests/WorktreeMergedCleanup.Tests.ps1` (self-running assertion scripts, the
existing harness):

**"Cleans" must mean *removed*, not *requested*.** Removal is delegated to a detached
watcher (`remove-worktree-local-dev.ps1`), so the `cleanup: removing...` stderr line
only proves the request. Every case marked "cleans" polls with a bounded timeout and
asserts the worktree registration disappears (`git worktree list`) and the directory is
gone (or the removal log records why it was preserved). Report-only cases assert both
directory and branch are untouched.

Matrix cases:

- Hook default (no env, no config) → report-only, stderr includes the config hint.
- Hook + env `1` → cleans; hook + env `0` → report-only.
- Hook + config `true` → cleans; hook + config `false` → report-only without hint.
- Env overrides config, hook-only: hook + env `1` + config `false` → cleans;
  hook + env `0` + config `true` → report-only.
- Direct calls ignore the env var entirely (env `1` set, no config → no cleanup).
- `-Cleanup` overrides config `false`.
- Non-interactive direct + config `true` → cleans (including target-path exclusion);
  `false` → skips.
- Invalid/duplicated config value → fails closed to report-only with warning.
- No eligible worktrees → no prompt, nothing persisted.
- Ask-once persistence is covered via the config-write path (interactive `Read-Host`
  itself is not automatable; test the function that maps an answer to a config write),
  including the config-write-failure warning path.
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
- `-DryRun` / `-OutputFormat Json` structured detection interface — the stderr lines
  serve the current consumers (humans, Claude); revisit if a tool integration needs it.
- `-Wait` on cleanup / synchronous removal and a removed/preserved/failed summary —
  both require touching removal mechanics; tests poll with a bounded timeout instead.
- Minimum-age grace period before a merged worktree becomes eligible.
