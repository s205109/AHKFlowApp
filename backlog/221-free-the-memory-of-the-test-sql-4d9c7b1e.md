# 221 - Free the memory of the test SQL container

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (`scripts/test-sql-container.common.ps1`, `scripts/test-fast.ps1`)
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup

## Summary

After a test run, the checkout's shared SQL Server test container keeps running and holds about
2.1 GB in WSL. By design, every checkout and worktree that ran its tests has its own. The
container also has no memory limit of its own. This item makes an idle test container hold less
memory, or none, and keeps the next run fast.

## User story

As the developer who runs several agents in worktrees on one laptop, I want idle test SQL
containers to give their memory back, so that a test VM or a second test suite can start without
running out of memory.

## Acceptance criteria

- [ ] A record in this item names the chosen approach. It states the memory that an idle test
      SQL container holds in WSL before and after the change, measured as in the Notes.
- [ ] A checkout's test SQL container that no run uses gives its memory back within a time that
      the record names.
- [ ] The record says whether the test SQL container gets a memory limit, and why. When it gets
      one, the container stays within that limit during an Integration run.
- [ ] The record states the start time of the SQL Server in a second Integration run, before and
      after the change.

## Out of scope

- The WSL memory limit of the two laptops that `windows-provisioning` sets up, the M16HE and the
  M16VY. Backlog 138 of `windows-provisioning` sets it: 10 GB on the M16HE and 12 GB on the M16VY.
- The `dotnet` build servers. The watch in the Notes shows that they stop by themselves.
- The SQL Server of `docker-compose.yml`.
- The throwaway container that `-Ephemeral` builds. Its caller removes it after the run
  (`scripts/test-sql-container.common.ps1:537`, "It removes the throwaway container it built with").
- The container that `Testcontainers.MsSql` starts under a plain `dotnet test`. The fixture
  disposes of it at the end of the run
  (`tests/AHKFlowApp.TestUtilities/Fixtures/SqlContainerFixture.cs:50`, "await _container.DisposeAsync();").

## Notes / dependencies

- Filed from a session about memory on Bart's laptop BARTM16, on 26 November 2026. BARTM16 is the
  build PC in `windows-provisioning`. There, Windows Terminal or Claude sometimes runs out of
  memory when a VM or a test suite starts.
- Measured on BARTM16 at commit `734149c3` of `main`, during one run of
  `scripts/test-fast.ps1 -Mode Integration` (713 tests, 1.1 minutes):
  - WSL (`vmmemWSL`) grew from 0.8 GB to 3.7 GB.
  - The container `ahkflowapp_d54210af-testsql` reached 1.76 GB during the run.
  - The `dotnet` processes reached 1.56 GB.
  - The commit charge of Windows grew from 23.8 GB to 29.4 GB.
- Limits of that measurement: it is one run of one checkout. Other Claude sessions ran on BARTM16
  at the same time, and their memory is in the numbers. The script took a sample about every 3.5
  seconds, so it can miss a short peak.
- No start time of a second run is measured yet. The measured run built a new container, and its
  log says: Shared SQL test container started in 9276.889 ms. The word "started" means a new
  container, and "reused" means one that was already there
  (`scripts/test-fast.ps1:519`, "$sharedSqlVerb = if ($sharedSqlContainer.Reused) { 'reused' } else { 'started' }").
  A stopped container that a run starts again also counts as reused
  (`scripts/test-sql-container.common.ps1:442`, "$reused = $true").
  So the start of a stopped container is not measured either. Measure the time before the change
  before the code changes.
- Watched for 20 minutes after that run, with a sample every 30 seconds:
  - The watch started at 14:43:31, about 8.5 minutes after the run ended. No sample covers the
    7.5 minutes before it.
  - `VBCSCompiler` (0.24 GB) stopped by itself about 10 minutes after the run.
  - The 15 MSBuild worker nodes (0.82 GB) stopped by themselves about 15 minutes after the run.
  - The idle container held 2245 MB at the start of the watch, more than its 1.76 GB during the
    run. So 1.76 GB is not its peak. It kept 2.1 to 2.2 GB for the first 10 minutes of the watch,
    until `docker stop`.
  - WSL held 3.47 GB at the start of the watch. It gave its Linux cache back, from 817 MB to about
    170 MB, and 2 minutes later it was at about 2.9 GB. BARTM16 runs WSL with
    `autoMemoryReclaim=gradual`.
  - After `docker stop`, WSL fell from 3.1 GB to 0.9 GB within one minute. The commit charge fell
    by about 2 GB.
- The container keeps running on purpose. The comment on `-FreshSql` says that a second run then
  starts in about a second instead of sixteen
  (`scripts/test-fast.ps1:23`, "one left, which is what makes a second run start in about a second instead of sixteen.").
  A run starts a stopped container again
  (`scripts/test-sql-container.common.ps1:247`, "$output = & docker start $ContainerName 2>&1").
- SQL Server on Linux takes up to 80% of the memory that it sees, unless `memory.memorylimitmb`
  or `MSSQL_MEMORY_LIMIT_MB` says otherwise. It needs at least 2 GB to start. Microsoft
  recommends a Docker memory limit with headroom, and `MSSQL_MEMORY_LIMIT_MB` below it:
  <https://learn.microsoft.com/sql/linux/configure/performance-best-practices-sql-server-memory>
  and <https://learn.microsoft.com/sql/linux/install-upgrade/setup>.
- Approaches to weigh: a Docker memory limit with `MSSQL_MEMORY_LIMIT_MB`; a stop at the end of
  each run; a stop after a time without runs. A stop frees the memory of an idle container, but it
  sets no limit while a run uses it. The ownership check refuses to share one container between
  checkouts
  (`scripts/test-sql-container.common.ps1:180`, "if ($State.Project -ne $ComposeProject) {").
- Spec: none — not started.
- Plan: none — not started.
