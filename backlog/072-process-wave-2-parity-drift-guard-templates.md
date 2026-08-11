# 072 - Process wave 2 - parity, drift guard, templates

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs, backlog template)
- **Difficulty**: complex
- **Stage**: 1-pickup
- **Depends on**: 071-development-process-artifacts, 076-guard-exception-commit-to-plans-repo-from-worktree, 077-pre-commit-refusal-of-human-commits-on-main

## Summary

Wave 2 of the development process. Wave 1 wrote the process down in three places.
Wave 2 keeps those three places from drifting apart, adds Difficulty to the backlog
template and the filing script, and records the process vocabulary.

## User story

As a contributor, I want the process documents checked by a script so that a change to
one of them can never leave the other two behind.

## Acceptance criteria

- [ ] A PowerShell suite check compares `docs/development/workflow.md`,
      `docs/development/workflow.html`, and
      `docs/development/ahkflow-workflow-cheatsheet.html`. It compares stage names and
      order, exit conditions, and next-stage labels including failure edges. It fails on
      any disagreement and names the losing file and line. `workflow.md` wins.
- [ ] The check builds the legal edge-target set from the 11 stage ids it extracts, plus
      `2-design/3-plan/4-execute`, `stay`, `terminal`, `blocked/`, and `none`. Every edge
      target must be a case-sensitive member of that set.
- [ ] The check recomputes the SHA-256 of the cheatsheet HTML and compares it against
      `docs/development/ahk-workflow.pdf.source.sha256`. A mismatch means the PDF is
      stale. It also checks that the PDF page tree contains `/Count 1`.
- [ ] A drift guard scans the process sections of `AGENTS.md`. It fails on a rule line
      without a `docs/development/workflow.md#stage-N-name` anchor, and on an anchor that
      does not exist in `workflow.md`.
- [ ] `backlog/000-backlog-item-template.md` carries a `- **Difficulty**:` line and a
      `- **Stage**:` line.
- [ ] `scripts/new-backlog-item.ps1` writes both lines into every new item.
- [ ] `.claude/CLAUDE.md` is aligned line by line with `workflow.md`. No rule appears in
      both with different wording.
- [ ] The private-plan status visibility question is investigated and the finding is
      written down: how a session sees the stage of work whose plan lives in the private
      repo.
- [ ] `CONTEXT.md` gains the terms stage, edge, wave, difficulty, housekeeping worktree,
      and emitter.
- [ ] `docs/adr/` gains one ADR: process canon lives in `workflow.md`.
- [ ] The friction baseline table below is filled by backlog 071 task 8.

## Friction baselines

Measured once in wave 1, approximate, from the last two weeks of transcripts and
repository history. Wave 3 to wave 5 targets are stated against these numbers.

| Count | Baseline | Method |
|---|---|---|
| Blocked-agent handoffs | | |
| Directory-bound commands handed to the human | | |
| Cleanup popups and blocked runs | | |
| Next-step asks | | |
| CI minutes on non-.NET changes | | |

## Out of scope

- Cleanup user experience — that is wave 3 (backlog 073).
- CI routing for configuration-only changes — that is wave 4 (backlog 074).
- The commands skill and recap rules — that is wave 5 (backlog 075).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §10 and §13
  (private plans repo).
- The parity comparison model and the drift-guard rule are already specified in §10. This
  item implements them; it does not redesign them.
