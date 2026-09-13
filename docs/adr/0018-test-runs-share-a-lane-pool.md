# Test runs share a Lane pool

Local test runs share the machine through a Lane pool, not through a machine-wide lock. The pool is
a set of Lanes in a per-user folder, so it covers every test run of one user account on one machine.
A Suite takes one Lane while it runs, and a .NET run holds half the pool, rounded up, for its whole
length. The existing checkout lock, `.test-run.lock`, stays one per checkout and still refuses a
second run there.

Backlog 146 asked for "one machine-wide lock". The trigger was a laptop that stopped responding
when two terminals ran the PowerShell suites at once. The design notes are in the backlog 146 spec.

## Considered options

**Refuse the second run** was rejected. The pre-push hook runs the Fast slice, so a push from one
worktree would fail while any test ran in another.

**Make the second run wait** was rejected. A push would wait behind a Coverage or Integration run
in another worktree for several minutes.

**Divide the worker count at start** was rejected. A running pool of workers cannot shrink. The
first run keeps 6 workers, the second takes 3, and 9 Suites then run at once. That is not one limit.

**A named semaphore** was not chosen. Microsoft's documentation for Windows semaphore objects says:
"Closing the handle does not affect the semaphore count; therefore, be sure to call ReleaseSemaphore
before closing the handle or before the process terminates"
([Semaphore Objects](https://learn.microsoft.com/windows/win32/sync/semaphore-objects)). A killed
run never calls it, so the pool would stay short for as long as another run kept the semaphore
alive. An open file handle is closed by the operating system however the process ends. The checkout
lock already relies on that.

## Why the checkout lock stays per checkout

The two protections do different jobs. The checkout lock protects build output: two .NET runs in
one checkout instrument the same assemblies and lose coverage data, as backlog 082 measured. That
danger does not cross checkouts. The Lane pool protects the machine, and that danger does. Moving
the lock file to a machine-wide place would refuse runs that corrupt nothing.

## Why the pool keeps one recorded capacity

Each process proposes a capacity with the backlog 145 rule, and two processes can propose different
numbers, because `Environment.ProcessorCount` respects each process's affinity and CPU limit. If each
used its own number, a whole-pool reservation would not be the whole pool. So the pool records one
capacity. A run may replace it only while it holds the entry lock and no Lane is held. While any Lane
is held, the recorded capacity stands for every run.

## Why a .NET run holds half the pool, rounded up

The .NET modes have no worker count, so they cannot take a Lane per unit of work. Half the pool,
rounded up, leaves room for Suites beside one .NET run. The whole pool would make a push wait behind
every other run. No Lanes at all would leave a .NET run and a Suite run with no shared limit.

Rounding up has a cost that was accepted. Two .NET runs fit together only when the capacity is even.
On a capacity of 1, 3 or 5, the second .NET run waits for the first. Rounding down with a floor of
one would let two fit on 3 and 5, but it would give a single .NET run a smaller share of the machine
than the grill settled on. The design review kept rounding up as the smallest change and asked for
the serialization to be written down, which this paragraph does. It never lets two .NET runs take
more than the pool.

A run takes its Lanes one at a time while it holds a single entry lock. Without that lock, runs that
each hold part of what they need can wait on each other for ever.

## Why a wait has no time limit

A run waits for a Lane for as long as that takes. A limit would need a number somebody must choose
and defend. A run that hangs is named in the waiting run's one line, so a developer knows what to
stop. This follows ADR 0014, which also chose a held file over a clock.

## Consequences

- A measurement session in timing mode holds the whole pool, so no other run that takes Lanes can
  start work during it. Every such run on the machine waits until the session ends. The pool cannot
  stop work that takes no Lanes: an opted-out run, a command typed by hand, or a child process that
  outlived a killed run. A measurement still needs a quiet machine.
- A Suite's recorded duration leaves out its wait for a Lane. It still includes the slowdown from
  other work running at the same time.
- A run inside a run takes no Lanes. Each script reads `AHKFLOW_TEST_LANES_HOLDER` once, at start.
  An owner sets it for what it starts and restores it when it ends. The Suite runner passes the
  decision to its Workers, because Workers share one process and so share its environment.
- `AHKFLOW_TEST_LANES=off` skips the pool for a deliberate overlap. Nothing skips the checkout lock.
- An explicit `-MaxParallel` sets one run's Worker count. It is never a capacity proposal.
- A killed run's Lanes come back at once, but its child processes can keep running outside the pool.
