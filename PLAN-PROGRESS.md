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
- [x] Task 4 — four collections, four fixtures, classes moved. The suite now runs in parallel.
      64 tests passed, 0 failed. Test host 1 m 26 s, wall clock 128.29 s.

      Against the honest serial number from Task 3, which carried the same 64 tests:
      241.62 s to 128.29 s wall clock, and 196 s to 86 s in the test host.

      The design predicted a slowest group of 70.51 s and got 86 s, so contention cost about
      1.22 times. That is far milder than backlog 126's 2.1 times, which fits: this work is bound
      by the processor and this machine has 16.

      No `maxParallelThreads` cap yet. Task 5 adds it. It changes nothing here, because there are
      only four parallel collections to begin with, but it is what bounds CI.
- [x] Task 5 — thread cap, copy rule, written balance rule. Commit `17e991a7`. The cap is proven
      read, not only copied: the same tree gives 257.14 s at one thread and 128.29 s at four.
      `docs/development/testing-workflow.md` gained the placement rule, and two stale sentences
      in it were corrected.
- [x] Task 6 — measure, and prove the way back. Commit `865d983f`. Five warm runs, all 64 tests
      passing: 117.67 / 107.18 / 110.60 / 115.48 / 98.23. Median 110.60 s, mean 109.83 s, max
      117.67 s. Against the honest serial number of 257.14 s that is 2.33 times faster, and it
      beats the design's target of a median under 160 s. The serial fallback run passed, so the
      way back is proven rather than assumed.
- [x] Task 7 — the soak. 30 of 30 passed, every run with 64 tests and no failure line. No new
      flaky test appeared, so nothing was filed. Backlog 126 found a latent flake the moment it
      went parallel; this suite did not.

All seven tasks are done. The plan is finished.
