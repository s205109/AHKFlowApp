---
applyTo: "**"
---

<!-- sync-marker body-sha256=75077b887e2def28bae0d9b88b9d98e85ee30ceb6e083c812a5081d52017e280 pasted-to-web=2026-08-13 -->

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

- Always write prose in ASD-STE100 (Simplified Technical English): one meaning per
  word, one verb per action, active voice, simple tenses only, one instruction per
  sentence, max 20 words (instructions) / 25 (explanations).
- Follow Zinsser: clarity, simplicity, brevity, humanity. Humanity limits the rest —
  plain and direct, not robotic. Easy to read beats short.
- Exceptions: code, commands, file paths, identifiers, error messages, quoted text.
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
