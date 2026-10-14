# 181 - Dev seed endpoint tests hard-code catalog counts

## Metadata

- **Epic**: Development process
- **Type**: Chore
- **Interfaces**: none (API test project, one production `.csproj`)
- **Difficulty**: moderate
- **Stage**: 3-plan

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

## Out of scope

- Changing the seed catalogs themselves.
- Seed count assertions in other test projects. They can join this item if a search finds any.

## Notes / dependencies

- Found while planning backlog 173, grilling decisions 3 and 6. Item 173 fixed the documented
  counts and added a test that holds the hotkeys summary in Swagger at the endpoint's real count.
- The hard-coded lines today: 27 (8 categories), 40 (19 hotkeys), 53 to 55, and 69 to 71
  (8, 16, and 19).
- The API test project cannot see the catalogs. `HotstringSeedSamples` and `DefaultHotkeyCatalog`
  are internal to `AHKFlowApp.Application`, and its `.csproj` grants internals only to
  `AHKFlowApp.Application.Tests` and `AHKFlowApp.TestUtilities`. The fix needs either a new
  `InternalsVisibleTo` entry for `AHKFlowApp.API.Tests`, or a helper in `AHKFlowApp.TestUtilities`
  that exposes the counts. Choose one at Design.
- `DefaultCategories` lives in `AHKFlowApp.Domain` and may already be public. Check before you
  plan the change.
- Spec: none yet.
- Plan: none yet.
