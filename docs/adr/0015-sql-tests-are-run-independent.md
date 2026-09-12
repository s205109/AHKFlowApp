# SQL-backed tests are run-independent, and prove it by dropping first

<!-- citation-check:ignore-file -->
<!-- This ADR is a point-in-time record. Its code citations were true when it was written, on
     2026-09-10. Backlog 133 then moved those lines while carrying out the decision here. -->

[ADR 0013](0013-sql-backed-tests-isolate-by-database.md) says isolation is a property a test class
proves about itself. That claim covered one run. The SQL Server container was created for a run and
removed when the run ended, so every database started empty whatever any test did.

The Reused test server ends that. One container now serves many runs in a checkout, so a test opens
a database another run already filled. Isolation is therefore a claim across runs as well as within
one, and this document names the obligation that follows.

**A test that needs an empty database drops it first, before it builds anything, never after.**

## Why first, and not last

Backlog 133 was filed asking for the opposite: each affected test would drop its database when it
finished. That reading has one failure it cannot recover from. A killed run, a stopped test, or a
crash leaves the database behind, and the next run then fails for a reason nothing in the code
caused. Correctness would depend on the previous run having completed, which is exactly the property
a test suite must not have.

Dropping first depends on nothing. Whatever a container holds when a run starts — a clean state, a
half-finished run's leftovers, or a database from a week ago — the test drops it and builds what it
needs. What it costs is set out under "The cost the three drops add" below: nothing for six of the
nine tests, and a full schema build for the other three.

The drop is `EnsureDeletedAsync`. The EF Core documentation describes this exact use: the method
drops the database if it exists, and pairing it with a fresh build leaves the database in a clean
state before each execution of the test.

## What the rule applies to, and why it is drawn there

The rule is drawn around the starting state a test needs. It is not drawn around the tests that
failed when the reuse was measured, and it is not drawn around the way a test reaches its schema. A
test whose assertion only holds from an empty database drops that database first. Every other test
is left alone.

Nine tests need an empty database. Six reach an intermediate migration. Three build a whole schema
and then assert that the build did work.

### The six that reach an intermediate migration

Five failed on a second run against one container, all with the same `System.NotSupportedException` (`src/Backend/AHKFlowApp.Infrastructure/Migrations/20260722105522_HotkeyTypedActions.cs:197`, "throw new System.NotSupportedException("). Against a database already at head, EF Core reads a request for an earlier migration as a request to migrate down, and that migration refuses to be reverted.

The sixth passed (`tests/AHKFlowApp.Infrastructure.Tests/Persistence/MigrationTests.cs:70`, "await migrator.MigrateAsync("). It targets the twentieth of twenty-one migrations, so its revert crossed only the twenty-first, whose `Down` is supported. It reverted schema and then rebuilt it, which is not what its name claims it does, and it reported success.

### The three that stop testing instead of failing

These three never throw against a warm database. They quietly do no work, which is harder to notice
than a failure.

- (`tests/AHKFlowApp.Infrastructure.Tests/Persistence/MigrationTests.cs:33`, "public async Task Migrate_AppliesPendingMigrationsWithoutError()") holds the fixed database name `MigrationTests_Apply` and calls `MigrateAsync()` with no target. On a warm server there are no pending migrations, so the call applies nothing and the assertion passes against no work.
- (`tests/AHKFlowApp.Infrastructure.Tests/Persistence/MigrationTests.cs:46`, "public async Task Migrate_IsIdempotent_RunsTwiceWithoutError()") wants a first call that builds the schema and a second that changes nothing. On a warm server both calls change nothing, so the claim in its name is never exercised.
- (`tests/AHKFlowApp.Infrastructure.Tests/Persistence/AppDbContextTests.cs:45`, "public async Task EnsureCreated_AppliesSchemaWithoutError()") calls `EnsureCreatedAsync`, which does no work when the database already exists. Its name says the schema is applied. On a warm server nothing is.

A rule written around "migrates to an explicit target migration" would have missed all three. That
is why this rule names the starting state instead.

### What the rule leaves alone

Tests that migrate straight to head and then read only their own rows are untouched. Migrating an
up-to-date database changes nothing, and changing nothing is exactly what those tests want.

(`tests/AHKFlowApp.Infrastructure.Tests/Persistence/AppDbContextTests.cs:31`, "public async Task CanConnect_WhenDatabaseExists_ReturnsTrue()") is the clearest boundary case. It needs a database that exists, and it creates one. An earlier run's database meets the same precondition, so the test keeps its meaning either way.

### The cost the three drops add

