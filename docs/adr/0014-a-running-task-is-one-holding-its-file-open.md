# A running task is one holding its output file open

The watcher decides that a background command is still running by asking the operating system
whether anything holds its Task output file open for writing. It opens the file for reading while
denying others write access, and treats one outcome as running: a sharing violation, HResult
`0x80070020`.

Before this, a task was running when its file did not end with `[exited with code N]` or
`[killed]`. That rule needs no state of its own, which is why item 123 chose it. It is also wrong
whenever a session dies without writing a marker, and the file then reads as running for ever.

Measured on 2026-09-08, on one developer machine: 489 task output files matched this repository,
41 counted as running under the marker rule, and 4 were actually being written. The oldest file
counted as running had not changed for 15 days.

The marker rule is kept for what it is good at. It still reports the exit code and the killed
state, and it still ends the follow loop when a run finishes. It no longer decides which tasks are
candidates.

## Why the file handle

It is exact. It needs no threshold anyone has to tune, and no clock. A run that goes quiet for an
hour is still running, and a file abandoned a second ago is already not.

It costs almost nothing. Probing all 489 files took 62 ms, against 1649 ms for the discovery pass
that already reads the end of every file.

The handle is held for the whole run, not only during a write. Measured against a task writing
once every three seconds: held on 24 of 24 probes across 14 seconds.

## Why the HResult and not the exception type

`FileNotFoundException` and `DirectoryNotFoundException` both derive from `IOException`, and a
task output file can be deleted between the folder listing and the probe. Catching `IOException`
would report a file that no longer exists as running. Only `0x80070020` means a writer holds it.

| Situation | Exception | HResult | Verdict |
|---|---|---|---|
| A writer holds the file | `System.IO.IOException` | `0x80070020` | running |
| Nobody holds it | none, the open succeeds | — | not running |
| The file was deleted | `System.IO.FileNotFoundException` | `0x80070002` | not running |
| The folder was deleted | `System.IO.DirectoryNotFoundException` | `0x80070003` | not running |
| The path cannot be opened | `System.UnauthorizedAccessException` | `0x80070005` | not running |

## Considered options

**An age cutoff** was rejected. It replaces one wrong answer with another: a long quiet run looks
dead, and the threshold has to be guessed and then defended.

**A live-process check** was rejected. Nothing on disk maps a session id to a process, so it would
mean reading agent-harness internals the watcher has no contract with.

**A live-session check, from the session transcript's last write time**, was rejected for the same
reason and because it is still an age cutoff, just on a different file.

## What this supersedes

Item 123 shipped "it tails the newest still-running task output file for this repository,
including files that belong to any of the repository's worktrees".

**This decision supersedes the newest-across-everything half of that rule.** Selection is no
longer the newest running file wherever it sits. Three preferences apply in order — the caller's
session, then the script's own checkout, then the newest by last write — and each is skipped when
it matches no running task. Newest is now the last resort, not the rule.

The other half stands. The search still reaches every checkout, so a worktree's task files are
still found (`scripts/watch-task.ps1:109`, "function Get-RepositoryCheckoutPath").

`AGENTS.md` already tells an agent to hand over the watcher path in the checkout the run belongs
to. That instruction only means anything if the checkout narrows the choice, and until now it did
not.

## Consequences

- **A third terminal state exists.** A file that ends with no terminal marker and that nobody
  holds open is not running and has no exit code. Under the old rule that combination could not
  occur, so a missing exit code meant killed. It no longer does: the watcher reports "stopped
  without a terminal marker", and only a `[killed]` marker means killed. Five display sites in
  `scripts/watch-task.ps1` carry the old assumption and all five change.
- **Liveness ends a follow.** A writer that closes without writing a marker leaves the marker rule
  saying "running" for ever. The follow loop now stops once the writer has released the file and
  the reader has caught up to the end.
- A task whose runner keeps the file open but never writes is correctly reported as running. That
  is a hung run, and telling a hung run from a finished one is the point of the watcher.
- A file held open for writing by anything else would read as running. In practice only the
  harness writes these files.
- The watcher now opens every candidate file once more per pass. The cost is measured above and is
  small next to the reads it already does.
