# Docs Current-State Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the active docs match shipped reality for first release: one coherent README quickstart + a small end-user front door, staleness fixes, merged/archived historical material, and a clean backlog.

**Architecture:** Text-only changes. Runs AFTER plans A (backend consistency) and B (scripts organization) so it documents the final code shape and script paths.

**Tech Stack:** Markdown; `gh` CLI for the PR.

## Global Constraints

- Feature branch (`feature/docs-simplification`), PR to `main`.
- **Prerequisite:** plans A and B merged. If not, stop.
- Optimize for readability. English. Do not rewrite architecture docs; fix and trim only.
- Historical material is ARCHIVED, not deleted (user decision). Archive home: `docs/superpowers/plans/` unless roadmap open question #6 chose `docs/history/`.
- `docs/superpowers/**` content is historical — never "fix" old specs/plans to match current reality.
- Every command quoted in the README quickstart must be spot-run before commit.

## Resume instructions

`git log --oneline -10` shows landed task commits; unchecked boxes are remaining. Tasks are independent; T7 must run last.

---

### Task 1: README quickstart coherence

**Files:**
- Modify: `README.md:17-45` (Local Development → Running Locally + options)
- Inspect first: `Properties/launchSettings.json` at repo root (root-launcher profiles `"API + LocalDB"` / `"API + Docker SQL"`), `src/Backend/AHKFlowApp.API/Properties/launchSettings.json` (profiles incl. `"Docker SQL (Recommended)"`), AGENTS.md:55-60, `docs/development/docker-setup.md:30-40`

**Context (2026-07-04 docs audit):** Option 1 mixes the root launcher with a separate API+frontend recipe and a manual `dotnet ef database update` step that contradicts auto-migrate-at-startup in Development. README, AGENTS.md, and docker-setup.md each label a different path "recommended".

- [ ] **Step 1:** Rewrite Option 1 as ONE recipe: root launcher (`dotnet run` with the chosen profile), no manual migration step (state "the API migrates and seeds its database at startup in Development"). Keep the alternative (separate API/frontend terminals) as a clearly separate "advanced" variant or drop it if docker-setup.md already covers it.
- [ ] **Step 2:** Pick the single recommended path — Docker SQL (matches AGENTS.md and docker-setup.md) — and align the "recommended" wording in all three files. README's Docker-Compose option stays but loses the "(recommended)" label.
- [ ] **Step 3:** Spot-run each quoted command on a clean-ish checkout (at minimum: the root launcher command starts API+UI; URLs respond on 5600/5601).
- [ ] **Step 4: Commit** `docs: coherent README quickstart, single recommended path`

### Task 2: End-user Getting Started front door

**Files:**
- Modify: `README.md` (top, after the intro line)
- Inspect first: `docs/architecture/product-vision.md` §2/§5 (source of truth for what to say), `docs/cli/windows-install.md`

- [ ] **Step 1:** Add a short "What is AHKFlow?" + "Getting started (users)" section: 2-3 sentences on the product; the first-five-minutes path (sign in → create a hotstring → assign to a profile → Downloads → run the `.ahk` file with AutoHotkey v2 installed); link CLI install (`winget install AHKFlow.CLI` per docs/cli/windows-install.md) and note the app never runs scripts itself (AGENTS.md Out of Scope). Keep it under ~30 lines; contributor content moves below it.
- [ ] **Step 2: Commit** `docs: add end-user getting-started front door to README`

### Task 3: Staleness fixes (batch)

**Files:**
- Modify: `docs/development/playwright-setup.md:31` — example URL `localhost:7601` → `localhost:5601`
- Modify: `docs/architecture/product-vision.md` §5 Current Scope — add: entity version history with revert, recycle bin (restore/purge), in-app changelog
- Modify: `AGENTS.md` CI/CD workflows list — add `release-cli.yml` with a one-line role (packages `ahkflow-win-x64.zip` for CLI releases/winget); verify the exact behavior by reading `.github/workflows/release-cli.yml` first

- [ ] **Step 1:** Apply the three fixes.
- [ ] **Step 2: Commit** `docs: fix stale port, scope list, workflow inventory`

### Task 4: configuration-strategy.md trim

