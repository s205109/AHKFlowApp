# Test runs share a Lane pool

Local test runs share the machine through a Lane pool, not through a machine-wide lock. The pool is
a fixed set of Lanes in a per-user folder. A Suite takes one Lane while it runs, and a .NET run
holds half the pool for its whole length. The existing checkout lock, `.test-run.lock`, stays one
per checkout and still refuses a second run there.

Backlog 146 asked for "one machine-wide lock". The trigger was a laptop that stopped responding
when two terminals ran the PowerShell suites at once. The design notes are in the backlog 146 spec.

## Considered options

**Refuse the second run** was rejected. The pre-push hook runs the Fast slice, so a push from one
worktree would fail while any test ran in another.

**Make the second run wait** was rejected. A push would wait behind a Coverage or Integration run
in another worktree for several minutes.

**Divide the worker count at start** was rejected. A running pool of workers cannot shrink. The
first run keeps 6 workers, the second takes 3, and 9 Suites then run at once. That is not one limit.

**A named semaphore** was not chosen. The .NET `Semaphore` class does not enforce thread identity,
so nothing records which process took a count. A killed run therefore cannot give its count back,
and the pool could stay short for as long as another run kept the semaphore alive. An open file
handle is closed by the operating system however the process ends. The checkout lock already relies
on that.

## Why the checkout lock stays per checkout

The two protections do different jobs. The checkout lock protects build output: two .NET runs in
one checkout instrument the same assemblies and lose coverage data, as backlog 082 measured. That
danger does not cross checkouts. The Lane pool protects the machine, and that danger does. Moving
the lock file to a machine-wide place would refuse runs that corrupt nothing.

## Why a .NET run holds half the pool

The .NET modes have no worker count, so they cannot take a Lane per unit of work. Half the pool,
rounded up, lets two .NET runs from two checkouts run together. A Suite runner still gets Lanes
while one .NET run is going. The whole pool would make a push wait behind every other run. No
Lanes at all would leave a .NET run and a Suite run with no shared limit.

A run takes its Lanes one at a time while it holds a single entry lock. Without that lock, runs that
each hold part of what they need can wait on each other for ever.

## Why a wait has no time limit

A run waits for a Lane for as long as that takes. A limit would need a number somebody must choose
and defend. A run that hangs is named in the waiting run's one line, so a developer knows what to
stop. This follows ADR 0014, which also chose a held file over a clock.

## Consequences

- A measurement session in timing mode holds the whole pool, so its numbers never include another
  run's load. Every other test run on the machine waits until the session ends.
- A run inside a run takes no Lanes. The outer run marks its children with
  `AHKFLOW_TEST_LANES_HOLDER`, which prevents a pool where every Lane is held by a Suite waiting for
  its own inner run.
- `AHKFLOW_TEST_LANES=off` skips the pool for a deliberate overlap. Nothing skips the checkout lock.
- An explicit `-MaxParallel` sets one run's Worker count and never resizes the pool. Two runs with
  different pool sizes would count different Lanes, and the limit would break.
