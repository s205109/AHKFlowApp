# 034 - Align UI labels with CONTEXT.md vocabulary

## Metadata

- **Epic**: Domain model adoption
- **Type**: Chore
- **Interfaces**: UI

## Summary

The glossary (`CONTEXT.md`, PR #192) declares canonical terms whose avoided synonyms still appear as live UI labels. Docs-only Wave 3 recorded the vocabulary; this item makes the UI follow it.

## Acceptance criteria

- [ ] Kind filter label `Type` → `Kind` (`Pages/Hotstrings.razor:42`)
- [ ] Inline grid checkbox label `Any` → matches "Apply to all profiles" (`Pages/Hotstrings.razor:901`)
- [ ] `EntityChips` `Any` chip → glossary-conformant label (`Components/Common/EntityChips.razor:5`)
- [ ] Delivery option label `Hotstring` → non-overloading term, e.g. `Typed` (`Components/Hotstrings/HotstringEditDialog.razor:65`)
- [ ] Ending-character labels (`Expand immediately (no ending character)`, `Omit ending character`) conform to the glossary's "Ending character" entry — verify wording, no rename forced (`HotstringEditDialog.razor:268,272`, `Hotstrings.razor:982,985`)
- [ ] Sweep remaining pages/dialogs (incl. Hotkeys mirror components) for `Type`/`Any` labels
- [ ] Affected bUnit/E2E assertions and `data-test` docs updated

## Out of scope

- Renaming enum members or API contract fields (`HotstringDelivery.Type` stays)
- CLI output wording

## Notes / dependencies

- Source: local review of PR #192 (finding 5), 2026-07-16
- Check space constraints on mobile chips before choosing the `Any` replacement
