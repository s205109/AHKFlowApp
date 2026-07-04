---
name: dck-de-sloppify
description: Use when cleaning AHKFlowApp code, warnings, dead code, TODOs, formatting, sealed classes, or CancellationToken flow.
---

# De-Sloppify

## Core Principles

1. **One cleanup concern at a time** - Do not mix feature work with cleanup.
2. **Verify after each phase** - Build and run affected tests before moving on.
3. **Safe removals only** - Dead-code tools miss reflection, DI, serialization, and config references.
4. **Keep commits reviewable** - Separate format, analyzer, dead-code, and behavioral cleanup.
5. **Use project conventions** - Explicit use cases, controller APIs, private entity setters, and cancellation propagation.

## 7-Step Pipeline

### 1. Format

```bash
dotnet format AHKFlowApp.slnx
dotnet format AHKFlowApp.slnx --verify-no-changes
```

### 2. Remove Unused Usings

```bash
dotnet format AHKFlowApp.slnx analyzers --diagnostics IDE0005
```

Then build.

### 3. Fix Diagnostics

Use Roslyn MCP when available:

```text
get_diagnostics
```

Prioritize compiler warnings, nullability issues, obsolete APIs, and unused variables.

### 4. Remove Dead Code

Use:

```text
find_dead_code
find_references
```

Then search strings manually:

```bash
rg -n "TypeName|nameof\\(TypeName\\)|Activator.CreateInstance|JsonDerivedType|AddScoped|AddTransient|AddSingleton" src tests
```

Remove only after compile-time and string/config references are clear.

### 5. Resolve TODOs

```bash
rg -n "TODO|HACK|FIXME|XXX" src tests
```

Fix small stale items. For larger work, create or reference an issue rather than leaving vague comments.

### 6. Seal Classes

Use `get_type_hierarchy` and test searches before sealing. Do not seal xUnit fixture base classes, intentional extension points, or classes with designed `virtual` members.

### 7. Propagate CancellationToken

Trace from controller action or use case into EF Core, HttpClient, file IO, and helper methods:

```csharp
public async Task<Result<HotstringDto>> ExecuteAsync(
    GetHotstringQuery request,
    CancellationToken cancellationToken)
{
    var entity = await db.Hotstrings.FindAsync([request.Id], cancellationToken);
    ...
}
```

## Verification Per Phase

At minimum:

```bash
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
```

For docs/skills-only cleanup, use targeted grep/setup verification instead of full app tests when appropriate.

## Anti-Patterns

- One giant "cleanup everything" commit.
- Removing public or DI-discovered types based only on zero references.
- Replacing meaningful assertions with weaker ones.
- Sealing classes used as test bases or extension points.
- Reintroducing Minimal API or MediatR examples during cleanup.
- Changing behavior while claiming "cleanup only".

## Decision Guide

| Scenario | Run |
|---|---|
| Quick PR tidy | Format, unused usings, diff review |
| Warning cleanup | Diagnostics phase |
| Large stale area | Dead-code safety checks |
| Async review | CancellationToken phase |
| Performance prep | Dead code plus sealing |
