# Claude Code Context Cleanup — Implementation Plan

> **For agentic workers:** Execute task-by-task. Steps use `- [ ]` syntax for tracking. Verify token savings after each phase.

**Goal:** Reduce always-on Claude Code context for this repo by ~2k tokens via plugin pruning, scope dedup, and AGENTS.md dedup — without losing functionality.

**Approach:** Three independent phases. Each ends with a verification step. Phases ordered by ROI.

**Stack touched:** Claude Code CLI (`claude plugin` commands), AGENTS.md, no application code.

---

## Baseline (measure first)

- [ ] **Step 0.1: Capture baseline token counts**

Run in this Claude Code session: `/context`

Record current values for: Memory files total, Skills total, Custom agents total, "Plugin (...)" subtotals.

Current observed baseline (from this session):
- Memory files: 5.8k
- Skills: 3k
- Custom agents: 201 tok

After-cleanup target: Memory files ≤ 5.0k, Custom agents ~50 tok, plugin always-on overhead reduced by ~1.6k.

---

## Phase 1: Disable low-ROI plugins (biggest win)

**Files:** None (CLI state changes). Plugin state persists in `~/.claude/`.

**Plugins to disable** (confirmed token cost via `claude plugin details`):

| Plugin | Always-on tok | Reason |
|---|---|---|
| `pr-review-toolkit` | ~1,404 | 6 always-loaded agents; `code-review` plugin covers PR review |
| `frontend-design` | ~59 | MudBlazor is opinionated; skill targets bespoke UI |
| `skill-creator` | ~75 | `microsoft-skill-creator` (in microsoft-docs) covers .NET skill authoring |
| `claude-code-setup` | ~92 | `claude-automation-recommender` is one-shot; re-enable on demand |

**Total savings: ~1.6k always-on tokens.**

- [ ] **Step 1.1: Disable pr-review-toolkit (user scope)**

Run: `claude plugin disable pr-review-toolkit --scope user`
Expected: "Plugin pr-review-toolkit disabled"

- [ ] **Step 1.2: Disable frontend-design**

Run:
```
claude plugin disable frontend-design --scope user
claude plugin disable frontend-design --scope project
```
Both scopes are enabled today; both must be disabled.

- [ ] **Step 1.3: Disable skill-creator**

Run: `claude plugin disable skill-creator --scope user`

- [ ] **Step 1.4: Disable claude-code-setup**

Run: `claude plugin disable claude-code-setup --scope user`

- [ ] **Step 1.5: Verify disables took effect**

Run: `claude plugin list 2>&1 | rg "pr-review-toolkit|frontend-design|skill-creator|claude-code-setup" -A1`
Expected: all four show `Status: ✘ disabled` for all listed scopes.

- [ ] **Step 1.6: Commit nothing (CLI state, not repo state)**

Plugin enable/disable state lives in `~/.claude/`, not in the repo. No commit needed.

---

## Phase 2: Drop duplicate user-scope copies

**Context:** Six plugins are installed at both user and project scope. User decision: keep project-scope copies (version-controlled in `.claude/`), drop user-scope duplicates.

**Plugins to drop user-scope copy of:**
- claude-md-management
- code-review
- csharp-lsp
- feature-dev
- frontend-design (already disabled in Phase 1; user scope still installed)
- playwright

**Files:** None directly. Settings live in `~/.claude/settings.json` and project `.claude/settings.json`. The `claude plugin uninstall --scope user` command edits the user file.

- [ ] **Step 2.1: Check uninstall command syntax**

Run: `claude plugin uninstall --help`
Expected: shows `--scope <scope>` option.

- [ ] **Step 2.2: Uninstall claude-md-management user copy**

Run: `claude plugin uninstall claude-md-management --scope user`
Expected: removes user-scope entry; project-scope entry remains.

- [ ] **Step 2.3: Uninstall code-review user copy**

Run: `claude plugin uninstall code-review --scope user`

- [ ] **Step 2.4: Uninstall csharp-lsp user copy**

Run: `claude plugin uninstall csharp-lsp --scope user`

- [ ] **Step 2.5: Uninstall feature-dev user copy**

Run: `claude plugin uninstall feature-dev --scope user`

- [ ] **Step 2.6: Uninstall frontend-design user copy**

