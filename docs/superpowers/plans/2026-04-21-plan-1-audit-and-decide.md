# Plan 1 — Audit & Decide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land PR #66, take a frozen snapshot of outdated packages and security findings, and publish a short decisions doc that tells later plans what to do with each finding.

**Architecture:** No production code changes in this plan. One PR merge (PR #66), two read-only audits, one markdown artifact. The artifact lives at `docs/superpowers/audits/2026-04-21-baseline-audit.md` and is referenced from plans 2-6 when they start.

**Tech Stack:** `gh` CLI, `dotnet list package`, the `cck-security-scan` skill.

---

## File Structure

**Create:**
- `docs/superpowers/audits/2026-04-21-baseline-audit.md` — the decisions doc; captures outdated packages, security findings, per-plan disposition.

**Modify:** none.

**Merge:** PR #66 (`fix/unique-resource-names` → `main`). No local code edits in the roadmap feature branch — PR #66 is merged via `gh` on its own branch.

---

## Pre-flight

Before starting the first task, confirm:

- You are on the existing `feature/codebase-simplification-roadmap` branch (created during brainstorming and holding the roadmap spec). Run `git branch --show-current` — expected: `feature/codebase-simplification-roadmap`.
- Working tree is clean. Run `git status --short` — expected: no output.
- `gh auth status` reports you are logged in to GitHub.
- `dotnet --version` reports `10.0.x`.

If any check fails, stop and fix before proceeding.

---

## Task 1: Refresh PR #66 against main

**Files:**
- No files changed in this working tree. The PR branch lives on the remote; we only interact with it through `gh`.

- [ ] **Step 1: Inspect PR #66 head commit and mergeability**

Run:

```bash
gh pr view 66 --json number,title,state,headRefName,mergeable,mergeStateStatus,isDraft
```

Expected: `"state":"OPEN"`, `"isDraft":false`, a `headRefName` of `fix/unique-resource-names`. `mergeable` may be `UNKNOWN` — that is fine, we refresh next.

- [ ] **Step 2: Check whether the PR branch is behind main**

Run:

```bash
gh pr view 66 --json commits --jq '.commits[-1].oid'
gh api repos/:owner/:repo/compare/main...fix/unique-resource-names --jq '{ahead: .ahead_by, behind: .behind_by}'
```

Expected: a JSON object like `{"ahead": N, "behind": M}`. If `behind` is `0`, skip Step 3 and go to Step 4. If `behind` > 0, continue.

- [ ] **Step 3: Update the PR branch with latest main**

Run:

```bash
gh pr update-branch 66
```

Expected: output `"Updated pull request #66 ..."`. If this command fails with a merge conflict, stop and ask the human — PR #66 is author-owned and conflict resolution may need their input. Do not attempt a force-push.

- [ ] **Step 4: Wait for CI to complete on the refreshed branch**

Run:

```bash
gh pr checks 66 --watch
```

Expected: all checks end in `pass`. If any check fails, stop and ask the human before proceeding — we are not reworking PR #66 in this plan.

- [ ] **Step 5: Commit — nothing to commit in this task**

No local files changed. Proceed to Task 2.

---

## Task 2: Merge PR #66

**Files:** none locally.

- [ ] **Step 1: Merge PR #66**

Run:

```bash
gh pr merge 66 --merge --delete-branch
```

We use `--merge` (not `--squash` or `--rebase`) to match the repo's history — the recent `git log` shows merge commits for every PR (e.g., `Merge pull request #80`). `--delete-branch` removes the remote branch after merge.

Expected: `"Merged pull request #66"` and `"Deleted branch fix/unique-resource-names"`.

- [ ] **Step 2: Pull main locally and confirm the merge commit is there**

Run:

```bash
git fetch origin
git log origin/main --oneline -5
```

Expected: top commit is the PR #66 merge commit.

- [ ] **Step 3: Rebase the current feature branch on top of the new main**

Run:

```bash
git rebase origin/main
```

Expected: `Successfully rebased and updated refs/heads/feature/codebase-simplification-roadmap.`
If a conflict appears, resolve it (the roadmap spec is unlikely to conflict with a Bicep/ps1 change in PR #66) and continue.

- [ ] **Step 4: Commit — nothing to commit in this task**

Rebase does not produce a commit of its own. Proceed to Task 3.

---

## Task 3: Seed the audit document

**Files:**
- Create: `docs/superpowers/audits/2026-04-21-baseline-audit.md`

- [ ] **Step 1: Ensure the audits directory exists**

Run:

```bash
ls docs/superpowers/
```

Expected: `plans  specs` listed. If `audits` is missing, `git` will pick it up when the file is added — no explicit `mkdir` needed on Windows bash; `Write` tool creates parent directories.

- [ ] **Step 2: Create the audit file with the fixed sections**

Create `docs/superpowers/audits/2026-04-21-baseline-audit.md` with the exact following content:

```markdown
# Baseline Audit — 2026-04-21

> Snapshot captured during plan 1 of the codebase simplification roadmap.
> Every finding here is tagged with the plan that will handle it.

## PR #66 — unique-suffix Azure resource names

- Status: **merged** on 2026-04-21.
- Disposition: closed during plan 1.

## Outdated packages

_Populated in Task 4._

## Security findings

_Populated in Task 5._

## Per-plan disposition

_Populated in Task 6._
```

- [ ] **Step 3: Commit the seed file**

Run:

```bash
git add docs/superpowers/audits/2026-04-21-baseline-audit.md
git commit -m "docs(audit): seed baseline audit for plan 1"
```

Expected: single-file commit on `feature/codebase-simplification-roadmap`.

---

## Task 4: Capture outdated packages

**Files:**
- Modify: `docs/superpowers/audits/2026-04-21-baseline-audit.md`

- [ ] **Step 1: Run `dotnet list package --outdated` across the solution**

Run:

```bash
dotnet list package --outdated
```

Expected: output begins with `The following sources were used:` and ends with one `Project ...` block per .csproj in the solution. Capture the full stdout.

If `dotnet list package --outdated` fails with a NuGet restore error, run `dotnet restore` once and retry. Do not upgrade anything.

- [ ] **Step 2: Record findings in the audit file**

Replace the `## Outdated packages` section in `docs/superpowers/audits/2026-04-21-baseline-audit.md` so it looks like this, with the actual stdout pasted into the fenced block:

```markdown
## Outdated packages

Snapshot via `dotnet list package --outdated` on 2026-04-21.

\`\`\`text
<paste full stdout here>
\`\`\`

- Disposition: no upgrades in this roadmap cycle. Re-evaluated when individual plans need a specific package bumped (e.g., MediatR for a bug fix). Tracked as a future backlog item.
```

(The `\`\`\`` escaping is only for rendering in this plan — in the audit file, use real triple backticks.)

If the `dotnet list` output is empty (no outdated packages), replace the fenced block with the single line `No outdated packages as of 2026-04-21.` and keep the disposition sentence.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/superpowers/audits/2026-04-21-baseline-audit.md
git commit -m "docs(audit): record outdated-package snapshot"
```

---

## Task 5: Capture security findings

**Files:**
- Modify: `docs/superpowers/audits/2026-04-21-baseline-audit.md`

- [ ] **Step 1: Invoke the security-scan skill**

Invoke the skill named `cck-security-scan` via the Skill tool. Follow its instructions exactly. Do not fix anything it finds — this task is record-only.

Expected: a skill report listing findings by layer (secrets, dependencies, code, configuration, infra, network) with severity.

- [ ] **Step 2: Record findings in the audit file**

Replace the `## Security findings` section with the following shape, substituting the actual findings. Keep the structure even if the list is short — an empty bullet list is better than a missing section.

```markdown
## Security findings

Scan via `cck-security-scan` skill on 2026-04-21.

| ID | Severity | Layer | Summary | Disposition |
|----|----------|-------|---------|-------------|
| S-1 | high \| med \| low | secrets \| deps \| code \| config \| infra \| network | one-line description | plan 3 \| plan 4 \| plan 6 \| defer (backlog) |
| ... | ... | ... | ... | ... |

If the scan finds nothing, state: "No findings above the skill's reporting threshold on 2026-04-21."
```

Dispose each finding by mapping it to the plan that will fix it:
- secrets / config leak → plan 6 (docs + consistency sweep) if it's a docs leak, plan 3 if it's in code.
- dead or unsafe code → plan 3.
- script-level concerns (`deploy.ps1`, `setup-*`) → plan 4.
- infra (Bicep) changes → **defer**; spec non-goals exclude Bicep edits.
- anything requiring an upgrade → **defer** (upgrades excluded this cycle).

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/superpowers/audits/2026-04-21-baseline-audit.md
git commit -m "docs(audit): record security-scan findings"
```

---

## Task 6: Finalize per-plan disposition

**Files:**
- Modify: `docs/superpowers/audits/2026-04-21-baseline-audit.md`

- [ ] **Step 1: Fill the per-plan disposition section**

Replace the `## Per-plan disposition` section with this content, adjusting the bullets under each plan based on what Tasks 4 and 5 recorded:

```markdown
## Per-plan disposition

Each plan 2-6 opens by re-reading this section. Only items listed under its plan are in its scope.

### Plan 2 — Targeted coverage uplift
- No audit findings route here directly. Coverage gaps are discovered inside plan 2.

### Plan 3 — Code simplification
- <list security findings IDs disposed to plan 3, or "none">
- <list dead-code hot spots if any surfaced during the security scan>

### Plan 4 — Script + deploy.ps1 overhaul
- <list script-layer security findings, or "none">
- PR #66's new unique-suffix variables are now in `scripts/.env.<env>` — plan 4's preflight must read them.

### Plan 5 — Local-install path (no Azure)
- No audit findings route here directly. Scope is fixed by the roadmap spec.

### Plan 6 — Docs + consistency sweep
- <list docs / config-leak findings, or "none">
- Cross-reference: README, AGENTS.md, `.claude/CLAUDE.md`, `.github/**`.

### Deferred
- Package upgrades (outdated-package snapshot).
- Any infra / Bicep security findings.
- <anything else marked `defer` in the findings table>
```

- [ ] **Step 2: Re-read the full audit file end-to-end**

Run:

```bash
cat docs/superpowers/audits/2026-04-21-baseline-audit.md
```

Verify:
- No `<paste ...>` or `<list ...>` placeholders remain.
- Every security finding has both a severity and a disposition.
- Every plan under "Per-plan disposition" has at least one concrete bullet (even if that bullet is "none").

If any placeholder remains, go back to the task that owns it and fix it.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/superpowers/audits/2026-04-21-baseline-audit.md
git commit -m "docs(audit): per-plan disposition and close plan 1"
```

---

## Task 7: Open plan 1 pull request

**Files:** none.

- [ ] **Step 1: Push the feature branch**

Run:

```bash
git push -u origin feature/codebase-simplification-roadmap
```

Expected: new remote branch, PR creation link in the output.

- [ ] **Step 2: Open the PR**

Run:

```bash
gh pr create --title "docs: plan 1 audit & decide" --body "$(cat <<'EOF'
## Summary
- Merges the roadmap spec from `docs/superpowers/specs/2026-04-21-codebase-simplification-roadmap-design.md`.
- Adds the baseline audit at `docs/superpowers/audits/2026-04-21-baseline-audit.md`.
- Closes plan 1 of the simplification roadmap; PR #66 landed as part of this plan.

## Test plan
- [ ] CI (`build-test`, `bicep-lint`, coverage gate) passes.
- [ ] Audit doc has no placeholders; every finding has a disposition.
EOF
)"
```

Expected: PR URL in output. Record it — plans 2-6 will reference this audit.

- [ ] **Step 3: Wait for CI and request review**

Run:

```bash
gh pr checks --watch
```

Expected: all checks pass. The merge itself is a human decision — the plan stops here.

---

## Definition of Done

- [ ] PR #66 merged on main.
- [ ] `docs/superpowers/audits/2026-04-21-baseline-audit.md` committed, with:
  - Outdated-package snapshot or "none" line.
  - Security findings table or "no findings" line, each finding dispositioned.
  - Per-plan disposition section, every plan covered.
- [ ] Plan 1 PR open with green CI.
- [ ] No production code changed in this plan (only the audit doc and the rebase of the roadmap branch).

---

## Rollback

- Nothing to roll back locally — only a doc was added.
- PR #66 rollback (if merge turns out to be wrong): revert via `gh pr revert 66` or a manual `git revert <merge-sha>` PR. Do not force-push main.
