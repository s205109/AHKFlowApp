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
- [ ] The friction baseline table below is filled by backlog 071 task 8.
- [ ] The drift guard also checks that no document tells a reader to run the gate "before
      opening a PR". The gate gates the pull request going **ready**, not its creation, and
      the wording drifted back once already. Backlog 071 fixed
      `docs/development/testing-workflow.md`, `docs/development/coverage.md`, and
      `AGENTS.md`; the guard keeps them fixed.

## Friction baselines

Measured once by backlog 071, on 2026-08-11. **Every number is approximate.** The window is
2026-07-28 to 2026-08-11 — the last two weeks. The sources are 244 local session transcripts,
the worktree removal log, and the GitHub run history. Wave 3 to wave 5 targets are stated
against these numbers.

**These numbers were re-measured on 2026-08-11 after review round 4 found the first set
invalid.** The original method pattern-matched the serialized JSONL line rather than the
parsed message, so it counted tool results as human turns, matched commands inside tool
output, and counted `Timeout=300s` configuration echoes as timeout events. The first set was
too high by roughly 5 to 20 times. Do not use it; it is recorded in git history only.

The corrected method parses each JSONL record, keeps only `text` blocks, and separates
`user` from `assistant` roles. Window unchanged: 2026-07-28 to 2026-08-11, 245 transcripts.

| Count | Baseline | Method |
|---|---|---|
| Blocked-agent handoffs | 30 messages across 18 sessions | Assistant **text** blocks matching `AHKFLOW_ALLOW_MAIN`, `cannot commit`, or `agent-worktree-main-write`. Tool results excluded — they carry the refusal text too, which is what inflated the original 570 |
| Directory-bound commands handed to the human | 120 commands across 18 sessions | Command lines inside fenced `powershell`/`bash`/`sh` blocks **in assistant text only**, starting `git`, `gh`, `dotnet`, `pwsh`, or `npm`, carrying no `git -C`, `--repo`, `--project`, or absolute path. The original 2750 counted fenced blocks appearing anywhere in the serialized record, including tool output |
| Cleanup popups and blocked runs | 16 events | `.claude/worktrees/worktree-removal.log` lines matching `cannot access the file`. **Real timed-out events: 0.** The original 107 added 91 lines matching `timeout`, every one of which was a `Timeout=300s` configuration echo, not an event |
| Next-step asks | 59 messages across 49 sessions | `user`-role **text** blocks matching `what … next`, `next step`, `wat nu`, or `hoe verder`. The original 163 included 104 tool results, which are `user`-role records but not the human speaking |
| CI minutes on non-.NET changes | **not reproducible — re-measure before use** | The classification read each PR's *current* file list, so a PR touched after measurement reclassifies and the number moves. The original 142.7 minutes over 26 runs cannot be reproduced. A valid method must classify from the files as they were at the run's own commit |

Known limits that remain. Counts 1, 2 and 4 are text patterns, so they still catch
discussion of a handoff as well as a handoff. Count 3 reads only the removal log, so a
cleanup failure that never reached the log is invisible. Count 5 needs a new method before
it means anything.

The lesson worth keeping for the wave-2 checks: a pattern run over serialized JSON measures
the transcript format, not the behaviour. Parse first, then count.

## Out of scope

- Cleanup user experience — that is wave 3 (backlog 073).
- CI routing for configuration-only changes — that is wave 4 (backlog 074).
- The commands skill and recap rules — that is wave 5 (backlog 075).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §10 and §13
  (private plans repo).
- The parity comparison model and the drift-guard rule are already specified in §10. This
  item implements them; it does not redesign them.
