# 071 - Development process artifacts

## Metadata

- **Epic**: Development process
- **Type**: Process / documentation
- **Interfaces**: none (docs, backlog, AGENTS.md, .claude/CLAUDE.md)
- **Difficulty**: complex
- **Stage**: 4-execute

## Summary

Write the canonical development process (wave 1): `docs/development/workflow.md`, the HTML
decision tree, the one-page PDF cheatsheet, the reusable design system, and reduce the
process sections of `AGENTS.md` and `.claude/CLAUDE.md` to a rule index that links to
`workflow.md`.

## User story

As the repository owner, I want one written process with a visible current stage per backlog
item, so any agent or session can name where work stands and what comes next without asking
me.

## Acceptance criteria

- [ ] `docs/development/workflow.md`: 11 stage nodes with all 8 fields, transition table
      (success, failure, blocked, not-applicable, resume edges), current-stage field rule,
      four worked walkthroughs
- [ ] `docs/development/workflow.html`: self-contained decision tree, prints cleanly,
      keyboard reachable, colour never the only signal; published as an Artifact with the
      URL recorded
- [ ] `docs/development/ahkflow-workflow-cheatsheet.html` and `docs/development/ahk-workflow.pdf`,
      generation reproducible, source-hash sidecar committed
- [ ] `docs/development/ahkflow-design-system.html` extracted from the insights-report
      visual language
- [ ] `AGENTS.md` and `.claude/CLAUDE.md` process sections reduced to links into `workflow.md`
- [ ] Stage field stamped on open items 031, 042, 070, 071
- [ ] Five friction counts measured (approximate) and recorded
- [ ] Fresh-session test run against 031, 042, and active 071; results reported
- [ ] Wave items 2–5, child items (P2 guard exception, P5 pre-commit hook, P6 CI routing),
      and the claude-code#30176 blocked item filed
- [ ] Parity check and drift guard specified precisely enough to build in wave 2

## Out of scope

- Changes to `scripts/`, `.github/workflows/`, guards, hooks, `CONTEXT.md`, `docs/adr/`, or
  any skill — later waves
- Personal `~/.claude` configuration — final wave, kept out of the repository

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` (private plans repo)
- Research: `docs/superpowers/research/2026-08-10-worktrees-and-linking-071.md` (private plans repo)
