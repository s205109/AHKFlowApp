---
name: build-fix
description: >
  Diagnose and fix build failures, test failures, and formatting violations in AHKFlowApp.
  Load when: "build error", "build failed", "test failed", "compilation error",
  "CS error", "fix build", "tests are failing", "broken build", "lint error",
  "format error", "migration error".
---

# Build Fix

## Diagnosis Flow

### 1. Read the Error Message Exactly

Run the build and read the full error output:

```bash
dotnet build --configuration Release 2>&1
```

Errors contain: file path, line number, error code (e.g., `CS0246`), and description. Read all of it before acting.

### 2. Identify the Root Cause

- **CS0246 / CS0234** — Type or namespace not found → missing `using`, wrong namespace, or missing package reference
- **CS0103** — Name does not exist → typo, wrong scope, or missing `using`
- **CS1061** — Type does not contain definition → method/property doesn't exist on that type, check the type
- **CS0161** — Not all code paths return → missing `return` in a branch
- **CS8618** — Non-nullable property uninitialized → add `= null!` or initialize in constructor
- **CS0115** — No suitable method to override → method signature mismatch with base class

### 3. Find Where Types Are Defined

Use Grep to locate type definitions:

```bash
# Find where a class or interface is defined
grep -r "class CreateHotstringCommand" src/
grep -r "interface IMediator" src/

# Find which namespace a type belongs to
grep -r "namespace.*Application" src/Backend/AHKFlowApp.Application/
```

### 4. Fix Root Cause — Not Symptom

Fix the actual problem, not just make the error go away. A suppression (`#pragma warning disable`) is almost never the right fix.

## Common Issues and Fixes

### Missing Package Reference

```bash
# Check what packages are installed
cat src/Backend/AHKFlowApp.Application/AHKFlowApp.Application.csproj

# Add missing package (no version — gets latest stable)
dotnet add src/Backend/AHKFlowApp.Application package Ardalis.Result
dotnet add src/Backend/AHKFlowApp.API package Ardalis.Result.AspNetCore
dotnet add src/Backend/AHKFlowApp.Application package MediatR
dotnet add src/Backend/AHKFlowApp.Application package FluentValidation
```

After adding packages, wait for the post-scaffold-restore hook to complete before building.

### Namespace Mismatch

```csharp
// Error: type 'CreateHotstringCommand' not found
// Check the actual namespace in the file:
// Application/Commands/CreateHotstringCommand.cs
namespace AHKFlowApp.Application.Commands;  // ← must match using in consuming file

// Fix: add correct using
using AHKFlowApp.Application.Commands;
```

### Handler Not Registered with MediatR

```csharp
// Error: No handler registered for CreateHotstringCommand
// Fix: ensure handler assembly is registered
services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssembly(typeof(CreateHotstringCommand).Assembly));
```

### Wrong Return Type on Handler

```csharp
// Error: cannot implicitly convert 'Result' to 'Task<Result<HotstringDto>>'
// Handlers must return Task<Result<T>>, not ValueTask or Result directly

// BAD
public async ValueTask<Result<HotstringDto>> Handle(...) { }

// GOOD
public async Task<Result<HotstringDto>> Handle(...) { }
```

### EF Core Migration Errors

```bash
# "No migrations configuration type was found"
# Ensure startup project is set correctly:
dotnet ef migrations add <Name> \
  --project src/Backend/AHKFlowApp.Infrastructure \
  --startup-project src/Backend/AHKFlowApp.API

# "Unable to create an object of type 'AppDbContext'"
# AppDbContext needs a design-time factory or connection string in appsettings.Development.json
```

### Test Failures — Assertion vs Logic

Read the failure message carefully:

```
Expected: True
Actual:   False
  at result.IsSuccess.Should().BeTrue()
```

- If the assertion is wrong → fix the test
- If the behavior is wrong → fix the handler/validator
- Check: did you apply migrations to the test database? (`await db.Database.MigrateAsync()`)

### Format Violations

```bash
# See which files need formatting
dotnet format --verify-no-changes

# Fix all formatting
dotnet format

# Then verify again
dotnet format --verify-no-changes
```

### Testcontainers — Docker Not Running

```
Could not pull image 'mcr.microsoft.com/mssql/server:2022-latest'
```

Fix: Start Docker Desktop before running integration tests.

## Anti-patterns

### Don't Skip Hooks

```bash
# BAD — hides real problems
git commit --no-verify

# GOOD — fix the hook failure, then commit
```

### Don't Add Broad Try-Catch to Hide Errors

```csharp
// BAD — swallowing a build/runtime error
try { /* broken code */ }
catch (Exception) { }

// GOOD — fix the root cause
```

### Don't Ignore the Error Message

Read the full error output. The line number and error code tell you exactly what's wrong. Guessing wastes time.

### Don't Downgrade Packages to Fix Compatibility

```bash
# BAD — don't pin to old versions to avoid fixing the real issue
dotnet add package MediatR --version 12.0.0

# GOOD — use latest stable, fix the incompatibility properly
dotnet add package MediatR
```

## Quick Reference

| Error Code | Meaning | Common Fix |
|---|---|---|
| CS0246 | Type/namespace not found | Add `using`, check project reference, add NuGet package |
| CS0103 | Name doesn't exist | Typo, wrong scope, missing `using` |
| CS1061 | Member doesn't exist | Wrong type, check API surface |
| CS8618 | Non-nullable uninitialized | Add `= null!` or initialize |
| CS0115 | No method to override | Signature mismatch with base |
| CS0161 | Not all paths return | Add missing `return` |
