# 122 - Plan guard judges the wrong backlog item

## Metadata

- **Epic**: Worktree tooling
- **Type**: Bug
- **Interfaces**: none - repository tooling
- **Difficulty**: moderate
- **Stage**: 9-ship

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

- [x] A worktree whose recorded number names an item that is not its own is judged against its own
      item instead.
- [x] A sweep removes a worktree whose recorded number names one item while its directory name
      matches a second item that sits in `backlog/done/` with an implemented plan, and the manifest
      is not edited. Proved by a fixture, so the box can be settled before this branch merges.
- [x] A worktree with no recorded backlog item is still removable, **including when its directory
      name matches an open item**. The empty-number allow stays ahead of the name lookup.
- [x] A name lookup that cannot answer keeps the worktree. More than one item carrying the slug, or
      an item that cannot be read, refuses instead of falling back to the recorded number. Only
      "no item carries this slug" falls back. Added after review; see **The review round** below.
- [x] An unreadable manifest still refuses.
- [x] A test builds a worktree whose recorded number and whose directory name point at two
      different items, and asserts the guard reads the right one.
- [x] The name lookup accepts a suffixed item number such as `022b`.
- [x] `scripts/setup-worktree-local-dev.ps1` records `022b` for a worktree whose open item is named
      `022b-<slug>.md`. It records an empty value today, which switches the plan guard off for that
      worktree.
- [x] `scripts/setup-worktree-local-dev.ps1` still derives a number from `backlog/` only, and the
      backlog 073 regression test still passes unchanged.
- [x] `ConvertTo-BacklogSlug` in `scripts/slug.common.ps1` stays the only slug rule in the
      repository.

### The outcome log names the reason that applied

- [x] A kept-worktree line in `.claude/worktrees/worktree-removal.log` carries the guard's own
      reason. Proved by running the real hook and the real sweep, not by scanning source text.
- [x] Two different refusal reasons produce two different lines in that log.
- [x] Both the sweep and the removal hook gate write the reason.
- [x] A long or multi-line reason still produces exactly one log line.
- [x] When the guard allows but the recorded number and the directory name disagree, the removal
      still happens and the diagnostics file names both numbers.

## The review round

Review found that the first implementation failed open. The slug lookup returns three statuses,
and the guard handled only `found`. Both `absent` and `unusable` fell back to the recorded number,
so an ambiguous or unreadable slug judged a different item — the original defect through a second
door.

Measured on the built branch before the fix, with two items sharing the slug and a stale recorded
item 118 whose bullet said `Plan: none`:

```
Allow  : True
Reason : backlog item 118 states it has no plan
Item   : 118
```

After the fix, the same fixture:

```
Allow  : False
Reason : 2 backlog items carry the slug 'probe-slug'
```

`absent` still falls back, because no item carries the slug and there is nothing else to judge.
`unusable` refuses. When one item matched and only the read failed, the refusal names that item
rather than the recorded number.

The earlier ambiguity test could not catch this: its recorded item refused on its own, so the
fallback looked safe. The new test gives the recorded item a `Plan: none` bullet, which allows.

## The second review round

A second review found four more ways the guard could judge the wrong item, plus one stale comment.

**The direct hook never logged the disagreement.** The sweep wrote "Plan guard judged backlog item
X; the worktree manifest records item Y" on the allow path, and the hook wrote nothing. The
acceptance box above says "the diagnostics file names both numbers", and it does not say "in the
sweep only", so the hook was missing half of it. The hook now writes the same sentence, and
`tests/WorktreeRemoveHook.Tests.ps1` drives the real hook to prove it.

**The base was resolved twice.** The slug lookup ran `rev-parse` and `ls-tree` for itself, and an
`absent` answer then sent the number lookup through the same two calls again. A base ref such as
`origin/main` moves, so a fetch between the two calls let the guard answer "no item carries this
slug" against one commit and read the recorded item out of another. `Get-BacklogInventoryFromRef`
now takes one snapshot, and both lookups match against it.

**An unreadable folder read as "no such slug".** The working-tree slug scan used
`Get-ChildItem -Filter ... -ErrorAction SilentlyContinue`, so a folder it could not read came back
as `absent`, and the guard fell back to the recorded number. `-ErrorAction Stop` alone does not fix
this: measured on Windows, `Get-ChildItem` with a `-Filter` answers a folder under a deny rule with
an empty list and raises nothing at all. The filter is gone, the name test does that work instead,
and the same call now throws and returns `unusable`.

