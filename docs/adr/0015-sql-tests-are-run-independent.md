# SQL-backed tests are run-independent, and prove it by dropping first

[ADR 0013](0013-sql-backed-tests-isolate-by-database.md) says isolation is a property a test class
proves about itself. That claim covered one run. The SQL Server container was created for a run and
removed when the run ended, so every database started empty whatever any test did.

The Reused test server ends that. One container now serves many runs in a checkout, so a test opens
a database another run already filled. Isolation is therefore a claim across runs as well as within
one, and this document names the obligation that follows.

**A test that needs an empty database drops it before it migrates, never after.**

## Why first, and not last

Backlog 133 was filed asking for the opposite: each affected test would drop its database when it
finished. That reading has one failure it cannot recover from. A killed run, a stopped test, or a
crash leaves the database behind, and the next run then fails for a reason nothing in the code
caused. Correctness would depend on the previous run having completed, which is exactly the property
a test suite must not have.

Dropping first depends on nothing. Whatever a container holds when a run starts — a clean state, a
half-finished run's leftovers, or a database from a week ago — the test drops it and builds what it
needs. It also costs no extra time, because every test this rule touches already migrated from
scratch.

The drop is `EnsureDeletedAsync`. The EF Core documentation describes this exact use: the method
drops the database if it exists, and pairing it with a fresh build leaves the database in a clean
state before each execution of the test.

## What the rule applies to, and why it is drawn there

The rule covers every test that migrates to an explicit target migration, rather than every test
that failed when the reuse was measured.

Six facts do that. Five of them failed on a second run against one container, all with the same
`System.NotSupportedException`
(`src/Backend/AHKFlowApp.Infrastructure/Migrations/20260722105522_HotkeyTypedActions.cs:197`, "throw
new System.NotSupportedException("). Against a database already at head, EF Core reads a request for
an earlier migration as a request to migrate down, and that migration refuses to be reverted.

The sixth passed (`tests/AHKFlowApp.Infrastructure.Tests/Persistence/MigrationTests.cs:70`, "await
migrator.MigrateAsync("). It targets the twentieth of twenty-one migrations, so its revert crossed
only the twenty-first, whose `Down` is supported. It reverted schema and then rebuilt it, which is
not what its name claims it does, and it reported success. Drawing the rule around the five that
failed would have left that one in place, passing for a reason nobody intended.

Tests that migrate straight to head are untouched. Migrating an up-to-date database is a no-op, so
they were already run-independent.

## The other half: queries that name no owner

Four assertions in the CLI suite asked the database for a row by its trigger value and nothing else
(`tests/AHKFlowApp.CLI.Tests/Integration/HotstringCliIntegrationTests.cs:114`,
".FirstOrDefaultAsync(h => h.Trigger =="). Two failed on the second run and two passed, because the
row they found from the earlier run happened to carry the same values.

Those four never proved they were reading a row they created. The class already gives each instance
its own owner id, and every other assertion in it uses that id, so the fix restores a rule the class
already followed everywhere else.

This is the second shape of the same obligation. A test is run-independent either because it drops
what it reads, or because it only ever reads rows it can prove are its own.

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
ADR 0013 asks, but "what happens when that database already holds an earlier run's rows". Two
answers are acceptable: drop it first, or read only rows the test can prove it owns.

**Reaching an intermediate migration goes through one helper.** A test cannot get there and forget
the drop, because the helper does both. A PowerShell suite fails a test file that reaches
`IMigrator` directly, so a bypass is visible in review rather than discovered months later by a
second run.

**Local runs stop proving the cold path.** With the server reused, a normal local run no longer
shows that the suite works against nothing. Continuous integration still does, on every pull
request, because it runs plain `dotnet test` (`.github/workflows/ci.yml:71`, "dotnet test
--configuration Release --no-build --verbosity normal") with no shared connection string. That is
the trade this decision accepts: the cold proof moves from every local run to every pull request.

**`-FreshSql` exists for the case where somebody wants the cold path locally.** It removes the
container and starts a new one. It is not part of any gate, because putting it there would give back
the whole saving at the moment a developer feels it most.
