# 087 - Backlog template carries the Stage field

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (repo process)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

`docs/development/workflow.md` names the item's `Stage` field as the durable record of where the
work stands, but `backlog/000-backlog-item-template.md` has no such field. So every item either
grows one by hand or never gets one, and a resumed session cannot tell which.

## User story

As a session picking work up after a cleared context, I want every backlog item to carry a Stage
field, so that I can read the stage instead of guessing it from the branch and the commit log.

## Detail

The workflow document treats the field as required. `docs/development/workflow.md:78` calls the
`Stage` field in the backlog item the durable stage record, and line 80 tells a resumed session to
read it first. The template does not produce one, so items drift three ways:

- `backlog/done/084-guard-fails-closed-on-pipeline-bound-move-sources.md` has no Stage line
- `backlog/done/076-guard-exception-commit-to-plans-repo-from-worktree.md` reached `backlog/done/`
  still reading `Stage: 3-plan` (corrected in pull request #296)
- Other items carry a Stage line that matches nothing in the template

Adding the field to the template settles the spelling and the starting value. Items are filed at
Intake, and `workflow.md:257` says an item keeps `Stage: 1-pickup` until the Difficulty stamp
lands, so the template's own starting value needs deciding rather than guessing.

## Acceptance criteria

- [ ] The template carries a Stage line, with a starting value the workflow document supports
- [ ] The existing items in `backlog/`, `backlog/done/`, and `backlog/blocked/` either carry an
      accurate Stage line or are listed here as deliberately left alone
- [ ] The rule that ships an item sets `Stage: 9-ship`, already in `workflow.md:480`, is checked
      by something other than a reviewer's eye, or the item records why it cannot be

## Out of scope

- Any change to the stage names or the stage sequence
- Adding other missing metadata fields, such as Difficulty

## Notes / dependencies

- Found in review of pull request #296 (backlog 083 redelivery)
