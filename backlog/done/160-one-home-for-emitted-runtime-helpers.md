# 160 - One home for emitted runtime helpers

## Metadata

- **Epic**: Script generation
- **Type**: Refactor
- **Interfaces**: none (internal Application code; no UI, API, or CLI contract change)
- **Difficulty**: moderate
- **Stage**: 9-ship

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

- [x] One Application type decides which Runtime helpers a set of hotstrings and hotkeys needs.
      `AhkScriptGenerator` and `GetHotstringPreviewQueryHandler` both get that answer from it, and
      neither refers to `HotstringEmitter.PasteHelperFunction` directly.
- [x] One Application type builds a definition's Description comment lines and its `#HotIf`
      wrapping. `AhkScriptGenerator`, `GetHotstringPreviewQueryHandler`, and
      `GetHotkeyPreviewQueryHandler` all call it, and none of them joins `EmitHotIfOpen`,
      `HotIfClose`, and the comment lines itself.
- [x] `HotkeyEmitter` and the hotkey preview do not call `HotstringEmitter` for anything.
- [x] A test compares the SQL Delivery expression in `ListHotstringsQuery` with
      `HotstringEmitter.ResolveEffectiveDelivery` across the threshold, and fails when they
      disagree.
- [x] The existing generator, preview, and round-trip tests pass without edits to their expected
      text. `git diff origin/main...HEAD` shows no change to any expected AHK string in `tests/`.
- [x] `CONTEXT.md` defines **Runtime helper**, and the new types use that term.

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
  - The paste helper constant: (`src/Backend/AHKFlowApp.Application/Services/HotstringEmitter.cs:19`, "public const string PasteHelperFunction ="). <!-- citation-check:ignore records the tree at filing time, before this item moved the code -->
  - The generator adds the helper: (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:36`, "lines.Add(HotstringEmitter.PasteHelperFunction);"). <!-- citation-check:ignore records the tree at filing time, before this item moved the code -->
  - The hotstring preview adds it again: (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs:119`, "HotstringEmitter.PasteHelperFunction"). <!-- citation-check:ignore records the tree at filing time, before this item moved the code -->
  - The generator opens `#HotIf`: (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:93`, "lines.Add(HotstringEmitter.EmitHotIfOpen("). <!-- citation-check:ignore records the tree at filing time, before this item moved the code -->
  - The hotstring preview wraps: (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs:116`, "HotstringEmitter.EmitHotIfOpen(matchType, hs.ContextValue!)"). <!-- citation-check:ignore records the tree at filing time, before this item moved the code -->
  - The hotkey preview wraps: (`src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyPreviewQuery.cs:51`, "HotstringEmitter.EmitHotIfOpen(matchType, hk.ContextValue!)"). <!-- citation-check:ignore records the tree at filing time, before this item moved the code -->
  - The SQL copy of the Delivery rule: (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/ListHotstringsQuery.cs:210`, "Mirrors HotstringEmitter.ResolveEffectiveDelivery").
- Verification: pure refactor. Name the covering tests and paste their fresh pass output.
- Spec: none — `moderate` goes from Pickup to Plan.
- Plan: `docs/superpowers/plans/2026-09-26-one-home-for-emitted-runtime-helpers-plan-160.md`
- **Ticked at Document, 2026-09-27, against `7ce3961`.** Evidence for each criterion:
  1. (`src/Backend/AHKFlowApp.Application/Services/RuntimeHelpers.cs:15`, "internal static class RuntimeHelpers")
     decides. The generator asks it at
     (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:35`, "lines.AddRange(RuntimeHelpers.NeededBy(hsList, hkList));"),
     and the hotstring preview asks it at
     (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs:109`, "RuntimeHelpers.NeededBy([hs], [])").
     A search for `PasteHelperFunction` in `src/` finds nothing.
  2. (`src/Backend/AHKFlowApp.Application/Services/DefinitionWrapping.cs:14`, "internal static class DefinitionWrapping")
     builds both. The generator calls it at
     (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:84`, "lines.AddRange(DefinitionWrapping.InWindowContext(").
     Both previews call its `PreviewSnippet`, at
     (`src/Backend/AHKFlowApp.Application/Queries/Hotstrings/GetHotstringPreviewQuery.cs:108`, "string snippet = DefinitionWrapping.PreviewSnippet(")
     and (`src/Backend/AHKFlowApp.Application/Queries/Hotkeys/GetHotkeyPreviewQuery.cs:43`, "string snippet = DefinitionWrapping.PreviewSnippet(").
     A search for `EmitHotIfOpen`, `HotIfClose`, and `DescriptionCommentLines` in the generator and
     in `Queries/` finds nothing.
  3. A search for `HotstringEmitter.` in `HotkeyEmitter.cs` and `GetHotkeyPreviewQuery.cs` finds
     nothing. `HotkeyEmitter.cs` names the class only in an XML `cref`, which is not a call.
  4. The 11-row theory is at
     (`tests/AHKFlowApp.Application.Tests/Hotstrings/ListHotstringsQueryHandlerTests.cs:667`, "public async Task ExecuteAsync_DeliveryAroundAutoThreshold_MatchesEmitterResolver(").
     With `>=` changed to `>` in the SQL copy, exactly 3 of its 11 cases failed, all with
     `kind: Text, delivery: Auto`: `asciiChars: 200, supplementaryChars: 0, trailingSpaces: 0`,
     `asciiChars: 199, supplementaryChars: 0, trailingSpaces: 1`, and
     `asciiChars: 0, supplementaryChars: 100, trailingSpaces: 0`. The session that ran Execute
     recorded the run on 2026-09-27, in commit `a49ae75`.
  5. At Verify, the generator, preview, and round-trip tests passed: Fast 116 of 116, Integration
     41 of 41 and 19 of 19. `git diff origin/main...HEAD -- tests/` removes one line, which is a
     comment in `GetHotkeyPreviewQueryTests.cs`, and adds only the new theory.
  6. (`CONTEXT.md:129`, "**Runtime helper**:") defines the term. `RuntimeHelpers` carries it in its
     name and summary, and `DefinitionWrapping` uses it in its summary.
- **Document verdict.** Task 2 updated `docs/development/ahk-v2-syntax.md` and the code comments
  that named a moved member. Re-read after Simplify, they match the code. No README, skill, or
  `CONTEXT.md` change is needed.
