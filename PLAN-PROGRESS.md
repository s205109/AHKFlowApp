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
