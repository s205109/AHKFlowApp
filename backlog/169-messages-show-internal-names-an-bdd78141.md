# 169 - Messages show internal names and wrong plurals

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 8-review

## Summary

Four findings about text an owner reads. Validation messages carry C# property names, delete
messages say "(s)" and "them" for a single item, and the Delivery help text packs three ideas
into one sentence.

## User story

As an owner, I want every message to use the words the interface uses, so that I can tell what
happened and what to do next.

## Acceptance criteria

- [x] A validation message an owner can reach names the field by its visible label, not by its
      property name. `ContextValue` and `ProfileIds` do not appear in any message the UI shows.
- [x] A validation message does not lead with a bare property-name prefix such as `ProfileIds:`.
- [x] A delete message for exactly one item reads as singular, in the title, the body and the
      snackbar.
- [x] The `{deleted} deleted; {missing} were already gone` message reads correctly when either
      count is 1.
- [x] The Delivery help text is two sentences or fewer per idea, and either `CONTEXT.md` defines
      "case-conforming" or the text stops using it.

## Out of scope

- Product and page naming, which item 170 covers.
- Translating the app. This is English wording only.
- What a category delete affects. Backlog 205 owns it.
- How the Recycle Bin shows a Macro. Backlog 206 owns it.
- The shortcut warning rule and its refusal message. Backlog 207 owns them.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F11, F15, F17 and F20. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F17 and F20 are one pattern, seen twice.** Restoring an item whose stored window context
  holds a double quote shows `ContextValue must not contain double-quote characters.` for a field
  labelled **Value**, inside a section called **Only in specific windows**, which `CONTEXT.md`
  calls a **Window context**. The import dialog shows `ProfileIds: At least one profile must be
  specified when AppliesToAllProfiles is false.` for a checkbox labelled **Apply to all
  profiles** and a selector labelled **Profiles**. `CONTEXT.md` also lists "all-profiles" under
  Avoid for that term.
- **F15, the plurals.** Ten places in `Pages/Hotstrings.razor` and `Pages/Hotkeys.razor`.
  Selecting one row and deleting gives `Delete hotstrings?` / `Delete 1 hotstring(s)? You can
  restore them from the Recycle Bin.` and then `Deleted 1 hotstring(s).` That is three plural
  errors for one item. One string has a second problem: `Deleted {deleted} hotstring(s);
  {missing} were already gone.` produces `1 were already gone.`
- **F11, the Delivery help text.** The second sentence packs three ideas into one through a
  parenthetical and a semicolon, and "case-conforming" appears nowhere in `CONTEXT.md`. AGENTS.md
  Plain English says not to stack clauses and to use common words. The 200-character figure in
  the first sentence is correct and matches
  `HotstringDeliveryDefaults.AutoClipboardThresholdChars`.
- **Split at pickup on 2026-11-05, one pull request per outcome.** The sweep put seven findings
  in this item because they all concern text, not because one change fixes them. This item keeps
  outcome 1, the wording (F17, F20, F15 and F11), because that is what its title says. Outcome 2,
  what a category delete affects (F10), moved to backlog 205. Outcome 3, Macro definitions in the
  Recycle Bin (F18), moved to backlog 206. Outcome 4, the absolute-claim rule (F24), moved to
  backlog 207. Each new item has its own worktree from `main`. The original note asked for the
  outcomes in that order, so outcome 1 goes first.
- Spec: none — each fix is small, but agree the vocabulary against `CONTEXT.md` before editing
  strings.
- Plan: `docs/superpowers/plans/2026-11-05-messages-name-visible-labels-plan-169.md`
