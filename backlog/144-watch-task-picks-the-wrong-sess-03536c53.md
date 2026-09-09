# 144 - Watch task picks the wrong session and crashes on a null checkpoint

## Metadata

- **Epic**: Developer workflow
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: complex
- **Stage**: 4-execute

## Summary

`pwsh scripts/watch-task.ps1` tailed a task belonging to a different session, then stopped with
a parameter-binding error instead of printing output. Both faults hit the same run, and either
one alone makes the watcher unusable while a long job is going.

## User story

As a developer watching a long background run, I want the watcher to tail my own session's task
and keep tailing it, so that I can tell a working run from a hung one.

## Background

Observed on 2026-09-07 while a five-step Gate was running. The full output was:

```
37 other tasks are also running. Use -List to see them and -Index to pick one.

Tailing C:\Users\btase\AppData\Local\Temp\claude\c--Dev-segocom-github-AHKFlowApp\4f3aef63-a229-40b0-9a39-ce7d5fef331c\tasks\biuv84h69.output

Task output could no longer be read: C:\Users\btase\AppData\Local\Temp\claude\c--Dev-segocom-github-AHKFlowApp\4f3aef63-a229-40b0-9a39-ce7d5fef331c\tasks\biuv84h69.output. Cannot bind argument to parameter 'Consumed' because it is null
```

Two separate faults.

**The crash.** The message after the path is `$reader.ReadError`, surfaced by
(`scripts/watch-task.ps1:900`, "Task output could no longer be read: $Path."). That text is the
.NET binding failure for a mandatory parameter given `$null`. The parameter is
(`scripts/watch-task.ps1:507`, "[Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Consumed,"),
where `AllowEmptyCollection` permits an empty array but not `$null`. The call that supplies it is
(`scripts/watch-task.ps1:786`, "Set-TailReaderCheckpoint -Reader $Reader -Consumed $consumed"),
fed by
(`scripts/watch-task.ps1:785`, "$consumed = if ($chunks.Count -gt 0) { $chunks[0] } else { [byte[]]::new(0) }").

**The root cause, proven on 2026-09-08.** The bug gate in
[`docs/development/workflow.md`](../docs/development/workflow.md) is satisfied.

PowerShell unrolls an array when it captures a statement's value, and a zero-length array unrolls
to nothing at all. So the `else` branch below stores `$null`, not an empty array:

```powershell
$a = if ($false) { 1 } else { [byte[]]::new(0) }
$null -eq $a   # True
```

That is the branch at
(`scripts/watch-task.ps1:785`, "else { [byte[]]::new(0) }"). The earlier reading in this item was
right that `$chunks[0]` is never null. It is the `else` branch that is null, and it is already
null before `Set-TailReaderCheckpoint` ever sees it.

`$chunks` is empty when the backward scan never runs a round. The scan's first condition is
(`scripts/watch-task.ps1:735`, "while ($position -gt 0 -and"), and `$position` starts at the file
length. So a task output file of **zero bytes** takes the `else` branch, and the call at
(`scripts/watch-task.ps1:786`, "Set-TailReaderCheckpoint -Reader $Reader -Consumed $consumed")
then fails to bind.

Reproduced end to end with the real script against a fixture holding one zero-byte `.output`
file. The output matches the report word for word:

```
Tailing ...\tasks\task.output

Task output could no longer be read: ...\tasks\task.output. Cannot bind argument to parameter 'Consumed' because it is null.
```

A zero-byte file is also why the watcher chose that file. An empty file holds no terminal marker,
so it counts as running, and a file created moments ago has the newest last write time. The two
faults in this item share one trigger.

**The wrong session.** The folder match is case-insensitive
(`scripts/watch-task.ps1:212`, "if ($Name.Equals($mangled, [System.StringComparison]::OrdinalIgnoreCase)) {"),
so `c--Dev-...` and `C--Dev-...` both belong to this repository and the differing capital is not
the fault. The default pick is the newest running file by last write time
(`scripts/watch-task.ps1:21`, "3. It picks the newest running file by last write time and tails it, following by byte").
With several live sessions that is a guess, and the watcher has no way to prefer the caller's own
session. The default pick is
(`scripts/watch-task.ps1:1289`, "return (Watch-Record -Record $running[0]").

