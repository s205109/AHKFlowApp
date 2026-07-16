# Matt Pocock Skills Adoption Plan — AHKFlowApp


## Context

Adopt selected skills from `mattpocock/skills` into AHKFlowApp's cross-agent skill system (`.agents/` canonical source, synced via `scripts/agents/setup-cross-agent-skills.ps1` to `.claude/skills/`, `.github/skills/`, and the Codex plugin). No `npx skills` installer — manual copy, `mp-` prefix convention, AHKFlow-owned adaptations (same fork policy as `dck-*`).

Verified against the current upstream repo and the current worktree:

- **Clean slate.** Commit `46ce04a "Removed skills"` deleted the earlier `mp-handoff` and `grilling` experiments; `.agents/` now contains only `dck-*`, `dn-*`, `playwright-cli`, `worktrees`. Everything below is a fresh copy.
- The earlier Codex `setup-matt-pocock-skills` run's output (AGENTS.md block, `docs/agents/*`, `CONTEXT.md`, ADRs) was also discarded — but those drafts are known-good starting material.
- Upstream dependency chain: `triage` → `grilling` + `domain-modeling` + `docs/agents/issue-tracker.md` + triage labels; `grill-with-docs` → `grilling` + `domain-modeling`; `grill-me` → thin wrapper over `grilling`; `improve-codebase-architecture` → `codebase-design` vocabulary + `grilling` + `domain-modeling` + `CONTEXT.md`/ADRs.

User decisions (this session): **GitHub Issues** as tracker; **adopt triage now**; **codebase-design concepts-only**; **defer improve-codebase-architecture**.

## Per-skill verdicts

| Skill | What it does (concise) | Verdict | Notes |
|---|---|---|---|
| `grilling` | Reusable relentless one-question-at-a-time interview loop | **Copy** → `mp-grilling` | Foundation for grill-me, grill-with-docs, triage. Complements (not duplicates) `superpowers:brainstorming` — grilling interrogates, brainstorming designs. |
| `grill-me` | User-invoked wrapper that starts a grilling session | **Copy (ref-rewrite only)** → `mp-grill-me` | Only change: `/grilling` → `/mp-grilling`. |
| `domain-modeling` | Actively maintains domain glossary (`CONTEXT.md`) + sparse ADRs; challenges terminology, tests edge cases against code | **Copy as-is (whole folder)** → `mp-domain-modeling` | Includes `CONTEXT-FORMAT.md` / `ADR-FORMAT.md` supporting files. High value: AGENTS.md Domain Terms already drift (prior session found Trigger/Replacement inconsistencies). No overlap with dck skills (they cover *how* to implement, not *what terms mean*). |
| `grill-with-docs` | Grilling session that updates CONTEXT.md/ADRs as decisions land | **Copy (ref-rewrite only)** → `mp-grill-with-docs` | Refs → `mp-grilling`, `mp-domain-modeling`. |
| `handoff` | Compact conversation into handoff doc for another agent | **Copy** → `mp-handoff` | Keep upstream `disable-model-invocation: true`. |
| `triage` | Issue state machine: category (bug/enhancement) + one of 5 states; verifies claims, grills, writes agent briefs | **Copy + adapt** → `mp-triage` | Copy whole folder (incl. `AGENT-BRIEF.md`, `OUT-OF-SCOPE.md`). Refs → `mp-grilling`, `mp-domain-modeling`. Requires `docs/agents/issue-tracker.md` + `triage-labels.md` + 5 GitHub labels. |
| `setup-matt-pocock-skills` | One-time repo config scaffolder (tracker, labels, domain-doc layout) | **Concepts-only (recommended)** — don't copy the skill; hand-write its outputs | Run-once skill; its exact outputs are known (drafted + approved in the prior Codex session). Copying a setup skill into the permanent skill set adds maintenance for zero recurring value. Unresolved Q1 if you disagree. |
| `codebase-design` | Design vocabulary: deep modules, seams, deletion test, locality | **Concepts-only** (per your decision) | ~6-rule "Abstraction and Module Design" section → `dck-scaffolding`; "test through the caller-facing interface" → `dck-testing`; one deletion-test line → AGENTS.md. Do NOT import the term-ban ("service", "component", "API") or the strict two-implementations rule. |
| `improve-codebase-architecture` | Scans for deepening opportunities, HTML report, grilling loop on selected candidate | **Defer** (per your decision) | Revisit once CONTEXT.md/ADRs exist and dck skills carry the design rules; will need adaptation to dck vocabulary since `mp-codebase-design` won't exist. |

