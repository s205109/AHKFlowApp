---
alwaysApply: true
description: >
  Enforces latest stable NuGet package versions and proper dependency management for .NET 10.
---

# Package Management Rules

- Never hardcode package versions from memory — training data contains outdated versions.
- Run `dotnet add package <name>` without `--version` to get latest stable automatically.
- `MediatR.Extensions.Microsoft.DependencyInjection` was merged into `MediatR` — only `MediatR` is needed.
- Microsoft.* packages targeting .NET 10 use 10.x versions (EF Core, Extensions, AspNetCore).
- When writing `<PackageReference>`, use `dotnet add package` first to resolve the correct version.
- With `Directory.Packages.props` (CPM), individual .csproj files must NOT specify `Version=`.
- Never downgrade a package unless explicitly asked. Prefer release over preview/RC.
