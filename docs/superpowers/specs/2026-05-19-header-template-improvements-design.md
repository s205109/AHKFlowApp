# Header Template Improvements Design

**Date:** 2026-05-19
**Status:** Design - ready for implementation planning

## Goal

Replace the minimal default header with a richer, commented header. Add token substitution at script-generation time so headers (and footers) can include `{ProfileName}`, `{AppVersion}`, `{HotstringCount}`, `{HotkeyCount}`, `{GeneratedAt[:format]}`.

## Current State

`src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs:5-11`:

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force
SetCapsLockState "AlwaysOff"
SetWorkingDir A_ScriptDir
```

`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:11-33`: `Generate(profile, hotstrings, hotkeys)` emits `profile.HeaderTemplate` verbatim, then sections, then `profile.FooterTemplate`.

`SetCapsLockState "AlwaysOff"` forcibly disables CapsLock — surprising side-effect. Removed.

## New Default Header

```ahk
; {ProfileName} — AHKFlowApp v{AppVersion}
; {HotstringCount} hotstrings, {HotkeyCount} hotkeys
; Generated {GeneratedAt:yyyy-MM-dd HH:mm}Z

#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
SendMode "Input"
SetWorkingDir A_ScriptDir
SetTitleMatchMode 2

```

## Token Substitution

New service `HeaderTokenRenderer` (`src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs`):

- Inputs: profile name, hotstring count, hotkey count, generation timestamp (`TimeProvider.GetUtcNow()`), app version.
- Supported tokens: `{ProfileName}`, `{AppVersion}`, `{HotstringCount}`, `{HotkeyCount}`, `{GeneratedAt}` (default format `o`) or `{GeneratedAt:fmt}` where `fmt` is any valid `DateTimeOffset` format string.
- **All token formatting uses `CultureInfo.InvariantCulture`.** This applies to `{GeneratedAt:fmt}` formatting and to numeric tokens (`{HotstringCount}`, `{HotkeyCount}`). Generated `.ahk` files must be culture-independent — a German developer's script must not produce comma decimal separators or non-English month names.
- Unknown tokens are left as-is (no exception) to avoid surprise data loss.
- Tokens not in the template are silently ignored.

**Literal-brace escaping.** Authors who want a literal `{` or `}` in their header (e.g. a JSON snippet in a comment) write `{{` and `}}`. The renderer collapses `{{` → `{` and `}}` → `}` as a final pass *after* token substitution. Concretely:

- Pass 1: substitute recognized tokens (`{ProfileName}`, `{GeneratedAt:fmt}`, etc.).
- Pass 2: collapse `{{` → `{`, `}}` → `}`.

This means a template that needs a literal `{HotstringCount}` (without substitution) is written as `{{HotstringCount}}` and will render as the literal string `{HotstringCount}`. Confirm with unit tests covering: a token, a literal brace, a token next to a literal brace, an unknown token, and an empty template.

App version source: introduce `IAppVersionProvider` returning the informational version from the assembly attributes (already populated by MinVer). Injected into `HeaderTokenRenderer`.

`AhkScriptGenerator.Generate` constructs the renderer's input from the counts of the supplied collections and the injected `TimeProvider`, then renders both `profile.HeaderTemplate` and `profile.FooterTemplate` before emitting.

## Backward Compatibility

- Existing stored profile headers are not rewritten. Token substitution applies to every profile's header/footer on generation, so existing profiles will see tokens substituted only if their headers happen to contain them (no-op otherwise).
- `DefaultProfileTemplates.Header` constant update only affects *newly created* profiles.

## Files In Scope

### Backend

- `src/Backend/AHKFlowApp.Domain/Constants/DefaultProfileTemplates.cs` — replace `Header` constant.
- `src/Backend/AHKFlowApp.Application/Services/HeaderTokenRenderer.cs` (new)
- `src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs` — inject renderer + `TimeProvider`, call before emitting header/footer.
- `src/Backend/AHKFlowApp.Application/Abstractions/IAppVersionProvider.cs` (new) + Infrastructure implementation.
- DI registration in `src/Backend/AHKFlowApp.API/Program.cs`.

### Tests

- `tests/AHKFlowApp.Application.Tests/Services/HeaderTokenRendererTests.cs` — token presence, unknown tokens preserved, format suffix on `{GeneratedAt}` honored, `{GeneratedAt}` default format `o`, **InvariantCulture used regardless of `CurrentCulture`** (test sets `Thread.CurrentThread.CurrentCulture = new CultureInfo("de-DE")` and asserts no `,` in numeric output and no German month names in date output), **literal-brace escaping** (`{{` and `}}` collapsed to single braces, including when adjacent to tokens).
- `tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs` — generator emits header with tokens replaced.

## Test Strategy

Unit tests on `HeaderTokenRenderer` and `AhkScriptGenerator` only — no integration test needed because generation is pure logic plus injected clock/version.

## Risks and Watchouts

- Existing custom headers that contain literal `{` or `}` adjacent to nothing token-like are unaffected — only recognized token patterns are substituted in pass 1, and pass 2 only collapses doubled braces.
- `{GeneratedAt:fmt}` parsing: split on first `:` to extract the format. A user could deliberately put `:` in the format — supported because the format string runs to the closing `}`.
- InvariantCulture is a deliberate departure from a `TimeProvider` user's local culture — call this out in the renderer's XML doc so future contributors don't "fix" it.

## Done Criteria

- New default header appears for newly created profiles.
- `HeaderTokenRenderer` ships in `Application.Services`.
- `AhkScriptGenerator` substitutes tokens in both header and footer.
- Generator unit tests cover every token plus unknown-token preservation.
