---
name: dck-build-fix
description: Use when AHKFlowApp build, test, format, compiler, migration, or lint errors need diagnosis and repair.
---

# Build Fix

## Loop Discipline

Use a bounded fix loop, not open-ended guessing.

1. Default maximum: 5 iterations; hard cap: 10.
2. Each iteration must reduce the error/failure count or produce a new root-cause finding.
3. Same errors after a fix means STUCK: stop, report evidence, and change approach.
4. More errors after a fix means REGRESSION: revert that iteration's change and re-plan.
5. Categorize before editing; fix the highest-leverage root cause first.

Report each iteration briefly: `Iteration 2/5: fixed missing use-case registration; 3 compiler errors remain`.

## Build-Fix Flow

1. Run:

```bash
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
```

If assets are missing in a fresh checkout, run `dotnet restore AHKFlowApp.slnx`, then rebuild.

2. Parse every error with file, line, code, and message.
3. Group by root cause.
4. Apply the smallest targeted fix.
5. Rebuild and compare counts.

Roslyn MCP tools are useful when available:

```text
get_diagnostics
find_symbol
find_references
get_project_graph
```

## Common Compiler Fixes

| Code | Meaning | Fix |
|---|---|---|
| CS0246 / CS0234 | Type or namespace missing | Add using, project reference, or package |
| CS0103 | Name does not exist | Check scope, typo, or missing field/parameter |
| CS1061 | Member missing | Verify actual type and API surface |
| CS0161 | Not all code paths return | Return a typed result on every path |
| CS8618 | Non-nullable uninitialized | Initialize or make construction explicit |
| CS0115 | Bad override | Match base signature or remove override |
| CS0535 | Interface member missing | Implement the required member |

## AHKFlowApp-Specific Issues

### Use Case Handler Not Registered

Runtime DI error:

```text
Unable to resolve service for IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
```

Fix registration in Application DI:

```csharp
services.AddUseCase<CreateHotstringCommand, Result<HotstringDto>, CreateHotstringCommandHandler>();
```

### Handler Signature Drift

Handlers implement `IUseCaseHandler<TRequest,TResult>`:

```csharp
internal sealed class CreateHotstringHandler(AppDbContext db)
    : IUseCaseHandler<CreateHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(
        CreateHotstringCommand request,
        CancellationToken cancellationToken)
    {
        await db.SaveChangesAsync(cancellationToken);
        return Result.Success(dto);
    }
}
```

Do not reintroduce `IMediator`, `IRequest`, `IRequestHandler`, or `Handle(...)`.

### EF Core Migration Errors

Use real paths:

```bash
dotnet ef migrations add <Name> --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

If `project.assets.json` is missing, restore first. If `AppDbContext` cannot be created, inspect API configuration and design-time startup errors rather than adding a repository layer.

### Format Failures

Because the repo root has both `AHKFlowApp.slnx` and `AHKFlowApp.csproj`, target the solution explicitly:

```bash
dotnet format AHKFlowApp.slnx --verify-no-changes
dotnet format AHKFlowApp.slnx
```

Line-ending drift after adding files is common; run format, then verify again.

### Test Failures

Use the test-fix loop:

1. Read the failing assertion.
2. Read the production behavior.
3. Decide whether the bug is production code, test setup, or expectation drift.
4. Never weaken assertions just to pass.
5. Re-run the smallest affected test, then broaden.

```bash
dotnet test tests/AHKFlowApp.API.Tests --configuration Release --filter "FullyQualifiedName~HealthControllerTests"
```

## Anti-Patterns

- Suppressing warnings or errors instead of fixing the root cause.
- Adding broad `catch (Exception)` blocks to hide failures.
- Downgrading packages to dodge compatibility work.
- Skipping hooks with `--no-verify`.
- Retrying the same failed fix loop without new evidence.
- Reintroducing repositories, Minimal APIs, or MediatR abstractions.

## Exit Conditions

| State | Action |
|---|---|
| Error count reaches zero | Run affected tests |
| Same errors repeat | Stop and report STUCK with evidence |
| Error count increases | Revert iteration and report REGRESSION |
| SDK/tooling missing | Restore/install only the missing prerequisite |
| Tests fail after build fix | Start bounded test-fix loop |