Run: `claude plugin uninstall frontend-design --scope user`
(Project scope was disabled in Phase 1, but kept installed since it's in repo settings.)

- [ ] **Step 2.7: Uninstall playwright user copy**

Run: `claude plugin uninstall playwright --scope user`

- [ ] **Step 2.8: Verify only project-scope copies remain**

Run: `claude plugin list 2>&1 | rg "claude-md-management|^  ❯ code-review|csharp-lsp|feature-dev|^  ❯ frontend-design|^  ❯ playwright@" -A2`
Expected: each plugin appears exactly once with `Scope: project`.

- [ ] **Step 2.9: Decision point — abort if any plugin disappears entirely**

If verification shows a plugin missing entirely (not in project either), STOP. The project-scope install may have depended on the user-scope cache. Re-install at project scope with: `claude plugin install <name>@claude-plugins-official --scope project`.

---

## Phase 3: Dedupe AGENTS.md

**File:** `C:\Dev\segocom-github\AHKFlowApp\AGENTS.md`

**Duplications confirmed (verified by reading the file):**

1. **Naming** section appears twice:
   - Lines 98-104 under `## Code Conventions > ### Naming`
   - Lines 157-166 under `## Rules > ### Naming`
   - The `## Rules` version is more complete (adds Validators, EF configurations, Delete commands)

2. **Testing** section appears twice:
   - Lines 140-153 under `## Testing`
   - Lines 200-209 under `## Rules > ### Testing`
   - Largely overlapping. The top-level `## Testing` has 3 unique bullets (TDD-first guidance, Test alongside, Skip-list, "Test behavior not implementation") that the Rules version lacks.

**Strategy:** Keep the top-level `## Testing` section (richer guidance), drop the duplicate `### Testing` from `## Rules`. For Naming, keep the more complete `## Rules > ### Naming`, delete the shorter `## Code Conventions > ### Naming`.

Estimated savings: ~600-1000 tokens from AGENTS.md (loaded into every session).

- [ ] **Step 3.1: Delete the shorter Naming block from Code Conventions**

In `AGENTS.md`, delete lines 98-105 (inclusive of blank line after):

```markdown
### Naming
- Controllers: plural (`HotstringsController`, `ProfilesController`)
- DTOs: `{Entity}Dto`, `Create{Entity}Dto`, `Update{Entity}Dto` (records)
- Commands: `Create{Entity}Command`, `Update{Entity}Command`
- Queries: `Get{Entity}Query`, `List{Entities}Query`
- Handlers: `{Command/Query}Handler`
- Async methods: `*Async` suffix

```

The `## Code Conventions` heading and its `### Patterns We Use` / `### Patterns We DON'T Use` subsections stay.

- [ ] **Step 3.2: Delete the duplicate Testing block from Rules**

In `AGENTS.md`, delete lines 200-210 (the `### Testing` subsection under `## Rules`):

```markdown
### Testing

- **Integration tests first** — WebApplicationFactory + Testcontainers catches serialization, middleware, DI, and query bugs.
- **Never `UseInMemoryDatabase`** — different behavior from real providers. Always use Testcontainers (SQL Server).
- **NSubstitute for third-party boundaries only** — don't mock what you own (no mocking DbContext, repositories, or internal services).
- Test naming: `MethodName_Scenario_ExpectedResult`.
- AAA pattern (Arrange/Act/Assert) with blank line separation; one assertion concept per test.
- Assert on `Result.IsSuccess` / `Result.Status` in handler unit tests.
- Shared fixtures: `IClassFixture<T>`, `ICollectionFixture<T>` for expensive setup (containers).
- Frameworks: xUnit, FluentAssertions, NSubstitute.

```

The top-level `## Testing` (currently lines 140-153) is the surviving canonical source.

- [ ] **Step 3.3: Move Naming under Rules to be the canonical Naming**

After Step 3.1, the file has only ONE `### Naming` (the one currently at lines 157-166 under `## Rules`). That's fine — no further structural change needed. The `## Rules > ### Naming` heading stays.

- [ ] **Step 3.4: Verify AGENTS.md still parses and reads cleanly**

Re-read the modified `AGENTS.md` and confirm:
- Exactly one `### Naming` heading
- Exactly one `### Testing`-related section (the top-level `## Testing`)
- No orphan headings or broken markdown

- [ ] **Step 3.5: Commit on a feature branch**

Memory rule: NO direct commits to main. All work goes on feature branches via PR.

```
git checkout -b chore/agents-md-dedup
git add AGENTS.md
git commit -m "chore: dedupe AGENTS.md naming + testing sections

Removes duplicated Naming and Testing subsections that appeared in
both top-level sections and the Rules section. Saves ~600-1000
always-on context tokens."
```

- [ ] **Step 3.6: Open PR**

Run: `gh pr create --base main --title "chore: dedupe AGENTS.md" --body "Removes duplicated Naming and Testing sections from AGENTS.md to reduce always-on context. No semantic changes — kept the more complete version of each."`

---

## Phase 4: Verify total savings

- [ ] **Step 4.1: Restart Claude Code session**

Plugin enable/disable changes require a session restart to take effect (per `claude plugin update --help` note).

- [ ] **Step 4.2: Re-run /context and compare**

Run: `/context`

Expected deltas vs baseline:
- Skills total: down by ~250-300 tok (3 removed skills: frontend-design, skill-creator, claude-automation-recommender)
- Custom agents: down by ~150 tok (6 pr-review-toolkit agents gone, but no longer pre-loaded)
- Plugin always-on (aggregated): down by ~1.6k tok
- Memory files: down by ~600-1000 tok (AGENTS.md dedup, once PR merged)

If total free space gain is < 1.5k tokens, investigate which step under-delivered.

---

## Self-Review

**Spec coverage:**
- ✅ Plugin disables (Phase 1)
- ✅ AGENTS.md dedup (Phase 3)
- ✅ Scope dedup (Phase 2) — added per user clarification
- ✅ Verification (Phase 4)

**No placeholders:** all commands literal, all line numbers cite the read file.

**Type/name consistency:** plugin names match `claude plugin list` exactly.

**Risk:** Phase 2 uninstall could remove a needed plugin if project-scope copy depends on user-scope cache. Step 2.9 handles this — abort and reinstall at project scope if needed.

---

## Unresolved questions

None — both clarifications answered up front.
