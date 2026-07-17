# Prevent stale Codex plugin cache when skills change

## Context

PR #198 added the `impeccable` skill. The repo-side chain is verified correct after checkout:

- `.claude/skills/impeccable` → symlink → `.agents/impeccable` ✓
- `.github/skills/impeccable` → symlink → `.agents/impeccable` ✓
- `plugins/ahkflowapp/skills/impeccable` → hard-linked mirror (SKILL.md + reference/ + scripts/) ✓

But Codex didn't see it: `codex plugin add` freezes a copy of `plugins/ahkflowapp/` into its installed cache, stamped with `plugin.json` version `0.1.0+codex.20260716153142` (July 16, pre-impeccable). Nothing refreshes that cache when skills change, and the version bump is a manual step that only lives in old plan docs. Goal: make the cache refresh automatic (user chose auto-reinstall).

## Design

Both fixes go into `scripts/agents/setup-cross-agent-skills.ps1` (and its `.sh` sibling), because the existing `.githooks/post-merge` hook already re-runs that script whenever `.agents/` changes after a pull — so the pull path, the manual-sync path, and the fresh-clone path all converge there.

### 1. Content-hash version bump (deterministic, idempotent)

After `Sync-CodexPluginSkillDirectory` runs:

- Compute a stable hash of the Codex skills payload: sort all files under `plugins/ahkflowapp/skills/` by relative path (ordinal), get each file's git blob OID via `git hash-object` (applies clean filters, so line-ending differences between platforms/checkouts don't change the result), SHA-256 over the `<oid>  <path>` lines, take first 12 hex chars.
- Rewrite `plugins/ahkflowapp/.codex-plugin/plugin.json` `version` to `0.1.0+codex.<hash12>` **only if it differs** — no churn when nothing changed, and the same content always produces the same version on every machine (so a puller's hook never dirties the tree if the committer ran sync).
- Print `[FIX] plugin.json version bumped — commit this change` when it rewrites.

Note: semver build metadata (`+…`) may be ignored by strict version comparison, but that doesn't matter here — freshness is guaranteed by step 2's reinstall, not by Codex's own up-to-date check. The hash-version is for visibility and for detecting drift.

### 2. Auto-reinstall the Codex plugin cache

New final step in the script:

- If `codex` CLI is not on PATH → print an informational skip line, exit 0 (no failure on machines without Codex).
- Otherwise run `codex plugin add ahkflowapp@ahkflowapp-local --json` when the installed cache is stale. Staleness check: read the installed plugin's `plugin.json` version (locate via `codex plugin list --json`; if that output shape is awkward, fall back to always reinstalling — the add is cheap and idempotent).
- Always print the reminder: `Codex sessions capture skills at startup — start a new Codex session to pick up changes.`

### 3. Mirror in `setup-cross-agent-skills.sh`

Apply the same two steps to the bash variant so non-Windows environments behave identically. Hash with `sha256sum`, reinstall gated on `command -v codex`.

### 4. Docs

- `AGENTS.md` (or the `worktrees`/`dck-verify` skill if more apt — prefer AGENTS.md "Prerequisites"/agent-skills area): one short note that the sync script now bumps `plugin.json` and refreshes the Codex plugin cache automatically; new Codex sessions are required after skill changes.
- Remove/soften any stale "manually bump version" instructions if found in active docs (the mentions found are in dated plan docs — leave those as history).

Deliberately skipped (YAGNI, per brainstorm): CI guard for version bumps — the deterministic auto-bump plus post-merge hook makes forgetting nearly impossible; revisit only if drift recurs.

## Files touched

- `scripts/agents/setup-cross-agent-skills.ps1` — hash-bump + reinstall logic
- `scripts/agents/setup-cross-agent-skills.sh` — same, bash
- `plugins/ahkflowapp/.codex-plugin/plugin.json` — version becomes `0.1.0+codex.<hash12>` (first run of updated script)
- `AGENTS.md` — one-line doc note
- This plan: `docs/superpowers/plans/2026-07-17-codex-plugin-cache-refresh-plan.md` (commit first, on the feature branch)

## Workflow

Feature branch (`fix/codex-plugin-cache-refresh`) from `main`, PR to merge — no direct commits to main. Commit spec/plan immediately after writing, before review.

## Verification

1. Run `scripts/agents/setup-cross-agent-skills.ps1` → confirm `plugin.json` version changed to hash form; run again → confirm no changes (idempotent).
2. Touch a skill file (e.g. add a trailing newline in a `.agents/*/SKILL.md`), re-run → version changes; revert, re-run → version returns to previous hash.
3. Confirm `codex plugin list` shows the new version and the installed cache directory contains `impeccable/`.
4. Simulate the pull path: `git merge` a branch touching `.agents/` in a scratch clone (or just verify `.githooks/post-merge` still triggers the script — its trigger paths already include `.agents/` and the setup scripts; add `plugins/ahkflowapp/` to the trigger list if not covered).
5. Start a new Codex session and confirm `impeccable` appears in available skills.
