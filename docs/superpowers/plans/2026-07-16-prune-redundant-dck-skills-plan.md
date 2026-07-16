# Prune redundant dck-* knowledge skills

## Context

`/plugin` reports most `dck-*` and `dn-*` skills as "never used". This is not a bug —
discovery, symlinks, and frontmatter are all verified healthy, and `dck-verify` (4x),
`grilling` (7x), `find-skills` (2x) prove skill election works in this repo.

Two real causes:

1. **Ambient vs. discrete triggers.** "Use when writing C#" describes a continuous state
   with no moment where the agent stops to load a reference. "Verify before commit" is a
   moment. The ones with discrete triggers fire; the ambient ones never do.
2. **Redundancy with AGENTS.md.** AGENTS.md already encodes modern-C# conventions, error
   handling via Ardalis.Result, the testing strategy, HttpClient resilience, Serilog, and
   configuration/secrets rules — always-loaded. The matching skills have no gap to fill.

The upstream kit (`codewithmukesh/dotnet-claude-kit`) separates an always-loaded *rules*
layer from on-demand *knowledge* skills. This repo flattened the rules into AGENTS.md but
kept the skills, so they duplicate content that is already in context.

Outcome: retire the ambient skills whose content AGENTS.md already covers. Each one costs
~33 tok/session of description that never pays off, and is a second source of truth that
can drift from AGENTS.md. Total saving is modest (~230 tok/session); the real win is
removing the drift risk and the misleading "never used" noise.

## Mechanism

`.claude/skills/README.md` documents deactivation: a skill dir with `REFERENCE.md` and no
`SKILL.md` is ignored by Claude Code, Copilot, and the Codex plugin.
`scripts/agents/setup-cross-agent-skills.ps1` auto-discovers `.agents/` subdirectories
(`Get-ChildItem`, line 104) — no hardcoded list to update.

Per skill: `git mv .agents/<skill>/SKILL.md .agents/<skill>/REFERENCE.md`, then re-run the
setup script once at the end to drop the projections in `.claude/skills/`, `.github/skills/`,
and `plugins/ahkflowapp/skills/`.

## Deactivate (7)

Each is ambient-triggered AND covered by an AGENTS.md section:

| Skill | Lines | Covered by AGENTS.md section |
|---|---|---|
| `dck-modern-csharp` | 81 | Code Conventions / Patterns We DON'T Use |
| `dck-error-handling` | 271 | Architecture Rules (Ardalis.Result, ProblemDetails) |
| `dck-testing` | 341 | Testing |
| `dck-httpclient-factory` | 143 | Tech Stack + Performance (IHttpClientFactory, resilience) |
| `dck-serilog` | 85 | Tech Stack (Serilog sinks) |
| `dck-configuration` | 89 | Security + CI/CD (user-secrets, App Service config) |
| `dck-workflow-mastery` | 88 | Meta-guidance about agent workflow; pure overhead |

Before deactivating each, diff its content against the named AGENTS.md section. If a skill
carries a concrete rule AGENTS.md lacks, port that one line into AGENTS.md first — do not
lose it. Expect this to be rare; the skills are mostly code examples of rules already stated.

## Keep

- **Fires or discrete trigger:** `dck-verify`, `dck-build-fix`, `dck-de-sloppify`,
  `dck-migration-workflow`, `dck-scaffolding`, `dck-security-scan`.
- **Unique content, not redundant:** `dck-ef-core` (ATTRIBUTION.md notes dotnet/skills
  `optimizing-ef-core-queries` guidance was merged in — AGENTS.md has none of it),
  `dck-openapi`, `dck-blazor-mudblazor`.
- **All `dn-*`:** discrete audit triggers ("audit this test file"). Never used because the
  audit was never requested — not redundant. Leave alone.

## Files touched

- `.agents/<skill>/SKILL.md` → `REFERENCE.md` for the 7 above (source of truth)
- `AGENTS.md` — only if porting a rule; line 294 names verify/build-fix/de-sloppify, all kept
- `.agents/ATTRIBUTION.md` — no edit needed; none of the 7 are `dotnet/skills` vendored
- Regenerated, not hand-edited: `.claude/skills/`, `.github/skills/`, `plugins/ahkflowapp/skills/`

## Verification

1. `pwsh scripts/agents/setup-cross-agent-skills.ps1`
2. `pwsh scripts/agents/check-symlinks.ps1` — no broken links
3. Confirm the 7 are gone from all three surfaces and the keepers survive:
   `ls .claude/skills/ .github/skills/ plugins/ahkflowapp/skills/`
4. `/plugin` in a fresh session — the 7 no longer listed; `dck-verify` et al. still `✓ on`
5. `git status` — only the intended renames

## Out of scope

Not adding hooks or routing lines to CLAUDE.md. Worth noting for later: `playwright-cli` is
the only skill CLAUDE.md explicitly routes to, and it is also among the few that get used.
If the keepers still under-fire after this, adding named routing lines is the next lever.

## Unresolved

1. Port-or-drop if a skill has a rule AGENTS.md lacks — port into AGENTS.md, or drop it?
2. `dck-ef-core`/`dck-openapi`/`dck-blazor-mudblazor` kept, but ambient — leave, or deactivate too?
3. Branch name: `chore/prune-redundant-dck-skills`?
