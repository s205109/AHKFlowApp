# 071 - Development process artifacts

## Metadata

- **Epic**: Development process
- **Type**: Process / documentation
- **Interfaces**: none (docs, backlog, AGENTS.md, .claude/CLAUDE.md)
- **Difficulty**: complex
- **Stage**: 8-review

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

- **The wave-1 file allowlist was widened by two files during review round 1**, with the
  human's approval on 2026-08-11. Spec §1 listed six new `docs/development/` files plus
  `AGENTS.md`, `.claude/CLAUDE.md`, `backlog/`, and `docs/superpowers/`. Review finding 2
  showed that `docs/development/testing-workflow.md` contradicted the corrected rule: it
  told the reader to run the gate before *opening* a pull request, while the draft pull
  request now opens at Pickup, long before the gate can run. Shipping wave 1 with that file
  unchanged would have left the exact contradiction the review had just caught. So
  `docs/development/testing-workflow.md` and `docs/development/coverage.md` were added to
  the allowlist and fixed here rather than deferred to wave 2.
  `.github/PULL_REQUEST_TEMPLATE.md` followed for the same reason: its checklist item was
  the last place still calling the gate a "pre-PR" gate, and a checklist is where a reader
  meets the rule.
  Review round 6 added `scripts/check-plan-workflow-parity.ps1`, the first `scripts/` change in
  this wave. Three consecutive rounds found Appendix A drifting from the source, each caught
  by hand and each fixed only where the review pointed. The check finds it in seconds and
  exits non-zero, so the next round cannot repeat that; leaving it in a scratchpad would
  have thrown away the one artifact that stops the defect recurring.
  Review round 2 added `.gitattributes` as well. This item's own criterion requires the PDF
  generation to be **reproducible**, and it was not: `core.autocrlf=true` with no HTML rule
  meant a clean clone checked the cheatsheet out as CRLF, whose hash differs from the
  committed sidecar. `*.html text eol=lf` makes the criterion true here rather than leaving
  it open for wave 2.
- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` (private plans repo)
- Research: `docs/superpowers/research/2026-08-10-worktrees-and-linking-071.md` (private plans repo)
- Plan: `docs/superpowers/plans/2026-08-10-development-process-plan-071.md`
