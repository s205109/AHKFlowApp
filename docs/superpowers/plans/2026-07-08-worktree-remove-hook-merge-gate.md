# Gate WorktreeRemove Hook On Merge + Clean Status

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop Claude Code's exit-time worktree removal from deleting worktrees whose branch is
not yet merged into `main`. Only auto-remove a worktree when its branch is **merged into `main`
AND** the working tree is **clean**; otherwise preserve folder + branch and log manual guidance.
Provide an explicit `AHKFLOW_WORKTREE_FORCE_REMOVE=1` opt-out for discarding unmerged worktrees.

**Tech Stack:** PowerShell 5.1 scripts, git worktrees, Claude Code `WorktreeRemove` hook,
Markdown skill/docs, repository PowerShell test scripts.

---

## Context

**Symptom.** A worktree `hotstrings-redesign` (branch `feature/hotstrings-redesign`, never merged
into `main`) was opened in Claude Code, no changes were made, `/exit` → "remove worktree" was
chosen, and the worktree folder was deleted. Confirmed in
`.claude/worktrees/worktree-removal.log` (2026-07-08 10:06:22): the folder was removed; the branch
survived only because `git branch -d` refused it ("branch contains unmerged commits").

**Root cause.** Two *separate* removal mechanisms exist and were conflated:

1. **Create-time cleanup** — `scripts/cleanup-merged-worktrees.ps1`, run by `new-worktree.ps1`.
   Removes only worktrees that are **merged into `main` AND clean**, on explicit opt-in. This is
   what the merged `docs/worktree-cleanup-ask-on-create-plan` governs.
2. **Exit-time removal** — `scripts/remove-worktree-local-dev.ps1`, the `WorktreeRemove` hook
   (registered in `.claude/settings.json`). Fires on Claude's native `/exit` → "remove worktree".
   It removes the worktree **folder unconditionally** — no merge check. Only *branch deletion* is
   gated (via `git branch -d`, which is why the branch survived).

The expectation ("only delete worktrees already merged into `main` via a PR") describes mechanism
#1, but the deletion came from #2, which has no such guard. The repo uses merge-commit PRs
("Merge pull request #NNN"), so `git branch --merged main` / `git merge-base --is-ancestor`
correctly classify PR-merged branches — the guard is reliable here.

## Decisions

- Gate in **Hook mode** (`Invoke-HookMode`), *before* the watcher is spawned, so the destructive
  rename/delete never starts for an ineligible worktree. The worktree still exists at that point,
  so both probes work against it. Watcher mode stays unchanged.
- Eligibility = **has a branch AND merged AND clean**, matching the conservatism of
  `Get-EligibleMergedWorktrees` in `cleanup-merged-worktrees.ps1` (which skips branch-less
  worktrees at `:102` and requires a clean tree at `:110`).
- **Detached HEAD** (no branch) is **not eligible** → preserve unless forced. The merge probe alone
  (`HEAD` ancestor of `main`) would otherwise auto-remove a clean detached worktree parked on a
  commit already in `main`, which the create-side helper never does. Exit-time removal deliberately
  stays as conservative as create-time cleanup.
- If `main` cannot be resolved (probe error), treat as **not merged** → preserve (fail safe).
- Force override env var `AHKFLOW_WORKTREE_FORCE_REMOVE=1`; accepted truthy values `1|true|yes|y`
  (case-insensitive), reusing the exact `Test-EnvironmentFlagEnabled` helper from
  `new-worktree.ps1`.
- **Force semantics = "bypass the gate; then behave exactly as the hook does today."** It does NOT
  escalate destructiveness: the watcher still deletes only the folder and still uses safe
  `git branch -d` (`remove-worktree-local-dev.ps1:758`), so an unmerged branch is **preserved** and
  DB/Docker teardown still runs only if the branch actually deletes (`:770`). Fully discarding an
  unmerged branch and its resources remains a deliberate manual `git branch -D` (already printed in
  the branch-delete guidance). This keeps `FORCE_REMOVE` from silently destroying unmerged commits.
- A brand-new zero-commit worktree (on a branch) is trivially an ancestor of `main` → merged →
  removed. Acceptable (nothing to lose); matches the create-side semantics.

