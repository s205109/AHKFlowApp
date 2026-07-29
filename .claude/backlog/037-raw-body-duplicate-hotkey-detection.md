# 037 - Raw body duplicate hotkey detection

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Detect when a Raw hotkey body defines a hotkey that another hotkey in the same Profile already defines.
AutoHotkey treats a duplicate hotkey as a load error, and that error stops the **whole** Profile script
from loading — not just the offending line.

## User story

As an Owner, I want to be told when a Raw body redefines a key another hotkey already uses, so that one
paste does not stop my entire Profile script from loading.

## Acceptance criteria

- [ ] The Raw body is scanned for top-level hotkey definition lines.
- [ ] A definition that collides with another hotkey in the same Profile is reported before saving.
- [ ] A definition that collides with another line inside the same Raw body is reported too.
- [ ] The report names the colliding hotkey, so the Owner can find it.
- [ ] Generated `.ahk` output is unchanged.

## Out of scope

- Parsing or validating the rest of the Raw body. `ahk-v2-syntax.md` already records that the existing
  brace counter errs deliberately rather than drift toward being a script IDE, and the same limit
  applies here.
- `#HotIf` context awareness. AutoHotkey allows the same key twice under different contexts, but
  hotkeys carry no context fields today, so there is nothing to compare.
- Known shortcuts. That is a different concept and a different mechanism — see
  `docs/superpowers/specs/2026-07-28-hotkey-conflict-warnings-design.md`.

## Notes / dependencies

- Found while designing hotkey shortcut warnings, and deliberately kept out of it. The two are often
  confused, so the distinction matters: this is a **duplicate**, which AHKFlow blocks, and it is
  detectable from data AHKFlow already holds. A **known shortcut** is something outside AHKFlow using a
  combination, which can only be warned about from a curated list.
- This is the higher-severity failure of the two. A known shortcut costs one hotkey; a duplicate costs
  the entire Profile script.
- `docs/adr/0004-hotkey-typed-actions-and-raw-escape-hatch.md` states the risk and gives the exact
  case: a body of `return` followed by a second line `^a::Run("calc")` passes validation today and
  injects a whole new top-level definition.
- Typed hotkeys are already safe. The unique index at
  `src/Backend/AHKFlowApp.Infrastructure/Persistence/Configurations/HotkeyConfiguration.cs:48-50` is
  owner-wide, so two typed hotkeys can never share a combination. Raw bodies bypass it because the
  combination lives in free text rather than in the `Key` and modifier columns.
- Needs its own brainstorm and spec before any code. The scanner's failure modes — what counts as a
  top-level definition line, how comments and continuations are handled — are the whole design.
