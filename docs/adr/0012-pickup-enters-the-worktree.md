# Pickup enters the worktree

Pickup creates the worktree with `scripts/new-worktree.ps1`, then switches the session into it
with the agent's native `EnterWorktree` tool, passing the path the script printed.

Before this, the session created the worktree and stayed in the main checkout. It reached the
worktree with a leading `cd` on every command. Nothing durable recorded the switch, so a resumed
session started again on `main` and did not know where the work lived.

Entering is what makes the location durable. The harness writes a `worktree-state` record into the
session transcript and moves the transcript into the project folder for the worktree path. A
resumed session comes back inside the worktree without being told to.

Entering also switches this repository's own worktree write guard on. That guard decides whether a
session is inside a worktree by reading the working directory in the hook payload. While the
session sat in the main checkout the guard classified it as a main-checkout session, so its write
isolation never fired at all.

## Considered options

Creating the worktree through `EnterWorktree` with `name` was rejected. That route works — the
tool fires the `WorktreeCreate` hook, which runs the same script — but it cannot pass `-Title` or
`-BaseRef`. `-Title` is what makes the worktree name agree with the backlog item's file name,
because `new-worktree.ps1` and `new-backlog-item.ps1` slug the same title the same way.
`-BaseRef` is what stacks work on an unmerged branch. Passing `path` to a worktree the script
already made keeps both, and it records `enteredExisting`, so leaving the worktree never offers to
delete it.

Restoring the worktree on resume, as a separate piece of work, was rejected because it turned out
to need none. It was measured: a resumed session already returns to a worktree entered with
`EnterWorktree`. It was a prerequisite, not an alternative.

Marking the session at pickup and refusing main-checkout writes until it enters was rejected. It
does not answer the problem. The session's working directory would still be the main checkout, so
a resumed session would still come back to `main`. It stops a wrong write; it does not move the
session. It also needs state the guard does not have — the guard keeps nothing between calls, so
this would add a marker file keyed by session id, a reader on every later call, and a rule for
when the marker expires.

## Consequences

**A plan or a spec cannot be committed from inside the worktree.** `docs/superpowers` is a
separate private repository, linked into each worktree from the main checkout. Once the session is
isolated, the harness refuses every command that sends git there — `git -C docs/superpowers ...`
and `cd docs/superpowers && git ...` alike. The refusal comes from the harness, not from this
repository, so `AHKFLOW_ALLOW_MAIN=1` does not lift it.

The route around it is to step outside for the commit only: leave the worktree and keep it, commit
in the plans repository, then enter the same path again. That is about three extra calls, a few
times per item. The old route paid a `cd` on every single command and still lost the location.

**Native `Edit` and `Write` do not work under `docs/superpowers`.** The harness resolves the
symlink to the main checkout and refuses, telling the agent to edit a worktree copy that cannot
exist. Writing the file from the shell works, and so does writing it elsewhere and copying it in.
This is the defect `backlog/blocked/058-native-edit-refusal-names-missing-worktree-copy.md`
records, still present.

**Shell commands must be simple and their paths literal.** Two layers refuse otherwise. The
harness refuses a command it cannot verify stays inside the worktree, which includes loops and
command substitution. This repository's guard refuses a write whose target path it cannot expand,
which includes a shell variable.

**A stacked pickup still calls the script directly.** Nothing changes there. The script takes
`-BaseRef`; the tool has no equivalent, and the tool is only ever used to enter a worktree that
already exists.
