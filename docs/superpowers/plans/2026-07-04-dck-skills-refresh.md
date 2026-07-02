# Refresh cck-* skills from dotnet-claude-kit, then rename to dck-

## Context

The project's agent skills (`.agents/<name>/SKILL.md`, symlinked into `.claude/skills/`, `.github/skills/`, and hard-linked into `.agents/plugins/plugins/ahkflowapp/skills/` for Codex) were originally sourced from `codewithmukesh/dotnet-claude-kit` under a `cck-` prefix. PR #156 (merged) removed MediatR project-wide and replaced it with an explicit use-case pattern (`IUseCase<TRequest,TResult>` → `ValidatingUseCase<TRequest,TResult>` → internal `IUseCaseHandler<TRequest,TResult>.ExecuteAsync()`), and updated most skills accordingly. The user then copied 18 fresh `SKILL.md` files from upstream into three staging folders (`.agents/_adapt`, `.agents/_updates`, `.agents/_candidates`, commit `67317f8` "temp skills") to review what's changed upstream and pull in anything valuable. This plan reconciles that staged content with the project's actual (fixed) architecture, decides what to add/reject, folds in a few upstream-repo features the user is considering (Roslyn-analysis MCP tooling), and finishes with the requested `cck-` → `dck-` rename.

Three research passes fed this plan: (1) a full read of all 12 active skills + the rules/hard-link/symlink setup, (2) a full read of all 18 staged files flagged against this project's real conventions, (3) a survey of the upstream repo's full 45-skill catalog, its 10 "rules", and its licensing.

## Decisions locked in (via brainstorming with user)

