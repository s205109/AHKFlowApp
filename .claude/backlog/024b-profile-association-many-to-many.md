# 024b - Many-to-many profile association

## Metadata

- **Epic**: Profiles
- **Type**: Refactor
- **Interfaces**: API

## Summary

Replace the single nullable `ProfileId` foreign key on `Hotkey` and `Hotstring` with junction tables (`HotkeyProfile`, `HotstringProfile`) plus an `AppliesToAllProfiles` boolean flag on each parent entity ("Any" semantics).

## User story

As a user, I want to assign a hotkey or hotstring to multiple profiles, or to "Any" (every profile, current and future), so I don't have to duplicate definitions per profile.

## Acceptance criteria

- [ ] `HotkeyProfile (HotkeyId, ProfileId)` and `HotstringProfile (HotstringId, ProfileId)` junction tables with composite primary keys and cascade-delete on the parent side.
- [ ] `AppliesToAllProfiles` (bool) added to both `Hotkey` and `Hotstring`. When true, the junction is empty for that row and the row is included in every profile's generated script (current and future).
- [ ] EF migration drops the existing nullable `Hotstring.ProfileId` (and `Hotkey.ProfileId` if 022b hasn't already removed it). Dev DBs are scratch (per spec D7); no copy-forward SQL.
- [ ] API DTOs gain `Guid[] ProfileIds` and `bool AppliesToAllProfiles`. Validation: when `AppliesToAllProfiles=true`, `ProfileIds` must be empty; when false, at least one profile must be selected.
- [ ] List endpoints accept an optional `profileId` filter that returns rows in the junction OR with `AppliesToAllProfiles=true`.
- [ ] Unit tests cover the validation invariant; integration tests cover create/update/delete flows for both entities under both modes.

## Out of scope

- UI changes (covered in 022 for hotkeys; hotstring UI revisit covered in note on 014).
- Script generation logic (covered in 026).

## Notes / dependencies

- Depends on **024** (Profile entity must exist).
- Required by **022, 022b, 026**.
- Design spec: `C:\Users\btase\.claude\plans\start-your-work-on-validated-walrus.md` (Phase 2).