Decision matrix (after branch + main-checkout are captured, before the watcher snapshot):

```
hasBranch = branchName is set (HEAD is not detached)
merged    = hasBranch AND HEAD is ancestor of main  (git -C <worktree> merge-base --is-ancestor HEAD main)
clean     = working tree has no changes             (git -C <worktree> status --porcelain is empty)
force     = env AHKFLOW_WORKTREE_FORCE_REMOVE is truthy

force                       -> remove (spawn watcher; folder-only removal + safe branch -d, as today)
merged AND clean            -> remove (spawn watcher, as today)
otherwise                   -> PRESERVE: log reason (unmerged / dirty / detached) + manual-removal
(unmerged / dirty / detached)  guidance + force hint; return 0, no watcher
```

## File Structure

- Modify `scripts/remove-worktree-local-dev.ps1` — the gate (main change).
- Modify `Tests/WorktreeMergedCleanup.Tests.ps1` (or add `Tests/WorktreeRemoveHook.Tests.ps1`) —
  regression tests.
- Modify `.agents/worktrees/SKILL.md` — document the exit-time gate + force override; then resync.
- Modify `scripts/README.md` — update the `remove-worktree-local-dev.ps1` row.
- Modify `docs/development/worktree-isolation-manual-testing.md` — the "Remove the worktree" section.
- Resync (not by hand) `plugins/ahkflowapp/skills/worktrees/SKILL.md` via
  `scripts/agents/setup-copilot-symlinks.ps1`.

---

### Task 1: Add Failing Regression Tests

**Files:** Modify `Tests/WorktreeMergedCleanup.Tests.ps1` (or new `Tests/WorktreeRemoveHook.Tests.ps1`).

The harness already provides `Add-TestWorktree -Dirty` / `-Unmerged`
(`Tests/WorktreeMergedCleanup.Tests.ps1:60`) and `New-WorktreeToolingRepo` (:198). Drive the hook
by piping `{"worktree_path":"<path>"}` JSON to `remove-worktree-local-dev.ps1` and assert on the
removal log / final folder state. Cover:

- [ ] merged + clean → folder removed (unchanged behavior).
- [ ] unmerged → folder **preserved**; log names the unmerged reason + manual guidance.
- [ ] merged + dirty → folder **preserved**.
- [ ] detached HEAD (clean, ancestor of `main`) → folder **preserved** (new-behavior divergence).
- [ ] unmerged + `AHKFLOW_WORKTREE_FORCE_REMOVE=1` → folder removed **AND** the log records the
  force-override decision (e.g. a "force override: bypassing merge/clean gate" line).

The genuine red-green cases are the **preserve** ones (unmerged / dirty / detached): they fail on
today's script, which removes unconditionally. The force case must **not** assert on folder
absence alone — today's hook also removes an unmerged folder, so that assertion is green on both
old and new code. Instead assert the **force-specific log signal** so the test proves the gate was
consulted and the force branch was taken.

The watcher is async/detached. For the *remove* cases, poll for folder state with a bounded wait
(as the manual doc does) *and* assert the force/decision log line; for the *preserve* cases, assert
on the hook-side stderr/log decision (no watcher is spawned), which is deterministic.

Run and confirm the new preserve cases (and the force-signal assertion) FAIL against the current
script.

### Task 2: Implement The Gate In `remove-worktree-local-dev.ps1`

**Files:** Modify `scripts/remove-worktree-local-dev.ps1`.

- [ ] Add `Test-EnvironmentFlagEnabled` — copy verbatim from `scripts/new-worktree.ps1:31`
  (truthy = `^(1|true|yes|y)$`). Keep both definitions identical.
- [ ] Add a removability probe (function or inline) computing `merged` / `clean` via the existing
  `Invoke-GitCapture` helper so probe output is logged consistently:
  - `hasBranch`: `$branchName` is non-null (the hook already sets it to `$null` for detached HEAD,
    `:467`). Detached ⇒ not eligible.
  - `merged`: only when `hasBranch` — `Invoke-GitCapture @('-C', $worktreeFull, 'merge-base', '--is-ancestor', 'HEAD', 'main')`
    → `ExitCode -eq 0`. Any error resolving `main` ⇒ not merged.
  - `clean`: `Invoke-GitCapture @('-C', $worktreeFull, 'status', '--porcelain')` → no non-empty lines.
