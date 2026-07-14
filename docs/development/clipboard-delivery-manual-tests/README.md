# Clipboard Delivery Manual Testing

Manual acceptance checklist from
[`docs/superpowers/plans/2026-07-13-clipboard-delivery-plan.md`](../../superpowers/plans/2026-07-13-clipboard-delivery-plan.md#verification).
Run once against a real AutoHotkey v2 install before merging `feature/wt-clipboard-delivery`.

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
| Boundary 199 | `b199` | `199-a.txt` | Auto | Expand immediately | Preview chip = **Typed**; types visibly |
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
