# SQL-backed tests isolate by their own database, not by collection

A test that touches SQL Server keeps itself apart from every other test by working in a database
of its own. The xUnit collection is not the isolation mechanism. It is only how a fixture
instance gets shared.

Two shapes of that exist here, and both are database isolation.

- **A database per test class.** `SharedSqlServerFixture` hands a class the shared *server's*
  connection string, and the class names its own catalog on it. `HotstringPersistenceTests` opens
  `HotstringPersistenceTests`, and `SchemaPolishBackfillTests` opens `SchemaPolish_Backfill`. All
  eight SQL-backed classes in `AHKFlowApp.Infrastructure.Tests` work this way. Its other two
  classes, both under `Services/`, touch no database and take no fixture.
- **A database per test run.** `SqlContainerFixture` builds one name through
  `SqlTestDatabase.CreateConnectionString`, and every class in `AHKFlowApp.API.Tests` shares it.

Owner id is not the boundary, and this document said for a while that it was. `TestUserBuilder`
gives every authenticated client the same fixed oid unless a test calls `WithOid`. Random owner
ids are a tool for the few tests that assert one owner cannot see another's rows, such as
`KnownShortcutsControllerTests`. They keep no test apart from any other by default.

That distinction is easy to lose, and losing it is expensive in both directions. Reading a
collection as an isolation boundary makes a suite serial for no reason, which is what
`AHKFlowApp.API.Tests` and `AHKFlowApp.Infrastructure.Tests` both did: every class carried one
collection attribute so it could receive one `ICollectionFixture`, and the side effect was that
no two of those tests ever ran at once. Measurement put `API.Tests` at 1.05x parallelism on a
sixteen-core machine, and `Infrastructure.Tests` at 1.0x.

Only `Infrastructure.Tests` was then changed. `API.Tests` still reads that way today, for the
reasons in the Consequences section below.

Reading it the other way round is worse. Dropping the attribute to gain parallelism, without
first checking what each class actually writes to, would let two tests share a catalog and
produce a failure that depends on scheduling. `Infrastructure.Tests` was safe to change because
each of its classes already named a different database.

So the rule is: **isolation is a property a test class proves about itself, and a collection is a
tool for sharing a fixture or for forcing exclusivity.** Reach for a collection when a test needs
one of those two things, never as a way to avoid thinking about isolation.

## What a shared host would additionally require

**Nothing in this section is built.** `AHKFlowApp.API.Tests` still runs every class through one
shared collection, one after another. Backlog 128 designed the shared host, measured the gain at
about twelve seconds, and the human declined it, because the Integration target was already met
without it. The design is filed as backlog 134, which is still on its own branch and reaches
`backlog/` only when that branch merges. Look there first, and read this section meanwhile.
What follows is the part of that design which database isolation does not cover, kept here so
the next reader need not work it out again.

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

**Leaving both suites serial** was rejected for `Infrastructure.Tests`, because the cost was
measured and then removed: the assembly ran in 26 s serial and runs in 8 s now. That is the
number this decision earned.

For `API.Tests` the same measurement says something different. Its eight classes that build
their own host hold 5.84 s across 24 tests, while the other 215 tests hold 15.13 s; only the
first number is a floor. So 15.13 s is the most that reshaping could win back, and the human
chose to leave `API.Tests` serial once the Integration target was met without it. That
unclaimed 15.13 s is what the shared-host item is holding.

## Consequences

The two suites this decision names ended up in different places, so they are written out
separately. Reading either one as the state of both is the mistake this section exists to stop.

### `AHKFlowApp.Infrastructure.Tests`, where the rule is in force

A new SQL-backed test class runs in parallel by default. It reaches the shared server through
`IClassFixture<SharedSqlServerFixture>`, not through a collection, and it names its own database
on that server. Two classes that name the same database are not isolated from each other, so a
new class either picks a fresh name or joins the class it shares with in one collection. None of
that is discoverable from the code alone, so it belongs in the testing guide as well as here.

Parallelism is bounded by the machine, not by the core count of whoever measured it. This project
therefore carries an explicit `maxParallelThreads` of 4 in its own `xunit.runner.json`, rather
than inheriting the processor count, because its classes share one SQL Server. It is the only
test project in the repository with such a file; every other one keeps the default.

### `AHKFlowApp.API.Tests`, where nothing changed

All 29 classes still carry `[Collection("WebApi")]` and share one `ICollectionFixture`, so no two
of them run at once. That fixture is `ApiTestFixture`, and it does build one host: its
`InitializeAsync` creates a single `CustomWebApplicationFactory` that every class in the
collection uses. What the suite has no version of is a **process-scoped host that parallel
collections could reach**. The one host it has is reachable only from inside the serial
collection, which is why it needs none of the locking the section above describes.

There is also no exclusive collection and no thread cap. The rule at the top of this document
still describes what the suite would have to prove; it does not describe what the suite does
today.

If backlog 134 runs, the Infrastructure rules apply here as well, plus one more that is specific
to hosts: a class that builds its own host with `WithWebHostBuilder` joins the exclusive
collection, and that suite then earns a `maxParallelThreads` of its own.
