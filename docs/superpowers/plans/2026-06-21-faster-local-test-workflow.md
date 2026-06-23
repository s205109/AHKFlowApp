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
- 2026-06-22 E2E follow-up: `PublishBlazorForE2E` was confirmed as the publish cost center and made incremental. A refresh run passed in 196.4s with publish; an unchanged rerun skipped `dotnet publish` and passed in 184.0s, so the cached path is equivalent but less valuable than the SQL-container work.
- 2026-06-22 fresh baseline after the fast/integration split: `measure-tests.ps1` passed all projects; E2E remained the largest explicit slice at 125.7s wall / 42.6s unattributed setup, followed by API 49.4s, CLI 27.5s, Infrastructure 26.2s, Application 24.7s, UI 9.9s, and Domain 1.6s.
- 2026-06-22 E2E stack reuse: the three E2E flow classes now share one `StackFixture` collection fixture and reset mutable DB rows per test. E2E-only measurement dropped to 102.3s wall with one named `StackFixture.InitializeAsync` entry at 16.4s and cheap per-test resets.
- 2026-06-22 E2E pruning: removed the slower hotstrings mobile bulk-delete browser duplicate after confirming bUnit page/component coverage plus API endpoint coverage. The hotkeys mobile bulk-delete E2E remains as the representative browser select-mode smoke path. E2E-only measurement passed 9 tests at 91.8s wall / 70.2s summed test duration / 21.5s unattributed setup, and full coverage still passed.
- 2026-06-22 full post-pruning measurement: `measure-tests.ps1` passed all projects; E2E was still largest at 94.0s wall / 75.0s summed test duration / 19.0s unattributed setup, followed by API 39.9s, Infrastructure 24.7s, CLI 22.7s, Application 22.6s, UI 8.3s, and Domain 1.9s. The slowest classes were `HotkeysMobileFlowTests` at 37.0s and `HotstringsMobileFlowTests` at 28.8s.
- 2026-06-22 E2E conflict pruning: removed mobile duplicate-conflict browser flows from `HotkeysMobileFlowTests` and `HotstringsMobileFlowTests`. `HotkeyEditDialogTests.SaveConflict_ShowsKeyErrorInline` and `HotstringEditDialogTests.SaveConflict_ShowsTriggerErrorInline` keep the inline-dialog behavior coverage, including the no-`.mud-alert` assertion, while API/Application tests keep duplicate-conflict semantics covered. Remaining E2E keeps mobile CRUD, representative mobile bulk select, and tablet overflow layout checks. E2E-only measurement passed 7 tests at 80.8s wall / 57.9s summed test duration; `HotkeysMobileFlowTests` dropped from 37.0s to 28.6s and `HotstringsMobileFlowTests` dropped from 28.8s to 19.0s.
- 2026-06-22 full post-conflict-pruning measurement: `measure-tests.ps1` passed all projects; E2E remained largest at 75.1s wall / 56.1s summed test duration / 19.0s unattributed setup, followed by API 56.0s, Application 28.6s, Infrastructure 28.4s, CLI 25.0s, UI 10.0s, and Domain 1.9s. The slowest classes were still E2E (`HotkeysMobileFlowTests` 27.3s, `HotstringsMobileFlowTests` 17.9s, `HotstringsCrudFlowTests` 10.9s), but API now has the largest single setup cost (`SqlContainerFixture.StartAsync` 19.8s).
- 2026-06-22 hotstrings CRUD conflict pruning: removed `HotstringsCrudFlowTests.DuplicateTrigger_ShowsConflictSnackbar` after confirming `HotstringEditDialogTests.SaveConflict_ShowsTriggerErrorInline`, `HotstringsPageTests.Page_OnConflictResponse_ShowsErrorSnackbar`, `HotstringsEndpointsTests.Post_DuplicateTrigger_Returns409_WithProblemDetails`, and `CreateHotstringCommandHandlerTests.Handle_WhenDuplicateTriggerInSameProfile_ReturnsConflict` cover the behavior at cheaper layers. E2E-only measurement passed 6 tests at 67.6s wall / 46.3s summed test duration / 21.3s unattributed setup; `HotstringsCrudFlowTests` is now one 4.5s desktop CRUD smoke. Remaining E2E flows keep desktop CRUD, mobile CRUD, tablet overflow layout, and representative mobile bulk-select browser coverage. Next sequencing: move to API/Infrastructure SQL fixture setup reuse unless fresh full measurement changes the ordering.
- 2026-06-23 fresh post-pruning measurement: `measure-tests.ps1` passed all projects; E2E remained largest at 82.8s wall / 57.6s summed test duration / 25.2s unattributed setup, followed by API 57.8s, CLI 29.7s, Infrastructure 27.1s, Application 25.0s, UI 11.7s, and Domain 1.8s. Slow setup entries were `StackFixture.InitializeAsync` 20.5s, then one `SqlContainerFixture.StartAsync` each in API 13.3s, Infrastructure 12.7s, Application 12.3s, and CLI 11.3s. Because remaining E2E flows still carry unique browser/layout coverage and Testcontainers' built-in reuse is experimental and disables automatic cleanup, the next actionable target was API-side fixture/auth reuse rather than a default reusable Docker container.
- 2026-06-23 API fixture/auth reuse: API tests now share one collection-level `ApiTestFixture` with a SQL-backed `CustomWebApplicationFactory`, and authenticated API clients use per-request test-auth headers instead of building a derived factory for each client. `WithTestAuth` remains available for CLI integration tests and still authenticates by default there. API-only measurement passed 135 tests at 31.2s wall / 17.6s summed test duration / 13.6s unattributed setup, down from the fresh 57.8s wall / 41.7s summed API measurement.
- 2026-06-23 full post-API-reuse measurement: `measure-tests.ps1` passed all projects; E2E was still largest at 69.3s wall / 48.7s summed test duration / 20.6s unattributed setup, followed by API 33.5s, CLI 31.1s, Infrastructure 26.2s, Application 26.2s, UI 10.3s, and Domain 1.6s. The slowest test was `HotkeysMobileFlowTests.BulkDelete_OnPhoneViewport_UsesSelectMode` at 11.8s, with duplicated setup work creating rows through the same FAB/dialog path already covered by `CreateEditDelete_OnPhoneViewport_UsesFabAndFullScreenDialog`.
- 2026-06-23 hotkey mobile bulk-delete setup: seeded the two owned hotkeys directly through the E2E SQL-backed API fixture, leaving the browser path focused on mobile select mode, row checkbox selection, confirmation, API bulk delete, and snackbar feedback. Targeted E2E passed with the test at about 3s. E2E-only measurement passed 6 tests at 49.5s wall / 33.2s summed test duration / 16.2s unattributed setup. A fresh full measurement passed all projects with E2E at 52.9s, Infrastructure 25.2s, CLI 24.8s, Application 22.8s, API 22.5s, UI 7.0s, and Domain 2.1s. Next sequencing: remaining E2E mobile CRUD tests are the largest individual tests, while repeated SQL startup remains the largest cross-project setup cost; prefer one more bounded E2E setup/pruning pass only if cheaper-layer coverage already proves the duplicate behavior, otherwise move to the planned fast/integration trait filtering work for `Application.Tests` and `CLI.Tests`.
- 2026-06-23 hotstring mobile CRUD narrowing: replaced the hotstring phone create/edit/delete E2E flow with a focused phone FAB/dialog smoke after confirming desktop hotstring browser CRUD, bUnit hotstring page/dialog/mobile-list coverage, and API/Application CRUD tests cover the removed behavior at cheaper layers. The hotkey phone CRUD flow remains as the representative mobile FAB/full-screen browser CRUD path. E2E-only measurement passed 6 tests at 44.2s wall / 27.9s summed test duration / 16.4s unattributed setup. A fresh full measurement passed all projects with E2E at 45.3s, Infrastructure 24.7s, CLI 22.2s, API 21.9s, Application 19.8s, UI 7.0s, and Domain 1.9s. Full coverage still passed at 90.2% line / 59.7% branch. Next sequencing: stop E2E pruning for now and move to the planned fast/integration trait filtering for `Application.Tests` and `CLI.Tests`.
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
- Make the E2E Blazor publish target incremental:
  - Publish from the frontend build output with `--no-build --no-restore`.
  - Track frontend source inputs and stamp the publish outputs after a successful publish.
  - Keep full coverage/pre-push behavior unchanged while allowing unchanged local E2E reruns to skip publish.
