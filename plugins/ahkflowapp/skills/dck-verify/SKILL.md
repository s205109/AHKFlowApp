---
name: dck-verify
description: Use when verifying AHKFlowApp build, tests, formatting, diagnostics, security, or readiness before commit, push, or PR.
---

# Verify

## Principle

Verification is evidence, not confidence. Report PASS, WARN, FAIL, or SKIP for each phase you run.

## Phase Selection

| Change | Phases |
|---|---|
| Feature, refactor, pre-PR | All 7 |
| Bug fix | Build, diagnostics, tests, diff |
| Dependency update | Build, tests, vulnerable packages, format |
| EF migration | Build, migration SQL review, tests, format, diff |
| Skill/docs only | Targeted text checks, setup script if skill surface changed, diff |
| Formatting only | Format check and diff |

When unsure, run the full pipeline.

## 7-Phase Pipeline

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

```bash
dotnet test --configuration Release --no-build --verbosity normal
```

For narrow changes, run affected test projects first, then broaden if risk warrants:

```bash
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --verbosity normal
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
```

Any failing test is FAIL.

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

Verdict: READY / NEEDS FIXES
```

Do not claim ready until the evidence is fresh.
