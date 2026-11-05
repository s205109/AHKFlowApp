# The test-audit workflow

The `test-audit` workflow audits tests case by case. It proposes cases to remove, merge, rework
or speed up, and it tries to disprove every removal before you act on it. Backlog 188 built it
for PowerShell test Suites and ran it on ten Suites. Backlog 194 added a .NET mode. The script is
`.claude/workflows/test-audit.js`.

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
{
  "worktree": "C:\\Dev\\segocom-github\\AHKFlowApp\\.claude\\worktrees\\wt-my-topic",
  "suites": ["MeasureTestModes.Tests.ps1", "BacklogStaleOpen.Tests.ps1"]
}
```

`worktree` is required in both modes. It is the absolute path of the worktree to audit. Every
prompt and every command of the run uses it. `report` is optional. It is the path of the
research report the auditors read, and each mode has its own default.

Approve the launch when Claude Code asks. The workflow refuses an empty list and a list of more
than five Suites. Five is the limit because each Suite gets its own auditor, and the refuters
then run one after another. More Suites make a run of several hours.

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
- In PowerShell mode, a refuter tests every REMOVE, and every MERGE that saves 1 second or more
  (`MIN_MERGE_SAVED`). The run log counts the MERGE claims it skips. The .NET mode refutes every
  MERGE the auditor returns.

## Refuter mode

A refuter tries to disprove each REMOVE and MERGE claim. It puts the bug back into the script
under test, runs the Suites that name that script, and checks whether another case still fails.
A claim survives only when another case fails, or when the behaviour is really gone. The refuter
then restores the script with `git checkout`, and it reports whether the worktree is clean.

Refuters run one at a time, at medium effort, in the same worktree. They do not get their own
copy. A copy made with `isolation: 'worktree'` is a full managed worktree: it is slow to make,
takes a port slot and a branch, runs a cleanup sweep, stays behind afterwards, and refuses git.
Two refuters in one worktree at the same time would see each other's edits.

## The .NET mode

The .NET mode audits .NET test classes in Candidate groups. A Candidate group is a set of test
classes that one auditor reads together. Pass `kind: "dotnet"` and one to five groups:

```json
{
  "worktree": "C:\\Dev\\segocom-github\\AHKFlowApp\\.claude\\worktrees\\wt-my-topic",
  "kind": "dotnet",
  "timings": "C:\\Dev\\segocom-github\\AHKFlowApp\\.claude\\worktrees\\wt-my-topic\\.superpowers\\ranking.md",
  "groups": [
    {
      "name": "boot",
      "project": "tests\\AHKFlowApp.E2E.Tests\\AHKFlowApp.E2E.Tests.csproj",
      "classes": ["BootFailureFlowTests", "FirstPageLoadDiagnosticsTests"],
      "candidates": ["SPEED UP: BootFailureFlowTests.FirstBootFailure_ReloadsThePage — waits the 10 s boot grace period"]
    }
  ]
}
```

- `project` is the path of the `.csproj` file, relative to the worktree.
- `classes` lists the test classes the auditor reads.
- `candidates` lists leads from an earlier triage, as text. The auditor checks each one again.
- `timings` is optional. It is a file with each test's median duration. The auditor reads its
  estimates from it. Without it, the auditor estimates from the research report.

The auditor runs no test. It returns only changes that save 0.5 seconds or more. A change that
drops an assertion, or a step that an assertion depends on, is never a SPEED UP. It is a REMOVE
or a MERGE.

The .NET mode refutes every REMOVE and every MERGE, so its merge threshold is 0.5 seconds. A
claim stands only when two tests fail on the same defect:

1. The refuter puts the defect back with the smallest change, or switches the feature off.
2. It runs the audited test. That test must fail. If it passes, the change is not the defect the
   test guards against, so the refuter tries another change.
3. It runs the tests that the auditor names as still catching the defect. The claim is upheld
   when one of them fails on the same change, or when the behaviour is really gone.
4. It restores the file with `git checkout --`, and builds Release again.
5. It reports whether the worktree is clean.

A failure counts only when its message names the changed behaviour. A refuter runs a timed-out
E2E test once more, and says so.

No API or UI of the audited worktree may run during a .NET run. A running app locks the Release
build. Each E2E claim costs about 3 to 5 minutes, because each test run builds, publishes the
app, and starts its own SQL Server container.

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
