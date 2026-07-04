# Scripts Organization + Friendly Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide internal scripts in subfolders (`scripts/ci/`, `scripts/agents/`), index everything in `scripts/README.md`, retire the obsolete backlog-seeding script, and give the user-facing manual scripts consistent friendly output — with zero behavior change and zero touches to the worktree contract.

**Architecture:** File moves + reference updates + output-only edits. Every move is preceded by a full-reference inventory; CI must stay green.

**Tech Stack:** PowerShell 5.1 (all scripts except `generate-changelog-json.ps1`, which is PS 7 by design), Python 3 (coverage gate), GitHub Actions.

## Global Constraints

- Feature branch (`feature/scripts-organization`), PR to `main`.
- **Worktree contract — DO NOT TOUCH:** `new-worktree.ps1`, `setup-worktree-local-dev.ps1`, `remove-worktree-local-dev.ps1`, `prune-worktree-databases.ps1`, `prune-worktree-docker.ps1`, `worktree-{database,docker,git,json,log,powershell}.common.ps1`, `.worktreeinclude`, `scripts/.env.worktree`, `scripts/.env.local`. They stay flat in `scripts/` and unmodified.
- No behavior/logic changes anywhere — moves, reference updates, and output formatting only.
- All PS scripts must keep parsing under Windows PowerShell 5.1 (except the documented PS 7 one).
- Friendly output uses the existing helpers in `scripts/Common.ps1` (inspect it first; extend it only with output helpers, never logic).

## Resume instructions

`git log --oneline -10` shows landed task commits; unchecked boxes are remaining. Tasks 2-4 each depend on Task 1's inventory (re-run its grep if resuming cold). Task 6 is independent of 2-5.

---

### Task 1: Reference inventory (read-only, no commit)

- [ ] For every candidate file, list all repo references:

```bash
for f in check-coverage-thresholds.py generate-changelog-json.ps1 \
         setup-copilot-symlinks.ps1 check-symlinks.ps1 \
         setup-cross-agent-skills.ps1 setup-cross-agent-skills.sh \
         create-github-issues.ps1; do
  echo "== $f"; grep -rn "$f" --include="*" . 2>/dev/null | grep -v "^\.git/" | grep -v "docs/superpowers"
done
```

Check especially: `.github/workflows/*.yml`, `run-coverage.ps1`, `docs/development/coverage.md`, `docs/development/versioning.md`, `AGENTS.md`, `.claude/` (skills, hooks, settings), `plugins/`, `.agents/`, and each script's own `$PSScriptRoot`-relative dot-sourcing. Record the hit list in the PR description. Historical docs (`docs/superpowers/`, `docs/copilot/`) are NOT updated.

### Task 2: Move CI-internal scripts to scripts/ci/

**Files:**
- Move: `scripts/check-coverage-thresholds.py` → `scripts/ci/`, `scripts/generate-changelog-json.ps1` → `scripts/ci/`
- Modify: every Task-1 hit — expected at minimum: `.github/workflows/ci.yml` (two python invocations: summary footer + threshold enforcement), any workflow invoking generate-changelog-json.ps1, `scripts/run-coverage.ps1` (if it calls the python gate), `docs/development/coverage.md`, `docs/development/versioning.md`.

- [ ] **Step 1:** `git mv` both files; update all references.
- [ ] **Step 2:** Add a header comment to `generate-changelog-json.ps1`'s invocation site (workflow) noting it requires PS 7 (`#Requires -Version 7.0`) and runs in CI where pwsh is available.
- [ ] **Step 3:** Local checks: `python scripts/ci/check-coverage-thresholds.py --help` (or a no-arg dry run against an existing CoverageReport if available); `scripts/run-coverage.ps1` end-to-end.
- [ ] **Step 4: Commit** `chore: move CI-internal scripts to scripts/ci`
- [ ] **Step 5:** Push branch; confirm the CI run is green (coverage steps find the new path) before continuing.

### Task 3: Move agent-config scripts to scripts/agents/

**Files:**
- Move: `scripts/setup-copilot-symlinks.ps1`, `scripts/check-symlinks.ps1`, `scripts/setup-cross-agent-skills.ps1`, `scripts/setup-cross-agent-skills.sh` → `scripts/agents/`
- Modify: every Task-1 hit — expected at minimum: `AGENTS.md` Prerequisites ("Run `scripts/setup-copilot-symlinks.ps1` after cloning…"), cross-references inside the scripts themselves, any `.claude/` or `plugins/` docs mentioning them.