**Other upstream skills checked, none adopted:** `ask-matt` (router for full set), `to-spec`/`to-tickets`/`implement`/`wayfinder` (not required by chosen skills; overlap superpowers plan workflow), `tdd`/`code-review`/`diagnosing-bugs` (overlap superpowers + dck-verify), `prototype`/`research`/`resolving-merge-conflicts`/`teach`/`writing-great-skills` (low marginal value; superpowers:writing-skills covers the last). None are hard dependencies of the adopted set.

## Adoption order (answers Q7)

**Wave 0 — Commit this plan:** save to `docs/superpowers/plans/2026-07-16-mp-skills-adoption-plan.md`, commit.

**Wave 1 — Foundation (grilling family + domain modeling + handoff), one PR:**
1. Copy into `.agents/`: `mp-grilling`, `mp-grill-me`, `mp-domain-modeling` (whole folder), `mp-grill-with-docs`, `mp-handoff`; rewrite internal refs to `mp-` names; rename `name:` frontmatter to match folders.
2. Add AHKFlow-owned-adaptation header comment to each (upstream: `mattpocock/skills`, update-policy: manual-selective-merge).
3. Add `mattpocock/skills` section + license to `.agents/ATTRIBUTION.md` (verify upstream license file first).
4. Run `setup-cross-agent-skills.ps1`; verify symlinks/hard links; commit.

**Wave 2 — Repo config (hand-written setup outputs), one PR:**
1. `docs/agents/issue-tracker.md` — GitHub template (prior session draft; PRs-as-request-surface: off).
2. `docs/agents/domain.md` — single-context layout.
3. `docs/agents/triage-labels.md` — five defaults (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`).
4. `## Agent skills` block in `AGENTS.md` (tracker + labels + domain docs pointers).
5. Document relationship: `.claude/backlog/` stays as personal backlog; inbound bugs/enhancements + triage flow live in GitHub Issues.

**Wave 3 — First domain-modeling session (interactive, uses the new skills):**
1. Run `mp-domain-modeling` to create `CONTEXT.md` — migrate (move, not copy) `## Domain Terms` from `AGENTS.md`, replacing it with a short pointer section.
2. Seed `docs/adr/` with genuinely qualifying ADRs only (prior session judged "EF context direct" redundant with AGENTS.md; "one script per profile" was the good example).

**Wave 4 — Triage, one PR:**
1. Copy `mp-triage` (+ supporting files) with ref rewrites.
2. Create the 5 labels in `s205109/AHKFlowApp` via `gh label create`.
3. Sync script + verify.

**Wave 5 — dck concept migration, one PR:**
1. `dck-scaffolding`: add "Abstraction and Module Design" section (deletion test; no interfaces solely for mocking/symmetry — real variation or external-system isolation justifies a seam; small caller-facing interfaces; locality as extraction criterion; no speculative helpers).
2. `dck-testing`: add "Test through the caller-facing interface" principle.
3. `AGENTS.md`: one line — "Abstractions must earn their place — apply the deletion test; avoid pass-through wrappers and interfaces created solely for mocking or symmetry."
4. Edit `.agents/dck-*` only; re-run sync script.

Deferred: `improve-codebase-architecture` (re-evaluate after Waves 1–5 bed in).

## Conventions applied throughout

- Canonical source `.agents/<skill>/SKILL.md`; never edit mirrors; run sync script after changes; `git diff --check`.
- All internal cross-skill references rewritten to `mp-` names.
- Worktree branch per wave (`feature/wt-mp-*` / `chore/wt-mp-*`), PR to main.

## Verification

- `setup-cross-agent-skills.ps1` runs clean; `.claude/skills/` shows `mp-grilling`, `mp-grill-me`, `mp-grill-with-docs`, `mp-domain-modeling`, `mp-handoff`, later `mp-triage` symlinks; Codex plugin hard links present.
- New session: skills appear in available-skills list; `/mp-grill-me` starts a grilling session; `mp-domain-modeling` triggers on terminology work.
- Wave 4: `gh label list` shows the five labels; test `mp-triage` on one real or dummy issue.
- `dotnet build`/`test` untouched (docs/skills only) — CI format check still passes.

## Unresolved questions

1. setup-matt-pocock-skills: hand-write outputs (rec) or copy skill, run once, then delete?
2. Existing `.claude/backlog/` items: migrate to GitHub Issues or keep both surfaces?
3. Move Domain Terms → CONTEXT.md in Wave 3 (rec) or keep duplicated for now?
4. Trim wayfinder section from issue-tracker.md template (no wayfinder skill adopted)?
5. Waves 1–2: separate PRs (rec) or combined?