- **Install Roslyn Navigator MCP** (`CWM.RoslynNavigator` v0.7.1) so the richer verify/build-fix/de-sloppify content can use real code-navigation tools instead of being stripped down.
- **Keep Swashbuckle** — discard the `_candidates/openapi` file (it promotes .NET 10 built-in OpenAPI; not worth a real migration right now).
- **Keep `.claude/rules/` as-is** (`agents.md`, `hooks.md` only) — the other 8 upstream rules (coding-style, architecture, security, testing, performance, error-handling, git-workflow, packages) would duplicate `AGENTS.md`, which is already always-loaded via the `CLAUDE.md` `@../AGENTS.md` import.
- **No additional upstream skills** beyond the 18 already staged — skip `authentication`, `resilience`, `tdd`, `ci-cd` for this pass.
- **Strip references to upstream's 10 specialist subagents** (`dotnet-architect`, `refactor-cleaner`, `security-auditor`, etc.) — none exist in this project; skills must stay self-contained. MCP *tool* calls stay (since MCP is being installed), only the named-agent delegation language goes.
- **Skip Verify snapshot-testing library** — no current use case.
- **Discard `ddd` and `api-versioning` candidates entirely** — `ddd` prescribes aggregates + repository pattern (opposite of this project's fixed architecture); API versioning isn't needed yet and every example is Minimal-API/Mediator-based.

## Skill-by-skill disposition

### Keep content as-is, rename only (6)
`cck-blazor-mudblazor`, `cck-ef-core`, `cck-error-handling`, `cck-openapi`, `cck-security-scan`, `cck-testing` — already correctly reflect the explicit use-case pattern, SQL Server, Ardalis.Result, Swashbuckle. Their `_updates/*` counterparts (`ef-core`, `error-handling`, `security-scan`, `testing`) add nothing (Postgres examples, near-duplicate content, or a skipped snapshot-testing pattern) — discard those staged files.

### Not renamed, not touched (2)
`mp-handoff`, `playwright-cli` — never came from dotnet-claude-kit, no `cck-` prefix today, out of scope for the rename.

### Update in place, then rename (4)
- **`cck-migration-workflow` → `dck-migration-workflow`** (full rewrite — the stalest skill in the set): fix wrong project paths (use real `src/Backend/AHKFlowApp.Infrastructure` / `src/Backend/AHKFlowApp.API`), replace the nonexistent `dotnet outdated` tool with `dotnet list package --outdated`, remove invented example packages (`WolverineFx`, pinned Serilog version — contradicts AGENTS.md's "never pin/guess versions" rule), remove references to nonexistent `knowledge/*.md` docs and a "project-setup" skill. Use `_updates/migrate/SKILL.md` as a structural reference only, not a source of correct paths.
- **`cck-build-fix` → `dck-build-fix`**: merge in `_updates/build-fix`'s bounded-iteration-loop framing (iteration caps, STUCK/REGRESSION detection) on top of the existing project-specific error diagnosis (CS-code fixes, use-case DI registration errors). Keep MCP tool calls, strip "dotnet-architect agent" references per the agents decision.
- **`cck-scaffolding` → `dck-scaffolding`**: minor fix — entity example should use `private set` (matching real `Domain/Entities` like `Hotstring`, `Hotkey`) not a public setter. Discard `_updates/scaffold` and its `references/architecture-patterns.md` entirely — its Minimal-API/Mediator/DDD/Modular-Monolith templates are the direct inverse of this project's fixed architecture; nothing salvageable beyond a checklist concept the current skill already covers.
- **`cck-verify` → `dck-verify`**: adopt `_updates/verify`'s richer 7-phase pipeline (build → MCP diagnostics → MCP antipattern detection → tests → security-scan phase → format → git-diff review) with PASS/WARN/FAIL verdicts and phase selection by change type, now that Roslyn MCP is being installed. Fix the existing stale cross-reference ("the **build-fix** skill" → `dck-build-fix`). Strip specialist-agent references.

### Add as new skills, `dck-`-prefixed from the start (6)
- **`dck-httpclient-factory`** — low conflict; rewrite the one Minimal-API example (`app.MapPost("/charge", ...)`) into a controller action.
- **`dck-modern-csharp`** — C# 14/.NET 10 syntax reference (primary constructors, collection expressions, `field` keyword, pattern matching); complements, doesn't replace, AGENTS.md's "Patterns We Use" list.
- **`dck-serilog`** — comprehensive Serilog setup guide; project already mandates Serilog but has no dedicated skill for it.
- **`dck-configuration`** — despite sitting in `_updates`, no existing skill covers this topic. Rewrite the Key Vault example: this project currently uses **App Service Configuration** for prod secrets (Key Vault is documented as planned-but-not-provisioned) — describe the real current story (user-secrets locally → App Service Config in Azure), note Key Vault only as a future option.
- **`dck-de-sloppify`** — 7-step cleanup pipeline (format, unused usings, analyzer warnings, dead code, TODOs, seal classes, propagate `CancellationToken`). Keep MCP calls (`find_dead_code`, `detect_antipatterns`, `get_type_hierarchy`), strip the "refactor-cleaner agent" reference.
- **`dck-workflow-mastery`** — git worktrees, plan mode, verification loops, token/context discipline. Strip references to nonexistent companion skills (`instinct-system`, `architecture-advisor`, `convention-learner`) and specialist agents. Cross-reference this project's actual worktree hooks (`WorktreeCreate`/`WorktreeRemove` in `.claude/settings.json`) instead of assuming generic worktree setup.

### Discard entirely (remaining staged files)
`_candidates/ddd`, `_candidates/api-versioning`, `_candidates/openapi`, `_updates/ef-core`, `_updates/error-handling`, `_updates/security-scan`, `_updates/testing` — either architecturally incompatible or add no real value over what's already correct.

## Housekeeping

1. **Install Roslyn Navigator MCP**: `dotnet tool install -g CWM.RoslynNavigator` (v0.7.1, needs .NET 10 SDK — already in use). Create root `.mcp.json` (doesn't exist yet):
   ```json
   {
     "mcpServers": {
       "cwm-roslyn-navigator": { "command": "cwm-roslyn-navigator" }
     }
   }
   ```
2. **Attribution**: add `.agents/ATTRIBUTION.md` crediting `codewithmukesh/dotnet-claude-kit` (MIT, Mukesh Murugan) — satisfies MIT's notice-retention requirement since content was copied near-verbatim.
3. **Delete staging folders**: `.agents/_adapt/`, `.agents/_updates/`, `.agents/_candidates/` once their content is merged/adapted — they were an explicitly temporary "temp skills" commit.
4. **Repair the hard-link mirror**: 7 of 12 `.agents/plugins/plugins/ahkflowapp/skills/*` entries have silently degraded from hard links to plain copies (still content-identical today, but won't self-heal on the next direct edit). Re-run `scripts/setup-cross-agent-skills.ps1` after all content edits *and* again after the rename to regenerate `.claude/skills/`, `.github/skills/` symlinks and the plugin hard links correctly under the final `dck-` names.
5. **Rename (last step, per request)**: for all `cck-*` skills plus the 6 newly-added skills, rename the `.agents/<name>` directory and update the SKILL.md front-matter `name:` field to match (`mp-handoff`/`playwright-cli` excluded — never part of this kit). Re-run the setup script once more afterward.

## Verification

- Doc-only changes (no application code touched) — verify by grepping the whole `.agents/` tree for banned leftovers after edits: `MediatR|IRequestHandler|IMediator|Npgsql|ValidationFilter|dotnet-architect|refactor-cleaner|security-auditor|instinct-system|architecture-advisor|convention-learner` should return zero matches.
- After installing the MCP tool: confirm `cwm-roslyn-navigator` runs and, after a Claude Code restart, its tools are discoverable via `ToolSearch`.
- After the final rename + setup-script re-run: confirm `.claude/skills/dck-*` and `.github/skills/dck-*` resolve as symlinks, and `.agents/plugins/plugins/ahkflowapp/skills/dck-*/SKILL.md` are true hard links matching `.agents/dck-*/SKILL.md` content.
- `git status` should show the three staging folders gone and no leftover `.agents/cck-*` directories.

## Suggested sequencing (stacked PRs, per AGENTS.md git workflow)

1. Fix `cck-migration-workflow` staleness + repair the degraded hard-link mirror (independent, low risk).
2. Merge build-fix/verify upgrades + install Roslyn Navigator MCP + add `.mcp.json`.
3. Add the 6 new skills + `ATTRIBUTION.md`.
4. Final rename `cck-` → `dck-`, delete staging folders, re-run setup script.

## Unresolved questions

- `mp-handoff` SKILL.md front-matter says `name: handoff` (mismatches its `mp-handoff` dir) — fix while we're in the area, or leave alone?
- 4 stacked PRs OK, or squash some together?
- Attribution file at `.agents/ATTRIBUTION.md` OK, or prefer it under `docs/`?