**`ItemNumber` could name an item the guard never opened.** It started as the recorded number, and
an ambiguous or unresolvable slug lookup kept that value, which contradicts the field's own
contract. It now carries the lookup's own answer: the item when one was selected, and empty when
none was.

**The setup script's comment was stale.** It said the plan guard reads the recorded value rather
than re-deriving it. The guard resolves the item from the worktree name first now, and reads the
recorded value only as a fallback.

Three mutations proved the new tests. Each reverted one line, the named suite ran, and the line was
restored:

| Mutation | Suite | Result |
|---|---|---|
| The slug scan goes back to `-Filter` plus `SilentlyContinue` | `WorktreePlanGuard` | fails |
| The unusable refusal reports the recorded number again | `WorktreePlanGuard` | fails |
| The hook's allow-path diagnostic is deleted | `WorktreeRemoveHook` | fails |

The one-snapshot change carries no test of its own. Its effect only shows when the base ref moves
between two git calls, which no single-process test can stage. Every existing base-ref case in
`tests/WorktreePlanGuard.Tests.ps1` still passes, and those cover the resolve, absent, ambiguous,
and unresolvable paths.

One reviewer suggestion was not taken: dropping one of the two hook refusal fixtures. The box "Two
different refusal reasons produce two different lines in that log" is not scoped to the sweep, and
those two fixtures are the only proof of it on the hook path.

`pwsh ./scripts/run-powershell-suites.ps1` — 45 of 45 suites pass.

## How this was verified

`pwsh ./scripts/run-powershell-suites.ps1` — all 45 suites pass. Build, format check, and
`git diff --check main...HEAD` are green. The coverage slice reports nothing to run: this branch
changes no path that `.github/code-paths-filter.yml` covers.

Every new test was proved with a mutation. Each mutation reverted one line, the named suite ran,
and the line was restored:

| Mutation | Suite | Result |
|---|---|---|
| The guard's slug lookup returns nothing | `WorktreePlanGuard` | fails |
| The empty-number allow loses to the slug route | `WorktreePlanGuard` | fails |
| The guard's number shape drops `[a-z]?` | `WorktreePlanGuard` | fails |
| `setup-worktree-local-dev.ps1` drops `[a-z]?` | `WorktreeLocalDevSetup` | fails, on the new case only |
| The sweep logs the old fixed sentence | `WorktreeMergedCleanup` | fails |
| The hook gate logs the old fixed sentence | `WorktreeRemoveHook` | fails |
| The allow-path diagnostic is deleted | `WorktreeMergedCleanup` | fails |
| The `unusable` refusal is deleted, so it falls back again | `WorktreePlanGuard` | fails |
| A read failure returns an empty item number | `WorktreePlanGuard` | fails |
| `absent` refuses as well, so nothing falls back | `WorktreePlanGuard` | fails |

The last row is worth naming. The first run of that mutation passed, because the fallback test
asserted only that the verdict refused, and refusing for the wrong reason still refuses. The test
now asserts the refusal comes from judging the recorded item, and a second case gives the recorded
item a `Plan: none` bullet so the fallback has to allow. Both sides of the split are pinned.

Two boxes are worth a word on how they were settled.

- "A long or multi-line reason still produces exactly one log line." Both writers now pass the
  reason through `Format-WorktreeLogReason`, and `tests/WorktreePlanGuard.Tests.ps1` asserts that
  neither one bypasses it. The formatter's own flattening and truncation stay pinned by
  `tests/WorktreeRemovalLog.Tests.ps1`.
- "`ConvertTo-BacklogSlug` stays the only slug rule." No slug rule was added.
  `Get-WorktreeSlugFromName` removes a `wt-` prefix from a name; it never builds a slug.

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
  plan reuses the idea rather than writing a second slug rule, and it leaves both of those
  behaviors alone: the folder rule is a backlog 073 regression fix, and re-deriving a recorded
  number would reopen that same defect.
- A third, smaller defect rides along. `Get-WorktreeBacklogItemNumber` accepts three digits only, so
  it returns nothing for a suffixed item such as `022b`. An empty recorded number makes the plan
  guard allow removal with no check, which turns the guard off for that worktree without saying so.
  It is one character class, it does not touch the folder rule, and the plan already teaches the
  guard the same shape — so it is fixed here rather than filed separately.
- Spec: none - the root cause is proven above, so this goes straight to Plan.
- Plan: `docs/superpowers/plans/2026-08-28-plan-guard-identity-plan-122.md`
