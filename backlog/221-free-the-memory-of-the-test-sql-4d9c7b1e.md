# 221 - Free the memory of the test SQL container

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (`scripts/test-sql-container.common.ps1`, `scripts/test-fast.ps1`)
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup

## Summary

After a test run, the checkout's SQL Server test container keeps running and holds about 2.1 GB
in WSL. Every checkout and worktree that ran its tests holds its own. The container also has no
memory limit of its own. This item makes an idle test container hold less memory, or none, and
keeps the next run fast.

## User story

As the developer who runs several agents in worktrees on one laptop, I want idle test SQL
containers to give their memory back, so that a test VM or a second test suite can start without
running out of memory.

## Acceptance criteria

- [ ] A record in this item names the chosen approach. It states the memory that an idle test
      SQL container holds in WSL before and after the change, measured as in the Notes.
- [ ] A checkout's test SQL container that no run uses gives its memory back within a time that
      the record names.
- [ ] The test SQL container cannot take more memory than a limit that the record names.
- [ ] The record states the start time of the SQL Server in a second Integration run, before and
      after the change.

## Out of scope

- The WSL memory limit of the laptops. Backlog 138 of `windows-provisioning` sets it: 10 GB on the
  M16HE and 12 GB on the M16VY.
- The `dotnet` build servers. The watch in the Notes shows that they stop by themselves.
- The SQL Server of `docker-compose.yml`.

## Notes / dependencies

- Filed from a session about memory on Bart's laptop BARTM16, on 26 November 2026. There,
  Windows Terminal or Claude sometimes runs out of memory when a VM or a test suite starts.
- Measured on BARTM16 at commit `734149c3` of `main`, during one run of
  `scripts/test-fast.ps1 -Mode Integration` (713 tests, 1.1 minutes):
  - WSL (`vmmemWSL`) grew from 0.8 GB to 3.7 GB.
  - The container `ahkflowapp_d54210af-testsql` reached 1.76 GB.
  - The `dotnet` processes reached 1.56 GB.
  - The commit charge of Windows grew from 23.8 GB to 29.4 GB.
- Watched for 20 minutes after that run, with a sample every 30 seconds:
  - `VBCSCompiler` (0.24 GB) stopped by itself about 10 minutes after the run.
  - The 15 MSBuild worker nodes (0.82 GB) stopped by themselves about 15 minutes after the run.
  - WSL gave its Linux cache back, from 817 MB to about 170 MB. BARTM16 runs WSL with
    `autoMemoryReclaim=gradual`.
  - The idle container kept 2.1 to 2.2 GB for the whole 10 minutes, and WSL stayed at about
    2.9 GB.
  - After `docker stop`, WSL fell from 3.1 GB to 0.9 GB within one minute. The commit charge fell
    by about 2 GB.
- The container keeps running on purpose. The comment on `-FreshSql` in `scripts/test-fast.ps1`
  says that a second run then starts in about a second instead of sixteen.
  `scripts/test-sql-container.common.ps1` starts a stopped container again (line 247).
- SQL Server on Linux takes up to 80% of the memory that it sees, unless `memory.memorylimitmb`
  or `MSSQL_MEMORY_LIMIT_MB` says otherwise. It needs at least 2 GB to start. Microsoft
  recommends a Docker memory limit with headroom, and `MSSQL_MEMORY_LIMIT_MB` below it:
  <https://learn.microsoft.com/sql/linux/configure/performance-best-practices-sql-server-memory>
  and <https://learn.microsoft.com/sql/linux/install-upgrade/setup>.
- Approaches to weigh: a Docker memory limit with `MSSQL_MEMORY_LIMIT_MB`; a stop at the end of
  each run; a stop after a time without runs. The ownership check of
  `scripts/test-sql-container.common.ps1` (around line 199) refuses to share one container
  between checkouts.
- Spec: none — not started.
- Plan: none — not started.
