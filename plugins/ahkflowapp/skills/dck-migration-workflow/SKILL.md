---
name: dck-migration-workflow
description: Use when AHKFlowApp needs EF migrations, database updates, package updates, .NET upgrades, or rollback planning.
---

# Migration Workflow

## Core Principles

1. **Review before applying** - Generate and read SQL before applying EF migrations.
2. **Rollback plan always** - Know the previous migration, package commit, or branch rollback path before changing state.
3. **One logical change** - Keep each EF migration, package bump, or SDK move attributable.
4. **Verify after every step** - Build and run the affected tests after migrations or dependency changes.
5. **Use real project paths** - Infrastructure is `src/Backend/AHKFlowApp.Infrastructure`; startup project is `src/Backend/AHKFlowApp.API`.

## EF Core Schema Migration

### 1. Assess State

```bash
dotnet ef migrations list --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Use Roslyn MCP when available:

```text
find_symbol(name: entity or DbSet)
find_references(symbolName: changed property)
get_type_hierarchy(typeName: entity)
```

Confirm the model change is one rollback unit. Split unrelated schema changes.

### 2. Create Migration

Use descriptive change names:

```bash
dotnet ef migrations add AddEntityHistoryTable --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Avoid vague names like `UpdateDatabase` or entity-only names like `Hotstring`.

### 3. Review SQL

```bash
dotnet ef migrations script --idempotent --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Check for:

- `DROP COLUMN` / `DROP TABLE`
- `ALTER COLUMN` changes that truncate or lose precision
- non-nullable columns without safe defaults
- long-lock operations on large tables
- raw SQL that is not parameterized where runtime values are involved

For data-preserving renames, prefer a multi-step migration: add nullable column, copy data, enforce constraints, then drop the old column.

### 4. Apply and Verify

```bash
dotnet ef database update --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
```

Fresh worktrees may need `dotnet restore AHKFlowApp.slnx` before EF tooling or build commands.

### 5. Roll Back

```bash
dotnet ef database update <PreviousMigrationName> --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
dotnet ef migrations remove --project src/Backend/AHKFlowApp.Infrastructure --startup-project src/Backend/AHKFlowApp.API
```

Never edit a migration that has already been applied anywhere shared. Add a new migration.

## NuGet Updates

1. Audit:

```bash
dotnet list AHKFlowApp.slnx package --outdated
dotnet list AHKFlowApp.slnx package --vulnerable --include-transitive
```

2. Update one package at a time unless the change is an obvious patch-only batch.
3. Use `dotnet add package <name>` without `--version` unless the user explicitly asks for a specific version.
4. With Central Package Management, verify package versions land in `Directory.Packages.props`; project files should not gain `Version=`.
5. Never downgrade a package to avoid fixing a real compatibility issue.
6. Do not upgrade `Microsoft.ApplicationInsights.AspNetCore` to 3.x unless explicitly requested.

Verify each package step:

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
```

## .NET / SDK Upgrades

1. Inspect `global.json`, `Directory.Build.props`, and project TFMs.
2. Confirm installed SDKs with `dotnet --list-sdks`.
3. Update SDK/TFM in a branch that can be reverted.
4. Keep Microsoft packages aligned with the target .NET major version.
5. Restore, build, test, and run format verification.

```bash
dotnet restore AHKFlowApp.slnx
dotnet build AHKFlowApp.slnx --configuration Release --no-restore
dotnet test --configuration Release --no-build --verbosity normal
dotnet format AHKFlowApp.slnx --verify-no-changes
```

## Anti-Patterns

- Applying migrations without reading generated SQL.
- Using nonexistent `--dry-run` flags for `dotnet ef database update`.
- Using `dotnet outdated`; this repo relies on built-in `dotnet list package --outdated`.
- Adding invented packages or pinned versions from memory.
- Mixing schema, package, and SDK changes in one commit.
- Changing production secrets in committed `appsettings` files.

## Decision Guide

| Scenario | Action |
|---|---|
| Entity/property/config changed | Add EF migration, review SQL, apply locally, test |
| Column rename | Use data-preserving multi-step migration |
| Package vulnerability | Update package, build/test, document impact |
| Routine package refresh | One package or safe patch batch at a time |
| SDK / TFM change | Dedicated branch, restore/build/test/format |
| Migration already applied | Add a follow-up migration, do not edit history |
