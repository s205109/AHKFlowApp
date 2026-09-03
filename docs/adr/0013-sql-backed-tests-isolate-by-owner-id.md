# SQL-backed tests isolate by owner id, not by collection

A test that touches the shared database keeps itself apart from every other test by using its own
random owner id and scoping every assertion to it. The xUnit collection is not the isolation
mechanism. It is only how a fixture instance gets shared.

That distinction is easy to lose, and losing it is expensive in both directions. Reading a
collection as an isolation boundary makes a suite serial for no reason, which is what
`AHKFlowApp.API.Tests` and `AHKFlowApp.Infrastructure.Tests` both did: every class carried one
collection attribute so it could receive one `ICollectionFixture`, and the side effect was that
no two of those tests ever ran at once. Measurement put `API.Tests` at 1.05x parallelism on a
sixteen-core machine, and `Infrastructure.Tests` at 1.0x.

Reading it the other way round is worse. Dropping the attribute to gain parallelism, without
first proving that every class isolates by owner id, would let two tests write to the same rows
and produce a failure that depends on scheduling.

So the rule is: **isolation is a property a test class proves about itself, and a collection is a
tool for sharing a fixture or for forcing exclusivity.** Reach for a collection when a test needs
one of those two things, never as a way to avoid thinking about isolation.

## What a shared host additionally requires

Sharing one `WebApplicationFactory` across parallel classes is not free, and owner-id isolation
does not cover any of it.

`WebApplicationFactory<TEntryPoint>` tracks the clients it hands out and the derived factories it
creates in two plain `List<T>` fields, and adds to both with no lock. Concurrent `CreateClient()`
is a data race on those lists, so a shared accessor must serialise client creation.

Serilog's `Log.Logger` is a process-wide static. `Program.cs` assigns it while a host starts and
closes it in its `finally`. Any test that builds a second host therefore reaches outside its own
collection, whatever its data isolation looks like. Those tests belong in one collection marked
`DisableParallelization = true`. xUnit runs every parallel collection to completion before it
starts a non-parallel one, so such tests run last and alone, and no second host exists while a
shared host is serving parallel tests.

A process-scoped host has no natural disposer, because nothing in xUnit owns it. Whatever holds
it must register it for disposal at process exit. A host that outlives the run by a moment is
fine; a host disposed while another class still holds a client is not.

## Considered options

**One collection per class, each with its own fixture** was rejected. `SqlContainerFixture` starts
its own container whenever the shared connection string is missing from the environment, which is
what a plain `dotnet test` does, so eight classes would mean eight SQL Server containers.

**Hand-picked collection groups** were rejected as arbitrary. The grouping would carry no meaning,
would drift as classes are added, and would still start one host per group.

**Leaving both suites serial** was rejected because the cost is measured. In `API.Tests` the eight
classes that build their own host hold 5.84 s across 24 tests, while the other 215 tests hold
15.13 s; only the first number is a floor.

## Consequences

A new SQL-backed test class runs in parallel by default. A class that builds its own host joins
the exclusive collection. A class that cannot isolate by owner id says so and gets a collection
of its own. None of that is discoverable from the code alone, so it belongs in the testing guide
as well as here.

Parallelism is bounded by the serial floor and by the machine, not by the core count of whoever
measured it. `API.Tests` and `Infrastructure.Tests` therefore carry an explicit
`maxParallelThreads` in `xunit.runner.json` rather than inheriting the processor count, because
they share one SQL Server and, in the API case, one host. The four projects that share nothing
keep the default.
