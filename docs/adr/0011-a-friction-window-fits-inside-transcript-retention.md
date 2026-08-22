# A friction measurement window fits inside transcript retention

Friction metrics 1 and 4 match on wording, so their recall is unknown. Measuring it needs a
sample of messages read by hand. The sample is evidence only while the messages it describes
still exist.

Claude Code deletes session transcripts older than `cleanupPeriodDays`, which defaults to 30
days. The wave-2 window runs 2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z
(`scripts/measure-process-friction.ps1:74`, "$script:WindowStart = [datetime]::Parse('2026-07-15T14:14:32Z')")
and
(`scripts/measure-process-friction.ps1:75`, "$script:WindowEnd = [datetime]::Parse('2026-08-12T14:14:32Z')").

That window started ageing out of the transcripts on 2026-08-14, two days after it closed. By
2026-08-21 its first week was gone, along with nine of the 38 flagged next-step asks. A copy of
what remained was taken that day, which is the only reason backlog 113 could draw the sample
again.

So the rule, in two upper bounds: **a friction measurement window is at most 21 days, and the
draw runs at most 7 days after the window closes.** The draw may run as soon as the window
closes; there is no waiting period.

The arithmetic is what fixes those two numbers. The oldest message in a window sits at the
window's start. Its age when the draw runs is the window's length plus the delay after the
window closes. 21 plus 7 is 28, which is inside the 30-day retention period with two days to
spare. A rule stated as a minimum delay would give no guarantee at all: "at least 7 days after"
is satisfied on day 60, when the whole window is gone.

## Considered options

**Raising `cleanupPeriodDays` was rejected.** It is a setting on one person's machine, not a
setting this repository controls. It recovers nothing already deleted, and a rule that depends on
a machine setting is not a rule the repository can keep.

**Committing an artifact that survives deletion was rejected as a complete answer.** The sample
manifests already carry the full text of every sampled row, so any published label can always be
re-checked. That is worth keeping and it is not enough. It does not let anyone draw a *different*
sample from a past window, which is what a redraw needs. Committing the whole population is not
possible either: the 2026-08-21 copy is 445 MB of message text.

**Keeping the four-week window and accepting the risk was rejected.** Four weeks plus the time it
takes to measure, label and publish already exceeds 30 days. That is not a risk. It is what
happened.

## Consequences

**Once every full-population copy of a window is gone, that window can never be drawn again.**
Its manifest is then its only record. A retained copy of the transcripts is the one exception,
and backlog 113 depends on exactly that: it redraws the wave-2 window from a copy taken on
2026-08-21. A copy is a reprieve with its own deletion date, not a substitute for this rule.

**The wave-2 window keeps its four-week bounds.** Backlog 072 fixed them as a rule with a ticked
box, and every one of its five metrics was measured over them. Narrowing them now would redefine
the three metrics this rule was never about. So the wave-2 figures stay a four-week measurement
whose first week is no longer readable, and the next measurement is the first to use the rule.

**Figures from different windows are not comparable.** A 21-day window produces smaller counts
than a 28-day one for that reason alone. Any document publishing two windows' figures says which
window each one describes.

**The measurement gets a deadline it did not have.** The draw must have run within 7 days of the
window closing. That is the same bound stated in the rule above, and it is the only deadline.
Labelling can take longer, because the manifest carries the full text of every sampled row.
