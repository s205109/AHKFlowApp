# 177 - Dev-only config files ship in the published bundle

## Metadata

- **Epic**: CI/CD
- **Type**: Chore
- **Interfaces**: none (frontend project file, published output)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

Three committed dev-only config files in the Blazor `wwwroot` folder have no publish exclusion, so
`dotnet publish` copies them into the public bundle and the published service worker caches them.
Each one carries the switch that turns authentication off. A fourth file,
`appsettings.Development.json`, is kept out of git rather than out of the folder, so a publish run
on a developer's machine copies that one as well.

## User story

As a maintainer, I want the published bundle to hold only the files the published app needs, so
that it does not advertise a test-auth switch.

## Acceptance criteria

- [ ] `appsettings.Local.json`, `appsettings.E2E.json` and `appsettings.NoAuth.json` are absent
      from the published `wwwroot`.
- [ ] `appsettings.Development.json` is absent from the published `wwwroot` on a machine where
      that file exists, which is every developer's machine.
- [ ] Local development, the E2E run and the no-auth run all still read their config.
- [ ] A check or a test proves a published bundle holds no `appsettings` file other than the ones
      the app needs at run time.

## Out of scope

- Changing how the frontend resolves its environment.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F26, S4. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- All three files are committed under `src/Frontend/AHKFlowApp.UI.Blazor/wwwroot/`, and the
  project file has no publish exclusion for them. Each holds
  `{ "Auth": { "UseTestProvider": true } }`. `appsettings.E2E.json` and `appsettings.Local.json`
  also set `"ApiHttpClient": { "BaseAddress": "/" }`.
- The published worker then caches them for offline use. `service-worker.published.js` includes
  `/\.json$/` in `offlineAssetsInclude`, and `offlineAssetsExclude` holds only
  `/^service-worker\.js$/`.
- **`.gitignore` does not exclude a file from a publish.** The Blazor WebAssembly SDK takes
  `wwwroot` content from the disk, and `AHKFlowApp.UI.Blazor.csproj` has no exclusion for any
  `appsettings` file. `.gitignore` keeps `**/appsettings.Development.json` out of git, which
  is why CI publishes without it, and why a developer who copied the example file publishes with
  it. The publish guarantee has to be about the folder on disk, not about what git tracks.
- **This is not a way in**, and the item should not be read as a vulnerability.
  `AHKFlowApp.UI.Blazor/Program.cs` reads `Auth:UseTestProvider` from `builder.Configuration`,
  which is filled from `appsettings.json` plus `appsettings.{Environment}.json`. On .NET 10 a
  standalone Blazor WebAssembly app fixes that environment at build time, through the
  `WasmApplicationEnvironmentName` MSBuild property, which is baked into `_framework/dotnet.js`.
  The `Blazor-Environment` response header is no longer read. Completed item 049 records that
  change and cites the .NET 10 release notes. So a visitor cannot choose the environment at all,
  from the URL or from any header. Downloading these files tells somebody that a test-auth switch
  exists. It does not let them use it.
- AGENTS.md already states the related rule under **Security**: "Blazor WASM
  `wwwroot/appsettings*.json` is public (downloadable by any user) — never treat it as secret."
  The project knows the folder is public. These three files are dev-only, so they do not need to
  be in it.
- Spec: none — this is a publish-exclusion change.
- Plan: none — moderate work, goes straight to Plan at pickup.
