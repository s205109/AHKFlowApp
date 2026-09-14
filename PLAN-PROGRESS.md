# Plan 156 progress

Plan: `docs/superpowers/plans/2026-09-13-e2e-step-runs-alone-plan-156.md`

## Task 1 - FirstPageLoad names a network change

Commit: `df8db515` (`test: 156 first page load names a network change`)

Red (Step 4), `dotnet test tests/AHKFlowApp.E2E.Tests --configuration Release --filter "FullyQualifiedName~FirstPageLoadDiagnosticsTests"`:

```
Failed AHKFlowApp.E2E.Tests.FirstPageLoadDiagnosticsTests.NetworkChangedBoot_Open_NamesTheNetworkChange [952 ms]
  Error Message:
   Expected thrown.Message "... console.error: Failed to load resource: net::ERR_NETWORK_CHANGED ..." to contain
   "The browser reported net::ERR_NETWORK_CHANGED. The network of the machine changed during the boot. Chromium
   then failed the downloads in flight, even from 127.0.0.1. The likely cause is the machine, not the app or this
   test. In CI this happened when another test process removed a Docker container. See backlog 156.".

Failed!  - Failed:     1, Passed:     8, Skipped:     0, Total:     9, Duration: 14 s - AHKFlowApp.E2E.Tests.dll (net10.0)
```

Green (Step 6), same filter:

```
Passed!  - Failed:     0, Passed:     9, Skipped:     0, Total:     9, Duration: 11 s - AHKFlowApp.E2E.Tests.dll (net10.0)
```

Green (Step 7), `pwsh ./scripts/test-fast.ps1 -Mode E2E`:

```
Passed!  - Failed:     0, Passed:    79, Skipped:     0, Total:    79, Duration: 1 m 36 s - AHKFlowApp.E2E.Tests.dll (net10.0)
```

## Task 2 - Each test project writes its own result file

Commit: `28dddee7` (`fix: 156 CI writes one trx per test project, not one shared file`)

Red (Step 2), `pwsh ./tests/CiBuildTestSteps.Tests.ps1` on the pre-fix `ci.yml`:

```
A dotnet test step must not set LogFileName. Every test project then writes that one file, and
each overwrites the one before. Pass --logger trx and let VSTest name each file.

CiBuildTestSteps tests failed with 1 problem(s).
```

Green (Step 5), same command after the logger fix:

```
CiBuildTestSteps tests passed.
```

Green (Step 7), `pwsh ./scripts/run-powershell-suites.ps1 -Suite 'CiBuildTestSteps*'`:

```
[1/1 done] CiBuildTestSteps.Tests.ps1  0.4s  elapsed 0s
CiBuildTestSteps tests passed.
All 1 suite(s) passed.
```

Step 6 (each mutation case proven red): both `Test-MutationCase` lines were pointed at a wrong
expected string, the suite failed with both mutations reported unmatched, then the file was
restored and rerun green.

## Task 3 - CI runs the E2E project alone

Commit: `384e79cc` (`fix: 156 CI runs E2E alone, before other test projects`)

Red (Step 2), `pwsh ./tests/CiBuildTestSteps.Tests.ps1` on the Task 2 `ci.yml` (still one test
step):

```
The build-test job must run dotnet test in two steps: the E2E project alone, then every other test
project.

CiBuildTestSteps tests failed with 1 problem(s).
```

Green (Step 4), same command after the split:

```
CiBuildTestSteps tests passed.
```

Green (Step 6), `pwsh ./scripts/run-powershell-suites.ps1 -Suite 'CiBuildTestSteps*'`:

```
[1/1 done] CiBuildTestSteps.Tests.ps1  0.6s  elapsed 1s
CiBuildTestSteps tests passed.
All 1 suite(s) passed.
```

Step 5 (every new mutation case proven red): all 16 `Test-MutationCase` expected strings and the
comment case's `-eq 0` were corrupted at once. The suite then failed with 17 problems, one per
corrupted assertion, each showing the real problem text next to the wrong expectation. The file
was restored from a backup and rerun green.

## CI verification

A stale-citation fix was needed first: `28dddee7` and `384e79cc` shifted line numbers in
`tests/powershell-suites.json` and `.github/workflows/ci.yml`, which broke three Tier 2 citations
in already-shipped backlog items (`backlog/done/129-*`, `backlog/done/131-*`,
`backlog/done/138-*`). Fixed in `4b4efd37`.

CI run [34823560770](https://github.com/s205109/AHKFlowApp/actions/runs/34823560770) on PR #413,
`build-test` job (`103910863841`), confirms every item in the plan's Verification checklist:

- `E2E tests with coverage` ran 08:39:18Z-08:42:20Z (3m 2s, 79 tests), before `Test with coverage`
  at 08:42:20Z-08:43:31Z (1m 11s).
- The E2E step ran `NetworkChangedBoot_Open_NamesTheNetworkChange` (counted in its 79 tests, the
  same total as the local `test-fast.ps1 -Mode E2E` run above).
- `Test with coverage`'s E2E assembly logged
  `No test matches the given testcase filter 'FullyQualifiedName!~AHKFlowApp.E2E.Tests.'` and ran
  0 tests there.
- No `WARNING: Overwriting results file` line appears anywhere in the job log.
- `Publish test results` logged `Reading files TestResults/**/*.trx (9 files, 12.5 MiB)`: 1 from
  the E2E step, 8 from the second step.
- `Enforce per-assembly coverage thresholds` passed for all five assemblies (Domain, Application,
  Infrastructure, API, UI.Blazor).
- Both `repo-invariants` and `build-test` (and every other CI job) reported `success`.

Time cost: the two test steps together ran 4m 13s (3m 2s + 1m 11s). Before this change, attempt 2
of CI run 34714058897 spent 3m 42s in the single combined `Test with coverage` step. The split
costs about 31 seconds of extra wall-clock time, mostly a second VSTest host startup, in exchange
for the E2E step never sharing a runner process with a project that leaves a container for Ryuk.
