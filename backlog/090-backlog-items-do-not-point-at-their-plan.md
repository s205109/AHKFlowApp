# 090 - Backlog items do not point at their plan

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (repo process)
- **Difficulty**: complex
- **Stage**: 1-pickup

## Summary

A backlog item names its spec but not its plan, so a session that picks the item up reads the
spec and starts building from it. The plan is the later and more exact document, and it is missed.
This happened on backlog 077 on 2026-08-13.

## User story

As a session picking work up, I want the backlog item to name its plan, so that I implement the
plan the maintainer approved instead of re-deriving the work from the spec.

## Detail

### What happened

The session was asked to implement `backlog/077-pre-commit-refusal-of-human-commits-on-main.md`.
It read the item, read the spec the item names, and started writing code. It wrote
`.githooks/pre-commit.ps1` and `.githooks/pre-merge-commit` and began rewriting the test suite.
The maintainer then asked whether the plan had been used. It had not. The work was reverted with
`git checkout --` and restarted from
`docs/superpowers/plans/2026-08-13-pre-commit-main-branch-refusal-plan.md`.

Nothing was lost except the session's time. The spec is thorough, so the code the session wrote
was close to the plan's. It was not identical: the plan pins helper names
(`Get-CurrentBranchName`, `Invoke-AgentWorktreeRule`, `Invoke-IsolatedGitCommand`), a
`$script:ProtectedBranchName` constant, the exact warning strings the new tests assert, and a
task order that keeps the suite runnable at every step.

### Why the plan was missed

Three causes, each of which is enough on its own.

1. **The item does not name the plan.** `backlog/077-...md:38-44` lists the parent spec and the
   own spec. It has no plan line. The item is the first file a session reads, so its list of
   links is the reading list.
2. **The item's Stage field is stale.** It reads `Stage: 2-design`
   (`backlog/077-...md:9`). A finished plan means the work reached stage 3. An accurate stage
   would have contradicted the item's own link list and prompted a search.
3. **No search finds the plan by accident.** `docs/superpowers/` is a separate git repository
   linked into each worktree, so `git grep`, `git log`, and `git status` in this repository never
   see it. Discovery is a deliberate directory listing or nothing.

### How common the gap is

Measured on 2026-08-13 across `backlog/`, `backlog/done/`, and `backlog/blocked/`:

| Fact | Count |
|---|---|
| Items naming a path under `docs/superpowers/specs/` | 28 |
| Items naming a path under `docs/superpowers/plans/` | 5 |
| Plan files in `docs/superpowers/plans/` | 142 |
| Spec files in `docs/superpowers/specs/` | 79 |

Four of those five items are already in `backlog/done/`. So one open item names its plan.

### What would prevent it

The order below is smallest fix first. The item does not decide between them; that is the design
step's job.

- Add a plan line to `backlog/000-backlog-item-template.md`, beside a spec line, so a new item
  carries the slot and an empty slot is visible.
- Add a rule to `CLAUDE.md`: before implementing an item, list both `docs/superpowers/specs/` and
  `docs/superpowers/plans/` and search both for the topic. A plan wins over a spec.
- Put the backlog number in the spec and plan file names. `2026-08-10-development-process-design-071.md`
  already does this; `2026-08-13-pre-commit-main-branch-refusal-plan.md` does not, and the number
  077 appears nowhere in it. With the number in the name, one glob finds item, spec, and plan.
- Check the pointer mechanically, so a stage-3 item with no plan line fails rather than passing
  quietly.

## Acceptance criteria

- [ ] A session that reads a backlog item can reach that item's plan without guessing a file name
      or listing a directory it was not told about.
- [ ] `backlog/000-backlog-item-template.md` carries the slot the fix depends on, if the chosen
      fix is a template change.
- [ ] The open items that have a plan today carry the pointer, or the item records why they are
      left alone.
- [ ] The rule a session must follow is written in `CLAUDE.md` or `AGENTS.md`, not only in a
      backlog item.

## Out of scope

- Renaming the 221 existing files in `docs/superpowers/specs/` and `docs/superpowers/plans/`. If
  the fix is a naming convention, it applies to new files, and back-filling is its own item.
- Any change to the private plans repository's structure or to how `scripts/new-worktree.ps1`
  links it into a worktree.
- The Stage field itself. Backlog 087 owns that.

## Notes / dependencies

- Sibling of backlog 087 (backlog template carries the Stage field). Both change
  `backlog/000-backlog-item-template.md`, so whichever runs second rebases on the first.
- Found while implementing backlog 077 on 2026-08-13.
- The plan that was missed:
  `docs/superpowers/plans/2026-08-13-pre-commit-main-branch-refusal-plan.md` (private plans repo).
