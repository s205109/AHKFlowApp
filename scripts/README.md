# scripts/

Repository automation. User-facing scripts sit at the top level; internal
tooling lives in `ci/` and `agents/`. Worktree-contract files stay flat here
and must be changed as one set (see below).

## User-facing — deployment

| Script | Purpose |
| --- | --- |
| `deploy.ps1` | Provisions an AHKFlowApp Azure environment and configures CI/CD. |
| `teardown.ps1` | Tears down an AHKFlowApp Azure environment. |
| `update.ps1` | Publishes and package-deploys the current API code to an existing environment. |
| `setup-entra-app.ps1` | Idempotent Entra ID app registration setup for AHKFlowApp. |
| `setup-dev-entra.ps1` | Configures local-dev Entra ID app registration and wires local config. |
| `open-test-in-browser.ps1` | Opens the TEST frontend/API URLs from `.env.test`. |
| `open-prod-in-browser.ps1` | Opens the PROD frontend/API URLs from `.env.prod`. |

## User-facing — local dev & test

| Script | Purpose |
| --- | --- |
| `test-fast.ps1` | Runs explicit local test slices (fast, integration, E2E, coverage). |
| `run-coverage.ps1` | Runs tests with coverage, builds the merged report, enforces the CI coverage gate. |
| `measure-tests.ps1` | Measures test project, class, test, and SQL fixture setup timings. |
| `kill-dev-ports.ps1` | Frees the dev-server ports so `dotnet run` doesn't fail with "address already in use". |
| `publish-cli.ps1` | Publishes the `ahkflow` CLI as a native single-file executable with baked-in API/auth config. |
| `new-worktree.ps1` | Creates a git worktree and applies AHKFlowApp local-dev isolation. |

## CI-internal (`ci/`)

| Script | Purpose |
| --- | --- |
| `ci/check-coverage-thresholds.py` | Enforces per-assembly line/branch thresholds from the merged Cobertura report. |
| `ci/generate-changelog-json.ps1` | Regenerates the in-app changelog asset from `CHANGELOG.md` (requires PowerShell 7). |

## Agent tooling (`agents/`)

| Script | Purpose |
| --- | --- |
| `agents/setup-copilot-symlinks.ps1` | Thin wrapper that runs `setup-cross-agent-skills.ps1`. |
| `agents/setup-cross-agent-skills.ps1` | Builds repo-local cross-agent skill links from `.agents/` (Windows). |
| `agents/setup-cross-agent-skills.sh` | Same, for POSIX shells. |
| `agents/check-symlinks.ps1` | Lists link type/target/attributes under a path, for verifying skill links. |
| `agents/create-github-issues.ps1` | Historical one-time backlog seeding (issues long created); kept for reference. |

## Worktree internals — contract, do not reorganize

These form one contract: change them together or not at all. They stay flat in
`scripts/`.

| File | Purpose |
| --- | --- |
| `setup-worktree-local-dev.ps1` | Assigns deterministic localhost ports and writes worktree-local config. |
| `remove-worktree-local-dev.ps1` | WorktreeRemove hook: deletes the worktree + branch when a worktree is removed. |
| `cleanup-merged-worktrees.ps1` | Detects worktrees merged into `main` and removes the clean ones on opt-in (`-Cleanup`, `AHKFLOW_WORKTREE_CLEANUP=1` for Claude CLI native worktree creation, or the interactive prompt); invoked by `new-worktree.ps1` before it creates a worktree. |
| `prune-worktree-databases.ps1` | Drops orphaned per-worktree databases with no live git worktree. |
| `prune-worktree-docker.ps1` | Removes orphaned per-worktree Docker compose projects with no live git worktree. |
| `worktree-{database,docker,git,json,log,powershell}.common.ps1` | Shared helpers dot-sourced by the worktree scripts. |

Config: `.env.worktree` holds the per-worktree port/config template; `.env.local`
(gitignored) holds a developer's local overrides; the repo-root `.worktreeinclude`
lists ignored local files `new-worktree.ps1` copies into a new worktree.

## Shared helpers

| File | Purpose |
| --- | --- |
| `Common.ps1` | Shared output and prerequisite helpers for the deployment scripts. |
| `_open-env.ps1` | `Open-Env` helper that reads a saved `.env.<env>` and opens its URLs. |
| `test-sql-container.common.ps1` | Shared SQL Server Testcontainer settings for the coverage/test scripts. |
