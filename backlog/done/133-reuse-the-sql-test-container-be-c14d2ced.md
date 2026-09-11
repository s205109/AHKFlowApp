# 133 - Reuse the SQL test container between runs

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Tooling
- **Interfaces**: none (test infrastructure)
- **Difficulty**: complex
- **Stage**: 9-ship

## Summary

Every Integration and E2E run starts a fresh SQL Server container and removes it afterwards,
which costs 10 to 20 seconds a run. This item asks whether one container can serve several runs.
It cannot today, and the blocker is named below.

## User story

As a developer running the Integration slice several times in a row, I want the second run to
reuse the SQL Server the first one started, so that I do not pay a container start every time.

## What has to change first

**The migration tests must drop their own databases.** They migrate fixed database names from
scratch, and no test in the repository drops its database afterwards. On a reused container the
second run would find those databases already migrated and fail for a reason the code under test
did not cause. Backlog 128 hit exactly this, which is why its soak harness starts one container
per repetition instead of reusing one.

That is real work with a real risk: a test that drops and recreates its own database is a test
whose isolation now depends on its own cleanup running. Weakening the migration tests to save
15 seconds a run would be a bad trade, so this item has to show it did not.

## Acceptance criteria

The item's original criteria were written from a prediction. These replace them, copied from the
design's rewritten criteria without changing their wording. `## Notes / dependencies` below says
more about why.

**The tests**

- [x] All nine tests that need an empty database drop it before they build. This design names all
      nine: six in group one, three in group three.
- [x] The four owner-unscoped queries in `HotstringCliIntegrationTests` filter by the test's own
      owner id.
- [x] Running the Integration slice twice against one container passes both times.
- [x] Running the E2E slice twice against one container passes both times.
- [x] `pwsh ./scripts/measure-test-modes.ps1 -Soak tests/AHKFlowApp.Infrastructure.Tests -Runs 30`
      passes 30 of 30 against a reused container.
- [x] The migration tests still fail when a migration is broken. Break one on purpose, show the
      red run, and put it back.

      Proved again in Task 9. `SchemaPolish`'s `Up` body was commented out, then
      `pwsh .\scripts\test-fast.ps1 -Mode Integration` was run: `SchemaPolish_RemovesInconsistentProfileAssociations`
      failed with `Expected inconsistentHotstrings to be 0, but found 2 (difference of 2)`, and
      `dotnet test` exited 1 for `AHKFlowApp.Infrastructure.Tests` (`Failed: 3, Passed: 23, Total: 26`;
      the other two failures are the same broken column read, expected collateral). The body was put
      back (`git diff` showed no change from the committed file), and the slice was run again:
      `AHKFlowApp.Infrastructure.Tests` passed 26 of 26, all four Integration projects green, exit 0.
- [x] `Migrate_IsIdempotent_RunsTwiceWithoutError` still makes two migration calls after the drop,
      because the drop must not turn its subject into a single call.
- [x] A test that reaches an intermediate migration without the helper fails a PowerShell suite.
      Prove both routes: `IMigrator`, and `MigrateAsync` with a target migration string.

**The container's life**

- [x] Two successful runs in a row report the same container id, and `docker ps` shows one test
      container for the checkout, not two.
- [x] The 30-run soak reports the same container id at run 1 and run 30.
- [x] A run that fails leaves the container in place. Force a test failure and show the container
      still running afterwards.
- [x] `-FreshSql` replaces the container: the id after it differs from the id before it.
- [x] A stopped container is started, not replaced. `docker stop` it, run the slice, and show the
      same id afterwards.
- [x] A container that cannot be repaired is replaced once and the run continues. Plant a broken
      one before the slice starts: `docker run` the expected image with the expected name and both
      expected labels, but with no `--publish`. It exists, it runs, and it carries the right image,
      so the verification reaches the port check and fails there. Show one replacement, a new
      container id, and a green run.
- [x] A replacement that cannot itself be verified stops the run with the reason and the container
      name. Point the expected image at a tag that does not exist, and show the message.
- [x] Two checkouts do not share a container. Run the slice in this worktree and in the main
      checkout, and show two containers with different ids and different
      `com.ahkflowapp.compose-project` labels.
- [x] Removing the worktree removes its test container. Show it gone from `docker ps --all`.
- [x] `pwsh ./scripts/prune-worktree-docker.ps1` removes a test container whose checkout is gone,
      and leaves a live checkout's container alone.
- [x] Discovery and replacement stay inside the existing test-run lock. Show the order in
      `scripts/test-fast.ps1`.

**The measurement**

- [x] The saving is measured as a median of five warm Integration runs, written into the item
      beside the 49.59 s backlog 128 left, with all five runs and the maximum. The number includes
      the three group-three drops, which are a real cost this change adds.

      Five warm runs, one container reused throughout (id `18743b2d6d9b`, confirmed unchanged after
      every run): 44.64 s, 40.63 s, 38.81 s, 39.05 s, 40.23 s. Median **40.23 s**, mean 40.67 s, max
      44.64 s. Against the 49.59 s backlog 128 left, that is a 9.36 s saving, about 19%.

## Out of scope

- The E2E slice's own container. Handle it only if the same change covers it for free.
- Sharing a container across two developers or across CI jobs. This is about runs in one place,
  one after another.

## Notes / dependencies

- Filed out of backlog 128, which measured the cost: the SQL container start took 20.42 s,
  11.17 s and 10.65 s across three Integration runs, and that alone explained most of the spread
  between 107.50 s and 81.51 s.
- Every container gets a fresh name today, in `scripts/test-sql-container.common.ps1`, and is
  removed afterwards. `scripts/test-fast.ps1` owns that life for Integration and E2E.
- `SharedSqlContainer` already holds one container for the life of a test process. This item is
  about holding one across processes, which is a different problem.
- Backlog 128's design records this as blocked rather than merely deferred, and the block is the
  migration tests, not the container plumbing.
- Spec: `docs/superpowers/specs/2026-09-10-reuse-the-sql-test-container-design-133.md`
- Plan: `docs/superpowers/plans/2026-09-10-reuse-the-sql-test-container-plan-133.md`
- Backlog 128's design named this item's blocker under D7, before anybody measured it. The
  2026-09-10 design measured it instead: nine tests need an empty database, not "every test that
  migrates a fixed database name", and four CLI queries read a row they never proved they created.
  The design replaces this item's acceptance criteria. Task 9 of the plan copies the rewritten
  criteria in when the work ships.
- This item's own original acceptance criteria, above, were also written from a prediction: they
  named "every test that migrates a fixed database name" before anybody had counted which tests
  actually needed an empty one. The 2026-09-10 design measured the real blocker and replaced them
  with the rewritten criteria under `## Acceptance criteria`, which this task ticked against real
  runs.