- [ ] **Step 1:** `git mv` all four; update references; fix any `$PSScriptRoot`-relative paths inside them (e.g. if they resolve repo root as `$PSScriptRoot\..`, it becomes `$PSScriptRoot\..\..`).
- [ ] **Step 2:** Run `scripts/agents/check-symlinks.ps1` and `scripts/agents/setup-copilot-symlinks.ps1` — both must succeed from the new location.
- [ ] **Step 3: Commit** `chore: move agent-config scripts to scripts/agents`

### Task 4: Move create-github-issues.ps1 to scripts/agents/

**Context:** One-time backlog-seeding script (backlog 001); GitHub issues long created. User decision (roadmap decision #3): move, don't delete.

- [ ] **Step 1:** `git mv scripts/create-github-issues.ps1 scripts/agents/`; update any references (Task-1 inventory); fix internal `$PSScriptRoot`-relative paths if present.
- [ ] **Step 2: Commit** `chore: move create-github-issues script to scripts/agents`

### Task 5: scripts/README.md index

**Files:**
- Create: `scripts/README.md`

- [ ] **Step 1:** Write the index — one line per script, grouped:
  - **User-facing — deployment:** deploy.ps1, teardown.ps1, update.ps1, setup-entra-app.ps1, setup-dev-entra.ps1, open-test-in-browser.ps1, open-prod-in-browser.ps1
  - **User-facing — local dev & test:** test-fast.ps1, run-coverage.ps1, measure-tests.ps1, kill-dev-ports.ps1, publish-cli.ps1, new-worktree.ps1
  - **CI-internal (`ci/`):** check-coverage-thresholds.py, generate-changelog-json.ps1 (PS 7)
  - **Agent tooling (`agents/`):** the four moved scripts + create-github-issues.ps1 (historical one-time seeding, kept per decision)
  - **Worktree internals — contract, do not reorganize:** setup-/remove-worktree-local-dev.ps1, prune-worktree-*.ps1, worktree-*.common.ps1, plus `.env.worktree`/`.env.local`/`.worktreeinclude` semantics in one sentence
  - **Shared helpers:** Common.ps1, _open-env.ps1, test-sql-container.common.ps1
  Derive each description from the script's own synopsis/header — do not invent behavior.
- [ ] **Step 2:** Link the index from the repo README's contributor section (one line).
- [ ] **Step 3: Commit** `docs: add scripts/README.md index`

### Task 6: Friendly output pass on user-facing manual scripts

**Files:**
- Inspect first: `scripts/Common.ps1` (existing Write-* helpers and their styles; deploy.ps1 already uses them — treat deploy.ps1's output as the reference style)
- Modify (output lines only): `teardown.ps1`, `update.ps1`, `setup-entra-app.ps1`, `setup-dev-entra.ps1`, `publish-cli.ps1`, `kill-dev-ports.ps1`, `test-fast.ps1`, `run-coverage.ps1`, `open-test/prod-in-browser.ps1` (likely nothing to do — 2 lines each). `measure-tests.ps1` is EXCLUDED (roadmap decision #5: left as-is).

- [ ] **Step 1:** For each script: dot-source Common.ps1 if not already; replace ad-hoc `Write-Host` status lines with the Common.ps1 helper equivalents (section headers, success ✓ / warn / error styles as defined there); ensure every script ends with a clear one-line success or failure summary and a non-zero exit code on failure (verify the exit-code behavior already exists — do not add new failure handling logic, only surface what's there).
- [ ] **Step 2:** Parse check all scripts:

```powershell
Get-ChildItem scripts -Recurse -Filter *.ps1 | ForEach-Object {
  $t=$null;$e=$null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e)|Out-Null
  if($e){ Write-Host "FAIL $($_.Name)"; $e|ForEach-Object{Write-Host "  $($_.Message)"} } else { Write-Host "ok   $($_.Name)" }
}
```

Expected: `ok` for every file.
- [ ] **Step 3:** Smoke-run the safe ones locally: `test-fast.ps1`, `run-coverage.ps1`, `kill-dev-ports.ps1`, `publish-cli.ps1`. (Do NOT run deploy/teardown/update/entra scripts against Azure — visual diff of their output code paths is enough since deploy.ps1 is the untouched reference.)
- [ ] **Step 4: Commit** `chore: consistent friendly output for manual scripts`

---

## Final verification

- [ ] Parse-check loop (Task 6 Step 2) — all `ok`
- [ ] `scripts/test-fast.ps1` and `scripts/run-coverage.ps1` run green from repo root
- [ ] CI green on the PR (proves `scripts/ci/` paths)
- [ ] Worktree smoke: `scripts/new-worktree.ps1` to create a scratch worktree, then remove it — behavior unchanged (contract untouched; this catches accidental Common.ps1 breakage)
- [ ] `git diff main --stat` — no worktree-contract file appears
