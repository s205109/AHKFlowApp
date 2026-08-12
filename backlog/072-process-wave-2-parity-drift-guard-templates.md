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
- [ ] **The hash is line-ending independent.** Both the check and the sidecar generator
      read the file, replace every CRLF with LF, and hash the UTF-8 bytes of that
      normalized text. Hashing raw bytes made the result depend on the checkout: before
      round 2 this repository set `core.autocrlf=true` with no `*.html` rule in
      `.gitattributes`, and the same file hashed differently as LF and as CRLF. The
      `eol=lf` rule below fixed the working copy; normalized hashing is still required, so
      the check stays correct rather than merely consistent on one machine.
- [x] `.gitattributes` gains `*.html text eol=lf`, so the working copy stops depending on
      the platform. Done by backlog 071 in review round 2. The normalized hashing above
      stays regardless — it is what makes the check correct rather than merely consistent
      on one machine.
- [ ] A drift guard scans the process sections of `AGENTS.md`. The sections it scans are
      named explicitly: `Debugging`, `Plans`, `Verification After Implementation`, and
      `Git Workflow`, plus the `Plan before you edit` and
      `Create the worktree before you write the plan` sections of `.claude/CLAUDE.md`.
- [ ] Inside those sections the guard scans **only top-level bullet lines** — a line
      matching `^- ` at column 1. It fails on such a line without a
      `docs/development/workflow.md#stage-N-name` anchor, and on an anchor that does not
      exist in `workflow.md`.
- [ ] The guard ignores every other Markdown form, because those carry reference data
      rather than rules: table rows (`^|`), numbered list items (`^\d+\.`), indented or
      nested bullets (`^\s+- `), fenced code blocks, headings, and plain paragraphs. The
      verification routing table and the numbered exemption list in `AGENTS.md` are the
      reason this exclusion exists — they are process content that carries no anchor by
      design.
- [ ] A fixture proves both directions: an unanchored top-level bullet inside a scanned
      section fails the guard, and an unanchored table row inside the same section does not.
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
- [ ] The five friction counts are measured here, to the requirements below. Backlog 071 attempted this three times and withdrew every result; nothing is inherited.
- [ ] The drift guard also checks that no document tells a reader to run the gate "before
      opening a PR". The gate gates the pull request going **ready**, not its creation, and
      the wording drifted back once already. Backlog 071 fixed
      `docs/development/testing-workflow.md`, `docs/development/coverage.md`, and
      `AGENTS.md`; the guard keeps them fixed.

## Friction baselines

> **No baseline is published. Every attempt so far has been wrong, and measuring this
> properly is part of this item's work, not a prerequisite already met.**

Two attempts were made during backlog 071 and both were rejected in review:

1. **2026-08-10.** Pattern-matched the serialized JSONL line, so tool results counted as
   human turns, commands inside tool output counted as handed-over commands, and 91
   `Timeout=300s` configuration echoes counted as timeout events. Too high by 5 to 20 times.
2. **2026-08-11.** Parsed records and filtered to `text` blocks, which fixed the worst of it
   but still counted injected skill content as human input (it is stored as `role=user`),
   still filtered files by modification time rather than records by timestamp, still counted
   sidechain subagent messages, and still counted the same message twice when history was
   copied forward. Round 5's field-based audit found **18** in-window human next-step rows
   against the 59 published; handoffs 20 against 30; cleanup 15 against 16; commands 113
   distinct against 120 raw.

The pattern is the lesson: each attempt fixed the previous flaw and introduced or retained
another, and each produced a number confident enough to be used. So this item measures the
counts as a task with the requirements below, rather than inheriting a figure.

| Count | Baseline | Status |
|---|---|---|
| Blocked-agent handoffs | not established | Candidate figures 570, then 30, then 20 |
| Directory-bound commands handed to the human | not established | Candidate figures 2750, then 120, then 113 distinct |
| Cleanup popups and blocked runs | not established | Candidate figures 107, then 16, then 15 in-window |
| Next-step asks | not established | Candidate figures 163, then 59, then 18 |
| CI minutes on non-.NET changes | not established | 142.7 was not reproducible: it classified from each PR's *current* files, not the files at the run's own commit |

### What a valid measurement must do

Two scripts that both satisfy this list must produce the same number, so each rule names the
field it reads rather than describing an intention.

- [ ] **Window.** Select on the record's own `timestamp` field, `>= start` and `< end`, both
      in UTC. Never on file modification time.
- [ ] **Human turn.** A record counts only when `message.role == "user"` **and** at least one
      element of `message.content` has `type == "text"` **and** that record carries no
      `toolUseResult` field. Tool results and injected skill content both arrive as
      `role: user`; the `type` and `toolUseResult` tests are what separate them.
- [ ] **Sidechain.** Exclude any record with `isSidechain == true`. Report the excluded count
      alongside the result so the exclusion is visible rather than assumed.
- [ ] **Unit of count.** State it per metric and use it consistently: handoffs and next-step
      asks count **distinct `message.id`**; directory-bound commands count **command lines**,
      not messages, because one message can hand over several.
- [ ] **Deduplication.** Deduplicate on `message.id` across the whole corpus before counting,
      not per file. Copied-forward history repeats the same id in several transcripts.
- [ ] **Grouping.** "Sessions" means distinct transcript file names after deduplication, and
      a metric reports both the item count and the session count.
- [ ] **CI classification.** Resolve each run's changed files from its own
      `headSha` — `gh api repos/{owner}/{repo}/compare/{base}...{headSha}` — never from the
      pull request's current file list, which moves when the PR is touched later.
- [ ] **One primary result per metric.** Where this list allows a choice, the script fixes
      the choice and records it. An option that leaves two compliant scripts disagreeing is
      not a specification.
- [ ] Separate a real event from discussion of one, or state plainly that it does not and
      treat the figure as an upper bound.
- [ ] Publish the script with the numbers, so any figure can be reproduced and challenged.

Until those hold, wave 3 to wave 5 targets are stated as directions — fewer handoffs, fewer
directory-bound commands — not as percentages against a number.

## Out of scope

- Cleanup user experience — that is wave 3 (backlog 073).
- CI routing for configuration-only changes — that is wave 4 (backlog 074).
- The commands skill and recap rules — that is wave 5 (backlog 075).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §10 and §13
  (private plans repo).
- The parity comparison model and the drift-guard rule are already specified in §10. This
  item implements them; it does not redesign them.
