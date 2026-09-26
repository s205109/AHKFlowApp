# 160 - One home for emitted runtime helpers

## Metadata

- **Epic**: Script generation
- **Type**: Refactor
- **Interfaces**: none (internal Application code; no UI, API, or CLI contract change)
- **Difficulty**: moderate
- **Stage**: 0-intake

## Summary

The AutoHotkey code that touches the clipboard lives in a string constant inside the hotstring
Emitter. The generator and the hotstring preview each decide on their own when a Profile script
needs it. The generator and both preview handlers also each build the Description comment lines
and the `#HotIf` wrapping around a definition. Give that work one home, so each Runtime helper
and each wrapping rule exists once. The generated text must stay byte-for-byte the same.

## User story

As a developer who adds a Runtime helper or changes how a definition is wrapped, I want to change
one place, so that a Profile script and its previews cannot drift apart.

## Acceptance criteria

Write each criterion as state a reader can observe in the repository, not as a change to it.
"The handler returns `Result.NotFound()` for a missing id" can be checked. "The old check is
removed" and "tests cover the new API" cannot.

- [ ] One Application type decides which Runtime helpers a set of hotstrings and hotkeys needs.
      `AhkScriptGenerator` and `GetHotstringPreviewQueryHandler` both get that answer from it, and
      neither refers to `HotstringEmitter.PasteHelperFunction` directly.
- [ ] One Application type builds a definition's Description comment lines and its `#HotIf`
      wrapping. `AhkScriptGenerator`, `GetHotstringPreviewQueryHandler`, and
      `GetHotkeyPreviewQueryHandler` all call it, and none of them joins `EmitHotIfOpen`,
      `HotIfClose`, and the comment lines itself.
- [ ] `HotkeyEmitter` and the hotkey preview do not call `HotstringEmitter` for anything.
- [ ] A test compares the SQL Delivery expression in `ListHotstringsQuery` with
      `HotstringEmitter.ResolveEffectiveDelivery` across the threshold, and fails when they
      disagree.
- [ ] The existing generator, preview, and round-trip tests pass without edits to their expected
      text. `git diff origin/main...HEAD` shows no change to any expected AHK string in `tests/`.
- [ ] `CONTEXT.md` defines **Runtime helper**, and the new types use that term.

## Out of scope

- Any change to the generated text, including the helper's position in a preview.
- Turning the window-snap code into a Runtime helper. It stays inline for now; that choice changes
  the output and needs its own decision.
- A shared grammar project for the frontend and the backend (candidate 1 of the same review).
- The Raw kind-switch Options bug. That is backlog 161.

## Notes / dependencies

- **Where this came from.** Architecture review in session
  https://claude.ai/code/session_01EPTqaHBB9hCJgYiHcDySQe, candidate 2. Grilling round 1 settled
  the scope (paste helper plus wrapping; SQL Delivery copy gets a parity test only), byte-identical
  output, the **Runtime helper** term, and Difficulty `moderate`.
- Evidence at filing time:
  - The paste helper constant: (`src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs:19`, "public const string PasteHelperFunction =").
  - The generator adds the helper: (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:36`, "lines.Add(HotstringEmitter.PasteHelperFunction);").
  - The hotstring preview adds it again: (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs:119`, "HotstringEmitter.PasteHelperFunction").
  - The generator opens `#HotIf`: (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:93`, "lines.Add(HotstringEmitter.EmitHotIfOpen(").
  - The hotstring preview wraps: (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs:116`, "HotstringEmitter.EmitHotIfOpen(matchType, hs.ContextValue!)").
  - The hotkey preview wraps: (`src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyPreviewQuery.cs:51`, "HotstringEmitter.EmitHotIfOpen(matchType, hk.ContextValue!)").
  - The SQL copy of the Delivery rule: (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs:210`, "Mirrors HotstringEmitter.ResolveEffectiveDelivery").
- Verification: pure refactor. Name the covering tests and paste their fresh pass output.
- Spec: none — `moderate` goes from Pickup to Plan.
- Plan: none — written at Stage 3.
