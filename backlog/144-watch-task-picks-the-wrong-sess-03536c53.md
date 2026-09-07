# 144 - Watch task picks the wrong session and crashes on a null checkpoint

## Metadata

- **Epic**: Developer workflow
- **Type**: Bug
- **Interfaces**: CLI
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

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

**The root cause is not yet known.** `$chunks` is a `List[byte[]]` that only ever receives a
freshly allocated array, so `$chunks[0]` should not be null on that path. Either the null arrives
from somewhere else, or an assumption above is wrong. Nobody has reproduced it yet, so this item
must not enter Design until somebody can point at the line that produces the null. That is the
bug gate in [`docs/development/workflow.md`](../docs/development/workflow.md), not a formality.

**The wrong session.** The folder match is case-insensitive
(`scripts/watch-task.ps1:212`, "if ($Name.Equals($mangled, [System.StringComparison]::OrdinalIgnoreCase)) {"),
so `c--Dev-...` and `C--Dev-...` both belong to this repository and the differing capital is not
the fault. The default pick is the newest running file by last write time
(`scripts/watch-task.ps1:21`, "3. It picks the newest running file by last write time and tails it, following by byte").
With several live sessions that is a guess, and the watcher has no way to prefer the caller's own
session, because nothing tells it which session id it belongs to.

The candidate list also looks inflated. A file counts as running when it does not end with a
terminal marker
(`scripts/watch-task.ps1:19`, "2. Among <match>\<session id>\tasks\<task id>.output, a file is running when its content"),
so a task from a session that died without writing one counts as running for ever. Thirty-eight
at once suggests that is happening, but the count has not been checked against how many sessions
were actually alive.

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
- The `-List` and `-Index` paths, which already work and are the current way around this.

## Notes / dependencies

- Raised on 2026-09-07 while working backlog 141, from a real failed run. Kept out of 141 on
  purpose, so that item stayed one concern.
- The last two acceptance criteria may turn out to be one change or three. That is why Difficulty
  is `to-be-determined` rather than a guess.
- Spec: none yet — Design decides, once the null has a proven cause.
- Plan: none — filed at intake. A plan is written when somebody picks the item up.
