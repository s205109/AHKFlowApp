# 163 - New hotstring defaults to triggering inside words

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup

## Summary

A brand new hotstring starts with **Trigger inside words** switched on. AutoHotkey's own default
is off. So a new `btw` also fires in the middle of `abtw`, which few people expect.

## User story

As a user creating a hotstring, I want it to fire only at a word boundary unless I ask otherwise,
so that it does not expand inside unrelated words.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] A newly opened hotstring edit dialog shows **Trigger inside words** unticked.
- [ ] A bUnit test in `tests/AHKFlowApp.UI.Blazor.Tests` asserts the default of
      `HotstringEditModel.IsTriggerInsideWord`.
- [ ] The decision is recorded: either the default changes, or a comment in `HotstringEditModel`
      says why it differs from AutoHotkey.

## Out of scope

- Existing saved hotstrings. Whatever they hold stays as it is; this item is about the default
  a new one starts from.
- The Raw conversion path. Backlog 161 already makes a conversion out of Raw follow the
  definition's own flags.

## Notes / dependencies

- **Where this came from.** Grilling round on the backlog 161 plan, 2026-09-28. The 161 fix makes
  a Raw definition with no `?` convert to **Trigger inside words off**, which is correct. That
  leaves two ways to reach a Text hotstring disagreeing with each other: created fresh gives on,
  converted from Raw gives off.
- The default lives here: (`src/Frontend/AHKFlowApp.UI.Blazor/Validation/HotstringEditModel.cs:30`, "public bool IsTriggerInsideWord { get; set; } = true;").
  It carries no comment saying why.
- The domain record sets no default for the field at all, so this is purely a UI choice:
  (`src/Backend/AHKFlowApp.Domain/Entities/HotstringDefinition.cs:22`, "bool IsTriggerInsideWord,").
- AutoHotkey's default is off. Its parser only turns the flag on when the definition carries `?`:
  the `?` case in `Hotstring::ParseOptions` reads `aDetectWhenInsideWord = (*cp1 != '0');`, at
  https://github.com/AutoHotkey/AutoHotkey/blob/4898e08ef71ddc03934789030418f3f74b72544a/source/hotkey.cpp#L2518
- This changes app-facing behavior for every new hotstring, so it is never `trivial`.
- Check the seed catalog and any fixture that relies on the current default before changing it.
- Spec: none — not picked up yet.
- Plan: none — not picked up yet.