**A session id is available after all.** Claude Code sets `CLAUDE_CODE_SESSION_ID` in the
environment of a command it runs, and its value is the `<session id>` folder holding that
session's task files. Checked on 2026-09-08: the variable held
`3a54464d-70f2-4c8e-a05c-7185fbbb4412`, and that same name was the session folder under
`...\claude\C--Dev-segocom-github-AHKFlowApp\` holding this session's `.output` file. A human
running the watcher in their own terminal has no such variable. So it can be a preference with a
fallback, never a filter. Design decides.

The candidate list is inflated, and the numbers are now measured. A file counts as running when
it does not end with a terminal marker
(`scripts/watch-task.ps1:19`, "2. Among <match>\<session id>\tasks\<task id>.output, a file is running when its content"),
and nothing checks whether the session that wrote it still exists
(`scripts/watch-task.ps1:311`, "return [pscustomobject]@{ Running = $true;").

Measured on 2026-09-08, with the real watcher against the real temp tree:

- 482 output files matched this repository.
- 39 of them counted as running.
- The oldest of those 39 last changed 15 days ago, in a session long gone.
- Only 4 live checkouts exist on disk.

**The count line and the two ways out of it disagree.** The line counts every running record
(`scripts/watch-task.ps1:1283`, "$others = $running.Count - 1"), so it said 38 others. But `-List`
and `-Index` see only the newest 20 records
(`scripts/watch-task.ps1:1225`, "$recent = @($records | Select-Object -First 20)"), and only 4 of
those 20 were running. So
(`scripts/watch-task.ps1:1285`, "other $noun also running. Use -List to see them and -Index to pick one.")
names 38 tasks the reader cannot reach.

## Acceptance criteria

- [ ] Tailing a task file whose read hits the condition in the report prints output instead of
      throwing a binding error. `tests/WatchTask.Tests.ps1` covers the case.
- [ ] `Set-TailReaderCheckpoint` cannot receive `$null`: either its call sites are proven to pass
      an array, or the parameter states what a null means.
- [ ] With more than one running task, the watcher tails a task from the caller's own session when
      one exists, rather than the newest across every session.
- [ ] A task file left behind by a session that is gone does not count as running.
- [ ] The report line naming how many other tasks are running matches how many the watcher would
      actually choose between.

## Out of scope

- Any change to how Claude Code names or writes the task output files.
- Reworking what `-List` and `-Index` are for. They keep their shape and meaning.

**Corrected at Design on 2026-09-08.** This section first put the `-List` and `-Index` paths out of
scope entirely. Acceptance criterion 5 cannot hold while `-List` stops at a fixed 20 rows
(`scripts/watch-task.ps1:1225`, "$recent = @($records | Select-Object -First 20)"): with more than
20 running tasks, the count line names tasks that `-Index` cannot reach. So `-List` now shows every
running task, then enough newest stopped tasks to reach 20 rows. Nothing else about the two
switches changes.

## Notes / dependencies

- Raised on 2026-09-07 while working backlog 141, from a real failed run. Kept out of 141 on
  purpose, so that item stayed one concern.
- Difficulty was `to-be-determined` at filing. Set to `complex` at pickup on 2026-09-08. Criteria
  3 and 4 each need a decision with more than one reasonable answer: what identifies the caller's
  own session, and how to tell that a session is gone. Criterion 5's wording follows from both.
  The change also alters CLI output text, so it needs a spec.
- Spec: `docs/superpowers/specs/2026-09-08-watch-task-session-and-liveness-design-144.md`
- ADR: `docs/adr/0014-a-running-task-is-one-holding-its-file-open.md` — a running task is one
  holding its output file open. It narrows the preference order item 123 shipped.
- Plan: `docs/superpowers/plans/2026-09-08-watch-task-session-and-liveness-plan-144.md`
