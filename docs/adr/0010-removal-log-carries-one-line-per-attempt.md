# The removal log carries one line per attempt

`.claude/worktrees/worktree-removal.log` mixes two audiences. A human opens it to learn what
happened to a worktree. A script opens it to count cleanup outcomes for friction metric 3.
Today it serves neither well: one removal writes about twenty lines, and only the last one is
the outcome. Measured on 2026-08-21, removing `wt-move-merged-backlog-093-record-into-done`
wrote exactly 20 lines, including a row of equals signs, two process IDs, a temporary
param-file path, `DatabaseName=`, and `ComposeProject=`.

So the log splits in two. `worktree-removal.log` carries exactly one line per Removal
attempt, and its message is one of `Removed.`, `Kept: <reason>.`, or `Failed: <reason>.`
Everything else moves to `worktree-removal-diagnostics.log` beside it, in the same stamped
line shape.

## Considered options

**Keeping one file and adding a level prefix was rejected.** It makes the outcome findable
with a filter, but the human still opens a file where nineteen lines out of twenty are not
for them. The criterion this serves asks for a readable log, not a filterable one.

**Dropping the detail entirely was rejected.** `Write-DiagnosticLog`
(`scripts/remove-worktree-local-dev.ps1:218`, "function Write-DiagnosticLog {") already sends
it to stderr, so the argument was that a file adds nothing. It does not hold. The watcher is
a detached process that outlives the session that spawned it, so its stderr reaches nobody.
The detail would be lost exactly when a failure needs explaining.

**Renaming or archiving the existing 398 KB log was rejected.** `measure-cleanup-log-events.ps1`
reads that file by name, and the frozen ledger under
`docs/development/friction-samples/ledgers/` was computed from it. Moving it would break the
audit trail for a published figure to gain nothing.

## Consequences

The log file holds two shapes: old-style lines before this change, new-style lines after it.
That is accepted rather than fixed.

**The nine existing outcome patterns stay, and three new ones are added beside them.**
(`scripts/measure-process-friction.ps1:104`, "$script:CleanupOutcomePatterns = @(") is the
list. Deleting the old nine would make the historical part of the same file unreadable to the
script that measured it. The three new patterns are `^Removed\.`, `^Kept: `, and `^Failed: `.

A count that spans the change mixes two shapes and is not a like-for-like figure.
`docs/development/cleanup-event-identity.md` records the date so a reader can see it.

The diagnostics file is capped at 5 MB with one old generation kept, because replacing one
file that grows forever with another one is not an improvement. The cap size is a guess. The
human log needs no cap: one line per attempt keeps it small.

Every refusal that exists today has to be given a plain-word `Kept:` reason. A refusal with no
mapped wording would write nothing at all, which is worse than the verbose log this replaces.

**The outcome line stops being best-effort.** One removal is not one action: the rename can
succeed and the delete fail, the delete can succeed and the branch delete fail. So the design
carries a terminal-state table deciding which partial results read `Removed.` and which read
`Failed:`. The dividing line is the worktree folder itself, because a leftover branch,
database, or Docker project is reclaimed later by a prune script, while a half-deleted folder
is reclaimed by nothing.

**Writing one line reliably is harder than writing twenty unreliably.** A sweep removes
several worktrees in a run and each spawns its own detached watcher, so several processes
write both files at once. Today an append that loses a race throws, and the throw is swallowed
(`scripts/remove-worktree-local-dev.ps1:214`, "    } catch { }"). That was survivable when the
outcome appeared on twenty lines and one could go missing. With one line per attempt, a
swallowed failure erases the whole record of what happened to a worktree. So appends retry,
rotation takes a cross-process mutex, and a writer that still cannot write falls back to
stderr and then to `%TEMP%` rather than giving up.

Any text that reaches the line from outside — a human's lock reason, a .NET exception message
— is stripped of carriage returns and line feeds and truncated. One line per attempt is a
promise the writer keeps, not a hope about its inputs.
