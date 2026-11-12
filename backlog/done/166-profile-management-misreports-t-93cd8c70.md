# 166 - Profile management misreports the default

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Changing which profile is the default fails, and the error blames a name collision that does not
exist. Every switch through `PUT /api/v1/profiles/{id}` fails this way, with or without a rename.
The delete half of this item moved to backlog 210 at Pickup.

## User story

As an owner, I want to change which profile is the default, so that the scripts I download start
from the profile I chose.

## Acceptance criteria

- [x] The failing call is reproduced before any fix is written, and the record says what made it
      fail.
- [x] Ticking Default on a profile that is not the default makes it the default and clears the
      previous one, through the UI and through `PUT /api/v1/profiles/{id}`.
- [x] A duplicate-key violation from the owner-default index produces a message about the
      default, and only a real name collision produces the name message.
- [x] An integration test sets the default on a second profile and asserts exactly one default
      remains.

## Out of scope

- Changing the one-default-per-owner rule itself.
- What a profile delete costs the owner. Backlog 210 covers it.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F22, S2. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F22, what the sweep saw.** Renaming a profile and setting it as the default in one
  `PUT /api/v1/profiles/{id}` call failed with `A profile named 'Work2' already exists.` when no
  profile named Work2 existed. The sweep confirmed it at the API level, so it is not a UI problem.
- **The cause, reproduced on 2026-11-12.** The rename plays no part. The switch fails whenever
  the handler runs in a fresh context, and every API request gets a fresh context.
  1. The handler loads the target profile first, so the context tracks it first
     (`src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs:36`, "Profile? profile = await db.Profiles.FirstOrDefaultAsync(").
  2. It loads the old default second, and clears its flag
     (`src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs:53`, "await foreach (Profile other in db.Profiles"). Old code, replaced by the fix. citation-check:ignore
  3. EF Core 10.0.6 sends the two `UPDATE` statements in that tracking order. The first one sets
     `IsDefault = 1` on the target while the old default still has it.
  4. SQL Server checks the filtered unique index after each statement
     (`src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/ProfileConfiguration.cs:39`, "builder.HasIndex(x => new { x.OwnerOid, x.IsDefault })").
     So the first `UPDATE` fails with a duplicate key.
  5. One catch block turns every duplicate key into the name message
     (`src/Backend/AHKFlowApp.Application/Commands/Profiles/UpdateProfileCommand.cs:70`, "catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())"). Old code, replaced by the fix. citation-check:ignore
     Without a rename, the message names the profile's own name: `A profile named 'Work' already exists.`
- **The evidence.** A throwaway test ran the switch 40 times in each of four shapes, against a
  migrated SQL Server database, and captured the SQL.
  - Fresh context, as in the API: 40 of 40 failed, with a rename and without one.
  - The context that inserted both rows: 40 of 40 passed, with a rename and without one.
  - The order of the two `Id` values made no difference in either shape.

  The batch from a failing run, with the parameter values in comments:

  ```sql
  UPDATE [Profiles] SET [IsDefault] = @p0, [UpdatedAt] = @p1 OUTPUT 1 WHERE [Id] = @p2; -- @p0 = True,  @p2 = target
  UPDATE [Profiles] SET [IsDefault] = @p3, [UpdatedAt] = @p4 OUTPUT 1 WHERE [Id] = @p5; -- @p3 = False, @p5 = old default
  ```

  A passing run sends the same two statements in the other order. The test and its full output
  are in the worktree's `.superpowers/166-repro/`, which is local and gitignored.
- **Why the green test passes.** `Setting_IsDefault_true_clears_existing_default` adds both
  profiles to the context the handler then uses, old default first
  (`tests/AHKFlowApp.Application.Tests/Profiles/UpdateProfileCommandHandlerTests.cs:111`, "ctx.Profiles.AddRange(a, b);"). Old test, reworked by the fix. citation-check:ignore
  So the context tracks the old default first, and EF clears it first. The test for criterion 4
  needs a fresh context for the handler, or it passes against the bug.
- **The create path works for the same reason.** `POST /api/v1/profiles` with `isDefault: true`
  loads the old default before it adds the new profile
  (`src/Backend/AHKFlowApp.Application/Commands/Profiles/CreateProfileCommand.cs:63`, "db.Profiles.Add(profile);").
  It relies on the same tracking order, so the plan decides whether to harden it too.
- **Difficulty dropped from complex to moderate at Pickup.** The item was complex because of the
  delete half, which needs a Design decision. The default half has one correct outcome: the old
  default is cleared before the target is set, whatever order the context tracks them in.
- **Split at Pickup on 2026-11-12, one pull request per outcome.** This item keeps the default
  switch, criteria 1 to 4 of the original. What a delete costs, criteria 5 and 6 with finding F23,
  moved to backlog 210. Its worktree stacks on this item's branch, as the original note asked.
- Spec: none — the cause is found, and the fix has one correct outcome.
- Plan: `docs/superpowers/plans/2026-11-12-profile-default-switch-plan-166.md`
