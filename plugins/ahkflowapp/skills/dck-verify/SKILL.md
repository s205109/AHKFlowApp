---
name: dck-verify
description: Use when verifying AHKFlowApp build, tests, formatting, diagnostics, security, runtime behavior, or readiness — after implementing a change, and before commit, push, or PR.
---

# Verify

## Principle

Verification is evidence, not confidence. Report PASS, WARN, FAIL, or SKIP for each phase you run.

## Phase Selection

| Change | Phases |
|---|---|
| Feature, refactor, pre-PR | All 8 |
| Bug fix | Build, diagnostics, tests, diff — **plus runtime when the bug had an observable symptom** |
| Dependency update | Build, tests, vulnerable packages, format |
| EF migration | Build, migration SQL review, tests, format, diff |
| Skill/docs only | Targeted text checks, setup script if skill surface changed, diff |
| Formatting only | Format check and diff |

When unsure, run the full pipeline.

## 8-Phase Pipeline

### 1. Build

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

FAIL on any build error. If this fails, use `dck-build-fix`.

### 2. Roslyn Diagnostics

Use Roslyn MCP when configured:

```text
get_diagnostics
```

Scope to changed files for narrow work; use the solution for broad refactors. Treat new errors as FAIL and new warnings as WARN unless the project already accepts them.

### 3. Antipattern Detection

Use Roslyn MCP when available:

```text
detect_antipatterns
```

Look especially for sync-over-async, `DateTime.Now`/`UtcNow`, missing `CancellationToken`, `new HttpClient()`, broad `catch (Exception)`, and EF read queries missing `AsNoTracking` where appropriate.

### 4. Tests

Pick the slice that covers what changed. `docs/development/testing-workflow.md` owns the mode
definitions and the canonical pre-PR gate — follow it rather than restating commands here.

```bash
pwsh .\scripts\test-fast.ps1 -Mode Fast          # domain, validators, bUnit
pwsh .\scripts\test-fast.ps1 -Mode Integration   # EF Core, API, CLI flows
pwsh .\scripts\test-fast.ps1 -Mode E2E           # browser, PWA, mobile viewport
pwsh .\scripts\test-fast.ps1 -Mode Coverage      # full gate before a PR
```

The script manages one disposable shared SQL container; plain `dotnet test` falls back to slower
per-project Testcontainers. Any failing test is FAIL.

### 5. Security and Packages

```bash
dotnet list AHKFlowApp.slnx package --vulnerable --include-transitive
```

Review changed files for hardcoded secrets, SQL concatenation, missing auth attributes, permissive CORS, disabled HTTPS/cert validation, and accidental `.env` or credential files.

### 6. Format

Target the solution explicitly:

```bash
dotnet format AHKFlowApp.slnx --verify-no-changes
```

If line-ending drift or formatting changes are reported:

```bash
dotnet format AHKFlowApp.slnx
dotnet format AHKFlowApp.slnx --verify-no-changes
```

### 7. Diff Review

```bash
git status --short
git diff --stat
git diff --check
```

Inspect the diff for accidental files, debug leftovers, secrets, stale references, and changes outside the task.

### 8. Runtime Verification

The other seven phases prove the code compiles and the existing suite still passes. None of them
exercise the change. This phase does.

Route on what surface changed — the table in `AGENTS.md` under **Verification After Implementation**
is authoritative. In short:

| Changed | Evidence |
|---|---|
| Blazor UI flow | A new or extended `*FlowTests.cs` in `tests/AHKFlowApp.E2E.Tests`, green under `-Mode E2E` |
| UI, visual only | A `playwright-cli` drive of the running app plus a screenshot |
| API, use case, EF Core | An integration test covering the new behavior, green under `-Mode Integration` |
| CLI | A `CLI.Tests` integration flow, green under `-Mode Integration` |
| Emitted `.ahk` | An assertion on the generated text; manual AHK steps only for a construct never shipped before |
| Bug fix with an observable symptom | The original repro re-run, showing the symptom gone |

Prefer a durable test over a one-off drive — a test keeps proving the behavior after this session.

Report the artifact by path, not as a claim. SKIP is allowed only for one of the three exemptions in
`AGENTS.md`, and the exemption must be named. For the refactor exemption, name the covering tests and
paste their fresh output.

## Skill Surface Verification

When `.agents/*` skills change:

```bash
pwsh -NoProfile -File scripts/agents/setup-cross-agent-skills.ps1
```

Then verify:

```bash
Get-ChildItem -Directory .claude/skills | Select-Object -ExpandProperty Name
Get-ChildItem -Directory .github/skills | Select-Object -ExpandProperty Name
fsutil hardlink list ".agents/dck-verify/SKILL.md"
codex plugin list
```

For renamed skills, confirm no stale `.agents/cck-*` directories remain and the Codex plugin cache was refreshed if the active Codex plugin should see the new names.

## Final Report

```markdown
| Phase | Result | Evidence |
|---|---|---|
| Build | PASS | 0 errors |
| Diagnostics | SKIP | Roslyn MCP unavailable in this session |
| Tests | PASS | Failed: 0 |
| Format | PASS | verify-no-changes exit 0 |
| Diff | WARN | docs-only changes plus plugin cache refresh |
| Runtime | PASS | HotkeysCrudFlowTests.CreateRunHotkey_... green under -Mode E2E |

Verdict: READY / NEEDS FIXES
```

Do not claim ready until the evidence is fresh.

`Runtime = SKIP` blocks `READY` unless the Evidence cell names one of the three `AGENTS.md`
exemptions. Green build and green tests are not runtime evidence.
