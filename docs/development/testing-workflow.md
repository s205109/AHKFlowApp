# Local testing workflow

Use the fastest test slice that still covers the code you changed. The pre-push hook runs an incremental build plus the fast slice automatically; run the full coverage gate yourself before you mark a PR **ready** (CI enforces it on every PR with at least one changed path that `.github/code-paths-filter.yml` does not exclude).

This file is the single source for which tests to run and when. Other docs link here rather than restating commands.

## Housekeeping worktree

For small, unrelated doc or config tweaks — backlog notes, minor rule edits, one-off cleanups — that don't warrant their own branch, keep one long-lived worktree open, e.g. `chore/wt-backlog-housekeeping`. Commit each change to it immediately, as its own commit, so it shows up in git history right away — don't leave it staged or uncommitted. Don't open a PR after every commit. Once the branch holds a few of these, open the PR and start a fresh housekeeping worktree for the next round. If one change **grows in importance**, it does not close the round: it leaves the round and becomes tracked work of its own. See [`workflow.md`](workflow.md#stage-4-execute) for that route — publishing non-trivial work inside the housekeeping PR skips its whole tracked workflow.

<a id="canonical-pre-pr-gate"></a>

## The Gate — run it before you mark a PR ready

Five steps, in order. Nothing else counts as the gate.

