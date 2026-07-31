# 046 - E2E tests can run against a stale Blazor build

## Metadata

- **Epic**: Testing
- **Type**: Bug
- **Interfaces**: UI

## Summary

The E2E suite serves a published copy of the Blazor app. The target that produces that copy can decide it is up to date when it is not, so the browser tests can exercise code that is no longer on disk. A green E2E run is therefore not proof that the current code works.

## User story

As a contributor, I want a green E2E run to prove the code in my working tree works, so that I can trust the suite before opening a pull request.

## Background

`tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj` defines `PublishBlazorForE2E`, which runs `dotnet publish --no-build` before `VSTest`. `StackFixture` then serves `src/Frontend/AHKFlowApp.UI.Blazor/bin/<Configuration>/<TargetFramework>/publish/wwwroot`.

Three things combine into the bug:

1. The freshness inputs exclude `bin/` and `obj/`, so the compiled output the publish actually copies is not an input. MSBuild can call the target up to date after a rebuild.
2. `--no-build` means the publish copies whatever is in `bin/` at that moment. It never triggers a compile of its own.
3. The destination is never cleaned. Old hashed files such as `AHKFlowApp.UI.Blazor.<hash>.wasm` pile up next to new ones.

This was hit for real while implementing item 044. Two hashed copies of the UI assembly sat in the publish folder at once. A deliberately broken build — the new component parameters removed from `HotkeyEditDialog.razor` — passed a full 31-test E2E run. Only after deleting the publish folder did the run fail, correctly. The reliable procedure turned out to be an explicit `dotnet build`, then `dotnet publish`, then `test-fast.ps1 -Mode E2E -NoBuild`.

A test that cannot fail is worse than no test. This one hides regressions and wastes the time of whoever is chasing them.

## Acceptance criteria

- [ ] An E2E run after a source change always exercises that change, with no manual publish step
- [ ] The publish destination holds exactly one copy of the app, so stale hashed assets cannot be served
- [ ] Deliberately breaking a component that an E2E test asserts on makes that test fail on a normal `test-fast.ps1 -Mode E2E` run
- [ ] `docs/development/testing-workflow.md` describes whatever the resulting procedure is

## Out of scope

- Rewriting how the E2E suite hosts the app. `SpaHost` serving a published folder is fine; only its freshness is in question
- Making the E2E slice faster

## Notes / dependencies

- Target: `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`, `PublishBlazorForE2E`
- Fixture: `tests/AHKFlowApp.E2E.Tests/Fixtures/StackFixture.cs`
- Found while implementing item 044, and confirmed independently by a second reviewer
