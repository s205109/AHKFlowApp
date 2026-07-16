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
can drift from AGENTS.md. Total saving is modest (~200 tok/session); the real win is
removing the drift risk and the misleading "never used" noise.

Evidence caveat: `/plugin` usage counts are Claude-only — no equivalent stats exist for
Copilot or Codex. The retirement rationale therefore rests on the redundancy argument,
which is cross-agent by construction (AGENTS.md is always-loaded for all three), not on
the usage counts, which merely corroborate. A skill only qualifies for deactivation if
its content is ported to or already present in AGENTS.md.

## Mechanism

`.claude/skills/README.md` documents deactivation: a skill dir with `REFERENCE.md` and no
`SKILL.md` is ignored by Claude Code, Copilot, and the Codex plugin.
`scripts/agents/setup-cross-agent-skills.ps1` auto-discovers `.agents/` subdirectories
(`Get-ChildItem`, line 104) — no hardcoded list to update.

Per skill: `git mv .agents/<skill>/SKILL.md .agents/<skill>/REFERENCE.md`, then re-run the
setup script once at the end to drop the projections in `.claude/skills/`, `.github/skills/`,
and `plugins/ahkflowapp/skills/`.

## Deactivate (6)

Each is ambient-triggered AND covered by an AGENTS.md section. The content diff against
AGENTS.md has been done; the "Port to AGENTS.md first" column is the migration decision
(resolved: port, never drop — a skill deactivates only after its unique rules land in
AGENTS.md):

| Skill | Lines | Covered by AGENTS.md section | Port to AGENTS.md first |
|---|---|---|---|
| `dck-modern-csharp` | 81 | Code Conventions / Patterns We DON'T Use | Nothing — fully covered |
| `dck-error-handling` | 271 | Architecture Rules (Ardalis.Result, ProblemDetails) | Nothing — fully covered |
| `dck-testing` | 341 | Testing | One line: `FakeTimeProvider` (from `Microsoft.Extensions.TimeProvider.Testing`) for time-dependent tests |
| `dck-httpclient-factory` | 143 | Tech Stack + Performance (IHttpClientFactory, resilience) | One line: disable retries for unsafe HTTP methods (`options.Retry.DisableForUnsafeHttpMethods()`) when the client performs non-idempotent calls |
| `dck-serilog` | 85 | Tech Stack (Serilog sinks) | Two lines: keep `CreateBootstrapLogger()` before host build and `Log.CloseAndFlushAsync()` on exit; `UseSerilogRequestLogging` after exception middleware; structured `{Property}` templates over interpolation; never log secrets/tokens |
| `dck-configuration` | 89 | Security + CI/CD (user-secrets, App Service config) | Two lines: options classes use `.BindConfiguration().ValidateDataAnnotations().ValidateOnStart()`; Blazor WASM `wwwroot/appsettings*.json` is public (downloadable) — never treat as secret |

## Keep

- **Fires or discrete trigger:** `dck-verify`, `dck-build-fix`, `dck-de-sloppify`,
  `dck-migration-workflow`, `dck-scaffolding`, `dck-security-scan`.
- **Unique content, not redundant:** `dck-ef-core` (ATTRIBUTION.md notes dotnet/skills
  `optimizing-ef-core-queries` guidance was merged in — AGENTS.md has none of it),
  `dck-openapi`, `dck-blazor-mudblazor`.
- **`dck-workflow-mastery`** — originally slated for deactivation, moved to Keep. It
  demonstrably fires (it matched and loaded during the review of this very plan), and its
  skill-change verification guidance (setup script + mirror/cache checks, plan-vs-live-checkout
  review) has no AGENTS.md counterpart — not redundant.
- **All `dn-*`:** discrete audit triggers ("audit this test file"). Never used because the
  audit was never requested — not redundant. Leave alone.

## Files touched

- `.agents/<skill>/SKILL.md` → `REFERENCE.md` for the 6 above (source of truth)
- `AGENTS.md` — the ported lines from the migration table (Testing, Performance/Tech Stack,
  Security sections); line 294 names verify/build-fix/de-sloppify, all kept
- `.agents/ATTRIBUTION.md` — no edit needed; none of the 6 are `dotnet/skills` vendored
- `scripts/agents/setup-cross-agent-skills.sh` line 25 — fix stale
  `$AGENTS_ROOT/plugins/plugins/ahkflowapp/skills` to `<repo-root>/plugins/ahkflowapp/skills`
  (the path the `.ps1` actually maintains); otherwise POSIX regeneration writes the wrong tree
- `.claude/skills/README.md` — fix the same stale path in the "Why three locations?" table
- `plugins/ahkflowapp/.codex-plugin/plugin.json` — bump `version` so the Codex reinstall
  below picks up the pruned skill set
- Regenerated, not hand-edited: `.claude/skills/`, `.github/skills/`, `plugins/ahkflowapp/skills/`

## Verification

1. `pwsh scripts/agents/setup-cross-agent-skills.ps1`
2. `pwsh tests/SkillParity.Tests.ps1` — canonical/plugin skill sets match, byte-identical
   (`check-symlinks.ps1` only lists entries; it validates nothing)
3. Confirm the 6 are gone from all three surfaces, the keepers survive, and remaining
   `.claude/skills/`/`.github/skills/` entries are symlinks resolving into `.agents/`:
   `ls .claude/skills/ .github/skills/ plugins/ahkflowapp/skills/`
4. `/plugin` in a fresh session — the 6 no longer listed; `dck-verify` et al. still `✓ on`
   (verifies Claude only)
5. Refresh the installed Codex plugin — repo regeneration does not touch Codex's install
   cache (see 2026-07-04 plan):
   `codex plugin remove ahkflowapp --marketplace ahkflowapp-local`
   `codex plugin add ahkflowapp --marketplace ahkflowapp-local`
   Then `codex plugin list` and inspect the installed cache folder: the 6 absent, keepers present.
6. `git status` — expect: 6 `.agents/` renames (SKILL.md → REFERENCE.md), 18 projection
   deletions (6 skills × 3 surfaces), plus edits to `AGENTS.md`,
   `setup-cross-agent-skills.sh`, `.claude/skills/README.md`, and `plugin.json`

## Out of scope

Not adding hooks or routing lines to CLAUDE.md. Worth noting for later: `playwright-cli` is
the only skill CLAUDE.md explicitly routes to, and it is also among the few that get used.
If the keepers still under-fire after this, adding named routing lines is the next lever.

## Unresolved

1. `dck-ef-core`/`dck-openapi`/`dck-blazor-mudblazor` kept, but ambient — leave, or deactivate too?
2. Branch name: `chore/prune-redundant-dck-skills`?
3. Ported Serilog/config lines grow AGENTS.md by ~6 lines — OK, or trim further?
