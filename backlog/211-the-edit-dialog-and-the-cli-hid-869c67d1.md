# 211 - The edit dialog and the CLI hide an item with no profile

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | CLI
- **Difficulty**: moderate
- **Stage**: 8-review

## Summary

An item that applies to no profile opens in the edit dialog with an empty Profiles field and no
reason. The CLI lists the same item as `all`, which says the opposite of what is true.

## User story

As an owner, I want the edit dialog and the CLI to say when an item applies to no profile, so that
I can find and repair it from either place.

## Acceptance criteria

- [x] The hotstring and hotkey edit dialogs show a notice when they open a stored item that
      applies to no profile.
- [x] The notice hides once the owner chooses a profile or turns on Apply to all profiles.
- [x] A new item opens with no notice. So does a stored item whose profiles were cleared only in
      an unsaved inline edit.
- [x] `ahkflow` lists an item that applies to no profile with `no profile` in its Profiles column,
      not `all`.

## Out of scope

- The profile delete confirmation, its snackbar, and the "No profile" chip. Backlog 210 ships them.
- The inline row editor. The spec gives it no notice.

## Notes / dependencies

- **Split from backlog 210 at its Plan stage on 2026-11-13.** The 210 plan met the split trigger,
  and both split tests found these two tasks. Stack this item on 210's branch,
  `fix/wt-a-profile-delete-does-not-say-w-17c5dc02`, until 210 merges.
- Design is done in the 210 spec, sections 5 and 6. Difficulty is `moderate`, so Pickup goes
  straight to Plan.
- The plan was drafted with 210's plan. The first review of that draft found a defect: the notice
  read the dialog's current values. So a promoted inline edit with its profiles cleared showed the
  notice, while the stored item still had profiles. The plan fixes it with a `LoadedWithNoProfile`
  flag, set once from the stored DTO.
- Spec: `docs/superpowers/specs/2026-11-13-profile-delete-says-what-it-costs-design-210.md`, sections 5 and 6
- Plan: `docs/superpowers/plans/2026-11-13-edit-dialog-and-cli-show-no-profile-plan-211.md`
