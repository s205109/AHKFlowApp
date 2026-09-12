# 155 - E2E boot dies on network change during framework downloads

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: E2E tests
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

In CI, two E2E tests on two different stacks failed within the same second. In both, the
browser reported `net::ERR_NETWORK_CHANGED` while downloading framework files, and the Blazor
app never started. This item finds out why, and makes a boot survive it or fail in a way that
names the runner rather than the test.

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

## Acceptance criteria

- [ ] The item records the cause of the network change on the runner, with evidence, or records
      that the cause could not be found and what was checked.
- [ ] A boot that fails on `ERR_NETWORK_CHANGED` either recovers, or fails with a message that
      names the network change as the likely cause.
- [ ] A durable test shows the chosen behaviour when a framework download fails with a network
      error.
- [ ] `FirstPageLoad.TimeoutMs` still reads 30000, and no E2E test retries automatically.

## Out of scope

- Retrying a whole failed E2E test automatically. Backlog 148 explains why a retry hides the
  signal.
- Raising the 30 second budget. Both pages gave up after about 3 seconds, on the boot error
  screen, so a longer wait would not help.

## Notes / dependencies

- Follows backlog 154, which added the diagnosis that produced this evidence. It ships in pull
  request 411.
- Related: backlog 148 found the first failed boot in CI, and
  `backlog/blocked/068-two-flaky-tests-fail-intermittently-in-full-suite-runs.md` holds the
  repository's reasoning on failures seen only once.
- Spec: none — not designed yet
- Plan: none — not planned yet
