# Progress — backlog 075, commands skill and recap rules

Plan: `docs/superpowers/plans/2026-09-18-commands-skill-and-recap-rules-plan-075.md`

One line per finished task, written after its deliverable commit.

- [x] Task 1 — rules in `workflow.md` sections 6-7, `AGENTS.md` section, `CONTEXT.md` term,
      `.agents/handover-commands/SKILL.md`, mirrors, `tests/HandoverRules.Tests.ps1`. Commit
      `efa9aaa0`. Red run recorded first: 6 of 6 cases failed exactly as the plan predicted.
      Green run after: 6 of 6 passed. Mutation ("runs from any directory" -> "runs from one
      directory") turned only the quote-drift case red, then restore turned the suite green
      again with a clean tree. The mirror script must run with the shell's cwd inside the
      worktree — `git rev-parse --show-toplevel` reads cwd, not the script's own path, so a
      first attempt from outside the worktree silently synced main's skills instead and never
      touched `.agents/handover-commands`. No damage: main's skill set already matched, so
      nothing there changed. Re-ran with cwd in the worktree; the four expected new paths and
      the Codex plugin version bump appeared.

- [x] Task 2 — `.claude/hooks/stop-next-step.ps1` and `tests/StopNextStepHook.Tests.ps1`.
      Commit `e0a0d23d`. Red run recorded first: `FAILED: 14 test(s)`, matching the plan exactly
      (the hook did not exist, so every case that shells out failed with exit 64, and the module
      case failed with "Test-HumanPrompt is not recognized"). Green run after: 14 of 14 passed.

      **Two mutations, both proven.** Changing `'^Next:(.*)$'` to `'^Nextx:(.*)$'` turned exactly
      the three predicted cases red ("Next: with a step on the same line", "Bold **Next:**",
      "Next: followed by two list items"); the other 11 stayed green, including both refusal
      cases, because a hook that no longer recognises `Next:` still recognises `Nothing pending.`
      and still refuses a bare `Next:` (no match either way). Restored, green again. Deleting
      `if (Test-HumanPrompt -Record $record) { return $false }` from `Get-LineVerdict` turned
      exactly the predicted case red ("A turn with no tool call is allowed, even after a tool
      turn"): with the human-prompt branch gone, the reader walks past the human line into the
      prior tool call and refuses wrongly. Restored, green again, clean tree both times.

- [x] Task 3 — registered `.claude/hooks/stop-next-step.ps1` under `Stop` in
      `.claude/settings.json`. Commit `ed7655da`. Red run recorded first: the new settings case
      failed with ".claude/settings.json has no Stop hook." as predicted. After registering,
      all 15 cases passed, `.claude/settings.json` still parses, and
      `WorktreePowerShellHost.Tests.ps1` still passes. From this commit, a Claude Code session
      that loads these settings runs the hook at every turn end; the live check waits for
      Verify, as the plan says.

- [x] Task 4 — metric comment in `scripts/measure-process-friction.ps1`, three moved citations
      in `docs/development/cleanup-event-identity.md`, `Sessions:` block in
      `.github/PULL_REQUEST_TEMPLATE.md`, both baselines, five moved citations in the spec.
      Repo-side commit `f0b8d53d`, spec commit `c89f2ed` (plans repository, committed from
      outside the worktree).

      **All line-number predictions verified against the live tree before writing them, not
      copied from the plan.** `Test-HumanTurn`/`Get-MessageKey`/`Get-CleanupEventLine` landed at
      186/270/406 exactly as predicted. The five spec citations landed at 965/948/133/128/186,
      matching the plan's table exactly. `check-citation-freshness.ps1` passed for the public
      repository, the spec, and the plan. `ProcessFriction.Tests.ps1`,
      `CleanupEventScripts.Tests.ps1` and `StopNextStepHook.Tests.ps1` (its parity case loads
      the edited script) all passed. Baselines measured: `HandoverRules.Tests.ps1` 0.5s,
      `StopNextStepHook.Tests.ps1` 5.5s (it shells out 14 times).

      **Full Gate run.** `scripts/test-fast.ps1 -Mode PowerShell`: all 74 suites passed,
      including both new ones, alongside another session's concurrent worktree suite run
      sharing the same Lane pool.

All four tasks are done. The plan is finished, pending the live check (a fresh Claude Code
session) and Verify/Document/Ship.
