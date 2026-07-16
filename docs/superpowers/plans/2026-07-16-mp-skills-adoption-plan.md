# Matt Pocock Skills Adoption Plan — AHKFlowApp

## Context

Adopt selected skills from `mattpocock/skills` (MIT-licensed, verified) into AHKFlowApp's cross-agent skill system (`.agents/` canonical source, synced via `scripts/agents/setup-cross-agent-skills.ps1` to `.claude/skills/`, `.github/skills/`, and the Codex plugin). No `npx skills` installer — manual copy, `mp-` prefix convention, AHKFlow-owned adaptations (same fork policy as `dck-*`). Upstream snapshot pinned at commit `9603c1cc8118d08bc1b3bf34cf714f62178dea3b` — the baseline for future selective merges.

Verified facts:

- **Clean slate.** Commit `46ce04a "Removed skills"` deleted the earlier `mp-handoff`/`grilling` experiments (stale `mp-handoff` leftovers in `.github/skills/` and the plugin mirror were pruned on this branch). The untracked `.claude/skills/grilling/` folder (manual re-add for the grilling session) is **not** pruned by the sync script — it errors on non-symlink entries there. Wave 1 removes it explicitly before running the sync — superseded by `mp-grilling`.
- The Codex plugin mirror used to hard-link only `SKILL.md`; **fixed on this branch** — both sync scripts now mirror whole skill folders (companion files, seed templates, `agents/openai.yaml`) and `tests/SkillParity.Tests.ps1` compares full file trees. Prerequisite for the mp skills, which all ship companion files.
- The prior Codex `setup-matt-pocock-skills` run was a trial; its output was discarded. **The full setup will be run again interactively** (user decision).
- Upstream dependency chain: `triage` → `grilling` + `domain-modeling` + `docs/agents/issue-tracker.md` + triage labels; `grill-with-docs` → `grilling` + `domain-modeling`; `grill-me` → thin wrapper over `grilling`; `improve-codebase-architecture` → `codebase-design` vocabulary + `grilling` + `domain-modeling` + `CONTEXT.md`/ADRs.
- The setup skill only configures triage labels when it detects the triage skill installed, and upstream detection looks for a skill literally named `triage` (sibling folder or available-skill name) — it would not recognize `mp-triage`. The `mp-setup-matt-pocock-skills` adaptation rewrites that detection to `mp-triage`, and `mp-triage` must still be vendored **before** the setup runs.

## Decisions (all settled)

| Decision | Outcome |
|---|---|
| Issue tracker | GitHub Issues |
| Triage | Adopt now; skill vendored in Wave 1 |
| codebase-design | Concepts-only into dck skills |
| improve-codebase-architecture | Defer |
| setup-matt-pocock-skills | **Copy + adapt as `mp-setup-matt-pocock-skills`** (triage detection → `mp-triage`), run full setup interactively (Wave 2), keep afterwards with `disable-model-invocation: true` |
| `.claude/backlog/` | Keep both surfaces; no bulk migration; document backlog as personal pre-tracker surface, promote items to issues opportunistically |
| Domain Terms in AGENTS.md | **Move** to `CONTEXT.md` in Wave 3; replace with one-line pointer |
| Wayfinder section in issue-tracker.md template | Leave untouched (diff-clean vs upstream; inert without wayfinder skill) |
| PR granularity | Separate PR per wave |

## Per-skill verdicts

| Skill | What it does (concise) | Verdict | Notes |
|---|---|---|---|
| `grilling` | Reusable relentless one-question-at-a-time interview loop | **Copy** → `mp-grilling` | Foundation for grill-me, grill-with-docs, triage. Complements `superpowers:brainstorming` — grilling interrogates, brainstorming designs. Trim description to ≤140 chars (upstream 152). |
| `grill-me` | User-invoked wrapper starting a grilling session | **Copy (ref-rewrite only)** → `mp-grill-me` | Only change: `/grilling` → `/mp-grilling`. |
| `domain-modeling` | Maintains domain glossary (`CONTEXT.md`) + sparse ADRs; challenges terminology, tests edge cases against code | **Copy (whole folder)** → `mp-domain-modeling` | Includes `CONTEXT-FORMAT.md`/`ADR-FORMAT.md`. High value: AGENTS.md Domain Terms already drift. Trim description to ≤140 chars (upstream 216). |
| `grill-with-docs` | Grilling session that updates CONTEXT.md/ADRs as decisions land | **Copy (ref-rewrite only)** → `mp-grill-with-docs` | Refs → `mp-grilling`, `mp-domain-modeling`. |
| `handoff` | Compact conversation into handoff doc | **Copy** → `mp-handoff` | Keep upstream `disable-model-invocation: true`. |
| `triage` | Issue state machine: category + one of 5 states; verifies claims, grills, writes agent briefs | **Copy + adapt** → `mp-triage` (Wave 1) | Whole folder (incl. `AGENT-BRIEF.md`, `OUT-OF-SCOPE.md`). Refs → `mp-` names. |
| `setup-matt-pocock-skills` | One-time repo config scaffolder (tracker, labels, domain docs) | **Copy + adapt** → `mp-setup-matt-pocock-skills` (whole folder incl. seed templates); run in Wave 2; keep | Already `disable-model-invocation: true` upstream — retain. Adapt: triage detection must recognize `mp-triage` (upstream looks for literal `triage`). Trim description to ≤140 chars (upstream 183). |
| `codebase-design` | Design vocabulary: deep modules, seams, deletion test, locality | **Concepts-only** | ~6-rule section → `dck-scaffolding`; caller-facing-interface rule → `dck-testing`; deletion-test line → AGENTS.md. Do NOT import the term-ban or strict two-implementations rule. |
| `improve-codebase-architecture` | Scans for deepening opportunities, HTML report, grilling loop | **Defer** | Revisit after Waves 1–5; needs adaptation to dck vocabulary. |

