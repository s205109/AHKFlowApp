# 166 - Profile management misreports the default and the delete

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

Two separate defects on the Profiles page. Changing which profile is the default failed, and the
error blamed a name collision that did not exist. Deleting a profile silently leaves every item
scoped to it in the Applies to no profile state, so those items disappear from every generated
script with no warning.

## User story

As an owner, I want to change which profile is the default and to be told what a delete will
cost me, so that I do not lose items from my scripts without knowing.

## Acceptance criteria

- [ ] The failing call is reproduced before any fix is written, and the record says what made it
      fail. The notes below name a hypothesis, not a cause.
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
- **F22, the default. What is confirmed.** Renaming a profile and setting it as the default in one
  `PUT /api/v1/profiles/{id}` call failed with `A profile named 'Work2' already exists.` when no
  profile named Work2 existed. So a duplicate-key violation really was raised, and the handler
  really did report it as a name collision. Confirmed at the API level, so this is not a UI
  problem. `Commands/Profiles/UpdateProfileCommand.cs` has one catch block that maps every
  duplicate-key violation to that one message, which is why any violation reads as a name
  collision.
- **F22. What is not confirmed: the cause.** The sweep's explanation was that both rows carry
  `IsDefault = 1` inside the single `SaveChangesAsync`, so the filtered unique index
  `IX_Profile_Owner_DefaultOnly` on `(OwnerOid, IsDefault)` rejects it. The handler does clear the
  other profile's flag before it saves, so that explanation only holds if EF Core sends the two
  `UPDATE` statements in the order that sets before it clears. Nothing captured the SQL, so this
  is the leading hypothesis and not a diagnosis.
- **A green test covers the same switch**, which is the main reason to doubt the hypothesis as
  written. `Setting_IsDefault_true_clears_existing_default` in
  `tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandHandlerTests.cs` switches the
  default between two profiles against a migrated database, and it passes. Design has to find what
  the failing call did differently. The visible differences are that the failing call also renamed
  the profile, and that it ran against a context which loaded the target profile before the old
  default. Capture the SQL before writing a fix.
- The create path works. `POST /api/v1/profiles` with `isDefault: true` cleared the previous
  default correctly.
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
- **Split at pickup, one pull request per outcome.** The two halves share only the page they live
  on, and each one is verifiable on its own:
  1. **The default switch.** Reproduce the failure, fix it, and make the duplicate-key message say
     which rule failed. Criteria 1 to 4.
  2. **What a delete costs.** Tell the owner how many items a profile delete affects, and leave a
     record an affected item can be found by. Criteria 5 and 6.
  Keep them stacked rather than mixed. Half 2 overlaps item 175, which asks the same question for
  the restore path — read that item before designing this one.
- Spec: none — the delete half needs a Design decision on what to tell the owner and whether to
  offer a reassign.
- Plan: none — complex, so Design comes first at pickup.
