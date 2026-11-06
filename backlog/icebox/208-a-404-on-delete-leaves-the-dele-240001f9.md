# 208 - A 404 on delete leaves the deleted row on the page

## Metadata

- **Epic**: Frontend platform
- **Type**: Defect
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 0-intake

> **Iceboxed. This is an observation, not a plan.** It happens only when the owner deletes an
> item in another tab, on another device, or with the `ahkflow` CLI while a list page stays open.
> The owner sees an error, and the page's Reload button removes the row. No data is lost. It
> becomes worth doing if owners report stale rows, or when list pages get a live refresh.

## Summary

When a delete, or the category usage call before it, answers 404, the list page shows an error
snackbar but keeps the row. The row stays until the owner reloads the page.

## User story

As an owner, I want a row to disappear when the server says its item is already gone, so that
the page does not offer actions on something that no longer exists.

## Acceptance criteria

- [ ] On the Categories, Hotstrings, Hotkeys and Profiles pages, a delete that answers 404
      reloads the list, so the row is gone after the error.
- [ ] On the Categories page, a usage call that answers 404 reloads the list in the same way.

## Out of scope

- Live refresh of a list page when another tab or the CLI changes data.
- Any change to the delete itself, or to the error text.

## Notes / dependencies

- Raised as optional finding 2 by the Claude reviewer on PR #475 (backlog 205), round 1,
  review 5802494251. Declined there, because no page reloads its list after a 404 today, and a
  fix in one branch would make that branch differ from the rest.
- Evidence: no page in `src/Frontend/AHKFlowApp.UI.Blazor/Pages/` handles
  `ApiResultStatus.NotFound` on its own. Every failure branch only calls `Snackbar.Add`.
- Spec: none — iceboxed.
- Plan: none — iceboxed.
