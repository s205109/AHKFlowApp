# The test-audit workflow

The `test-audit` workflow audits PowerShell test Suites case by case. It proposes cases to
remove, merge, rework or speed up, and it tries to disprove every removal before you act on it.
Backlog 188 built it and ran it on ten Suites. The script is `.claude/workflows/test-audit.js`.

## When to run it

Run it when the Gate suggests a re-audit. The Gate does that for a Suite that runs over its time
budget. You can also run it on any Suite that has grown slow.

The workflow spends tokens. Batch 2 of backlog 188 used 0.84 million subagent tokens and 37
minutes for five Suites.

## The command

Type this in a Claude Code session, with the Suite file names:

```text
Run /test-audit on MeasureTestModes.Tests.ps1, BacklogStaleOpen.Tests.ps1
```

Claude starts the saved workflow with these `args`:

```json
{ "suites": ["MeasureTestModes.Tests.ps1", "BacklogStaleOpen.Tests.ps1"] }
```

Approve the launch when Claude Code asks. The workflow refuses an empty list and a list of more
than five Suites. Five is the limit because each Suite gets its own auditor, and the refuters
then run one after another. More Suites make a run of several hours.

The script names the worktree of backlog 188 in its constant `W`. Change `W` to your own
worktree before you run it from another one.

## The five verdicts

An auditor gives each case one verdict:

- **KEEP**: the case catches a defect that no other case catches, at a fair cost.
- **REWORK**: the case is worth keeping, but it should test the behaviour in another way.
- **MERGE**: another case already checks the same thing. The auditor names that case.
- **REMOVE**: no defect is lost, because another test still catches it, or the feature is gone.
- **SPEED UP**: keep the check, but make it cheaper. The auditor says how.

REMOVE, MERGE and SPEED UP need evidence with a `file:line`, and an estimate of the seconds saved.

The workflow uses lean settings to spend fewer tokens:

- An auditor returns only the cases it would change, and only when a change saves 0.5 seconds or
  more (`MIN_SAVED`).
- A refuter tests every REMOVE, and every MERGE that saves 1 second or more (`MIN_MERGE_SAVED`).
  The run log counts the MERGE claims it skips.

## Refuter mode

A refuter tries to disprove each REMOVE and MERGE claim. It puts the bug back into the script
under test, runs the Suites that name that script, and checks whether another case still fails.
A claim survives only when another case fails, or when the behaviour is really gone. The refuter
then restores the script with `git checkout`, and it reports whether the worktree is clean.

Refuters run one at a time, at medium effort, in the same worktree. They do not get their own
copy. A copy made with `isolation: 'worktree'` is a full managed worktree: it is slow to make,
takes a port slot and a branch, runs a cleanup sweep, stays behind afterwards, and refuses git.
Two refuters in one worktree at the same time would see each other's edits.

## Applying a batch

The workflow only proposes. It changes no test. You apply the changes afterwards, outside the run:

1. Read the table of verdicts and approve the changes by group.
2. Time each Suite alone before you change it: one warm-up run, then three counted runs.
3. Apply the approved changes, and commit each Suite on its own.
4. Run each changed Suite once, then time it again the same way as in step 2.
5. Record the before and after medians in `docs/development/cycle-time-record.md`.

The plan for backlog 188 asked for one change at a time, timed on its own. With 153 changes in
batch 1, that would have taken about 17 hours of runs. So a batch is applied by group, and each
Suite is timed before and after the whole group.

A removal needs one of two things. Either another test still fails on the bug the removed case
caught, or the behaviour it tested is gone. The commit body names that test or that behaviour.
A refuted claim is dropped.

Proposals you do not apply go into `docs/development/test-audit-deferred.md`, so a later backlog
item can pick them up.