**Other upstream skills checked, none adopted:** `ask-matt`, `to-spec`/`to-tickets`/`implement`/`wayfinder` (overlap superpowers plan workflow), `tdd`/`code-review`/`diagnosing-bugs` (overlap superpowers + dck-verify), `prototype`/`research`/`resolving-merge-conflicts`/`teach`/`writing-great-skills`. None are hard dependencies of the adopted set.

## Waves (one PR each)

**Wave 0 — done:** plan committed to `docs/superpowers/plans/2026-07-16-mp-skills-adoption-plan.md`. On approval: refresh with this revision, commit.

**Wave 1 — Vendor all seven skills:**
1. Copy into `.agents/`: `mp-grilling`, `mp-grill-me`, `mp-domain-modeling`, `mp-grill-with-docs`, `mp-handoff`, `mp-triage`, `mp-setup-matt-pocock-skills` (each whole folder, from upstream commit `9603c1c`); rewrite internal cross-refs to `mp-` names; `name:` frontmatter matches folder.
2. Adaptations: `mp-setup-matt-pocock-skills` triage detection → `mp-triage`; trim `description:` to ≤140 chars for `mp-grilling`, `mp-domain-modeling`, `mp-setup-matt-pocock-skills`.
3. AHKFlow-owned-adaptation header comment in each SKILL.md (upstream: `mattpocock/skills` @ `9603c1cc8118d08bc1b3bf34cf714f62178dea3b`, update-policy: manual-selective-merge).
4. Add `mattpocock/skills` (MIT) section to `.agents/ATTRIBUTION.md`, recording the pinned commit.
5. Explicitly delete the stray untracked `.claude/skills/grilling/` (the sync script errors on non-symlink entries there, it does not prune them); run `setup-cross-agent-skills.ps1`; verify symlinks/hard links; commit, PR.

**Wave 2 — Run the setup skill (interactive):**
1. Invoke `/mp-setup-matt-pocock-skills`; answer: GitHub Issues, default 5 triage labels, single-context domain docs.
2. Output: `docs/agents/issue-tracker.md` (wayfinder section left as upstream template), `docs/agents/triage-labels.md`, `docs/agents/domain.md`, `## Agent skills` block in `AGENTS.md`.
3. Add note: `.claude/backlog/` = personal pre-tracker surface; promote items to GitHub Issues opportunistically.
4. Commit, PR.

**Wave 3 — First domain-modeling session (interactive):**
1. Run `mp-domain-modeling` to create `CONTEXT.md`; **move** `## Domain Terms` out of `AGENTS.md`, leave one-line pointer.
2. Seed `docs/adr/` with genuinely qualifying ADRs only ("one script per profile" qualifies; "EF context direct" judged redundant with AGENTS.md).
3. Commit, PR.

**Wave 4 — Triage operational:**
1. `gh label create` the four missing state labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`) in `s205109/AHKFlowApp`; `wontfix` already exists (GitHub default) — reuse as-is. Keep existing `bug`/`enhancement` category mappings.
2. Live-test `mp-triage` on one real or dummy issue.
3. Commit any doc tweaks, PR (or direct if labels-only).

**Wave 5 — dck concept migration:**
1. `dck-scaffolding`: "Abstraction and Module Design" section (deletion test; no interfaces solely for mocking/symmetry — real variation or external-system isolation justifies a seam; small caller-facing interfaces; locality as extraction criterion; no speculative helpers).
2. `dck-testing`: "Test through the caller-facing interface" principle.
3. `AGENTS.md`: one line — "Abstractions must earn their place — apply the deletion test; avoid pass-through wrappers and interfaces created solely for mocking or symmetry."
4. Edit `.agents/dck-*` only; re-run sync script; commit, PR.

Deferred: `improve-codebase-architecture`.

## Conventions

- Canonical source `.agents/<skill>/SKILL.md`; never edit mirrors; sync script after changes; `git diff --check`.
- All internal cross-skill references rewritten to `mp-` names.
- Worktree branch per wave (`feature/wt-mp-*` / `chore/wt-mp-*`), PR to main.

## Verification

- Sync script clean (no description-budget WARN); `.claude/skills/` shows all seven `mp-*` symlinks; Codex plugin mirrors complete (companion files incl. `agents/openai.yaml` present); `tests/SkillParity.Tests.ps1` passes; stray `.claude/skills/grilling/` gone.
- New session: `/mp-grill-me` starts grilling; `mp-domain-modeling` triggers on terminology work; `/mp-setup-matt-pocock-skills` and `/mp-handoff` do not auto-trigger.
- Wave 4: `gh label list` shows all five triage state labels (four new + pre-existing `wontfix`); test triage run produces correct labels/comment (with AI-generated notice).
- CI unaffected (docs/skills only).

## Unresolved questions

None — all settled in the grilling session.