- Share the E2E runtime stack:
  - Use one xUnit collection fixture for the API factory, SPA host, Playwright, and browser across all E2E flow classes.
  - Reset mutable hotstring/hotkey/profile/category/preference rows before each E2E test to preserve test isolation.
  - Record `StackFixture` setup/reset timing when `AHKFLOW_TEST_TIMING=1`.
- Share the API runtime stack:
  - Use one xUnit collection fixture for the API test SQL container and base `CustomWebApplicationFactory`.
  - Keep unauthenticated clients unauthenticated by default, and mark authenticated API requests with `X-Test-*` headers instead of creating a derived factory per client.
  - Preserve `WithTestAuth` for CLI integration tests that need a default authenticated test user.
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
  - Confirmed the cost belongs to `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj` target `PublishBlazorForE2E`.
  - Cached publish output plus `--no-build --no-restore` skips publish on unchanged reruns and keeps the Playwright tests equivalent.
  - The measured local gain was modest compared with SQL fixture reuse, so E2E remains an explicit slice rather than part of the fast inner loop.
- Investigate E2E stack setup separately:
  - Confirmed E2E classes were already serialized through one collection but still created a separate `StackFixture` per class.
  - Moved `StackFixture` to the collection fixture and added per-test data reset, preserving isolation while starting the API/Spa/browser stack once.
  - Keep E2E explicit; the remaining cost is mostly browser flow duration, especially mobile hotstring/hotkey flows.

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
- Verify `scripts/test-fast.ps1 -Mode E2E` runs the 6 Playwright tests.
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
