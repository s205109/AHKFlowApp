# One shared API host, with an exclusive collection for the tests that build their own

`AHKFlowApp.API.Tests` runs its 239 tests against one `WebApplicationFactory` that is started
once and held for the process. Test classes reach it through an accessor that serialises client
creation. The eight classes that build a second host of their own sit in one xUnit collection
marked `DisableParallelization = true`.

Before this, every test class carried `[Collection("WebApi")]`. That is the only way xUnit
shares one `ICollectionFixture` instance, and it also means no two of those tests ever run at
the same time. Measurement put the whole suite at 17 s of wall clock for 17.88 s of test time,
a parallelism of 1.05x on a sixteen-core machine.

The tests do not need that serialisation for their data. Each one authenticates as a fresh
random owner and scopes its assertions to that owner, so two tests running at once do not see
each other's rows.

They do need it for three pieces of shared state, and this is the part that is easy to get
wrong.

`WebApplicationFactory<TEntryPoint>` keeps the clients it hands out and the derived factories
it creates in two plain `List<T>` fields, and adds to both without a lock. Concurrent
`CreateClient()` on one shared factory is a data race. The accessor therefore takes a lock
around client creation. A test holds the client it receives, not the lock, so the cost is
close to nothing.

Serilog's `Log.Logger` is a process-wide static. `Program.cs` assigns it while a host starts
and closes it in its `finally`. A second host starting while the first is serving requests
replaces the logger underneath it.

Disposal has no natural owner once the factory is process-scoped. Nothing in xUnit disposes it,
so the accessor registers the host for disposal at process exit. A host that lives for one test
run is fine. A host disposed while another class still holds a client is not.

The eight classes that call `WithWebHostBuilder`, or construct their own factory, hit the
second and third of those. Putting them in one non-parallel collection settles both at once,
because xUnit runs every parallel collection to completion before it starts a non-parallel one.
Those eight therefore run last, one at a time, and no second host ever exists while the shared
host is serving parallel tests.

## Considered options

**One collection per class, each with its own fixture** was rejected. It reads simpler, but each
`SqlContainerFixture` starts its own SQL Server container when the shared connection string is
absent from the environment, which is what a plain `dotnet test` does. Eight classes would mean
eight containers.

**Splitting the tests into a handful of hand-picked collections**, each with its own fixture,
was rejected as arbitrary. The grouping would carry no meaning, it would drift as classes are
added, and it would still start one host per group.

**Leaving the suite serial** was rejected because the cost is measured and large. The eight
exclusive classes hold 5.84 s across 24 tests, and the other 215 tests hold 15.13 s. Only the
first number is a floor.

## Consequences

A new API test class runs in parallel by default, which is the right default. A class that
builds its own host must join the exclusive collection, and a class that cannot isolate by
owner id must say so and get a collection of its own. Neither is discoverable from the code
alone, so both belong in the testing guide.

The parallelism this buys is bounded by the 5.84 s serial floor, not by the core count. Any
target written against this decision has to be measured, not extrapolated.
