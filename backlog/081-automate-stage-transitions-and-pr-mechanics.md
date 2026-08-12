# 081 - Automate stage transitions and PR mechanics

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: complex
- **Stage**: 1-pickup
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

`docs/development/workflow.md` describes every stage transition precisely, and every one of
them is still performed by hand: edit the `Stage` field, write a conventional commit, push,
and at Pickup also open the draft pull request. Backlog 071 walked that loop about a dozen
times in one branch and got the transition wrong or late more than once — both caught by
review rather than by tooling.

This item turns the written transition into a command.

## Why now

The process is finally specified tightly enough to encode. Wave 1 wrote it down and
deliberately changed no scripts, so none of it is automated. Backlog 072 holds no usable
figure for the friction this leaves — three measurement attempts were all rejected in review
— so the case for this item rests on the defects below, not on a count.

Three defects from the backlog-071 review rounds were transition mechanics, not rules:

- the Stage field was published before the pull request existed, so a failed
  `gh pr create` left the remote claiming a stage the work had not reached
- the Review failure edge was recorded *after* its fixes, twice
- the Ship closure commit was never pushed, so a merge would have dropped the records

A script makes the correct order the only order.

## User story

As a contributor, I want one command to complete a stage transition so that the field, the
commit, the push, and the pull request cannot disagree with each other.

## Acceptance criteria

- [ ] One script performs a transition end to end: set the `Stage` field to the target,
      commit with the conventional message, and push.
- [ ] It refuses a transition the canon does not allow. The legal targets come from
      `docs/development/workflow.md`, read at run time, not from a list copied into the
      script — a copy is one more thing to drift.
- [ ] Pickup also pushes the branch and opens the draft pull request, and stamps the Stage
      **only after** `gh pr create` succeeds.
- [ ] Ship pushes the closure commit before the ready flip.
- [ ] A failure edge refuses to run until the red evidence and a recovery task are recorded
      in `PLAN-PROGRESS.md`, matching the Verify failure rule.
- [ ] A housekeeping round with no item writes the `Stage:` line in its pull request body
      instead, with the read-modify-write sequence the canon specifies, including the
      read-back check.
- [ ] It works from a worktree without any main-checkout handover, for the paths it touches.
- [ ] Tests cover: each legal transition, a refused illegal one, the Pickup ordering, the
      Ship push, and the round pull-request-body path.

## Out of scope

- Creating worktrees. `scripts/new-worktree.ps1:106` refuses nested creation, so a new
  worktree still starts from the main checkout. Worth its own item if it stays painful.
- Reserving a backlog number before the worktree is named — backlog 080.
- Regenerating the PDF and rehashing the sidecar when an exit string changes. Related
  manual step, different trigger; file separately if this item does not absorb it.
- Any change to the guard — backlog 076.

## Notes / dependencies

- Depends on backlog 072, which adds `Stage` and `Difficulty` to the item template and to
  `scripts/new-backlog-item.ps1`. Without those the script has no field to edit on a fresh
  item.
- The canonical transition table is `docs/development/workflow.md` section 3: eleven stages,
  five edges each, and the exact target tokens. Section 4 carries the writer rule, the push
  boundaries, and the two-repo commit ordering.
- Read the legal targets from the document rather than duplicating them. Backlog 072's drift
  guard exists because copies of process rules drift; a script is just another copy.
