# Progress — backlog 132, parallel E2E stacks

Plan: `docs/superpowers/plans/2026-09-09-parallel-e2e-stacks-plan-132.md`

The human chose to stop after Task 4. Tasks 5 to 7 wait for their go-ahead.

One line per finished task, written after its deliverable commit.

- [x] Task 1 — one SQL server for the whole test process. Commit `9ef98383`. `ApiFactoryTests`
      passed, 1 test. The plan missed one thing: `StackFixture` calls `new ApiFactory()`, so it
      needed the assembly discriminator to keep the build green. Task 4 replaces that line.
- [ ] Task 2 — serialise host construction so Serilog cannot throw
- [ ] Task 3 — one browser install per test process
- [ ] Task 4 — four collections, four fixtures, classes moved
- [ ] Task 5 — thread cap, copy rule, written balance rule
- [ ] Task 6 — measure, and prove the way back
- [ ] Task 7 — the soak
