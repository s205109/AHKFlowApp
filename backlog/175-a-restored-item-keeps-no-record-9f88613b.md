# 175 - A restored item keeps no record of why it applies to no profile

## Metadata

- **Epic**: History
- **Type**: Defect
- **Interfaces**: API | UI
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

When a restore leaves an item applying to no profile, the failed rules are named only in a
snackbar. Dismiss it and nothing anywhere says why. The item reaches no generated script and
looks ordinary except for a blank Profiles cell.

## User story

As an owner, I want to find out later why a restored item reaches no script, so that I can repair
it without having to guess.

## Acceptance criteria

- [ ] After a reload, an item left applying to no profile by a restore still says somewhere why.
- [ ] That reason names the same rules the snackbar named at restore time.
- [ ] An item in this state is distinguishable in the grid from one an owner scoped to no profile
      on purpose, or the item records why that distinction is not needed.
- [ ] An E2E flow test reloads after the restore and asserts the reason is still reachable.

## Out of scope

- Changing ADR-0021's asymmetry between Restore and Revert, which is deliberate.
- Making a failing restore refuse instead. ADR-0021 chose the other behaviour on purpose.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F16, S3. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **The designed behaviour works.** A tombstone whose stored snapshot held a window-context value
  containing a double quote, which `WindowContextRules` now forbids, restored with this message:

  > Hotstring restored, but it applies to no profile: ContextValue must not contain double-quote
  > characters. Open it, fix those values, and choose its profiles again.

  The item came back with `appliesToAllProfiles: false` and no profiles, exactly as ADR-0021
  specifies. The technique matches the existing E2E test, and it is the realistic case: the rule
  landed after snapshots started being written.
- **The defect is what happens next.** The snackbar is raised with `RequireInteraction` set, and
  nothing persists its content. After dismissing it and reloading:
  - a search of the whole document for "double-quote" returns nothing;
  - `GET /api/v1/hotstrings` returns `restoreWarnings: null`;
  - the row looks ordinary except that its Profiles cell is blank;
  - opening the item shows no error at all until Save is pressed.
- So the reason is recoverable but not discoverable. Pressing Save does show the rule inline on
  the right field, and the bad value is still stored, which is what makes the repair path work.
- The message itself also names a property rather than the field's visible label. Item 169 covers
  that wording across the app.
- **This item asks to revisit an accepted consequence, not to fix an oversight.** ADR-0021
  Consequence 3 says it plainly: "'Applies to no profile' has two causes that look identical...
  Nothing persisted tells the two apart. Only the Restore response carries the rule messages." The
  second cause it names is an owner deleting every profile an item named, which is item 166's
  other half. So the work here changes a decision the project made on purpose, and it has to amend
  ADR-0021 or supersede it. Treat the third acceptance criterion above as the point of the item:
  it asks for exactly the distinction Consequence 3 accepted doing without.
- The rejected alternative in the same ADR is close to this item and is not the same thing.
  ADR-0021 rejected "Accept both unchanged, with a warning", because a broken value would then
  reach the next generated script. This item does not ask for that. It asks for the already-chosen
  behaviour to leave a record the owner can read later.
- Related. Item 166 records that a profile delete produces this same state with no warning at
  all. One path shouts and the other is silent. Design the two together: if a restore and a
  profile delete both need a durable record, one mechanism should serve both.
- Spec: needed — where the reason lives is a design decision. Options include persisting
  `restoreWarnings` on the item, writing a history entry, or marking the item as needing repair.
- Plan: none — complex, so Design comes first at pickup.
