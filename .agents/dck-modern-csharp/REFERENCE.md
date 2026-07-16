---
name: dck-modern-csharp
description: Use when writing or reviewing AHKFlowApp C# for .NET 10, C# 14, primary constructors, records, patterns, or collections.
---

# Modern C#

## AHKFlowApp Defaults

- Use primary constructors for dependency injection.
- Use records for DTOs, commands, queries, and value objects.
- Use collection expressions (`[]`) instead of verbose collection initialization.
- Use `sealed` unless a class is designed for inheritance.
- Use `TimeProvider` instead of `DateTime.Now` or `DateTime.UtcNow`.
- Use file-scoped namespaces and Allman braces.
- Use `var` when the type is apparent.

## Patterns

| Feature | Use |
|---|---|
| Primary constructors | DI services, controllers, handlers |
| Records | DTOs, commands, queries, value objects |
| Collection expressions | Empty collections and small literals |
| Pattern matching | Result/state branching where it improves clarity |
| Raw string literals | JSON, SQL snippets, expected text blocks |
| `required` | Configuration options and input objects that must be initialized |
| `field` keyword | Property validation without manual backing fields when supported |

## Examples

```csharp
public sealed record CreateHotstringCommand(CreateHotstringDto Input);
```

```csharp
internal sealed class ListHotstringsHandler(AppDbContext db)
    : IUseCaseHandler<ListHotstringsQuery, Result<PagedList<HotstringDto>>>
{
    public async Task<Result<PagedList<HotstringDto>>> ExecuteAsync(
        ListHotstringsQuery request,
        CancellationToken cancellationToken)
    {
        var items = await db.Hotstrings
            .AsNoTracking()
            .OrderBy(x => x.Trigger)
            .ToListAsync(cancellationToken);

        return Result.Success(Map(items));
    }
}
```

```csharp
string[] allowedExtensions = [".ahk", ".txt"];
List<Guid> selectedProfileIds = [defaultProfileId, .. request.ProfileIds];
```

## Use With Restraint

Modern syntax is a tool, not a goal. Avoid deeply nested property/list patterns when simple local variables are clearer. Do not replace clear domain methods with clever expressions.

## Anti-Patterns

- Traditional constructor plus `_field = field` ceremony for simple DI.
- Tuple types where a named record communicates intent.
- `new List<T>()` for simple empty or literal collections.
- Pattern matching that hides business rules.
- Nullable suppression without a clear invariant.
- Public setters on domain entity state.

## Decision Guide

| Scenario | Use |
|---|---|
| API request/response | `sealed record` |
| Handler/controller DI | Primary constructor |
| Domain state | private setters plus factory/domain methods |
| Small immutable value | `readonly record struct` when appropriate |
| Multi-line expected JSON | Raw string literal |
| Current time | `TimeProvider.GetUtcNow()` |
