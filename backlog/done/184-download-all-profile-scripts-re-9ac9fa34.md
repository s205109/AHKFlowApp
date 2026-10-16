# 184 - Download all profile scripts returns nothing for a brand-new owner

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: API | CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

A brand-new owner who downloads all profile scripts before any other request gets an empty zip.
The download must return the Default profile script that the app guarantees every owner has.

## User story

As an owner, I want my first download of all scripts to hold my Default profile script, so that
I do not have to open another page first to get a working file.

## Acceptance criteria

- [x] `GET /api/v1/downloads/zip` for an owner who has never called `GET /api/v1/profiles`
      returns a zip with one entry, `ahkflow_Default.ahk`.
- [x] After that download, `GET /api/v1/profiles` returns that same single Default profile, not a
      second one.
- [x] No test asserts that the zip for a brand-new owner is empty.

## Out of scope

- The lazy-seeding design itself. Backlog 174 kept it and so does this item.
- An owner who creates a profile before the first read, and so never gets a Default profile.
  `EnsureDefaultProfileAsync` seeds only when the owner has no profile at all.
- The single-profile download and preview. Both take a profile id, which a brand-new owner
  cannot know before a profile read has seeded it.

## Notes / dependencies

- GitHub issue: https://github.com/s205109/AHKFlowApp/issues/443
- Found by the Simplify altitude review and the Stage 8 review of #441 (backlog 174).
- Root cause, as the code stood at commit 20be9b41. This item's fix moves both lines below, so
  they are records of the old tree and the citation check skips them.
  - `GenerateAllProfileScriptsQueryHandler` reads the owner's profiles directly: (`src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsQuery.cs:24`, "List<Profile> profiles = await db.Profiles.AsNoTracking()") <!-- citation-check:ignore — pre-fix line at 20be9b41 -->
  - When it finds none, it returns an empty list: (`src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsQuery.cs:30`, "return Result.Success<IReadOnlyList<ProfileScript>>([]);") <!-- citation-check:ignore — pre-fix line at 20be9b41 -->
- Before this fix, only two handlers called `EnsureDefaultProfileAsync`: `ListProfilesQuery` and
  `GetDashboardStatsQuery`. The method is defined here:
  - (`src/Backend/AHKFlowApp.Application/Common/DefaultProfileSeeding.cs:12`, "internal static async Task EnsureDefaultProfileAsync(")
- The web UI is not affected in practice. The Downloads page lists profiles on load, which seeds
  the Default profile before the button is enabled:
  - (`src/Frontend/AHKFlowApp.UI.Blazor/Pages/Downloads.razor:95`, "ApiResult<IReadOnlyList<ProfileDto>> result = await ProfilesApi.ListAsync(_cts.Token);")
- The CLI command `ahkflow download zip` calls the zip endpoint directly, so a new CLI user hits
  the bug.
- The old test `GET_zip_with_no_profiles_returns_empty_zip` asserted the bug as correct behavior.
  The fix replaced it.
- Spec: none — the fix is one seeding call, the same one backlog 174 added to the dashboard.
- Plan: none — one added call plus updated tests. The user asked for the change directly on
  2026-10-16.
