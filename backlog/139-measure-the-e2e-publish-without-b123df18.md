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

**The saving is preliminary, and the number below is not yet a ceiling.** Two runs with the flag
gave 7.52 s and 10.00 s against a 12.37 s median for the normal publish, so the observed saving
ranges from 2.37 s to 4.85 s. Two runs are not evidence, and the two are 2.48 s apart, which is
most of the range itself. The first task is five paired runs, and only those fix the real ceiling.

Nothing here says the change is safe yet either. `SpaHost` calls `app.UseStaticFiles` with no
compression negotiation (`tests/AHKFlowApp.E2E.Tests/Fixtures/SpaHost.cs:61`, "app.UseStaticFiles(new StaticFileOptions"),
which is a starting point and not a finding. The service worker and the PWA tests read
`service-worker-assets.js`, which lists asset hashes, so check those before calling the flag
harmless.

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
