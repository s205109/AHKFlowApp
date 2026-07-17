# Replace 4-min coverage pre-push hook with quick checks

## Context

The pre-push hook (`.githooks/pre-push.ps1`) runs `scripts/run-coverage.ps1`: full restore, clean Release build with build servers disabled, SQL test container, all test projects with coverage collection, reportgenerator, and a Python threshold gate — ~4 minutes per push. CI (`ci.yml`) already runs the identical coverage + threshold gate on every PR, so the hook is fully redundant; its only value is earlier feedback. It slows every push (and background agent pushes have historically been killed by timeouts mid-hook, corrupting `obj/`).

Decision: replace the hook payload with quick checks — incremental build + container-free unit tests — targeting ≤90s warm (expected ~50–70s). No testcontainers, no format check (post-edit hooks auto-format locally; CI's `dotnet format AHKFlowApp.slnx --verify-no-changes` gates the PR — a local re-check measured ~40s warm for near-zero catch rate). CI remains the authoritative coverage gate; `run-coverage.ps1` stays available on demand.

Key discovery: `scripts/test-fast.ps1 -Mode Fast` already defines the container-free test slice (Domain.Tests, TestUtilities.Tests, UI.Blazor.Tests, Application.Tests `Category!=Integration`, CLI.Tests `Category!=Integration`). Reuse it rather than duplicating a project list.

### Supersedes

This plan supersedes the 2026-06-21 faster-local-test-workflow assumption that "pre-push full coverage stays mandatory by default" (`docs/superpowers/plans/2026-06-21-faster-local-test-workflow.md`). Since then the CI coverage + threshold gate runs on every PR, making the local gate redundant; the ~4-min hook cost outweighs its earlier-feedback value. Reversal explicitly approved 2026-07-17.

## Changes

### 1. New `scripts/pre-push-quick-checks.ps1`

Named after its sole caller. Thin fail-fast orchestrator, dot-sources `scripts/Common.ps1` for `Write-Step`/`Write-Success`:

1. `dotnet build --configuration Release` — incremental, build servers ON (no `--disable-build-servers`, no `UseSharedCompilation=false`, no clean, implicit restore)
2. Delegate tests to `& (Join-Path $PSScriptRoot 'test-fast.ps1') -Mode Fast -Configuration Release -NoBuild` — no coverage collection, no SQL container

Each failure names the failing step and reminds: CI still runs the full coverage + format gate; skip with `SKIP_PUSH_HOOK=1 git push` or `git push --no-verify`.

### 1b. Add `-NoBuild` switch to `scripts/test-fast.ps1`

Review measured ~111s warm because each of the five `dotnet test` invocations re-runs implicit restore/build after the solution was already built. Add an opt-in `[switch]$NoBuild` that appends `--no-build` to the `dotnet test` arguments (`Invoke-TestRun`), passed by the quick-checks script after its successful solution build. Default behavior unchanged for standalone use. Remeasure after implementation.

### 2. Edit `.githooks/pre-push.ps1`

- Call `scripts/pre-push-quick-checks.ps1` (resolved from `git rev-parse --show-toplevel`, same as today) instead of `run-coverage.ps1`
- Skip variable: new `SKIP_PUSH_HOOK`; keep honoring legacy `SKIP_COVERAGE_HOOK`
- Update messaging ("quick checks" instead of "coverage verification")
- `.githooks/pre-push` (sh shim) unchanged

### 3. New `tests/PrePushHook.Tests.ps1` + CI wiring

Durable regression test following the existing `tests/*.Tests.ps1` pattern. Harness: `git init` a temp repo containing a stub `scripts/pre-push-quick-checks.ps1` that records invocation and exits with a configurable code; run `.githooks/pre-push.ps1` from it. Cover:

- `SKIP_PUSH_HOOK=1` and legacy `SKIP_COVERAGE_HOOK=1` both short-circuit (exit 0, stub not invoked)
- Repo root resolved from the working tree being pushed (`git rev-parse --show-toplevel`), not the hook's own location
- Nonzero stub exit code propagates as hook failure
- `run-coverage.ps1` is never invoked (stub it too; assert no invocation)

Wire into the `worktree-powershell-tests` job in `ci.yml` alongside the existing `.Tests.ps1` entries.

### 4. Docs

- `scripts/README.md` — add `pre-push-quick-checks.ps1` row under "User-facing — local dev & test"
- `docs/development/testing-workflow.md` and `docs/development/coverage.md` — update mentions of the pre-push hook running coverage / `SKIP_COVERAGE_HOOK`

### 5. Agent memory (out-of-repo follow-up)

Update the agent memory note about background pushes and the ~4-min hook — obsolete once merged (hook drops to ≤90s).

## Gotcha: hooksPath points at the main checkout

`core.hooksPath` is an absolute path into the main checkout (branch `main`). Pushes from worktrees run the OLD hook until this branch merges. So:

- Verify the new behavior by invoking `scripts/pre-push-quick-checks.ps1` and `.githooks/pre-push.ps1` directly from the worktree
- When pushing this branch, use `SKIP_COVERAGE_HOOK=1 git push` (legitimate: CI gates the PR)

## Verification

1. Run `scripts/pre-push-quick-checks.ps1` twice; record cold and warm times — warm must be ≤90s (expected ~50–70s with `-NoBuild` dedup)
2. Confirm no SQL container is started (`docker ps` during run)
3. Failure path: temporarily break a Domain test → hook fails with clear step message; revert
4. `pwsh ./tests/PrePushHook.Tests.ps1` passes locally (covers skip vars, root resolution, exit propagation, no run-coverage invocation)
5. `test-fast.ps1 -Mode Fast` without `-NoBuild` still works (default unchanged)
6. `run-coverage.ps1` untouched; `ci.yml` diff limited to the `worktree-powershell-tests` job addition

## Unresolved questions

- None blocking. Decided: legacy `SKIP_COVERAGE_HOOK` kept as alias; test slice = test-fast Fast mode with new `-NoBuild`; name = `pre-push-quick-checks.ps1`; format check dropped from hook (CI + post-edit hooks own it); June-21 mandatory-coverage assumption explicitly superseded; hook test at full reviewer scope wired into `worktree-powershell-tests`.
