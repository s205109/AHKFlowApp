---
applyTo: "**"
---

# Personal Defaults

> These are general defaults. Repository-level instructions (AGENTS.md, CLAUDE.md, `.github/instructions/`) always take precedence.

## Tech Stack

- .NET 10, C#, PowerShell
- Blazor WebAssembly PWA with MudBlazor 9.x
- ASP.NET Core Web API (controller-based — no minimal APIs)
- EF Core + SQL Server, MediatR, Ardalis.Result, FluentValidation, Serilog

## Coding

- Readability first, then performance
- Primary constructors, file-scoped namespaces, Allman braces
- `var` when type is apparent; collection expressions; pattern matching over if-else
- `sealed` by default; `internal` by default; `public` only when needed
- No mapper libraries — explicit mapping only
- No repository pattern — inject `DbContext` directly in handlers
- Propagate `CancellationToken` everywhere; async all the way

## Testing

- xUnit + FluentAssertions + NSubstitute + Testcontainers (SQL Server)
- Integration tests first via `WebApplicationFactory` — no `UseInMemoryDatabase`
- Test naming: `MethodName_Scenario_ExpectedResult`
- Mock third-party boundaries only — never mock what you own

## Collaboration

- Ask clarifying questions if the request is unclear
- Concise, step-by-step responses — no long prose
- Don't propose broader changes without asking first
- Verify actual workspace structure before assuming conventions
