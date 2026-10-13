# 166 - Profile management misreports the default and the delete

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

Two separate defects on the Profiles page. The Default checkbox can never be used, and the error
it raises blames the profile's name. Deleting a profile silently leaves every item scoped to it
in the Applies to no profile state, so those items disappear from every generated script with no
warning.

## User story

As an owner, I want to change which profile is the default and to be told what a delete will
cost me, so that I do not lose items from my scripts without knowing.

## Acceptance criteria

- [ ] Ticking Default on a profile that is not the default makes it the default and clears the
      previous one, through the UI and through `PUT /api/v1/profiles/{id}`.
- [ ] A duplicate-key violation from the owner-default index produces a message about the
      default, and only a real name collision produces the name message.
- [ ] An integration test sets the default on a second profile and asserts exactly one default
      remains.
- [ ] The delete confirmation names how many items are scoped to that profile only, and what
      happens to them.
- [ ] An item left with no profile after a profile delete is marked or reported somewhere the
      owner can find after a reload.

## Out of scope

- Changing the one-default-per-owner rule itself.
- Reworking the Applies to no profile state. Item 175 covers how that state is recorded.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F22 and F23, both S2. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F22, the default.** `Commands/Profiles/UpdateProfileCommand.cs` clears the other profile's
  flag and sets this one's, then calls `SaveChangesAsync` once. Inside that single save both rows
  carry `IsDefault = 1`, the filtered unique index `IX_Profile_Owner_DefaultOnly` on
  `(OwnerOid, IsDefault)` rejects it, and the handler's catch block maps every duplicate-key
  violation to `A profile named '{name}' already exists.`
- The message is demonstrably false. Renaming and setting default in one call reported
  `A profile named 'Work2' already exists.` when no profile named Work2 existed. Confirmed at the
  API level, so this is not a UI problem.
- The create path works. `POST /api/v1/profiles` with `isDefault: true` cleared the previous
  default correctly. So today the only way to change the default is to create a new profile.
- **F23, the delete.** The dialog says only `Delete "Work"? This cannot be undone.` and the
  snackbar says only `Profile deleted.` A hotstring scoped to that profile alone came back with
  `appliesToAllProfiles=false` and zero profiles, and appeared in neither remaining script.
  Nothing marks it as needing repair.
- The inconsistency is the point. ADR-0021 treats this same state as serious enough to name every
  failed rule when a Restore causes it. When a profile delete causes it, the owner is told
  nothing.
- Deleting every profile does not leave an owner with none. `Queries/Profiles/ListProfilesQuery.cs`
  guards seeding with a row count rather than a marker, so a fresh `Default` appears. That makes
  the orphaning worse, not better: the owner ends up with a new empty profile and every
  named-profile item orphaned.
- This may ship as two pull requests, one per defect. Keep them stacked rather than mixed.
- Spec: none — the delete half needs a Design decision on what to tell the owner and whether to
  offer a reassign.
- Plan: none — complex, so Design comes first at pickup.
