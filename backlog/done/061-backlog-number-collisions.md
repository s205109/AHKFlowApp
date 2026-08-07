# 061 - Backlog numbers collide because they are picked by hand

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: UI | API | CLI (none — agent tooling only)

## Summary

Two backlog items can end up with the same number. It has already happened twice.

A new item's number is chosen by hand. The person or agent filing it has to list both `backlog/`
and `backlog/done/` and take the highest number. Nothing checks the result, so a wrong guess is
saved and committed.

Existing collisions (resolved 2026-08-07):

- `051` — `backlog/done/051-hotkey-raw-body-inline-error-not-rendering.md` kept `051` (most inbound
  references). `backlog/done/051-hotstrings-mobile-branch-stale-after-desktop-mutation.md` was
  renumbered to `backlog/done/063-hotstrings-mobile-branch-stale-after-desktop-mutation.md`.
- `058` — `backlog/058-native-edit-refusal-names-missing-worktree-copy.md` kept `058` (most inbound
  references). `backlog/done/058-template-key-use-warning.md` was renumbered to
  `backlog/done/064-template-key-use-warning.md`.

Every inbound reference to the renumbered files was updated in the same change.

The `b` suffix items (`022b`, `024b`, `027b`) are not collisions. Those are deliberate follow-ups to
a parent item and this work leaves them alone.

## Why the number matters

The number is a reference, not only a unique key. Items cite each other by bare number, and so do
documents and commit messages. Some examples in the repo today:

- `backlog/042-key-rebinds-as-first-class-rows.md:42` points at item 044
- `backlog/056-disabled-button-reason-unreachable-by-keyboard-and-touch.md:38` points at item 053
- `backlog/057-downloads-page-row-stays-disabled-when-the-file-save-fails.md:23` points at item 055
- `backlog/058-native-edit-refusal-names-missing-worktree-copy.md:25` points at item 054

So a duplicate number does not only break sorting. It makes an existing reference point at two
different items, and the reader cannot tell which one was meant.

This is also why the numbers should stay short. A longer unique name, such as a date and time
suffix, would remove collisions but make every reference harder to read and say.

## Acceptance criteria

- [x] A script scaffolds a new backlog item from `backlog/000-backlog-item-template.md`. It takes a
      title, works out the next free number across `backlog/` and `backlog/done/`, and writes the
      file
- [x] Nobody has to read or type a backlog number by hand to file an item
- [x] A check fails when two files share the same numeric prefix across `backlog/` and
      `backlog/done/`. The failure message names both files
- [x] The check runs in CI, so a duplicate cannot reach `main`
- [x] The `b` suffix items keep passing the check
- [x] The two existing collisions are resolved, and every reference to the renumbered items is
      updated in the same change

## Out of scope

- Moving the backlog into GitHub Issues. That is a separate decision, not this bug
- Changing the numbering scheme itself. Numbers stay short and stay the reference
- Changing the item template's sections

## Notes / dependencies

- The generator handles the common case: one person files one item and never sees a number
- The CI check handles the case a generator cannot. Two agents working in separate worktrees can
  each see 059 as the highest and each write 060. Only a check at merge time catches that
- If a filing date is wanted, add it as a `- **Filed**: YYYY-MM-DD` line in the Metadata section.
  Keep it out of the file name, so references stay short
- Renumbering the existing collisions is the risky part. Search for the old number as a bare
  reference before moving any file
- The check runs in CI only, not in `scripts/pre-push-quick-checks.ps1`. This item's acceptance
  criteria only ask for a CI check. Adding it to pre-push as well was considered and dropped, to
  keep this change to what the item asks for
