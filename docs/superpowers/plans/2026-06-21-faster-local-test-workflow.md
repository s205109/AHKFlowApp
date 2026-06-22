# Faster Local Test Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed up the AHKFlowApp local development loop while preserving the full coverage pre-push hook and CI confidence gate.

**Architecture:** Keep the existing full coverage path intact, then add explicit faster developer workflows around test categorization, measured timing, and targeted execution. Use evidence from timing reports before pruning tests or weakening any verification path.

**Tech Stack:** .NET 10, xUnit, bUnit, WebApplicationFactory, Testcontainers SQL Server, Playwright, Coverlet, ReportGenerator, PowerShell.

---

## Summary

- Keep the existing full coverage pre-push hook and PR coverage gate intact.
- Add a fast, explicit inner-loop workflow so normal edits do not require SQL/Testcontainers/E2E unless the touched area needs them.
- Current baseline: bUnit is not the main bottleneck. `UI.Blazor.Tests` ran 212 tests in 7.8s no-build; SQL/API-style tests are slower: Application 32.5s, API 35.6s, CLI 23s, Infrastructure 25.3s no-build.
- 2026-06-22 measurement: `Application.Tests` showed eight SQL container starts totaling about 314s of fixture startup work and about 56s wall clock. The shared-container prototype reduced it to one SQL container start and about 26.3s wall clock, so shared SQL container reuse should land before broader trait/filter work.
- Treat E2E as explicit unless frontend/browser behavior changed; its `PublishBlazorForE2E` MSBuild target already showed 72s before test execution in a no-build misfire.
- Use the existing project split first: `Domain.Tests` and `UI.Blazor.Tests` are fast whole-project slices; `API.Tests`, `Infrastructure.Tests`, and `E2E.Tests` are slow whole-project slices. Only `Application.Tests` and `CLI.Tests` need mixed-project filtering.

## Key Changes

- Add test taxonomy with xUnit traits only where project-level selection is not enough:
  - Add class-level `Category=Integration` only in `Application.Tests` and `CLI.Tests`.
  - Tag `Application.Tests` classes that use DB collections such as `HotstringDb`, `HotkeyDb`, `ProfileDb`, `CategoryDb`, `DashboardDb`, `DevDb`, `PreferenceDb`, and `ScriptGeneratorDb`.
  - Tag `CLI.Tests` classes that use `CliWebApi`.
  - Do not tag `API.Tests`, `Infrastructure.Tests`, or `E2E.Tests` in v1; they are selected or skipped as whole projects.
- Add a fast guard test for trait drift:
  - In `Application.Tests`, assert every class with one of the known DB `[Collection]` names has `Category=Integration`.
  - In `CLI.Tests`, assert every class with `[Collection("CliWebApi")]` has `Category=Integration`.
  - Run these guard tests in `-Mode Fast` so missing traits fail before an integration test leaks into the fast slice.
- Add `scripts/test-fast.ps1`:
  - `-Mode Fast`: `Domain.Tests`, `UI.Blazor.Tests`, `Application.Tests` filtered to `Category!=Integration`, and `CLI.Tests` filtered to `Category!=Integration`.
  - `-Mode Integration`: `Application.Tests` and `CLI.Tests` filtered to `Category=Integration`, plus whole-project `API.Tests` and `Infrastructure.Tests`.
  - `-Mode E2E`: whole-project `E2E.Tests`; no `Category=Browser` trait required in v1.
  - `-Mode Coverage`: delegates to `scripts/run-coverage.ps1`.
  - Fail if a selected project reports zero discovered tests.
- Add `scripts/measure-tests.ps1`:
  - Runs each test project with TRX logging.
  - Produces project/class/test duration rankings and project wall-clock timings.
  - Reports unattributed setup time as `project wall-clock - summed TRX test durations`, because TRX does not reliably attribute xUnit collection fixture startup to individual tests.
  - Captures SQL fixture setup timings for `SqlContainerFixture` and `MigratedDbFixture` when `AHKFLOW_TEST_TIMING=1`, writing machine-readable entries under `TestResults`.
  - Flags missing restore/build artifacts, zero-test runs, top slow tests, and top fixture/setup costs.
- Update docs:
  - Add `docs/development/testing-workflow.md`.
  - Update `docs/development/coverage.md` to clarify: fast loop is for development; full coverage remains pre-push/PR.
  - Document when to run bUnit, SQL integration, E2E, and full coverage.

## Test Pruning And Speedups

- Cull trivial tests only after the timing/value report identifies them as low signal.
- First pruning candidates: static render-only bUnit tests, DTO/record coverage, and duplicate UI assertions already covered by stronger interaction or E2E tests.
- After any pruning change, run `pwsh .\scripts\run-coverage.ps1`; if thresholds fail, restore the test or replace it with higher-value coverage. Lowering thresholds is out of scope for this plan and requires a separate explicit decision.
- Do not replace SQL Server Testcontainers with in-memory EF; optimize by selection, fixture reuse, and removing duplication.
- Investigate SQL fixture reuse before pruning:
  - Measure how many SQL containers start per test project and how long `StartAsync()` plus migrations take.
  - If Application test collection startup dominates, prototype one shared SQL Server container with separate per-collection databases and per-database migrations.
  - Keep isolation clear: do not merge unrelated API, CLI, or Infrastructure fixtures into the same container unless measurement shows the gain and the database names remain deterministic and disposable.
- Investigate E2E publish cost separately:
  - Confirm the cost belongs to `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj` target `PublishBlazorForE2E`.
  - Measure whether cached publish output, `--no-build`, or a conditional publish target materially improves E2E time.
  - Keep the full coverage/pre-push path unchanged unless a cached path is proven equivalent.

## Public Interfaces

- No runtime app API changes.
- New developer-facing script interfaces:
  - `pwsh .\scripts\test-fast.ps1 -Mode Fast`
  - `pwsh .\scripts\test-fast.ps1 -Mode Integration`
  - `pwsh .\scripts\test-fast.ps1 -Mode E2E`
  - `pwsh .\scripts\measure-tests.ps1`
- New test trait contract: `Category=Integration` on mixed-project integration classes only.

## Test Plan

- Verify `scripts/test-fast.ps1 -Mode Fast` runs expected non-integration tests and skips SQL/E2E.
- Verify `scripts/test-fast.ps1 -Mode Integration` runs SQL/API-backed tests, including whole-project `Infrastructure.Tests`.
- Verify `scripts/test-fast.ps1 -Mode E2E` runs the 10 Playwright tests.
- Verify the trait guard fails when an `Application.Tests` or `CLI.Tests` DB collection class lacks `Category=Integration`.
- Verify `scripts/measure-tests.ps1` reports nonzero test counts, ranks slow tests, and reports SQL fixture/setup overhead separately from per-test durations.
- After every pruning commit, run `pwsh .\scripts\run-coverage.ps1` before accepting the deletion.
- Run existing full gate: `pwsh .\scripts\run-coverage.ps1`.
- Confirm `.githooks/pre-push.ps1` still runs full coverage by default.

## Assumptions

- Pre-push full coverage stays mandatory by default.
- CI PR coverage stays unchanged in v1.
- Test deletion is allowed only when timing plus value analysis supports it and the coverage gate still passes.
- Fast/integration trait filtering is limited to `Application.Tests` and `CLI.Tests`; whole-project slow suites stay project-selected.
- Build artifacts and timing outputs remain ignored or under `TestResults`.
