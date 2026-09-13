# 156 - E2E boot dies on network change during framework downloads

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: E2E tests
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

In CI, two E2E tests on two different stacks failed within the same second. In both, the
browser reported `net::ERR_NETWORK_CHANGED` while downloading framework files, and the Blazor
app never started. The cause is Docker cleanup from another test project that runs at the same
time (see Findings). This item runs the E2E project on its own in CI, so no other project can
remove a container during an E2E boot. It also makes a first page load that still hits the error
name the network change as the likely cause.

Difficulty is `moderate`: the cause is known, and the fix is one CI step, one test helper
message, and their tests. No design question is left. This item was filed as 155 and renumbered
to 156, because backlog 140 took 155 on `main` first.

## User story

As a developer, I want an E2E run to stay green when the CI runner's network changes for a
moment, so that I do not run CI again for a failure my change did not cause.

## Evidence

CI run 34714058897, attempt 1, job `build-test`, on 2026-09-12, for pull request 411. 73 of 75
E2E tests passed. The two failures:

| Test | SPA host | Gave up after | Documents loaded |
|---|---|---|---|
| `ShortcutWarningFlowTests.RemappingCapsLockToCtrl_WarnsAboutTheDestination` | `127.0.0.1:42967` | 3065 ms | 2 |
| `WindowSnapFlowTests.CreateSnapLeftHotkey_PreviewKeepsBlockBodyLines_ThenGridShowsWindowAction` | `127.0.0.1:38565` | 3301 ms | 2 |

Both failure messages come from `FirstPageLoad.OpenAsync`, which backlog 154 added. Both say
the page is showing the boot error screen. The browser's own errors, in order:

```
console.error: Failed to load resource: net::ERR_NETWORK_CHANGED
console.error: Error in mono_download_assets: Error: download 'http://127.0.0.1:42967/_framework/Microsoft.AI.EventCounterCollector.qk5fl2xhco.wasm' ... failed 0 TypeError: Failed to fetch
console.error: Blazor failed to start: Error: Failed to start platform. Reason: Error: download ... failed 0 TypeError: Failed to fetch
```

The failed downloads were framework `.wasm` files, and they differ between the two pages:

- `Microsoft.AI.EventCounterCollector`, on both hosts
- `Microsoft.Extensions.Diagnostics` and `System.Private.CoreLib`, on port 42967
- `System.Diagnostics.DiagnosticSource`, on port 38565

The log holds 586 lines with `ERR_NETWORK_CHANGED`.

What this suggests, not yet proven:

- The two pages talked to two different SPA hosts, and both broke in the same second. So the
  cause is most likely on the runner, not in one host process.
- `ERR_NETWORK_CHANGED` is Chromium reporting that the machine's network changed while requests
  were in flight. It cancels those requests, including requests to `127.0.0.1`.
- `bootBlazor.js` reloaded each page once, as designed, and the second boot failed as well.

The failed jobs were run again on the same commit, which is attempt 2 of the same run.

## Findings

Found on 2026-09-13 by reading CI job logs. The cause is Docker cleanup from another test project,
which runs at the same time as the E2E project on the same runner.

How it happens:

1. The CI step `Test with coverage` in `.github/workflows/ci.yml` runs one `dotnet test` for the
   whole solution. The test projects run in parallel on one runner.
2. `AHKFlowApp.Infrastructure.Tests` gets its SQL container from `SharedSqlContainer`. That
   container is process-scoped and is never disposed. The test process ends without deleting it.
3. Ryuk, the Testcontainers cleanup container, removes it later. Its documented default
   `RYUK_RECONNECTION_TIMEOUT` is `10s`: cleanup starts 10 seconds after the test process
   disconnects.
4. Removing a container removes a network interface on the runner. Chromium reports that as
   `ERR_NETWORK_CHANGED` and cancels its requests in flight, including requests to `127.0.0.1`.
5. An E2E page that is downloading framework files at that moment fails to boot. The reload in
   `bootBlazor.js` can fall into the same cleanup, because Ryuk removes more than one container.

The timing matches in every run that logged the error:

| CI run | `Infrastructure.Tests` ended | Plus 10 s | E2E boot |
|---|---|---|---|
| 34406127602, 2026-09-09 | 21:22:22.2 | 21:22:32.2 | failed at 21:22:32.7 |
| 34525483086, 2026-09-10 | 20:22:03.9 | 20:22:13.9 | failed at 20:22:15.8 |
| 34714058897, 2026-09-12 | 19:29:59.9 | 19:30:09.9 | both started about 19:30:09.3, failed about 3 s later |

`API.Tests` logs `Delete Docker container` for its own containers, at other moments, and no E2E
boot was downloading files then. The failure needs a boot in flight at the exact moment of a
removal, so it stays rare. Any test project that uses `SharedSqlContainer` can cause it.
`Infrastructure.Tests` is the one that ended while E2E boots were running in these runs.

How often: 3 of the 81 CI runs since 2026-09-09. A scan of every failed `build-test` job in the
last 200 CI runs found no other `ERR_NETWORK_CHANGED`. Console capture only exists since backlog
154, so older failures could not show the error.

Backlog 148 (CI run 34200726352, 2026-09-08) fits the same timing: `Infrastructure.Tests` ended at
07:47:41.9 and the WindowSnap test failed at 07:48:21.4 on a 30 second wait. That run captured no
console output, so this is consistent, not proven.

The browser does not give the app the network error. The app sees only
`TypeError: Failed to fetch`. `ERR_NETWORK_CHANGED` appears only in the browser's own
`Failed to load resource` console line. So `bootBlazor.js` cannot name the network change, but
`FirstPageLoad` can, because it reads the console.

The E2E project also uses a SQL container, in `E2ESqlServer`. That container goes away only when
the E2E process ends, so it cannot break an E2E boot.

## Acceptance criteria

- [ ] The item records the cause of the network change on the runner, with evidence, or records
      that the cause could not be found and what was checked.
- [ ] The CI job `build-test` runs the E2E test project in a step of its own, and no other test
      project runs while that step runs.
- [ ] A PowerShell suite fails when `ci.yml` runs the E2E test project together with another
      test project again.
- [ ] When a first page load fails and the browser reported `net::ERR_NETWORK_CHANGED`, the
      `FirstPageLoad` failure message names a network change on the runner as the likely cause.
      A failure without that error does not carry the sentence.
- [ ] A test in `FirstPageLoadDiagnosticsTests` proves the previous box in both directions.
- [ ] `FirstPageLoad.TimeoutMs` still reads 30000, and no E2E test retries automatically.

## Out of scope

- Retrying a whole failed E2E test automatically. Backlog 148 explains why a retry hides the
  signal.
- Raising the 30 second budget. Both pages gave up after about 3 seconds, on the boot error
  screen, so a longer wait would not help.
- Changing `bootBlazor.js`. The cause is in CI, not in the app. The script also cannot name the
  cause, because the browser gives it only `TypeError: Failed to fetch`.
- Disposing `SharedSqlContainer` inside the test process. A removal still changes the network,
  only at a different moment, while E2E may still run beside it.

## Notes / dependencies

- Follows backlog 154, which added the diagnosis that produced this evidence. It ships in pull
  request 411.
- Related: backlog 148 found the first failed boot in CI, and
  `backlog/blocked/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md` holds the
  repository's reasoning on failures seen only once.
- Spec: none — the cause is known from CI logs, and no design question is left
- Plan: none — not planned yet
