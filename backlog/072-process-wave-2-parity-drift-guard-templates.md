# 072 - Process wave 2 - parity, drift guard, templates

## Metadata

- **Epic**: Development process
- **Type**: Process / tooling
- **Interfaces**: none (scripts, docs, backlog template)
- **Difficulty**: complex
- **Stage**: 4-execute
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
- [x] A plan-versus-canon check exists: `scripts/check-plan-canon-parity.ps1` compares a
      plan's Appendix A against `workflow.md` on every stage's exit string and all five edge
      targets, and exits 1 on any difference. Added by backlog 071 in review round 6, after
      three consecutive rounds found that drift by hand. It covers the stage machine only,
      not the narrative fields.
- [ ] The plan-versus-canon check joins the gates, so drift fails a run rather than waiting
      for a reviewer. Extend it to the narrative fields — Action, Technique, Context — or
      state plainly that those stay manual.
      **Design round correction:** "joins the suite" alone is not achievable. The suite runs
      in CI, and (`.gitignore:473`, "docs/superpowers") keeps that folder out of the checkout, so CI has no
      plan to compare. The check therefore joins in two halves: the suite runs it against
      fixture plans committed here, and `scripts/pre-push-quick-checks.ps1` runs it against
      the real plans, discovering them by `## Appendix A` rather than a hardcoded path, and
      skipping with a printed reason when the plans repository is absent. The narrative
      fields stay manual.
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
- [ ] `backlog/000-backlog-item-template.md` carries a `- **Difficulty**:` line. Backlog 087
      already added the `- **Stage**:` line.
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
      opening a PR". <!-- gate-wording:ignore --> The gate gates the pull request going **ready**, not its creation, and
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
      in UTC. Never on file modification time. **The bounds are fixed at
      2026-07-15T14:14:32Z to 2026-08-12T14:14:32Z** — four weeks ending at the moment wave 1
      merged. The rules below forbid leaving a choice open, and this rule left the two values
      unstated, so two compliant scripts could disagree. A window running past the wave-1
      merge would mix old-process friction with fixed-process friction.
- [ ] **Scope.** Every AHKFlow project directory, main and worktree. Counted on 2026-08-15:
      205 transcripts in the main directory, 198 more across 83 worktree directories, 403 in
      total. Worktree sessions are where handoffs, directory-bound commands, and cleanup
      popups actually happen, so the main directory alone drops just under half the data. The
      script reports the per-directory split next to the total. This supersedes "all 195
      transcripts in this project" below, which meant the main directory and is already stale.
- [ ] **Human turn.** A record counts only when `type == "user"` **and** either
      `origin.kind == "human"` **or** `promptSource` is one of `typed`,
      `suggestion_accepted`, `queued`. The two fields are alternatives, not a pair: a
      conjunction drops real turns. Measured over all 195 transcripts in this project:

      | `promptSource` / `origin.kind` | records | human turn? |
      |---|---|---|
      | `<absent>` / `<absent>` | 8452 | no — tool results and injected content |
      | `typed` / `human` | 636 | yes |
      | `system` / `task-notification` | 203 | no |
      | `suggestion_accepted` / `human` | 17 | yes |
      | `sdk` / `human` | 15 | yes |
      | `queued` / `human` | 4 | yes |
      | `typed` / `<absent>` | 2 | yes — a typed slash command, e.g. `/logo` |
      | `sdk` / `<absent>` | 1 | no — no human field on either side |

      The rule above counts 674 records — all 672 that carry `origin.kind == "human"`, plus
      the 2 typed ones that carry no `origin` at all — and excludes the other 8656.
      Requiring `typed` **and** `human` together counts only 636, silently dropping every
      accepted suggestion, every queued prompt, and every slash command.

      Do **not** test the shape of `message.content`. A real typed prompt carries a string
      and injected content carries an array, but injected content also carries a
      `text`-typed block, so the array/text-block test does not separate them either.
- [ ] **Sidechain.** Exclude any record with `isSidechain == true`. Report the excluded count
      alongside the result so the exclusion is visible rather than assumed.
- [ ] **Unit of count.** State it per metric and use it consistently: directory-bound
      commands count **command lines**, not messages, because one message can hand over
      several.
- [ ] **Deduplication key.** `message.id` exists only on **assistant** records
      (`msg_...`); a user record carries no `message.id` at all — verified against a live
      transcript. So handoffs (assistant text) deduplicate on `message.id`; next-step asks
      (user text) deduplicate on the record's top-level `uuid` instead. Using `message.id`
      for a user-role metric silently deduplicates nothing, because the field is always
      absent and every comparison is against `null`.
- [ ] **Grouping.** "Sessions" means distinct transcript file names after deduplication, and
      a metric reports both the item count and the session count.
- [ ] **CI classification.** Resolve each run's changed files from its own `headSha`
      against its own **run-time base**, not against current `main`:
      `gh run view <id> --json headSha,headBranch` then the merge-base of that `headSha`
      and the base branch **as it stood then** —
      `gh api repos/{owner}/{repo}/compare/{base}...{headSha}` records the diff at query
      time, so comparing against today's `main` reclassifies a run every time `main` moves.
      Record the resolved base SHA next to the result so the classification is itself
      reproducible, not only the file list.
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

- Spec: `docs/superpowers/specs/2026-08-15-process-wave-2-design-072.md` (private plans repo).
  It carries the 13 decisions the Design grilling settled, and closes the two gaps this item
  left open — the measurement window and the transcript scope.
- Plan: `docs/superpowers/plans/2026-08-15-process-wave-2-plan-072.md`
- Wave-1 spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §10 and
  §13 (private plans repo).
- The parity comparison model and the drift-guard rule are already specified in §10. This
  item implements them; it does not redesign them.
