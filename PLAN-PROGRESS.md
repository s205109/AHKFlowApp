# Progress — backlog 132, parallel E2E stacks

Plan: `docs/superpowers/plans/2026-09-09-parallel-e2e-stacks-plan-132.md`

The human chose to stop after Task 4. Tasks 5 to 7 wait for their go-ahead.

One line per finished task, written after its deliverable commit.

- [x] Task 1 — one SQL server for the whole test process. Commit `9ef98383`. `ApiFactoryTests`
      passed, 1 test. The plan missed one thing: `StackFixture` calls `new ApiFactory()`, so it
      needed the assembly discriminator to keep the build green. Task 4 replaces that line.
- [x] Task 2 — serialise host construction so Serilog cannot throw. Commit `97a11d6b`. The race
      is real and reproduced. Three rounds passed without the gate, which is why the plan told me
      to raise it; 20 rounds failed. The message is not the literal "already frozen" text, because
      `Program.cs` catches its own throw — the test sees
      "System.InvalidOperationException : The entry point exited without ever building an IHost."
      With the gate, 20 rounds pass. Both lifecycle checks pass, 2 tests. Rounds put back to 3.
- [x] Task 3 — one browser install per test process. Full E2E run passed: 64 tests, 0 failed,
      test host 3 m 16 s, wall clock 241.62 s. The suite is still serial here.

      **The 306.96 s baseline looks too high, and Task 6 must not trust it.** This run is still
      serial and carries two new tests, so it should have been slower than the baseline, not 65
      seconds faster. The likely reason is that the baseline was the first run in this worktree
      and paid for a cold browser download, a cold image pull and cold file caches. Task 6
      therefore measures the serial number again before it claims any saving.

      **The test count is now 64, not 62.** Task 2 added two lifecycle tests. The item's
      criterion 3 needs the same correction, and Task 6 makes it.
- [ ] Task 4 — four collections, four fixtures, classes moved
- [ ] Task 5 — thread cap, copy rule, written balance rule
- [ ] Task 6 — measure, and prove the way back
- [ ] Task 7 — the soak