**When it runs.** A draft pull request opens at Pickup, before any of this work exists, so
this is not a gate on *creating* a pull request. It gates the pull request going **ready**:
it runs at [Verify](workflow.md#stage-6-verify) and must be green before
[Ship](workflow.md#stage-9-ship) flips the PR out of draft. The anchor above keeps the old
`#canonical-pre-pr-gate` link working; the name changed, the target did not.

```bash
dotnet build AHKFlowApp.slnx --configuration Release
dotnet format AHKFlowApp.slnx --verify-no-changes
pwsh .\scripts\test-fast.ps1 -Mode PowerShell
pwsh .\scripts\test-fast.ps1 -Mode Coverage
git diff --check main...HEAD
```

Pass the `<base>...HEAD` range to `git diff --check`. The bare form inspects only uncommitted work, so on a clean branch it passes without ever looking at the commits you are about to propose. Run the bare form as well if you have changes still in flight.

`<base>` is `main` for ordinary work, but **not for a stacked PR**. Stacked work branches from another open branch via `-BaseRef`, and `main...HEAD` would then include the prerequisite branch's commits — failing your PR on someone else's whitespace. Read the real base and use it:

```bash
gh pr view --json baseRefName -q .baseRefName
git diff --check "$(gh pr view --json baseRefName -q .baseRefName)...HEAD"
```

**The coverage slice skips itself when it cannot measure anything.** Run the same command either
way. `-Mode Coverage` compares your branch against its base and skips when **every** changed file
matches one of the patterns in [`.github/code-paths-filter.yml`](../../.github/code-paths-filter.yml):
lowercase `.md` anywhere, anything under `docs/` or `.claude/`, any `.ps1` under `scripts/`, and
any `.ps1` directly in `tests/`. One file outside that list and the slice runs in full.

The list is a deny-list, so read it that way round: the slice runs for any path nobody excluded,
not only for a path the build compiles. A `.cs` file and a `.csproj` run it, and so do
`.github/workflows/ci.yml`, `.github/code-paths-filter.yml`, `Directory.Packages.props`, and
`scripts/ci/check-coverage-thresholds.py`. None of those last four compile. A pattern nobody
wrote costs a few minutes; it never costs coverage.

Renames count as two paths. Moving `src/Foo.cs` to `docs/Foo.md` still runs the slice, because the
build lost a file. Matching is case-sensitive: `scripts/Thing.PS1` is not `scripts/Thing.ps1`, and
`README.MD` is not `README.md`. Only lowercase `.md` is excluded.

The same file lists seven scripts under `coverage-tooling`. Changing one of those runs the slice
even though the patterns above exclude it, because the coverage step is the only local check that
runs `run-coverage.ps1` and what it loads.

A skip prints the base ref, every changed file, and the pattern that excluded it, so a green Gate
never looks like it checked more than it did. Pass `-Force` to run the slice anyway. When the
check itself cannot decide, it says so and runs the slice.

`ci.yml` reads the `code` patterns from that same file, so the two cannot drift apart. CI ignores
`coverage-tooling`, and that is correct rather than a gap: CI never runs `run-coverage.ps1`. Its
coverage step is a plain `dotnet test`. So on those seven paths this Gate is stricter than CI, and
never looser.

Then verify the change actually works — see **Verification After Implementation** in [`AGENTS.md`](../../AGENTS.md). A green gate proves nothing regressed; it does not prove the new behavior happened.

CI enforces the same build, format, and coverage-threshold steps, and it decides whether to run
them from the same file the local slice reads, `.github/code-paths-filter.yml`. On a pull request
whose changed files all match those patterns, the `build-test` job still starts, but every one of
its .NET steps is skipped — build, test, coverage, thresholds, and the format check are all
guarded by the `dorny/paths-filter` step in `ci.yml`. Nothing in those steps can fail on a diff
the filter excluded in full.

Two things still run on such a pull request. The changelog check
(`scripts/ci/generate-changelog-json.ps1 -Check`) sits above that filter in `build-test`, so it
runs on every pull request. And the `powershell-suites`, `codex-skills-hash-parity`, and
`bicep-lint` jobs carry no filter at all, so they run on every pull request too. Nothing checks
the .NET side of such a branch, which makes this local gate matter more there, not less. The
pre-push hook is a faster subset (incremental build + fast slice,
`scripts/pre-push-quick-checks.ps1`), not this gate.

## Fast inner loop

```bash
pwsh .\scripts\test-fast.ps1 -Mode Fast
```

Fast mode runs:

- `AHKFlowApp.Domain.Tests`
- `AHKFlowApp.TestUtilities.Tests`
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

Use this for EF Core, migrations, use case handlers that touch `AppDbContext`, API behavior, CLI integration flows, SQL query behavior, and anything that changes persistence wiring.

The script starts one disposable Docker SQL Server container for the selected SQL-backed projects, passes the server connection to the test processes, and removes the container when the run finishes. Direct `dotnet test` still falls back to the per-project Testcontainers fixture path.

Only mixed projects use `Category=Integration` in v1. Whole-project SQL/API suites are selected by project instead of traits.

## Browser and PWA tests

```bash
pwsh .\scripts\test-fast.ps1 -Mode E2E
```

E2E mode runs `AHKFlowApp.E2E.Tests`. Use it for browser flows, Playwright-covered UI behavior, mobile viewport behavior, service-worker/PWA behavior, and changes to the E2E fixture or published Blazor output. The script starts the same disposable shared SQL Server container used by Integration mode, and the E2E API fixture uses an isolated per-assembly database on that server.

A normal E2E run builds the project and its references. Every E2E run clears the Blazor publish folder, then publishes the app again before Playwright starts. That publish compiles and links the current source, so the browser always loads the code in your working tree. `-NoBuild` skips the solution build, but the Blazor publish still runs, so the app under test stays current. E2E flow classes share one API/Spa/browser stack, and each test resets mutable database rows before it starts.

### Writing a flow test

A UI change is verified by adding or extending a `*FlowTests.cs`. The shape — copy it from a neighbour such as `HotkeysCrudFlowTests.cs`:

```csharp
[Collection(E2ETestCollection.Name)]
public sealed class MyFeatureFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task DoingTheThing_ProducesTheVisibleResult()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.ClickAsync("[data-test=\"some-control\"]");

        await Assertions.Expect(page.Locator("[data-test=\"result\"]"))
            .ToContainTextAsync("expected");
    }
}
```

Four rules that are easy to get wrong:

- **Select on `data-test`**, not MudBlazor's generated classes — they change between MudBlazor versions.
- **Scope grid assertions to `.desktop-branch` or the mobile branch.** Both render into the DOM; the mobile one is hidden by CSS only, so an unscoped selector can match twice.
- **`MudAutocomplete` with `CoerceValue` needs a blur to commit.** `FillAsync` sets the text but not the bound value — follow it with `PressAsync("Tab")`.
- **Debounced fields only refresh a preview while the panel is already open.** Expand first, then fill, or the preview stays stale.

Assert on something a user would see — rendered text, a grid cell, a snackbar — not on internal component state.

## PowerShell script suites

```bash
pwsh .\scripts\test-fast.ps1 -Mode PowerShell
```

This mode runs every non-excluded `tests/*.Tests.ps1` suite through
`scripts/run-powershell-suites.ps1`. Use it when you change a git hook, a worktree script, the
backlog numbering rules, or the skill layout.

Each suite runs as its own process, so one failing suite does not stop the rest. The run prints a
table naming every suite, its result, and how long it took. The whole run takes about three minutes.

`CodexSkillsHashParity.Tests.ps1` is skipped. CI runs it in its own Linux job, because the bash
script it compares against refuses to run under Windows Git Bash.

CI runs the same script in the `powershell-suites` job, and that job has no docs-only filter, so it
runs on every PR.

## Full coverage gate

```bash
pwsh .\scripts\test-fast.ps1 -Mode Coverage
```

Coverage mode delegates to `scripts/run-coverage.ps1`. Run it before you mark a PR ready; CI enforces the same coverage + threshold gate on every pull request with at least one changed path that `.github/code-paths-filter.yml` does not exclude. The pre-push hook itself only runs quick checks (incremental build + fast slice, see `scripts/pre-push-quick-checks.ps1`), not this full coverage path. The local coverage script uses the same disposable shared SQL container behavior as Integration mode for the SQL-backed suites. Coverage mode skips itself when the branch changed no compiled file — see the Gate section above for the condition and the `-Force` switch. `run-coverage.ps1` makes no such check: calling it directly always runs the full slice.

### One test run at a time

`test-fast.ps1` and `run-coverage.ps1` share one exclusive lock file, `.test-run.lock`, at the
repository root. The second of those two scripts to start fails immediately and names the
first run's mode and process id. This includes the pre-push hook, which runs the Fast slice.

The lock only covers those two scripts. A `dotnet test` or `dotnet build` you type yourself,
and a build started from an IDE, take no lock and can still collide with a run in progress.
The completeness check below is what catches that case.

The lock exists because two runs in one repository destroy each other's coverage data.
coverlet instruments every assembly in a test project's output folder at test-session start.
When another run holds one of those files open, instrumentation fails and coverlet writes **no**
coverage file for that project — while `dotnet test` still exits 0.

The old result was a coverage-threshold failure with no real cause, several hundred lines below
the file-lock error that produced it. Two checks now stop that. `run-coverage.ps1` compares the
coverage files each test project produced against the projects the solution names, and refuses
to report when any are missing. The threshold gate reports a missing assembly under
`Coverage input incomplete`, not as a threshold failure.

Different worktrees do not collide. Each has its own repository root, its own `bin` folders, and
its own lock file.

If a run is killed, Windows releases the lock automatically. Never delete `.test-run.lock` to
recover. Only a live run blocks you, and the file stays on disk between runs by design. A
leftover `.test-run.lock.owner` file alone never blocks a run either.

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
- `HistoryDb`

`CLI.Tests` classes using `CliWebApi` must also have `[Trait("Category", "Integration")]`.

Guard tests run in Fast mode and fail if a DB/API-backed class is missing the trait, preventing integration tests from leaking into the fast local slice.