The six that reach an intermediate migration already built from nothing on every run, so dropping
first costs them nothing. The three above are different. On a warm server they used to do no work at
all, and now they build a full schema every run. That gives back part of the saving, on purpose. A
test that runs faster because it tests nothing is not a saving.

## The other half: queries that name no owner

Four assertions in the CLI suite asked the database for a row by its trigger value and nothing else (`tests/AHKFlowApp.CLI.Tests/Integration/HotstringCliIntegrationTests.cs:114`, ".FirstOrDefaultAsync(h => h.Trigger =="). Two failed on the second run and two passed, because the row they found from the earlier run happened to carry the same values.

Those four never proved they were reading a row they created. The class already gives each instance
its own owner id, and every other assertion in it uses that id, so the fix restores a rule the class
already followed everywhere else.

This is the second shape of the same obligation. Dropping what a test reads, and reading only rows a
test can prove are its own, are the two shapes this design had to build. They are not a closed list
of ways to be run-independent. The obligation is the property, and the techniques serve it: a test
must still start from the state it needs, and must still exercise its own subject. The
`CanConnect_WhenDatabaseExists_ReturnsTrue` case above meets both and uses neither technique.

## Considered options

**Drop at the end of the test**, as the item asked. Rejected above: it makes this run's correctness
depend on the previous run finishing.

**Give every run unique database names, and sweep old ones.** No test would need a drop. Rejected
because the databases then accumulate, the sweep becomes a new thing that can fail, and the
guarantee is no stronger than dropping first.

**Reset the whole container from `scripts/test-fast.ps1` at the start of a run.** Rejected because
it would move the names of test databases into a script, and it would do nothing for a plain
`dotnet test`, which is what CI runs.

**Testcontainers' own reuse feature.** `WithReuse` exists in the pinned version, but its own
documentation calls it experimental and warns that it disables the resource reaper. It also only
reaches the plain `dotnet test` path, where reuse has no value, because a CI job starts on a fresh
machine.

## Consequences

**A new SQL-backed test has one more question to answer.** Not only "which database is mine", which
ADR 0013 asks, but "what happens when that database already holds an earlier run's rows". An
acceptable answer shows two things: the test still starts from the state it needs, and it still
exercises its own subject. Dropping the database first answers it, and so does reading only rows the
test can prove it owns. So does needing nothing an earlier run could have broken.

**Reaching an intermediate migration goes through one helper.** A test cannot get there and forget
the drop, because the helper does both. A PowerShell suite fails a test file that reaches an
intermediate migration by any other route, so a bypass is visible in review rather than discovered
months later by a second run.

There are two such routes, not one. `IMigrator` is the obvious one. The other is the target
overloads on `DatabaseFacade`: EF Core 10.0.6 ships `Migrate(DatabaseFacade, String)` and
`MigrateAsync(DatabaseFacade, String, CancellationToken)`, whose `targetMigration` parameter is
documented as "The target migration to migrate the database to, or null to migrate to the latest".
A test can therefore name an earlier migration without ever mentioning `IMigrator`. The check covers
both routes, synchronous and asynchronous.

**Local runs stop proving the cold path.** With the server reused, a normal local run no longer
shows that the suite works against nothing. Continuous integration still does, on every pull
request, because it runs plain `dotnet test` (`.github/workflows/ci.yml:71`, "dotnet test --configuration Release --no-build --verbosity normal") with no shared connection string. That is
the trade this decision accepts: the cold proof moves from every local run to every pull request.

**`-FreshSql` exists for the case where somebody wants the cold path locally.** It removes the
container and starts a new one. It is not part of any gate, because putting it there would give back
the whole saving at the moment a developer feels it most.

**Trust in the container is established once, before the first test runs.** The script checks the
container, repairs or replaces it at most once, and then hands a connection string to the run.
Nothing recovers a container that dies while tests are running: that run fails, exactly as it fails
today when Docker stops. Recovering would mean rebuilding databases the run had already migrated and
restarting tests already in flight, which is a test-host job and nothing in this repository asks for
it. The next run finds no container, or one it cannot verify, and builds a fresh one.

**The test container is not a Compose project, so the cleanup paths need a second pass.** The
existing worktree cleanup finds and removes Compose projects (`scripts/worktree-docker.common.ps1:60`, "$json = & docker compose ls --all --format json 2>$null"), and the test
container is started with plain `docker run` (`scripts/test-sql-container.common.ps1:17-31`, "'run', '--detach', '--name',"). No name alone makes the first find the second. The container is therefore
labelled and discovered by label, and removed with `docker rm`, alongside the Compose teardown
rather than through it.
