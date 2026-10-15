# 172 - The import paste box caps input at half the limit

## Metadata

- **Epic**: Hotstrings
- **Type**: Bug
- **Interfaces**: UI
- **Difficulty**: moderate
- **Stage**: 5-simplify

## Summary

The import dialog's paste box stops accepting input at 524,288 characters, which is exactly half
the 1 MiB the server supports. The paste is truncated with no warning, so an owner can import a
partial script believing it was complete.

## User story

As an owner, I want to paste a whole script into the import box, so that I do not silently import
half of it.

## Acceptance criteria

- [ ] The paste box accepts a script up to `HotstringImportRules.MaxScriptLength`.
- [ ] A paste larger than `HotstringImportRules.MaxScriptLength` produces a visible message that
      says the script is too large. It is not cut down to the limit in silence.
- [ ] The dialog sets its own maximum length rather than inheriting a component default.
- [ ] A test covers a paste larger than 524,288 characters, and a second test covers a paste
      larger than `HotstringImportRules.MaxScriptLength`.

## Out of scope

- Raising the 1 MiB server limit.
- The file upload path, which the sweep found correct.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F19, S3. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- The rendered textarea in `Components/Hotstrings/HotstringImportDialog.razor` carries
  `maxlength="524288"`, so the browser stops accepting input at 512 KiB. The text simply stops:
  no warning, no message, no visible sign.
- `HotstringImportRules.MaxScriptLength` is `1_048_576`, and the server enforces that limit
  itself, so a 1 MiB script is supported.
- **The cap was never a decision.** The dialog sets no maximum length at all. 524,288 is
  MudBlazor's own default for the field, and it happens to be exactly half the supported size.
- **Raising the number alone does not fix the defect.** The defect is the silent truncation, and a
  `maxlength` of 1,048,576 truncates a 2 MiB paste in exactly the same silent way. So the item
  needs an answer for a paste the server would refuse: say so on screen, and prove it with a test
  above the server's limit as well as one above MudBlazor's default.
- The rest of the import feature was the best-built thing the sweep drove. The classifier gets
  every case right, including a duplicate against an earlier row in the same batch, matched
  without case. Only the edges produced findings.
- Spec: none — the fix is to set the limit the server already states.
- Plan: `docs/superpowers/plans/2026-10-15-import-paste-box-limit-plan-172.md`
