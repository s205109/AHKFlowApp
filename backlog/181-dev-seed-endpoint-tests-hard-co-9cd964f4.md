# 181 - Dev seed endpoint tests hard-code catalog counts

## Metadata

- **Epic**: Development process
- **Type**: Chore
- **Interfaces**: API docs (one Swagger summary); otherwise test projects only
- **Difficulty**: moderate
- **Stage**: 6-verify

## Summary

`DevSeedEndpointTests.cs` hard-codes the seed counts 8, 16, and 19. `AGENTS.md` requires tests to
derive expected seed counts from the seed source. A catalog change today breaks these tests, even
when the endpoint is correct.

## User story

As a contributor, I want the seed endpoint tests to read their expected counts from the seed
catalogs, so that a catalog change does not break unrelated tests.

## Acceptance criteria

- [ ] No test in `tests/AHKFlowApp.API.Tests/Dev/DevSeedEndpointTests.cs` compares a seed count
      with a number literal.
- [ ] Each expected count in that file comes from `DefaultCategories.Names`,
      `HotstringSeedSamples.All`, or `DefaultHotkeyCatalog.All`.
- [ ] The DevController summary for the categories seed endpoint is guarded the same way the
      hotkeys summary is, or it no longer states a number.
- [ ] With one extra row added to each seed catalog, no test in `AHKFlowApp.API.Tests` or
      `AHKFlowApp.Application.Tests` fails, except the two Swagger summary tests in
      `DevSeedEndpointTests.cs`.

## Out of scope

- Changing the seed catalogs themselves. The plan's probe adds a row to each catalog for the length
  of a test run only.
- E2E tests. The probe run does not cover them, and a text search found no seed count there.

## Notes / dependencies

- Found while planning backlog 173, grilling decisions 3 and 6. Item 173 fixed the documented
  counts and added a test that holds the hotkeys summary in Swagger at the endpoint's real count.
- The hard-coded lines in `DevSeedEndpointTests.cs`, after `main` was merged in on 2026-10-14:
  28 (8 categories), 41 (19 hotkeys), 85 to 87, and 101 to 103 (8, 16, and 19).
- The API test project cannot see the catalogs. `HotstringSeedSamples` and `DefaultHotkeyCatalog`
  are internal to `AHKFlowApp.Application`, and its `.csproj` grants internals only to
  `AHKFlowApp.Application.Tests` and `AHKFlowApp.TestUtilities`. Plan grilling chose a helper in
  `AHKFlowApp.TestUtilities` over a new `InternalsVisibleTo` entry.
- `DefaultCategories` lives in `AHKFlowApp.Domain` and is public.
- The search for other seed counts found 35 more failing tests in 10 files, so they joined this
  item as an Extension, with criterion 4. Plan review round 1 found 5 of them, which compare
  category-link totals with row counts. The plan lists them all.
- Depended on backlog 182, now resolved. From 2026-10-13, every restore failed with NU1902 and
  NU1903 on `System.Security.Cryptography.Pkcs` and `System.Security.Cryptography.Xml`. Merge
  commit `d9cd0051` brought 182's fix from `main` into this branch before Task 1. Test commands no
  longer need `-p:NuGetAudit=false`.
- Spec: none — `moderate`, so the item goes from Pickup to Plan.
- Plan: `docs/superpowers/plans/2026-10-14-dev-seed-test-counts-plan-181.md`.
