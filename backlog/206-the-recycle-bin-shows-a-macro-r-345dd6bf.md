# 206 - The Recycle Bin shows a Macro Replacement as raw tokens

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: API, UI
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The Recycle Bin shows a deleted Macro hotstring's Replacement as its stored text, with the raw
`{{cursor}}` token in it. The Hotstrings grid shows the same value with a `⌖ cursor` chip.

## User story

As an owner, I want the Recycle Bin to show a Macro the same way the Hotstrings grid does, so
that I can recognise the item before I restore it.

## Acceptance criteria

- [ ] The Recycle Bin shows a Macro definition the same way the grid does, not as the raw
      `{{cursor}}` token.
- [ ] The Recycle Bin shows a Date & time definition by its format summary, the same way the
      grid does, not as an empty Details cell.
- [ ] The Recycle Bin shows a Raw definition by the first line of its definition, the same way
      the grid does, not as the whole multi-line definition.

## Out of scope

- How the Hotstrings grid shows a Macro. The grid is the reference, not the change.
- The wording of other messages. Item 169 owns it.

## Notes / dependencies

- Split from backlog 169 at its Pickup on 2026-11-05. Item 169 asked for one pull request per
  outcome, and this is its outcome 3.
- Found by the acceptance sweep on 2026-10-13, finding F18. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F18, the Recycle Bin.** A deleted Macro hotstring's details read `<a
  href="{{cursor}}"></a>`. The grid renders the same value as a `⌖ cursor` chip.
- Spec: none — the grid already shows the result the owner expects, so nothing needs designing.
- Plan: `docs/superpowers/plans/2026-11-06-recycle-bin-shows-hotstring-kinds-plan-206.md`
- Scope widened at Plan on 2026-11-06: the owner asked to include Date & time in this pull
  request. Raw comes in too, because it needs only the Kind that the fix adds anyway.
- Follow-up, not yet filed: the History dialog also shows a Macro snapshot's raw `{{cursor}}`
  text. The plan review on 2026-11-06 kept it out of this item. The new item must first decide
  whether that preview shows chips or the exact stored text.
