# 122 - Plan guard judges the wrong backlog item

## Metadata

- **Epic**: Worktree tooling
- **Type**: Bug
- **Interfaces**: none - repository tooling
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

The worktree plan guard reads a backlog number from the worktree manifest. That number goes stale
when the item is renumbered, so the guard judges somebody else's item. When it refuses, the outcome
log always writes the same sentence, whatever the real reason was.

## User story

As a developer running a merged-cleanup sweep, I want the guard to judge the item my worktree
actually serves, and to say why it refused, so that a finished worktree does not survive forever
behind a message that is not true.

## Where this came from

`wt-give-each-worktree-removal-its-abefe700` survived every sweep between 2026-08-27 and
2026-08-28. Its item, 120, is in `backlog/done/`, every box is ticked, and the pull request merged.

## Root cause

The worktree manifest records `AHKFLOW_BACKLOG_ITEM=118`. Item 120 was filed as 117, renumbered to
118, then renumbered to 120. Nothing rewrote the manifest past 118.

`Test-WorktreePlanWasImplemented` therefore reads item 118, which is a different item that is still
open. Item 118's `- Plan:` bullet is still the unfilled template text `<path, or "none - reason">`.
That is not a path under `docs/superpowers/plans`, so the guard refuses.

Measured on 2026-08-28 by calling the guard directly against the live worktree:

```
item=[118]
Allow  : False
Reason : backlog item 118 names a plan outside docs/superpowers/plans
```

The same call with `120` returns `Allow : True`.

`scripts/new-worktree.ps1` printed the same finding on its own sweep the same day:

```
cleanup: keeping '...\wt-give-each-worktree-removal-its-abefe700' because backlog item 118 names
a plan outside docs/superpowers/plans.
```

## The two defects

**1. The recorded number goes stale.** Two places write the key. `new-backlog-item.ps1` writes it
once, when the item is filed. `setup-worktree-local-dev.ps1` derives it from the worktree name, but
only when no value is recorded yet: `Resolve-WorktreeBacklogItem` returns any recorded value
untouched. A renumber is a hand `git mv` plus a heading edit, so neither writer ever runs again, and
a wrong value is kept forever.

**2. The outcome log states a reason nobody checked.** Both writers hardcode one sentence,
`Kept: the plan was never implemented.`, whatever the verdict was. The real reason reaches stderr
and the diagnostics log. A human reading `.claude/worktrees/worktree-removal.log` sees only the
fixed sentence. That wording sent this investigation to item 120's checkboxes, which were correct
all along.

## Acceptance criteria

### The guard judges the item the worktree serves

- [ ] A worktree whose recorded number names an item that is not its own is judged against its own
      item instead.
- [ ] A sweep from the main checkout removes `wt-give-each-worktree-removal-its-abefe700` with no
      hand edit of its manifest.
- [ ] A worktree with no recorded backlog item is still removable. An unknown item still refuses.
- [ ] A test builds a worktree whose recorded number and whose directory name point at two
      different items, and asserts the guard reads the right one.
- [ ] `ConvertTo-BacklogSlug` in `scripts/slug.common.ps1` stays the only slug rule in the
      repository.

### The outcome log names the reason that applied

- [ ] A kept-worktree line in `.claude/worktrees/worktree-removal.log` carries the guard's own
      reason.
- [ ] Two different refusal reasons produce two different lines in that log.
- [ ] Both the sweep and the removal hook gate write the reason.
- [ ] A long or multi-line reason still produces exactly one log line.

## Out of scope

- `Get-NextBacklogNumber` and the number collisions that force a renumber. That is item 121.
- Renumbering or repairing other items that already collided.
- The merged-ness decision (`Test-BranchOwnWorkWasMerged`) and the sweep's precedence rules.
- The wording of outcome lines other than the plan-guard refusal.

## Notes / dependencies

- Item 121 on `fix/wt-backlog-numbering-reads-one-working-tree` fixes the numbering that causes
  renumbering. It says nothing about the manifest or the log, and it puts repairing already
  collided items out of scope. The two items do not overlap.
- The worktree directory is `wt-<slug>` and the backlog file is `<NNN>-<slug>.md`. Both names come
  from the same `ConvertTo-BacklogSlug`. Backlog 080 established that pairing, and
  `tests/BacklogNumbering.Tests.ps1` pins it. The slug survives a renumber; the number does not.
- Filing this very item hit item 121's defect again. The scaffold handed out 121, which
  `fix/wt-backlog-numbering-reads-one-working-tree` already holds. The file was renamed to 122 by
  hand, and the manifest had to be rewritten by hand as well. That second step is exactly the
  defect this item fixes, and nothing would have reminded a person to do it.
- The slug lookup this item needs already exists in `scripts/setup-worktree-local-dev.ps1`, but it
  scans `backlog/` only and never re-checks a number it already recorded. Grilling found it. The
  plan reuses it rather than writing a second one.
- Spec: none - the root cause is proven above, so this goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-08-28-plan-guard-identity-plan-122.md`
