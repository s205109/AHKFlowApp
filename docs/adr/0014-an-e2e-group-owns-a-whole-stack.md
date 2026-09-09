# An E2E group owns a whole stack, and the groups are balance buckets

The E2E suite runs its test classes in four xUnit collections. Each collection owns a database, an
API host, a SPA host and a browser.

Two things are still shared, and both are deliberate. The four collections use one SQL Server
container, and each names its own database on it. They also share Serilog's process-wide logger,
because `Program.cs` owns that static and the test code cannot take it away. The logger is the
reason host construction is serialised, and the Consequences section below gives the full rule.
Nothing else mutable crosses a collection boundary.

The four groups hold no meaning. They are balance buckets. A class belongs to the group that keeps
the four groups closest to equal, and nothing else decides it.

## Why the group is the unit that owns a stack

xUnit 2.9.3 never runs two tests from one collection at the same time. It parallelises across
collections only. So in this suite the number of collections is the number of tests that can run
at once, and every collection needs its own fixture instance.

An E2E test drives a browser against a running app. Giving each test class its own stack would
mean eighteen browsers and eighteen API hosts, which does not fit a four-core CI runner. Giving
every class one shared stack would mean eighteen classes writing to one database, so every test
would have to prove its own isolation, and one `WebApplicationFactory` would be handing out
clients to parallel threads.

Four groups is the middle. It buys four-way parallelism for the price of four stacks.

## Why this is not the grouping ADR 0013 rejected

[ADR 0013](0013-sql-backed-tests-isolate-by-database.md) rejected hand-picked collection groups as
arbitrary, and that rejection still stands where it was made. It was made about
`AHKFlowApp.Infrastructure.Tests`, where every test class already named its own database. A group
there would have added a fixture for nothing, because the classes were already kept apart without
it.

Here the group is the only thing that can own a browser. There is no per-class stack to fall back
on, so the group is not an extra layer over an existing boundary. It is the boundary.

The rule at the top of ADR 0013 is unchanged by this decision. Isolation is still a property each
group proves about itself, and it proves it the same way `AHKFlowApp.Infrastructure.Tests` does, by
naming its own database. What the grouping decides is which classes share a fixture, which is the
second use ADR 0013 lists for a collection.

## Considered options

**One collection per test class, each with its own stack.** Rejected on cost. Eighteen browsers
and eighteen API hosts do not fit the CI runner, which has four cores and 16 GB and is already
running the other test assemblies.

**One collection per test class, all sharing one stack.** Rejected on risk. Every entity in this
app carries an owner id, so a per-test owner would give data isolation. But ADR 0013 records that
owner id is not the isolation boundary in this repository, and that an earlier draft of that
document claimed otherwise and was wrong. Sharing one `WebApplicationFactory` across parallel
classes also needs a lock around client creation, which ADR 0013 describes. Four separate stacks
need neither, because no factory is ever reached from two threads.

**A test that fails when the groups drift out of balance.** Rejected. It would have to read
timings from an earlier run, so its verdict would depend on how busy the machine was that day and
on a file a previous run left behind. It would fail for reasons unrelated to the change under test.

## Consequences

**Balance is a written rule, not a check.** Each collection file lists the classes it holds and
the seconds each one measured. The testing guide says to put a new class in the smallest group.
Nothing enforces it. A class placed in the largest group makes the whole suite slower and no test
reports it.

One mistake cannot happen silently. A class that carries no collection attribute fails loudly,
because xUnit cannot construct a test class whose constructor takes a fixture it was never handed.

**A test class names its own group's fixture type in its constructor.** xUnit matches a
constructor parameter to a fixture by exact type, through a dictionary keyed on the parameter's
type. A parameter typed as the shared base class does not resolve. So moving a class from one
group to another means changing its collection attribute and its constructor parameter together.
Test bodies do not change, because every group's fixture exposes the same members.

**The slowest group sets the wall clock.** When one class grows past the size of a whole group,
the answer is to split that class, not to add a fifth group. Measured on 2026-09-09,
`ShortcutWarningFlowTests` alone held 60.07 seconds of a 260.22 second suite, which is why it is
filed as its own item.

**The four stacks share one SQL Server container.** They reach it through `SharedSqlContainer`,
which starts at most one container for the whole test process and keeps it until the process ends.
Nothing disposes it. Testcontainers removes it through its resource reaper.

**The four API hosts must be built one at a time.** This is a rule, not a preference, and Serilog
is the reason.

`Program.cs` creates a bootstrap logger and assigns it to the process-wide `Log.Logger`. Twenty-one
lines later it calls `AddSerilog`. Serilog reads the static logger at that second point and keeps
the instance it found. The source comments the choice: "This check is eager; replacing the
bootstrap logger after calling this method is not supported." The logger is then frozen much
later, the first time anything resolves `ILogger`.

So two hosts starting together can both keep the same bootstrap logger. That happens when the
second host assigns `Log.Logger` in the window between the first host's assignment and its own
read. Both hosts then freeze the same instance, and the second freeze throws
`InvalidOperationException` with the message "The logger is already frozen." That fails host
startup. It does not merely lose log lines.

The fix is a process-wide gate. One stack at a time runs its host construction and then resolves
`ILogger` once, before the gate is released. Holding the gate across both steps is what matters,
because the read and the freeze sit at opposite ends of host start-up.

Disposal stays concurrent, and one consequence remains. `Program.cs` closes the logger in a
`finally`, so the first stack to be disposed closes the logger the others still hold. Serilog turns
a closed logger into a no-op rather than throwing, so this costs log lines at the end of a run and
nothing else.
