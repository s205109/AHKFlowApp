# CLI UX Consistency Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One pass over the COMPLETE CLI surface (auth, downloads, hotstring, hotkey, category, profile) making flags, `--json` output, error messages, exit codes, and `--help` copy uniform — plus the deferred `--category` association flags. (Spec: [CLI Production Readiness](../specs/2026-07-04-cli-production-readiness-design.md), plan 5.)

**Architecture:** Audit-then-fix. No new features beyond the `--category` flags; everything else is normalization of what plans 1-4 and the pre-existing commands built.

**Tech Stack:** .NET 10, System.CommandLine, xUnit + FluentAssertions.

## Global Constraints

- **Prerequisite:** CLI plans 1-4 merged. If any is missing, stop.
- Feature branch `feature/cli-ux-consistency`, PR to `main`.
- Verification trio per task: `dotnet build AHKFlowApp.slnx` · `dotnet test tests/AHKFlowApp.CLI.Tests --configuration Release` · `dotnet format AHKFlowApp.slnx --verify-no-changes`.
- Behavior changes only where the audit finds divergence; every change updates the affected tests in the same commit.
- Spec decision #3: NO `--quiet`/`--no-color` — do not add them.
- No backend changes.

## Resume instructions

`git log --oneline -10` shows landed commits; unchecked boxes remain. T1's audit table (in the PR description) drives T2-T5 — regenerate it if resuming cold.

---

### Task 1: Audit (read-only, no commit)

- [ ] **Step 1:** Build the audit table — for every command (`login`, `logout`, `download ahk`, `download zip`, and the 5 verbs × 4 verticals), record: flags + aliases, argument addressing, `--json` envelope shape, error-handling mechanism (CliErrors vs copied chain vs `DownloadCommandRunner`), exit codes used, help text first line. Sources: every file under `src/Tools/AHKFlowApp.CLI/Commands/`, `Output/`.
- [ ] **Step 2:** Mark divergences against these canonical rules (from plans 1-4):
  - Aliases: `--profile/-p`, `--search/-s/--grep/-g`, `--description/-d`, `--name/-n`, `--trigger/-t`, `--replacement/-r`, `--key/-k`, `--json` (no alias), `--page`/`--page-size` (no alias).
  - Paged list JSON envelope: `{ items, page, pageSize, totalCount }`; single objects: bare object. Same property casing everywhere (`JsonSerializerOptions.Web`).
  - Not-found message shape: `<Entity> '<target>' not found.` → exit 2. Success-mutation shape: `<Verb>ed <entity> '<key>' (<id>).`
  - Every command's help description: imperative, ends with a period.
  - Exit codes: 0/1/2/3 exactly as the contract in plans 1-4.
- [ ] **Step 3:** Paste the table + divergence list into the PR description (opened as draft now).

### Task 2: Consolidate error handling

**Files:**
- Modify: any command still carrying a copied catch chain → wrap with `Services/CliErrors.RunAsync`
- Inspect: `Commands/Downloads/DownloadCommandRunner.cs` — it predates `CliErrors` and additionally handles `ProfileNotFoundException`. Fold that clause into `CliErrors` (catch `ProfileNotFoundException` → stderr message → 2) and delete the runner if nothing else remains, or leave the runner delegating to `CliErrors` if it carries download-specific logic (binary stdout). Decide from the code, note the choice in the commit body.
- Test: `tests/AHKFlowApp.CLI.Tests/Services/CliErrorsTests.cs` + affected command tests

- [ ] **Step 1:** Extend `CliErrorsTests` for any newly folded clause; run → FAIL. **Step 2:** consolidate. **Step 3:** full CLI tests → PASS; trio. **Commit** `refactor(cli): single error-handling path for all commands`

### Task 3: Normalize flags, messages, help copy

**Files:** every divergence T1 found (commands + formatters + their tests)

- [ ] **Step 1:** Apply the canonical rules; adjust tests in the same edit. Breaking flag renames are acceptable (no release yet — pre-1.0 surface), but keep old aliases when free (an extra alias costs nothing).
- [ ] **Step 2:** Trio + full CLI tests. **Commit** `fix(cli): uniform flags, messages, help copy`

### Task 4: Normalize `--json` output

**Files:** `Output/*Formatter.cs` + tests

- [ ] **Step 1:** Assert every paged list emits the same envelope and every single-object emits the bare object with `JsonSerializerOptions.Web` casing; unify any formatter that diverges. Add one cross-cutting test `Output/JsonEnvelopeConventionTests.cs` that runs each list formatter against a sample page and asserts the same top-level property names.
- [ ] **Step 2:** Trio. **Commit** `fix(cli): uniform json envelopes`

### Task 5: `--category` association flags (deferred from plans 1-2)

**Files:**
- Modify: `Commands/Hotstrings/NewHotstringCommand.cs`, `UpdateHotstringCommand.cs`, `Commands/Hotkeys/NewHotkeyCommand.cs`, `UpdateHotkeyCommand.cs` (+ their tests)
- Consumes: `ICategoriesApiClient` (plan 3), `CategoryResolver` matching pattern

Flag: `--category/-c` (repeatable, category NAME, resolved to ids via plan 3's paging `CategoryResolver.ResolveAsync` — NOT a single `ListAsync` page, since the API caps `pageSize` at 200; unknown name → stderr `Category '<name>' not found. Run 'ahkflow category list' to see available categories.` exit 2). On `update`, `--category` replaces the set; omitting it preserves the current set (read-modify-write already does).

- [ ] **Step 1:** Unit tests: create with 2 categories (assert `CategoryIds` in POST body), unknown category → 2, update replaces set, omit preserves. **Step 2:** implement on all four commands. **Step 3:** integration: extend hotstring + hotkey integration flows with a category association step. **Step 4:** trio + full solution tests. **Commit** `feat(cli): --category association on hotstring/hotkey new+update`

### Task 6: End-to-end smoke of the full surface

- [ ] **Step 1:** Against a local API (`Auth:UseTestProvider`): run one happy-path command per verb per vertical (20 commands), plus one failure per exit-code class (validation 2, auth 3 via `ahkflow logout` first, server 1 via stopped API). Record a transcript.
- [ ] **Step 2:** Paste the transcript into the PR; fix anything that reads wrong (message wording counts as a finding).
- [ ] **Step 3:** Full solution `dotnet test --configuration Release` + trio. **Commit** (if fixes) `fix(cli): smoke findings`

---

## Final verification

- [ ] Audit table in PR shows zero remaining divergences
- [ ] One error-handling path; `grep -rn "catch (ApiException" src/Tools/AHKFlowApp.CLI/Commands` → only via CliErrors (no inline chains)
- [ ] Verification trio + full solution tests green
