# 210 - A profile delete does not say what it costs

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: complex
- **Stage**: 3-plan

## Summary

Deleting a profile silently leaves every item scoped to it alone in the Applies to no profile
state. Those items then disappear from every generated script, and nothing warns the owner before
or after the delete. Split from backlog 166 at its Pickup on 2026-11-12.

## User story

As an owner, I want to be told what a profile delete will cost me, so that I do not lose items
from my scripts without knowing.

## Acceptance criteria

- [ ] The delete confirmation names how many items are scoped to that profile only, and what
      happens to them.
- [ ] An item left with no profile after a profile delete is marked or reported somewhere the
      owner can find after a reload.

## Out of scope

- Reworking the Applies to no profile state. Item 175 covers how that state is recorded.
- Changing which profile is the default. Backlog 166 covers it.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F23, S2. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **Split from backlog 166 at its Pickup on 2026-11-12.** That item held two outcomes that share
  only the Profiles page. It keeps the default switch, and this item takes criteria 5 and 6. Its
  note asked to keep the two pull requests stacked rather than mixed. Pull request #480 merged
  backlog 166 into `main` on 2026-11-12, before this pickup. So this worktree branches from
  `main` at `ba020699`, and no stack is needed.
- **F23, what the sweep saw.** The dialog says only `Delete "Work"? This cannot be undone.` and the
  snackbar says only `Profile deleted.` A hotstring scoped to that profile alone came back with
  `appliesToAllProfiles=false` and zero profiles, and appeared in neither remaining script.
  Nothing marks it as needing repair.
- **Why it happens.** The handler removes the profile, so each linked item loses that link
  (`src/Backend/AHKFlowApp.Application/Commands/Profiles/DeleteProfileCommand.cs:44`, "db.Profiles.Remove(profile);").
  It counts nothing and returns no body. The dialog text in
  `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor` is fixed, and holds no count.
- **A history entry already exists.** Before the delete, the handler records an Edit history entry
  for every hotstring and hotkey linked to the profile
  (`src/Backend/AHKFlowApp.Application/Commands/Profiles/DeleteProfileCommand.cs:39`, "await recorder.RecordHotstringsAsync(linkedHotstrings, HistoryChangeType.Edit, ct);").
  Design should check whether that entry can carry the record the second criterion asks for.
- The inconsistency is the point. ADR-0021 treats this same state as serious enough to name every
  failed rule when a Restore causes it. When a profile delete causes it, the owner is told
  nothing.
- Deleting every profile does not leave an owner with none. `Queries/Profiles/ListProfilesQuery.cs`
  guards seeding with a row count rather than a marker, so a fresh `Default` appears. That makes
  the orphaning worse, not better: the owner ends up with a new empty profile and every
  named-profile item orphaned.
- **A precedent exists.** Backlog 205 answered the same question for a category delete. Its
  confirmation counts the hotstrings and hotkeys that use the category, in
  `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/CategoryDeleteWording.cs`. A profile delete costs
  more: an item that loses its only profile also leaves every script.
- **Design this with item 175.** Item 175 asks the same question for the restore path. Its note
  says: "if a restore and a profile delete both need a durable record, one mechanism should serve
  both." Read it before designing this one.
- **Split at Plan on 2026-11-13.** The first plan met the split trigger, and both split tests
  found the same two tasks: the edit dialog notice and the CLI text, spec sections 5 and 6. They
  move to backlog 211, whose branch starts from this one. This item keeps the usage route, the
  confirmation, the snackbar and the "No profile" chip, which together close its user story.
- Spec: `docs/superpowers/specs/2026-11-13-profile-delete-says-what-it-costs-design-210.md`
- Plan: `docs/superpowers/plans/2026-11-13-profile-delete-says-what-it-costs-plan-210.md`
