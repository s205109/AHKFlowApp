# 169 - Messages show internal names and wrong plurals

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Seven findings about text an owner reads. Validation messages carry C# property names, delete
messages say "(s)" and "them" for a single item, two delete dialogs never say what the delete
affects, and one validation rule is narrower than the message that describes it.

## User story

As an owner, I want every message to use the words the interface uses, so that I can tell what
happened and what to do next.

## Acceptance criteria

- [ ] A validation message an owner can reach names the field by its visible label, not by its
      property name. `ContextValue` and `ProfileIds` do not appear in any message the UI shows.
- [ ] A validation message does not lead with a bare property-name prefix such as `ProfileIds:`.
- [ ] A delete message for exactly one item reads as singular, in the title, the body and the
      snackbar.
- [ ] The `{deleted} deleted; {missing} were already gone` message reads correctly when either
      count is 1.
- [ ] The category delete confirmation says how many hotstrings and hotkeys use that category.
- [ ] The Recycle Bin shows a Macro definition the same way the grid does, not as the raw
      `{{cursor}}` token.
- [ ] The Delivery help text is two sentences or fewer per idea, and either `CONTEXT.md` defines
      "case-conforming" or the text stops using it.
- [ ] `ShortcutWording.BannedTerms` refuses a positive absolute claim such as `will open the
      panel`, or the refusal message stops promising to cover what will happen.
- [ ] A test proves the banned-term list is complete against a set of examples written
      independently of the list itself.

## Out of scope

- Product and page naming, which item 170 covers.
- Translating the app. This is English wording only.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F10, F11, F15, F17, F18, F20 and F24.
  Full evidence in `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and
  gitignored.
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
- **F10, the category delete.** The dialog says only `Delete "Code"? This cannot be undone.` and
  the snackbar says only `Category deleted.` Deleting the Code category affected 7 items, 5
  hotstrings and 2 hotkeys, and the server already knows that number. The behaviour itself is
  correct and worth recording: items survive, only the link is removed, and one `Edit` history
  entry is written per affected item, so the change is recoverable through history. The owner is
  simply not told it happened.
- The hotstring delete dialog does name its count and does mention the Recycle Bin, so the app
  knows how to disclose impact. It just does not do it everywhere.
- **F18, the Recycle Bin.** A deleted Macro hotstring's details read `<a
  href="{{cursor}}"></a>`. The grid renders the same value as a `⌖ cursor` chip.
- **F11, the Delivery help text.** The second sentence packs three ideas into one through a
  parenthetical and a semicolon, and "case-conforming" appears nowhere in `CONTEXT.md`. AGENTS.md
  Plain English says not to stack clauses and to use common words. The 200-character figure in
  the first sentence is correct and matches
  `HotstringDeliveryDefaults.AutoClipboardThresholdChars`.
- **F24, the absolute-claim rule.** `Constants/ShortcutWording.cs` bans only negative
  constructions: `never`, `will not`, `cannot`, `won't`, `can't`. So `will not open the panel` is
  refused with "Say what the keys do, not what will or will not happen.", while `will open the
  panel` and `always opens the panel` are both accepted. The message promises both halves and the
  list enforces one.
- Why no test catches F24. `CreateCustomKnownShortcutCommandValidatorTests` drives its cases from
  `BannedTerms` itself and asserts every entry makes an absolute claim. That proves the list is
  internally consistent, never that it is complete.
- **Split at pickup, one pull request per outcome.** Seven findings sit in this item because they
  all concern text, not because one change fixes them. Four outcomes, each verifiable on its own:
  1. **Wording.** Property names out of messages, correct singulars, and the Delivery help text.
     F17, F20, F15 and F11.
  2. **What a category delete affects.** The dialog says how many items use that category. F10.
     This one is a behaviour change, not wording, and it mirrors item 166's delete half.
  3. **Macro definitions in the Recycle Bin.** Render them the way the grid does. F18.
  4. **The absolute-claim rule.** Either `ShortcutWording.BannedTerms` refuses a positive claim,
     or the message stops promising to. F24. This one needs a decision first.
  Take them in that order. Outcome 1 is the largest and touches the most strings.
- Spec: none — each fix is small, but agree the vocabulary against `CONTEXT.md` before editing
  strings.
- Plan: none — moderate work, goes straight to Plan at pickup.
