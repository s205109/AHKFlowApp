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

Only `Infrastructure.Tests` was then changed. `API.Tests` still reads that way today, for the
reasons in the Consequences section below.

Reading it the other way round is worse. Dropping the attribute to gain parallelism, without
first proving that every class isolates by owner id, would let two tests write to the same rows
and produce a failure that depends on scheduling.

So the rule is: **isolation is a property a test class proves about itself, and a collection is a
tool for sharing a fixture or for forcing exclusivity.** Reach for a collection when a test needs
one of those two things, never as a way to avoid thinking about isolation.

## What a shared host would additionally require

**Nothing in this section is built.** `AHKFlowApp.API.Tests` still runs every class through one
shared collection, one after another. Backlog 128 designed the shared host, measured the gain at
about twelve seconds, and the human declined it, because the Integration target was already met
without it. The design is filed as backlog 134. What follows is the part of that design which
owner-id isolation does not cover, kept here so the next reader need not work it out again.

Sharing one `WebApplicationFactory` across parallel classes is not free.

`WebApplicationFactory<TEntryPoint>` tracks the clients it hands out and the derived factories it
creates in two plain `List<T>` fields, and adds to both with no lock. Concurrent `CreateClient()`
is a data race on those lists, so a shared accessor must serialise client creation.

Serilog's `Log.Logger` is a process-wide static. `Program.cs` assigns it while a host starts and
closes it in its `finally`. Any test that builds a second host therefore reaches outside its own
collection, whatever its data isolation looks like. Those tests would belong in one collection
marked `DisableParallelization = true`. xUnit runs every parallel collection to completion before
it starts a non-parallel one, so such tests would run last and alone, and no second host would
exist while a shared host served parallel tests.

A process-scoped host has no natural disposer, because nothing in xUnit owns it. An earlier draft
of backlog 128 required disposal at process exit; backlog 128 then withdrew that requirement, and
backlog 134 keeps it out of scope. The host would live as long as the test process, the same way
`SharedSqlContainer` already holds its container. Disposing early, while another class still holds
a client, is the failure worth avoiding. Never disposing costs nothing, because the process is
ending anyway.

## Considered options

**One collection per class, each with its own fixture** was rejected. `SqlContainerFixture` starts
its own container whenever the shared connection string is missing from the environment, which is
what a plain `dotnet test` does, so eight classes would mean eight SQL Server containers.

**Hand-picked collection groups** were rejected as arbitrary. The grouping would carry no meaning,
would drift as classes are added, and would still start one host per group.

**Leaving both suites serial** was rejected for `Infrastructure.Tests`, because the cost is
measured. In `API.Tests` the eight classes that build their own host hold 5.84 s across 24 tests,
while the other 215 tests hold 15.13 s; only the first number is a floor. That 15.13 s is the
prize backlog 134 is still holding, and leaving `API.Tests` serial is exactly what the human
chose once the Integration target was met without it.

## Consequences

The two suites this decision names ended up in different places, so they are written out
separately. Reading either one as the state of both is the mistake this section exists to stop.

### `AHKFlowApp.Infrastructure.Tests`, where the rule is in force

A new SQL-backed test class runs in parallel by default. It reaches the shared server through
`IClassFixture<SharedSqlServerFixture>`, not through a collection. A class that cannot isolate by
owner id says so and gets a collection of its own. None of that is discoverable from the code
alone, so it belongs in the testing guide as well as here.

Parallelism is bounded by the machine, not by the core count of whoever measured it. This project
therefore carries an explicit `maxParallelThreads` of 4 in its own `xunit.runner.json`, rather
than inheriting the processor count, because its classes share one SQL Server. It is the only
test project in the repository with such a file; every other one keeps the default.

### `AHKFlowApp.API.Tests`, where nothing changed

All 29 classes still carry `[Collection("WebApi")]` and share one `ICollectionFixture`, so no two
of them run at once. There is no shared host, no exclusive collection, and no thread cap. The
rule at the top of this document still describes what the suite would have to prove; it does not
describe what the suite does today.

If backlog 134 runs, the Infrastructure rules apply here as well, plus one more that is specific
to hosts: a class that builds its own host with `WithWebHostBuilder` joins the exclusive
collection, and that suite then earns a `maxParallelThreads` of its own.