- [ ] When `AHKFLOW_WORKTREE_FORCE_REMOVE` bypasses the gate, emit a distinct log line (e.g.
  `Write-Log 'force override: AHKFLOW_WORKTREE_FORCE_REMOVE set; bypassing merge/clean gate.'`) so
  the force path is observable to the Task 1 test and in the log. Force does **not** change the
  watcher — folder-only removal + safe `git branch -d`, as today.
- [ ] Add `Write-UnmergedPreserveGuidance` modeled on `Write-TimeoutGuidance` /
  `Write-BranchDeleteGuidance`: log that the worktree was preserved, the specific reason
  (unmerged / uncommitted changes / detached HEAD), the manual `git worktree remove` + `prune` +
  `branch -d` commands, and the `AHKFLOW_WORKTREE_FORCE_REMOVE=1` opt-out.
- [ ] Insert the gate in `Invoke-HookMode` after `Test-RegisteredLinkedWorktree` (~line 541) and
  before the watcher snapshot (~line 547). Order the checks per the matrix; on preserve, call the
  guidance writer and `return` (no watcher spawned).
- [ ] Re-run Task 1 tests → all pass. Parse-check:
  `pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw scripts\remove-worktree-local-dev.ps1)) | Out-Null; 'parse OK'"`.

### Task 3: Update Skill + Script Docs

**Files:** `.agents/worktrees/SKILL.md`, `scripts/README.md`,
`docs/development/worktree-isolation-manual-testing.md`; resync
`plugins/ahkflowapp/skills/worktrees/SKILL.md`.

- [ ] `.agents/worktrees/SKILL.md` — state that exit-time removal now requires merged + clean, and
  document `AHKFLOW_WORKTREE_FORCE_REMOVE=1`.
- [ ] `scripts/README.md` — update the `remove-worktree-local-dev.ps1` row (merged+clean gate + force var).
- [ ] `docs/development/worktree-isolation-manual-testing.md` — the "Remove the worktree" section
  (~line 134) currently implies `/exit` → "remove worktree" always deletes; add that it only
  auto-deletes a merged, clean worktree, else preserves and logs guidance.
- [ ] Resync: `pwsh -NoProfile -File scripts/agents/setup-copilot-symlinks.ps1`. Do NOT hand-edit
  the plugin copy. Hash-verify `.agents/worktrees/SKILL.md` == `plugins/ahkflowapp/skills/worktrees/SKILL.md`.

### Task 4: Final Verification

- [ ] `pwsh -NoProfile -File Tests\WorktreeMergedCleanup.Tests.ps1` (+ new remove-hook test file) pass.
- [ ] `pwsh -NoProfile -File Tests\WorktreePowerShellHost.Tests.ps1` passes.
- [ ] `git diff --check` clean.
- [ ] `dotnet build AHKFlowApp.slnx --configuration Release` (safety net; no C# touched).
- [ ] Manual E2E (optional, scratch worktrees): unmerged worktree + `/exit` → preserved & logged;
  merge branch, `/exit` → removed; unmerged + `$env:AHKFLOW_WORKTREE_FORCE_REMOVE='1'` → removed.

---

## Resolved (from review)

- **Force scope.** `AHKFLOW_WORKTREE_FORCE_REMOVE=1` only bypasses the merged+clean gate; it keeps
  today's removal behavior (folder deleted, unmerged branch preserved via safe `branch -d`, DB/Docker
  reclaimed only if the branch deletes). It is **not** a `branch -D` / full-resource discard.
- **Detached HEAD.** Preserved unless forced — exit-time removal stays as conservative as
  create-time cleanup rather than auto-removing a clean ancestor-of-`main` detached worktree.
- **Force test.** Asserts the force-override log signal, not folder absence alone (which is green on
  the current script too).

## Unresolved Questions

- Force env name `AHKFLOW_WORKTREE_FORCE_REMOVE` ok, or another (e.g. `_REMOVE_FORCE`)?
- Split tests into new `Tests/WorktreeRemoveHook.Tests.ps1`, or append to the existing file?
- `main` ref hard-coded, or read a configurable main-branch name (repo only uses `main`)?
