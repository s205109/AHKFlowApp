# 174 - The dashboard profiles card under-reports and invents a state

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 7-document

## Summary

The dashboard shows 0 profiles until the owner visits the Profiles page, because the Default
profile is created lazily by the profiles query only. The same card then describes that profile
as "0 active", a state the domain does not have.

## User story

As an owner, I want the first screen to report the profile I actually have, so that I do not
think the app lost it.

## Acceptance criteria

- [ ] A brand-new owner's first view of `/` reports the profile count the app guarantees, with no
      visit to `/profiles` first.
- [ ] The profiles card footer uses words that match `CONTEXT.md`, which gives a Profile no
      active or inactive state.
- [ ] An integration test asserts the dashboard count for an owner who has never called
      `GET /api/v1/profiles`.

## Out of scope

- The lazy-seeding design itself, which the other entities share.
- The hotstring and hotkey counts, which the sweep found correct.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F2 and F3, both S3. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F2, the count.** `GET /api/v1/profiles` is what creates the Default profile. The dashboard
  reads counts without triggering that creation, so the first screen under-reports a profile the
  app guarantees exists. Measured:

  ```
  BEFORE /profiles:  { "total": 0, "active": 0, "default": 0 }
  GET /api/v1/profiles → creates and returns "Default" (isDefault: true)
  AFTER /profiles:   { "total": 1, "active": 0, "default": 1 }
  ```

- The browser console confirms the mechanism: loading `/` calls `/api/v1/dashboard/stats` and
  `/api/v1/preferences`, and never `/api/v1/profiles`.
- **F3, the word "active".** `Queries/Dashboard/GetDashboardStatsQuery.cs` passes
  `profilesTotal - profilesDefault` as the `Active` field, so "active" means "the number of
  profiles that are not the default". With one profile the footer reads "0 active · 1 default",
  which suggests the owner's only profile is switched off. `CONTEXT.md` gives a Profile no such
  state: it is "A named set of hotstrings and hotkeys that generates exactly one Profile script."
- Note the related difference found in another charter. `Queries/Profiles/ListProfilesQuery.cs`
  guards seeding with a row count rather than a marker, unlike hotstrings, hotkeys and
  categories. So profiles re-seed after a delete and the other three do not. Item 166 records why
  that matters for deletes.
- Spec: none — the fix is to seed or to count consistently, and to drop the invented word.
- Plan: `docs/superpowers/plans/2026-10-15-dashboard-profiles-card-plan-174.md`
