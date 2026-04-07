---
name: cck-verify
description: >
  Run verification commands to confirm the project builds, all tests pass, and
  code is properly formatted before committing or creating a PR.
  Load when: "verify", "check build", "run tests", "before commit", "before PR",
  "does it build", "are tests passing", "/verify".
---

# Verify

Run these steps in order before any commit or PR. All must pass.

## Step 1 — Restore and Build

```bash
dotnet restore && dotnet build --configuration Release --no-restore
```

Expected: `Build succeeded.` with 0 errors, 0 warnings (or known acceptable warnings only).

If build fails: stop and fix before continuing. See the **build-fix** skill.

## Step 2 — Run All Tests

```bash
dotnet test --configuration Release --no-build --verbosity normal
```

Expected: All tests pass. `Failed: 0`.

If tests fail: stop and fix before continuing. See the **build-fix** skill.

### Run a Single Test Project

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --verbosity normal
dotnet test tests/AHKFlowApp.Application.Tests --configuration Release --verbosity normal
dotnet test tests/AHKFlowApp.Domain.Tests --configuration Release --verbosity normal
```

### Run a Single Test by Name

```bash
dotnet test tests/AHKFlowApp.API.Tests --filter "FullyQualifiedName~HotstringsControllerTests"
```

## Step 3 — Format Check

```bash
dotnet format --verify-no-changes
```

Expected: exits with code 0, no output. If it reports files need formatting, run `dotnet format` to fix.

## Step 4 — Git Status Check

```bash
git status
```

Expected: Only the files you intended to change are modified. No accidental changes to:
- `appsettings.json` (should not contain secrets)
- `.env` files
- Migration files you didn't intend to add
- Binary files

## Quick Reference

| Command | Purpose |
|---|---|
| `dotnet build --configuration Release` | Verify compilation |
| `dotnet test --configuration Release --no-build` | Run all tests |
| `dotnet test tests/<Project> --configuration Release` | Run single project |
| `dotnet test --filter "FullyQualifiedName~<Name>"` | Run single test |
| `dotnet format --verify-no-changes` | Check formatting |
| `dotnet format` | Fix formatting |
| `git status` | Check for unexpected changes |

## When to Use

- Before every `git commit`
- Before creating a PR
- After a merge from main (to catch integration issues)
- After adding a NuGet package (ensure restore + build succeed)
- After adding an EF Core migration (ensure migration compiles)

## Success Indicators

- `Build succeeded.` — no errors
- `Passed! - Failed: 0` — all tests green
- `dotnet format` exits silently — no formatting violations
- `git status` shows only expected files

## Failure Indicators

- Any `Error` in build output → fix before committing
- `Failed: N` in test output → fix before committing
- `dotnet format` lists files → run `dotnet format` to fix, then re-verify
