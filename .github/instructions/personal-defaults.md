---
applyTo: "**"
---

<!-- sync-marker body-sha256=0bdc2bf5ea601dee5f2a28e0067c1ee7c6b6ff77ee0faf1d77cde1303959cdde pasted-to-web=2026-08-25 -->

# Personal Defaults

> General defaults. Repository instructions (AGENTS.md, CLAUDE.md,
> `.github/instructions/`) always take precedence.

## Tech Stack

- .NET 10, C#, PowerShell
- Blazor WebAssembly PWA with MudBlazor 9.x; MSAL auth
- ASP.NET Core Web API (controller-based — no minimal APIs); Swashbuckle for OpenAPI
- EF Core + SQL Server; explicit use cases (`IUseCase`/`IUseCaseHandler`) — no MediatR
- Ardalis.Result, FluentValidation, Serilog, Application Insights

## Build

- Central Package Management is on. Versions live in `Directory.Packages.props`.
  Never put `Version=` on a `PackageReference`.
- `TreatWarningsAsErrors` and `EnforceCodeStyleInBuild` are on. A warning fails the
  build — fix it, don't suppress it without saying why.
- Nullable and ImplicitUsings enabled.

## Coding

- Readability first, then performance
- Primary constructors, file-scoped namespaces, Allman braces
- `var` when the type is apparent; collection expressions; pattern matching over if-else
- `sealed` by default; `internal` by default; `public` only when needed
- No mapper libraries — explicit mapping only
- No repository pattern — inject `DbContext` directly in handlers
- Propagate `CancellationToken` everywhere; async all the way
- Inject `TimeProvider`. Never `DateTime.Now` or `DateTime.UtcNow` in testable code.

## Testing

- xUnit + FluentAssertions + NSubstitute + Testcontainers (SQL Server)
- bunit for Blazor components; Playwright for E2E
- Integration tests first via `WebApplicationFactory` — no `UseInMemoryDatabase`
- Test naming: `MethodName_Scenario_ExpectedResult`
- Mock third-party boundaries only — never mock what you own
- PowerShell scripts get Pester suites too, not just the C# projects

## Shell

- Always write command blocks for PowerShell. Tag the fence ```powershell.
- Never give me a bash heredoc (`<<'EOF'`). PowerShell reads `<<` as a redirection
  operator and fails.
- For `gh` PR bodies, use a here-string (`$body = @' ... '@`). Use `--body-file`
  only when the body is very long or a line starts with `'@`.
- Label a block ```bash only when bash is genuinely required, and say where to run it.

## Writing Style

- Follow Plain English. Easy to read matters more than short — when they conflict,
  use more words.
- One idea per sentence. Keep sentences under about 20 words.
- Use common words: "use" not "leverage", "cannot be undone" not "irreversible",
  "start" not "initiate".
- No idioms, no metaphors, no culture references. Name the thing directly.
- Active voice: "The handler saves the record", not "the record is saved by the
  handler".
- Keep identifiers exact — never simplify `IUseCaseHandler` or `Result.NotFound()`.
  Explain the term once instead.
- Quote existing error strings exactly. Apply these rules when you write a new one.
- Do not stack clauses. Split a long sentence into two.
- Exceptions: code, commands, file paths, identifiers, error messages, quoted text.
  Commit messages and PR titles stay short, grammar optional.
- Precision wins over style. Never drop a fact, condition, number, or scope
  qualifier to shorten a sentence.

## Collaboration

- In every response: concise and step-by-step. Lead with the answer.
- Never stop to ask about a routine choice — which approach, order, or name.
  Pick one, say which, keep going. I will correct you.
- Ask only when the answer changes the shape of the work, or the action cannot be undone.
- Always say when you are uncertain. Never invent a file path, API surface, package
  version, or config key. Say you'd need to check, or check.
- Check the actual workspace structure before you assume a convention.
- Don't propose broader changes without asking first.
- When you cannot finish an acceptance criterion, say so explicitly and leave the
  item open. Never quietly drop it.
