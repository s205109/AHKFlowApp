# 139 - Measure the E2E publish without Brotli compression

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test project build)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

The E2E publish step compresses every framework asset into `.br` and `.gz` siblings, and the E2E
SPA host may not need them. This item measures what `-p:CompressionEnabled=false` saves, and
whether the E2E stack still works without those files.

**The flag saves 2.65 s on a warm publish.** That is the compression-on median of 7.16 s minus the
compression-off median of 4.51 s, over five counterbalanced pairs. All five pairs saved time. The
full runs are in `## Measurement` below. This number replaces the preliminary 2.37 s to 4.85 s
range that two runs suggested earlier; those two runs were not counterbalanced and not evidence.

`## Findings` below records who reads the compressed output. Nothing in the E2E stack does. The
flag also changes one other file, the static web assets endpoint list, and it changes that file
only by removing the compression entries.

## User story

As a developer running the E2E slice, I want the publish to skip work the test host never reads,
so that a run starts testing sooner.

## Acceptance criteria

- [ ] Five paired warm runs are recorded in this item, five with `-p:CompressionEnabled=false` and
      five without, with every run, the median and the maximum for each set.
- [ ] This item states the saving as the difference of those two medians, and that number replaces
      the preliminary 2.37 s to 4.85 s range in the Summary.
- [ ] The item states whether the E2E SPA host reads the `.br` or `.gz` files, and whether the
      service worker or the PWA tests depend on them. Name the code that decides, in
      `tests/AHKFlowApp.E2E.Tests`, and quote it.
- [ ] If the flag is adopted, `pwsh ./scripts/test-fast.ps1 -Mode E2E` passes and reports the same
      test count as before the change.
- [ ] If the flag is not adopted, this item records the reason and closes.

## Out of scope

- Skipping the publish, or any up-to-date check on the publish target. Backlog 131 measured that
  and closed it.
- Any change to what the E2E tests assert.
- The `.br` and `.gz` files in a real deployment. This is about the E2E publish only, and a
  deployed app does want them.

## Findings

Task 1 published `src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj` twice in
`Release` on 2026-09-07, with .NET SDK 10.0.400. One publish used the normal command, the other
added `-p:CompressionEnabled=false`. Nothing else differed, and no timing was taken.

### The flag removes the compressed files and changes one other file

| Publish | `.br` files | `.gz` files | Other files |
|---|---|---|---|
| Normal | 207 | 207 | 217 |
| With `-p:CompressionEnabled=false` | 0 | 0 | 217 |

Both inventories list every file that is not a `.br` or `.gz` sibling, each with its SHA-256. The
two lists hold 217 files each. They agree on 216 of them, `wwwroot/service-worker-assets.js`
included.

They disagree on one file: `AHKFlowApp.UI.Blazor.staticwebassets.endpoints.json`, the static web
assets endpoint list. That file declares every URL the published output can serve, and the `.br`
and `.gz` URLs are declared in it, so the flag has to change it.

### That file changes only by dropping the compression entries

| Measure | Normal | With the flag |
|---|---|---|
| Endpoint entries | 2041 | 417 |
| Entries after removing every `.br` and `.gz` route and every `Content-Encoding` entry | 417 | 417 |

Comparing those two reduced sets by route, asset file and selectors together gives no difference
at all. So the flag removes 1624 compression entries and leaves the other 417 untouched. No plain
URL changed, and no URL started pointing at a different file.

### Who reads the compressed output

1. The E2E SPA host does not read `.br` or `.gz`. It serves the published wwwroot through one
   `PhysicalFileProvider` and one static files middleware, with no content negotiation
   (`tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs:61`, "app.UseStaticFiles(new StaticFileOptions").
2. The service worker never registers during an E2E run. The host binds to `127.0.0.1`
   (`tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs:21`, "builder.WebHost.UseUrls("), and the
   registration script treats that hostname as local development
   (`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/registerServiceWorker.js:3`, "window.location.hostname === '127.0.0.1' ||").
   On that branch it unregisters any worker and returns
   (`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/js/registerServiceWorker.js:9`, "if (isLocalDevelopmentHost) {").
3. Even if it did register, it would not ask for a compressed file. The published worker requests
   each asset by its plain URL and checks the manifest hash
   (`src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/service-worker.published.js:26`, "integrity: asset.hash").
   The manifest file name comes from the Blazor project
   (`src/Frontend/AHKFlowApp.UI.Blazor/AHKFlowApp.UI.Blazor.csproj:6`, "<ServiceWorkerAssetsManifest>").
