# 205 - A category delete does not say what it affects

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Deleting a category removes it from every hotstring and hotkey that uses it. The confirmation
and the snackbar never say so, so the owner does not know how many items the delete changed.

## User story

As an owner, I want the category delete confirmation to say how many items use that category,
so that I know what the delete changes before I confirm it.

## Acceptance criteria

- [ ] The category delete confirmation says how many hotstrings and hotkeys use that category.

## Out of scope

- What a category delete does. Items survive, and only the link to the category is removed.
- What a profile delete costs. Item 166 owns that question.
- The wording of other messages. Item 169 owns it.

## Notes / dependencies

- Split from backlog 169 at its Pickup on 2026-11-05. Item 169 asked for one pull request per
  outcome, and this is its outcome 2.
- Found by the acceptance sweep on 2026-10-13, finding F10. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F10, the category delete.** The dialog says only `Delete "Code"? This cannot be undone.` and
  the snackbar says only `Category deleted.` Deleting the Code category affected 7 items, 5
  hotstrings and 2 hotkeys, and the server already knows that number. The behaviour itself is
  correct and worth recording: items survive, only the link is removed, and one `Edit` history
  entry is written per affected item, so the change is recoverable through history. The owner is
  simply not told it happened.
- The hotstring delete dialog does name its count and does mention the Recycle Bin, so the app
  knows how to disclose impact. It just does not do it everywhere.
- This is a behaviour change, not wording. It mirrors the delete half of item 166, so read that
  item before planning this one.
- Spec: none — the server already knows the count, and the dialog only has to show it.
- Plan: none — moderate work, goes straight to Plan at pickup.
