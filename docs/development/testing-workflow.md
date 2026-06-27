# Local testing workflow

Use the fastest test slice that still covers the code you changed, then run the full coverage gate before pushing or opening a PR.

## Fast inner loop

```bash
pwsh .\scripts\test-fast.ps1 -Mode Fast
```

Fast mode runs:

- `AHKFlowApp.Domain.Tests`
- `AHKFlowApp.UI.Blazor.Tests`
- `AHKFlowApp.Application.Tests` filtered to `Category!=Integration`
- `AHKFlowApp.CLI.Tests` filtered to `Category!=Integration`

Use this for domain logic, validators, pure handlers, CLI parser/unit behavior, and Blazor component changes that do not require SQL Server, WebApplicationFactory, or browser automation.

## SQL and API-backed tests

```bash
pwsh .\scripts\test-fast.ps1 -Mode Integration
```

Integration mode runs:

- `AHKFlowApp.Application.Tests` filtered to `Category=Integration`
- `AHKFlowApp.CLI.Tests` filtered to `Category=Integration`
- `AHKFlowApp.API.Tests`
- `AHKFlowApp.Infrastructure.Tests`

Use this for EF Core, migrations, MediatR handlers that touch `AppDbContext`, API behavior, CLI integration flows, SQL query behavior, and anything that changes persistence wiring.

The script starts one disposable Docker SQL Server container for the selected SQL-backed projects, passes the server connection to the test processes, and removes the container when the run finishes. Direct `dotnet test` still falls back to the per-project Testcontainers fixture path.

Only mixed projects use `Category=Integration` in v1. Whole-project SQL/API suites are selected by project instead of traits.

## Browser and PWA tests

```bash
pwsh .\scripts\test-fast.ps1 -Mode E2E
```

E2E mode runs `AHKFlowApp.E2E.Tests`. Use it for browser flows, Playwright-covered UI behavior, mobile viewport behavior, service-worker/PWA behavior, and changes to the E2E fixture or published Blazor output.

The first E2E run after frontend source changes publishes the Blazor app before Playwright starts. Unchanged reruns reuse the cached publish output through the E2E project target, so the publish step is skipped while the browser tests still run normally. E2E flow classes share one API/Spa/browser stack, and each test resets mutable database rows before it starts.

## Full coverage gate

```bash
pwsh .\scripts\test-fast.ps1 -Mode Coverage
```

Coverage mode delegates to `scripts/run-coverage.ps1`. Run it before pushing or opening a PR; the pre-push hook and CI still use the full coverage path. The local coverage script uses the same disposable shared SQL container behavior as Integration mode for the SQL-backed suites.

## Trait contract

`Application.Tests` classes using these collections must have `[Trait("Category", "Integration")]`:

- `HotstringDb`
- `HotkeyDb`
- `ProfileDb`
- `CategoryDb`
- `DashboardDb`
- `DevDb`
- `PreferenceDb`
- `ScriptGeneratorDb`

`CLI.Tests` classes using `CliWebApi` must also have `[Trait("Category", "Integration")]`.

Guard tests run in Fast mode and fail if a DB/API-backed class is missing the trait, preventing integration tests from leaking into the fast local slice.
