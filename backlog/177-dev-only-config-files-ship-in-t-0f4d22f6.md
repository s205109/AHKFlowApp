# 177 - Dev-only config files ship in the published bundle

## Metadata

- **Epic**: CI/CD
- **Type**: Chore
- **Interfaces**: none (frontend project file, published output)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Three dev-only config files in the Blazor `wwwroot` folder have no publish exclusion, so
`dotnet publish` copies them into the public bundle and the published service worker caches them.
Each one carries the switch that turns authentication off.

## User story

As a maintainer, I want the published bundle to hold only the files the published app needs, so
that it does not advertise a test-auth switch.

## Acceptance criteria

- [ ] `appsettings.Local.json`, `appsettings.E2E.json` and `appsettings.NoAuth.json` are absent
      from the published `wwwroot`.
- [ ] Local development, the E2E run and the no-auth run all still read their config.
- [ ] A check or a test proves a published bundle holds no `appsettings` file other than the ones
      the app needs at run time.

## Out of scope

- `appsettings.Development.json`, which `.gitignore` already excludes from the repository and
  from any published build.
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
- **This is not a way in**, and the item should not be read as a vulnerability.
  `AHKFlowApp.UI.Blazor/Program.cs` reads `Auth:UseTestProvider` from `builder.Configuration`,
  which is filled from `appsettings.json` plus `appsettings.{Environment}.json`. The environment
  comes from `builder.HostEnvironment`, which a Blazor WebAssembly app takes from the host's
  `blazor-environment` response header and otherwise defaults to `Production`. A visitor cannot
  choose it from the URL or from a request header they control. So downloading these files tells
  somebody that a test-auth switch exists. It does not let them use it.
- AGENTS.md already states the related rule under **Security**: "Blazor WASM
  `wwwroot/appsettings*.json` is public (downloadable by any user) — never treat it as secret."
  The project knows the folder is public. These three files are dev-only, so they do not need to
  be in it.
- Spec: none — this is a publish-exclusion change.
- Plan: none — moderate work, goes straight to Plan at pickup.
