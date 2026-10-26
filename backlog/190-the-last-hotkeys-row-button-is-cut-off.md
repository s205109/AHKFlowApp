# 190 - The last hotkeys row button is cut off

## Metadata

- **Epic**: Hotkeys
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

On the hotkeys grid, the last button in each row sticks out of the Actions column. At a 1280 px
window, 56 px of the `open-full-editor` button is cut off on the right.

## User story

As an owner, I want every row button fully visible, so that I can see and use each one.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] At a 1280 px window, every button in a hotkeys row sits inside its cell, in view mode and in
      edit mode.
- [ ] An E2E flow test asserts that every row button sits inside its cell, in both modes.

## Out of scope

- The hotstrings grid. Backlog 185 owns it.
- The focus ring itself. Backlog 168 owns it.

## Notes / dependencies

- Found while picking up backlog 185, on 2026-10-18. Backlog 185 said to check this grid at its
  pickup and to file the same fault as its own item.
- Measured in Chromium at 1280×800 on `/hotkeys`, with the starter rows. The Actions cell runs
  from 1080 to 1240 px, with 16 px of padding on each side. The four 48 px buttons sit at:
  - `show-history`: 1096 to 1144
  - `delete`: 1148.09 to 1196.09
  - `start-edit`: 1200.19 to 1248.19
  - `open-full-editor`: 1248.19 to 1296.19

  The table container ends at 1240 px and has `overflow: auto`, so it cuts off whatever sticks out.
- Likely cause, the same as backlog 185: the Actions column is fixed at 160 px
  (`src/Frontend/AHKFlowApp.UI.Blazor/Pages/Hotkeys.razor:199`, "width:160px").
  Four 48 px buttons need 192 px before any gap or padding. The line breaks between the buttons
  render as spaces of about 4 px each. The Razor comment before `open-full-editor` removes the
  space before that button.
- Edit mode shows two buttons, `commit-edit` and `cancel-edit`, so it was not measured. Measure it
  at pickup.
- Backlog 185's plan fixes the hotstrings grid with a `MudStack` flex row with a 4 px gap, plus a
  wider column. The same approach likely fits here: four buttons and three 4 px gaps take 204 px,
  and the padding adds 32 px, so 236 px. That takes 76 px from the percentage columns, so check
  what it costs them before choosing it.
- Backlog 185's plan is in the plans repository:
  `docs/superpowers/plans/2026-10-18-hotstrings-row-buttons-fit-their-cell-plan-185.md`.
- Spec: none — a layout fault with a known place to look.
- Plan: `docs/superpowers/plans/2026-10-26-hotkeys-row-buttons-fit-their-cell-plan-190.md`
