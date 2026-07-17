# Replace 4-min coverage pre-push hook with quick checks

## Context

The pre-push hook (`.githooks/pre-push.ps1`) runs `scripts/run-coverage.ps1`: full restore, clean Release build with build servers disabled, SQL test container, all test projects with coverage collection, reportgenerator, and a Python threshold gate — ~4 minutes per push. CI (`ci.yml`) already runs the identical coverage + threshold gate on every PR, so the hook is fully redundant; its only value is earlier feedback. It slows every push (and background agent pushes have historically been killed by timeouts mid-hook, corrupting `obj/`).

Decision: replace the hook payload with quick checks — incremental build + format check + container-free unit tests — targeting ≤60–90s warm. No testcontainers. CI remains the authoritative coverage gate; `run-coverage.ps1` stays available on demand.

Key discovery: `scripts/test-fast.ps1 -Mode Fast` already defines the container-free test slice (Domain.Tests, TestUtilities.Tests, UI.Blazor.Tests, Application.Tests `Category!=Integration`, CLI.Tests `Category!=Integration`). Reuse it rather than duplicating a project list.

## Changes

### 1. New `scripts/pre-push-quick-checks.ps1`

Named after its sole caller. Thin fail-fast orchestrator, dot-sources `scripts/Common.ps1` for `Write-Step`/`Write-Success`:

1. `dotnet build --configuration Release` — incremental, build servers ON (no `--disable-build-servers`, no `UseSharedCompilation=false`, no clean, implicit restore)
2. `dotnet format --verify-no-changes --no-restore` — mirror the exact format command `ci.yml` runs (read ci.yml during implementation for parity)
3. Delegate tests to `& (Join-Path $PSScriptRoot 'test-fast.ps1') -Mode Fast -Configuration Release` — no coverage collection, no SQL container

Each failure names the failing step and reminds: CI still runs the full coverage gate; skip with `SKIP_PUSH_HOOK=1 git push` or `git push --no-verify`.

### 2. Edit `.githooks/pre-push.ps1`

- Call `scripts/pre-push-quick-checks.ps1` (resolved from `git rev-parse --show-toplevel`, same as today) instead of `run-coverage.ps1`
- Skip variable: new `SKIP_PUSH_HOOK`; keep honoring legacy `SKIP_COVERAGE_HOOK`
- Update messaging ("quick checks" instead of "coverage verification")
- `.githooks/pre-push` (sh shim) unchanged

### 3. Docs

- `scripts/README.md` — add `pre-push-quick-checks.ps1` row under "User-facing — local dev & test"
- `docs/development/testing-workflow.md` and `docs/development/coverage.md` — update mentions of the pre-push hook running coverage / `SKIP_COVERAGE_HOOK`

### 4. Agent memory (out-of-repo follow-up)

Update the agent memory note about background pushes and the ~4-min hook — obsolete once merged (hook drops to ≤90s).

## Gotcha: hooksPath points at the main checkout

`core.hooksPath` is an absolute path into the main checkout (branch `main`). Pushes from worktrees run the OLD hook until this branch merges. So:

- Verify the new behavior by invoking `scripts/pre-push-quick-checks.ps1` and `.githooks/pre-push.ps1` directly from the worktree
- When pushing this branch, use `SKIP_COVERAGE_HOOK=1 git push` (legitimate: CI gates the PR)

## Verification

1. Run `scripts/pre-push-quick-checks.ps1` twice; record cold and warm times — warm must be ≤90s
2. Confirm no SQL container is started (`docker ps` during run)
3. Failure paths: temporarily break formatting → step 2 fails with clear message; revert
4. `SKIP_PUSH_HOOK=1` and legacy `SKIP_COVERAGE_HOOK=1` both short-circuit the hook (invoke `.githooks/pre-push.ps1` directly)
5. `run-coverage.ps1` untouched — `git diff` shows no changes to it or `ci.yml`

## Unresolved questions

- None blocking. Legacy `SKIP_COVERAGE_HOOK` kept as alias (decided); test slice = test-fast Fast mode (decided); name = `pre-push-quick-checks.ps1` (decided).
