# Clipboard Delivery Manual Testing

Manual acceptance checklist from
[`docs/superpowers/plans/2026-07-13-clipboard-delivery-plan.md`](../../superpowers/plans/2026-07-13-clipboard-delivery-plan.md#verification).
Run once against a real AutoHotkey v2 install before merging `feature/wt-clipboard-delivery`.

## Fast path — `acceptance.ahk`

`acceptance.ahk` covers every runtime item in one file. It was produced by the real
`AhkScriptGenerator`, so it is byte-identical to what a download would emit — no API, UI,
or database needed. Run it with AutoHotkey v2 and type the triggers into Notepad.

**Close your other AutoHotkey scripts first.** A personal hotstring script running in the
background can swallow these triggers — during the 2026-07-15 pass, triggers silently
failed to fire on Space until an unrelated script was closed.

**`endchar` decides whether the implementation is correct.** The emitter assumes AHK
*consumes* the ending character for `X` (execute) hotstrings and re-sends it via
`A_EndChar`. If that assumption is wrong, two triggers fail together, and the fix is to drop
the `A_EndChar` argument in `HotstringEmitter.BuildClipboardBody` and update the golden
tests in `AhkScriptGeneratorTests.cs`.

| Type this | Assumption holds (ship it) | Assumption wrong (fix emitter) |
|---|---|---|
| `endchar` + Space | Five lines, then **exactly one** space | **Two** spaces — end char both survived and was re-sent |
| `omitend` + Space | **No** trailing space (omit honored) | **One** space — omit silently ignored |

Both probe the same unknown from opposite directions, so they agree. If they disagree,
stop and report it — that means something subtler than the plan's binary.

| Type this | Expect |
|---|---|
| `type199` + Space | 199 `a` characters typed visibly, character by character |
| `paste200` + Space | 200 `b` characters appear instantly (pasted) |
| `starend` | Fires with no ending char; no stray char after the text |
| `big100k` + Space | All 100,000 `x` characters arrive, no truncation or corruption |
| `clipmark` + Space | Copy a marker string first; after the paste, `Ctrl+V` elsewhere returns **the marker**, not the replacement |

The 199-vs-200 boundary is also proven statically: the generated script emits `:T:type199::`
(typed) and `:X:paste200::` (paste). Typing them only confirms the runtime behavior matches.

### Results — 2026-07-15, AHK v2.0.19

| Item | Result |
|---|---|
| `endchar` | **Pass** — exactly one space; AHK consumes the end char, so the `A_EndChar` re-send is correct |
| `omitend` | **Pass** — no trailing space; omit honored |
| `type199` | **Pass** — 199 `a` chars, typed |
| `paste200` | **Pass** — 200 `b` chars, pasted |
| `starend` | **Pass** — fires with no ending char |
| `big100k` | **Pass** — 100,000 chars pasted, no truncation or corruption; `ClipWait(1)` is sufficient |
| `clipmark` | **Pass** — clipboard restored to its pre-paste contents after the paste |

All items pass. The plan's pre-merge manual acceptance gate is satisfied.

## Full path (UI-driven)

Use this if you also want to exercise the Create/Preview path and the preview chip.

## Before you start

- AutoHotkey v2 installed; Notepad (or similar) open as the paste target.
- API + Blazor UI running locally.
- `payloads/` has ready-made paste text: `199-a.txt`, `200-b.txt`,
  `100000-digits.txt`, `5-line-endchar.txt`.

## Procedure

For each row: **Hotstrings → New hotstring**, Kind = Text, paste Trigger/Replacement,
set Delivery + checkboxes, Save, expand **Generated AutoHotkey code**, copy it into
a `.ahk` file, run with AutoHotkey v2, test in Notepad.

| # | Trigger | Replacement | Delivery | Checkboxes | Verify |
|---|---|---|---|---|---|
| End-char | `sig1` | `5-line-endchar.txt` | Clipboard | — | `sig1`+Space → exactly one space after "five" |
| Boundary 199 | `b199` | `199-a.txt` | Auto | Expand immediately | Preview chip = **Hotstring**; types visibly |
| Boundary 200 | `b200` | `200-b.txt` | Auto | Expand immediately | Preview chip = **Clipboard**; pastes instantly |
| Omit off | `om1` | `200-b.txt` | Clipboard | — | `om1`+Space → one space after text |
| `O` option | `om2` | `200-b.txt` | Clipboard | Omit ending character | `om2`+Space → no space after text |
| `*` option | `om3` | `200-b.txt` | Clipboard | Expand immediately | `om3` → no ending char after text |
| 100k paste | `big1` | `100000-digits.txt` | Auto | Expand immediately | Full 100,000 chars, no truncation/corruption |
| Clipboard restore | `rst1` | `200-b.txt` | Clipboard | — | Copy a marker string, trigger `rst1`+Space, then paste elsewhere → marker returns, not the replacement |

Notes:
- Rows other than the two boundary rows set Delivery = Clipboard explicitly so length doesn't matter.
- Check the preview chip (`data-test="preview-delivery"`) before testing in AHK.

## After testing

Record pass/fail in the plan's Verification section or PR description. Delete the test hotstrings afterward.