4. No test under `tests/` mentions a service worker, so no PWA test depends on the compressed
   files.
5. No test under `tests/` reads the static web assets endpoint list either. The E2E SPA host never
   opens it, and the file sits at the publish root rather than inside wwwroot, so the host does not
   even serve it.

Nothing in the E2E stack reads the `.br` and `.gz` files, and nothing reads the one other file the
flag changes.

## Measurement

Task 2 ran five counterbalanced pairs on 2026-09-07. Each pair publishes twice, once with
compression and once with `-p:CompressionEnabled=false`, and deletes the output folder before each
publish. Odd pairs publish with compression first, even pairs publish without it first, so neither
setting always gets the warm second slot. Two extra publishes ran first and were discarded, one of
each kind.

Conditions:

- Commit `1f0a24e4`, branch `chore/wt-e2e-publish-without-brotli`, working tree clean.
- .NET SDK 10.0.400, `Release`, `--no-restore --disable-build-servers -p:UseSharedCompilation=false`.
- Intel Core i9-11900H, 8 cores and 16 logical processors, 32 GB RAM, Windows 11 Pro 10.0.26200.
- Every publish was warm. No code changed during the run, and nothing else built at the time.

| Set | Runs (s) | Median (s) | Max (s) |
|---|---|---|---|
| Compression on | 7.67, 7.59, 5.87, 6.68, 7.16 | 7.16 | 7.67 |
| Compression off | 4.37, 4.82, 4.45, 4.51, 5.91 | 4.51 | 5.91 |

| Pair | Order | On (s) | Off (s) | Saving (s) |
|---|---|---|---|---|
| 1 | on first | 7.67 | 4.37 | 3.30 |
| 2 | off first | 7.59 | 4.82 | 2.77 |
| 3 | on first | 5.87 | 4.45 | 1.42 |
| 4 | off first | 6.68 | 4.51 | 2.17 |
| 5 | on first | 7.16 | 5.91 | 1.25 |

Saving, compression-on median minus compression-off median: 2.65 s.
Pair savings above zero: 5 of 5.

The compression-on median of 7.16 s is well below the 12.37 s median this item first recorded. The
earlier number came from a tree that was not as warm. The saving is the difference between the two
sets measured together, so it does not depend on that.

## Decision

**Adopt the flag.** The plan's rule adopts when the saving is at least 2 s and all five pair
savings are above zero. The saving is 2.65 s, and 5 of 5 pairs saved time. Both conditions hold,
so no extension run is needed.

This outcome was written down before any file changed.

### What changed

- `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj` — the `PublishBlazorForE2E` target's
  `Exec` gained `-p:CompressionEnabled=false`, with a comment above the target saying why the flag
  belongs there and not in the Blazor project file.
- `tests/AHKFlowApp.CLI.Tests/Launcher/E2EPublishTargetTests.cs` — one more `Contain` assertion, so
  the flag cannot be dropped without a test failing. Written first, watched fail, then made pass.
- `tests/AHKFlowApp.E2E.Tests/PublishFreshnessTests.cs` — the comment no longer says the `.br` and
  `.gz` siblings are skipped by the file patterns, because those siblings no longer exist.

### E2E slice, before and after

| Run | Failed | Passed | Total | Duration |
|---|---|---|---|---|
| Before the change | 0 | 57 | 57 | 3 m 51 s |
| After the change | 0 | 57 | 57 | 3 m 53 s |

The test count is the same, so the change did not alter discovery. The slice duration did not drop.
A 2.65 s saving is small next to a run of nearly four minutes, and run-to-run noise is larger than
that, so the slice total cannot show the saving. The paired measurement above is what measures it.

## Notes / dependencies

- Filed out of backlog 131, which measured the publish step while answering a different question.
- The publish command is in `tests/AHKFlowApp.E2E.Tests/AHKFlowApp.E2E.Tests.csproj`, in the target
  that runs before `VSTest`.
- The two preliminary runs behind the range above are in
  `docs/superpowers/plans/2026-09-06-e2e-incremental-publish-plan-131.md`.
- Compression is a Blazor publish feature, so prove the property name against the official .NET
  documentation for the version in `Directory.Packages.props` before relying on it.
- Spec: none — the change is one build property and a measurement.
- Plan: `docs/superpowers/plans/2026-09-07-e2e-publish-compression-plan-139.md`
