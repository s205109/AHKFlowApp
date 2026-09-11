# A shipping pull request is ready and fully ticked

A check refuses a pull request that finishes a Backlog item without closing its Records. It fires
on two conditions together: the pull request is **not a draft**, and **every** Acceptance box in
the item is ticked, while the item still sits in `backlog/`.

Neither condition works alone, and each one blocks a different wrong report.

`workflow.md` ticks the Acceptance boxes at Document and moves the file at Ship. So between those
two stages an item legitimately has every box ticked and still sits in `backlog/`. A check on box
state alone would refuse that state, which is the normal way of working.

Ship is the only stage with a ready pull request, so "ready" looks like the whole rule. But most
items ship over more than one pull request, and every pull request but the last must merge with
its item still open. Backlog 106 already rejected that rule for this reason.

Read together the two conditions leave no legitimate state. A partial delivery has unticked boxes.
The Document-to-Ship window is still a draft. Backlog 132, which merged with all five boxes ticked
and `Stage: 4-execute`, matches both.

## Considered options

**Box state alone.** Rejected. It refuses the specified Document-to-Ship window, so the check would
be switched off inside a week.

**Ready state alone.** Rejected. It refuses every pull request but the last of a multi-pull-request
item. This is the candidate backlog 106 rejected, for the same reason.

**A pull request that touches an item without moving it to `backlog/done/`.** Rejected by backlog
106 before this item existed. It is the ready-state rule with a weaker trigger, and it fails on the
same multi-pull-request shape.

**Reuse `.github/code-paths-filter.yml` to decide what counts as a delivery.** Rejected. It
excludes `scripts/**/*.ps1` and `tests/*.ps1`, so a process-tooling pull request counts as "not
code" — including the one that added this check. It was drawn for the coverage gate, which asks a
different question.

**Lower the stale-open threshold from 12.** Rejected. The number was measured and the measurement
is recorded in `scripts/backlog-staleness.common.ps1`. Healthy items scored 5 and 8, and the one
real defect scored 24. Lowering it turns a real signal into noise.

## Consequences

**The rule depends on drafts.** It is correct only because Pickup opens the pull request as a draft
and Ship flips it to ready. A pull request opened ready from the start would be refused at Document
time. `workflow.md` Stage 1 makes drafts the route, so the assumption holds, but it is an assumption
and not a fact about GitHub.

**`ci.yml` needs one more trigger.** Its `on: pull_request` block names no `types:`, so it defaults
to `opened`, `synchronize` and `reopened`. Flipping a pull request to ready fires
`ready_for_review`, which is not in that list. Without adding it, the check would never run at the
one moment it is meant to.

**The draft state cannot be read locally.** Stage 9 pushes before it flips to ready, so at pre-push
time the pull request is always still a draft. This check is therefore CI-only, and the local Gate
cannot pre-verify it. The script takes the draft state as a parameter so a fixture can still
exercise both branches.

**It is a backstop, not the real fix.** Backlog 132 happened because a person had to remember four
separate edits. Backlog 081 turns each Stage transition into one command, which is the fix that
stops the mistake instead of reporting it. This check keeps its value after 081 lands, because an
item can always be edited by hand, but nobody should read it as the answer to the underlying
problem.
