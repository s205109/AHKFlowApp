# 179 - Upstream skill block lives in committed settings

## Metadata

- **Epic**: Agent tooling
- **Type**: Chore
- **Interfaces**: none (Claude Code settings, hook script)
- **Difficulty**: moderate
- **Stage**: 5-simplify

## Summary

The repository keeps adapted forks of eight upstream `mattpocock-skills` skills, named `mp-*`.
The rule that blocks the upstream versions lives only in a personal `.claude/settings.local.json`,
which only the main checkout can see. A session started inside a worktree therefore can run the
upstream skills. This item moves the block into the committed `.claude/settings.json`, so it
applies in every session.

## User story

As a maintainer, I want the upstream versions of the forked skills blocked in every session, so
that an agent or a typed slash command in a worktree never runs instructions that point at the
wrong files.

## Acceptance criteria

- [ ] `.claude/settings.json` holds one `Skill(mattpocock-skills:<name>)` entry in
      `permissions.deny` for each `.agents/mp-*` fork, and no other `mattpocock-skills` entry.
- [ ] `.claude/settings.json` registers `.claude/hooks/block-upstream-mp-forks.ps1` under
      `UserPromptExpansion`, with a matcher that matches every fork and no other skill.
- [ ] `.claude/hooks/block-upstream-mp-forks.ps1` is in the repository. It exits 2 and names
      the `mp-` fork, including when the payload has no `command_name`.
- [ ] `tests/BlockUpstreamMpForksHook.Tests.ps1` is listed in `tests/powershell-suites.json`
      and passes.
- [ ] In a session started inside a worktree, with no `.claude/settings.local.json`, `/hooks`
      lists this worktree's `.claude/settings.json` registration as the only
      `UserPromptExpansion` hook. In that session the agent's call to
      `Skill(mattpocock-skills:grilling)` returns a permission denial, the typed
      `/mattpocock-skills:grilling` is blocked with a message that names `/mp-grilling`, and
      `/mp-grilling` still loads.

## Out of scope

- Removing the same rules from the personal `AHKFlowApp.settings.local.json` after the merge.
  That is personal cleanup and has no box here.
- `mattpocock-skills:handoff` and `mattpocock-skills:wait-what`. They stay reachable on purpose,
  because backlog 125 deleted the repository's copies.
- Codex and Copilot. Only Claude Code reads `.claude/settings.json`, and the upstream plugin is a
  Claude Code plugin.

## Notes / dependencies

- Phase 2 of the personal plan
  `docs/superpowers/personal/plans/2026-10-13-plan-file-prompts-and-split-settings-plan.md`.
  Phase 1 of that plan changed personal settings only.
- A `Skill(...)` deny gates only the agent's `Skill` tool. It does not stop a slash command the
  human types. The `UserPromptExpansion` hook with exit code 2 does.
- The personal hook at `C:\Users\btase\.claude\hooks\block-upstream-mp-forks.ps1` is the source
  for the repository copy.
- Spec: none — moderate work, the personal plan carries the design.
- Plan: `docs/superpowers/plans/2026-10-13-upstream-skill-block-committed-plan-179.md`

## Live check evidence

Run on 2026-10-13 by the human, in a fresh session started inside this worktree at `554da4d4`.
The worktree had no `.claude/settings.local.json` (`Test-Path` printed `False`).

1. `claude --version`: `2.1.296 (Claude Code)`.
2. `/plugin`: `mattpocock-skills` installed and enabled. The human reported a pass and pasted no
   text.
3. `/hooks`, `UserPromptExpansion`: one hook, from this worktree's project settings. The human
   reported a pass and pasted no text. Step 5 supports it: the block message names the
   repository's exec-form command, not the personal hook path, and only one block message
   appeared.
4. Agent `Skill` calls. Both returned the same denial:
   `Skill(mattpocock-skills:tdd)` (control) → `Error: Skill execution blocked by permission rules`.
   `Skill(mattpocock-skills:grilling)` → `Error: Skill execution blocked by permission rules`.
5. Typed `/mattpocock-skills:grilling` was blocked:

   ```text
   UserPromptExpansion operation blocked by hook:
   [pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ${CLAUDE_PROJECT_DIR}/.claude/hooks/block-upstream-mp-forks.ps1]: Blocked in AHKFlowApp. Use /mp-grilling instead of /mattpocock-skills:grilling.
   ```

   The matcher needs the `mattpocock-skills:` prefix, so this also proves that `command_name`
   carries the plugin scope.
6. Typed `/mp-grilling` loaded the fork from this worktree's `.claude/skills/mp-grilling`, with
   no block.
