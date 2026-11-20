# 215 - Restored snapshot tooltip test flakes after reload

## Metadata

- **Epic**: Test reliability
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan
- **Issue**: #490

## Summary

The E2E test `VersionHistoryFlowTests.RestoreOfSnapshotFailingCurrentRules_WarnsThenStillSaysWhyAfterAReload`
fails some of the time on CI. After the reload it hovers the "No profile" chip, and no open
tooltip appears within 5 seconds. It failed in CI runs 43961612031, 43968017996 and
44246967539, on two different branches.

## Root cause

The "No profile" chip moves down after the test hovers it, so the pointer is no longer over it
and the tooltip closes before the assertion sees it open.

- The page shows the category filter chips above the grid (`src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor:65`, "<CategoryFilterChips Categories=").
- That component renders nothing until the list has items (`src/Frontend/AHKFlowApp.UI.Blazor/Components/Common/CategoryFilterChips.razor:3`, "@if (Categories.Count > 0)").
- `OnInitializedAsync` fills that list only after three calls in a row: preferences, profiles, then categories (`src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotstrings.razor:351`, "await CategoriesApi.ListAsync("). The grid loads its rows on its own, with one call. So the rows often appear first.
- The test user always has categories. The first category list call seeds the defaults (`src/Backend/AHKFlowApp.Application/Queries/Categories/ListCategoriesQuery.cs:38`, "await EnsureSeededOnceAsync(ownerOid, ct);").
- The test hovers as soon as the row shows (`tests/AHKFlowApp.E2E.Tests/VersionHistoryFlowTests.cs:316`, "HoverAsync();").

**Reproduced on 2026-11-20.** A temporary probe held the `/api/v1/categories` response until
the hover was done, then released it. The chip moved from y=278.875 to y=326.875, and the test
failed with the CI message: `element(s) not found 'It breaks these rules: Value under Window
context must not contain double quotes.' But was: 'null'`. The same run without the hold
passed. With a 2 second fixed delay instead, the test passed: the tooltip opened and the
assertion passed before the chips arrived. So the test fails only when the chips arrive in the
short window after the hover and before the assertion's first check.

A person sees the same jump of the grid for a moment after the page opens. That is a minor
layout shift, not the defect this item fixes.

## User story

As a developer, I want this E2E test to pass every time the product works, so that a red CI
run means a real problem.

## Acceptance criteria

- [ ] The item states the root cause, with `file:line` evidence or a log line.
- [ ] `RestoreOfSnapshotFailingCurrentRules_WarnsThenStillSaysWhyAfterAReload` passes in 30 repeated local runs in a row.
- [ ] The test still checks that the "No profile" tooltip names the broken rule after a reload.

## Out of scope

- Other flaky E2E tests. File each one as its own item.

## Notes / dependencies

- GitHub issue #490 holds the triage comment and the first guess at the cause.
- The failing assertion is at (`tests/AHKFlowApp.E2E.Tests/VersionHistoryFlowTests.cs:317`, "await Assertions.Expect(page.Locator(").
- Spec: <path, or "none — reason">
- Plan: <path, or "none — reason">
