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