**Files:**
- Modify: `docs/development/configuration-strategy.md`
- Inspect first: `docs/environments.md` (already covers the homelab/UseTestProvider path — link, don't duplicate), README Option 3

- [ ] **Step 1:** Trim emoji-checklist styling to plain prose/tables; replace "Last Updated: Based on Microsoft Blazor documentation" with a real date; add a short section (or link to environments.md) for `Auth:UseTestProvider` / `appsettings.Local.json` local no-Azure config. Content that is correct stays — this is a trim, not a rewrite.
- [ ] **Step 2: Commit** `docs: trim + date configuration strategy, add local no-Azure config`

### Task 5: Merge worktree manual-testing docs

**Files:**
- Merge: `docs/development/worktree-docker-isolation-manual-testing.md` + `docs/development/worktree-port-isolation-manual-testing.md` → `docs/development/worktree-isolation-manual-testing.md`
- Inspect first: both docs (shared setup/teardown/Ctrl+C guidance; docker doc already links the port doc); `grep -rn "worktree-.*-manual-testing" . --include="*.md"` for inbound links

- [ ] **Step 1:** Create the merged doc: one shared setup/teardown frame, two scenario sections (port isolation, docker isolation). `git rm` the two originals; update inbound links.
- [ ] **Step 2: Commit** `docs: merge worktree manual-testing guides`

### Task 6: Archive historical material + backlog cleanup

**Files:**
- Move: `docs/development/github-setup.md` → `docs/superpowers/plans/2026-04-xx-github-setup-runbook.md` (keep original date if the file states one; add a one-line header: "Historical one-time setup runbook — archived 2026-07-04, content not maintained")
- Move: `docs/copilot/plans/*.md` (2 files) → `docs/superpowers/plans/` (same header treatment); remove the empty `docs/copilot/` tree
- Move: completed `.claude/backlog/` items (all except any with genuinely open work) → `.claude/backlog/done/`
- Modify: `.claude/backlog/015-…` and `017-…` — re-check the deferral boxes that are actually satisfied (015's CLI validation display → shipped with CLI; 017's HttpClient registration + `--profile` → shipped with backlog 028); add a parenthetical "(satisfied by 028/029)" per box
- Modify: `.claude/backlog/031-cli-winget-distribution.md` stays in the active backlog (winget community submission open)
- Modify: `.claude/CLAUDE.md` backlog line → "Backlog: `.claude/backlog/` — open items; completed items live in `done/`"
- Inspect first: `grep -rn "github-setup\|docs/copilot" . --include="*.md" | grep -v superpowers` for inbound links to fix

- [ ] **Step 1:** Execute the moves + edits; fix inbound links.
- [ ] **Step 2: Commit** `docs: archive historical runbooks, move done backlog items`

### Task 7: Post-A/B reference sweep (LAST)

- [ ] **Step 1:** `grep -rn "scripts/check-coverage-thresholds\|scripts/generate-changelog\|scripts/setup-copilot-symlinks\|scripts/check-symlinks\|scripts/setup-cross-agent-skills\|create-github-issues" --include="*.md" . | grep -v superpowers` — update any active-doc path missed by plan B.
- [ ] **Step 2:** Verify no active doc references removed code from plan A: `grep -rn "TestMessage" docs README.md AGENTS.md .claude --include="*.md"` → no hits outside superpowers.
- [ ] **Step 3:** Link check over active docs — for each `](relative/path)` target in README.md, AGENTS.md, docs/** (excluding superpowers), confirm the file exists:

```bash
grep -rhoE "\]\((\.{0,2}/)?[A-Za-z0-9_./-]+\.(md|json|ps1|py|yml)\)" README.md AGENTS.md docs --include="*.md" \
  | sort -u   # then resolve each relative to its containing file
```

(or use a link-checker one-liner; broken links = task failure).
- [ ] **Step 4: Commit** `docs: post-cleanup reference sweep`

---

## Final verification

- [ ] Link check (T7 S3) — zero broken relative links in active docs
- [ ] Every command quoted in README quickstart spot-run OK
- [ ] `grep -rn "MediatR\|7601\|TestMessage" README.md AGENTS.md docs .claude --include="*.md" | grep -v superpowers | grep -v "never\|don't\|Reintroducing"` → no stale hits
- [ ] `docs/copilot/` gone; `.claude/backlog/` contains only open items + `done/`
- [ ] PR to main, single concern: docs simplification
