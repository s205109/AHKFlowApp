# Cross-Agent Worktree Guardrails

## Summary

Store the replacement plan in a new managed worktree and branch, then remove the obsolete worktree and branch. Main remains read-only during planning.

New locations:

- Worktree: `.claude/worktrees/cross-agent-worktree-guardrails`
- Branch: `feature/wt-cross-agent-worktree-guardrails`
- Plan: `docs/superpowers/plans/2026-07-20-cross-agent-worktree-guardrails-plan.md`

Plan Mode prohibits repository mutations, so these actions remain pending execution.

## Worktree and Plan Lifecycle

1. From main, create the worktree exclusively through:

   ```powershell
   pwsh -NoProfile -File scripts/new-worktree.ps1 `
     -Name cross-agent-worktree-guardrails `
     -BranchName feature/wt-cross-agent-worktree-guardrails
   ```

2. Save this complete plan under the new filename and verify the managed-worktree manifest.
3. Commit it as `docs: plan cross-agent worktree guardrails`.
4. Confirm the new commit and plan file before deleting anything.
5. Force-remove `.claude/worktrees/agent-worktree-guard` using `remove-worktree-local-dev.ps1`.
6. Force-delete the obsolete unmerged branch `feature/wt-agent-worktree-only-enforcement`, as explicitly authorized.
7. Run Git worktree pruning and the repository's orphaned database/Docker cleanup scripts.
8. Verify only the new worktree and branch remain and the main checkout is clean.

## Enforcement Design

- Add a launcher:

  ```powershell
  .\scripts\agents\start-agent-worktree.ps1 `
    -Agent Claude|Codex|Copilot `
    -BranchName fix/wt-<topic> `
    [-AgentArguments <string[]>] `
    [-NoLaunch] `
    [-Cleanup]
  ```

- Require a complete `feature/wt-*`, `fix/wt-*`, or `hotfix/wt-*` branch name.
- Delegate creation and setup to `scripts/new-worktree.ps1`; validated existing worktrees are reused.
- Classify a writable worktree by Git linkage, allowed location, and a valid `scripts/.env.worktree` manifest.
- Allow agents read-only inspection in main. Block edits, builds, tests, formatters, unknown shell commands, branch creation, commits, and other filesystem mutations.
- Permit a narrow main-tree shell allowlist for searches, file reads, and read-only Git/GitHub queries.
- Agents may edit, build, test, commit, and push from managed worktrees.
- Set `AHKFLOW_AGENT_SESSION=1` on launched processes.
- Honor `AHKFLOW_ALLOW_MAIN=1` as a session-scoped full bypass and emit a visible warning.

## Cross-Agent Integration

- Implement one PowerShell policy core with thin Claude, Codex, and Copilot input/output adapters.
- Extend Claude `PreToolUse` coverage to Bash, Edit, Write, and write-capable MCP tools.
- Add Codex project hooks for Bash, `apply_patch`/Edit/Write, and MCP tools.
- Replace Copilot's ineffective Claude-specific Bash integration with its native stdin adapter.
- Preserve existing destructive-command protections.
- Add agent-scoped `pre-commit` and `reference-transaction` Git hooks. Human shells remain unrestricted.
- Block explicit paths and Git working-directory overrides targeting main even when the agent starts in a worktree.
- Document a thin-adapter contract for future coding agents.
- Update AGENTS guidance, the source worktree skill, setup diagnostics, and cross-agent synchronization.

## Verification

- Use temporary Git repositories for all guard tests; never create test commits in the real main checkout.
- Verify main permits reads but rejects writes, builds, tests, formatting, command chaining, redirects, branch creation, and commits.
- Verify bypass behavior and warning output.
- Verify managed worktrees allow implementation and Git operations.
- Verify unmanaged or invalid worktrees remain read-only.
- Test representative Claude, Codex, and Copilot hook payloads.
- Verify `git commit --no-verify` remains blocked by the agent-scoped ref hook.
- Verify human main-tree Git operations remain unaffected.
- Test launcher creation, reuse, branch validation, environment propagation, argument forwarding, and `-NoLaunch`.
- Run existing worktree Pester suites, cross-agent setup, Release build/tests, formatting verification, and `git diff --check`.

## Assumptions

- Version 1 covers local Windows Claude, Codex, and Copilot CLI/app/IDE surfaces.
- Hosted agents remain out of scope because they use remote clones.
- This is an accidental-misuse guardrail, not hostile-process isolation.
- The obsolete branch's two documentation-only commits may be discarded; recovery would only be possible through Git reflog until garbage collection.

## Unresolved Questions

None.
