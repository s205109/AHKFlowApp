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
      normalized text. Hashing the raw bytes makes the result depend on the checkout: this
      repository sets `core.autocrlf=true` and `.gitattributes` carries no `*.html` rule,
      so the same file is `590125CF…75F0F` with LF and `168A95B6…01625` with CRLF.
- [ ] `.gitattributes` gains `*.html text eol=lf`, so the working copy stops depending on
      the platform. The normalized hashing above stays regardless — it is what makes the
      check correct rather than merely consistent on one machine.
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
- [ ] `docs/development/testing-workflow.md` renames its "Canonical pre-PR gate" heading to
      name what the gate actually gates: the pull request going **ready**, not the pull
      request being created. The draft pull request opens at Pickup, long before the gate
      runs. Its opening line, "run the full coverage gate yourself before opening a PR",
      changes with it. `workflow.md` and `AGENTS.md` already say "before ready"; this file
      is the last one still saying "before you open a PR". It fell outside the wave-1 file
      allowlist, which is why it was not fixed there.

## Friction baselines

Measured once by backlog 071, on 2026-08-11. **Every number is approximate.** The window is
2026-07-28 to 2026-08-11 — the last two weeks. The sources are 244 local session transcripts,
the worktree removal log, and the GitHub run history. Wave 3 to wave 5 targets are stated
against these numbers.

| Count | Baseline | Method |
|---|---|---|
| Blocked-agent handoffs | about 570 messages across 80 sessions | Transcript lines matching `AHKFLOW_ALLOW_MAIN`, `cannot commit`, `agent-worktree-main-write`, or the isolation refusal text. A broader pattern that also counts `run these` and `Copy-Item` gives 602 messages across 91 sessions, so read 570 as the lower bound |
| Directory-bound commands handed to the human | about 2750 commands across 153 sessions | Command lines inside fenced `powershell`, `bash`, or `sh` blocks that start with `git`, `gh`, `dotnet`, `pwsh`, or `npm` and carry no `git -C`, no `--repo`, no `--project`, and no absolute path. 3197 fenced commands were examined, so about 86 percent were directory-bound |
| Cleanup popups and blocked runs | 107 events | `.claude/worktrees/worktree-removal.log`: 16 lines matching `cannot access the file` plus 91 lines matching `timed out` or `timeout` |
| Next-step asks | about 160 messages across 69 sessions | Transcript lines with a user role that also match `what ... next`, `next step`, `wat nu`, or `hoe verder` |
| CI minutes on non-.NET changes | about 143 job minutes over 26 runs | 96 `ci.yml` runs in the window. A run qualifies only when its PR changed no `*.cs`, `*.razor`, `*.csproj`, `*.props`, `*.targets`, `*.sln`, or `global.json` — kind, not location — and every remaining file matches `**/*.md`, `docs/**`, `.claude/**`, `.pr_agent.toml`, `.github/workflows/**`, `.githooks/**`, or `scripts/**/*.ps1`. Minutes are the summed job durations from `completedAt` minus `startedAt` |

Known limits of these numbers. A transcript line is one message, so a message that hands
over three commands counts as one match for count 1 and as three for count 2. Counts 1 and
4 use text patterns, so they catch discussion of a handoff as well as a handoff. Count 5
measures wall-clock job duration, not billed runner minutes.

## Out of scope

- Cleanup user experience — that is wave 3 (backlog 073).
- CI routing for configuration-only changes — that is wave 4 (backlog 074).
- The commands skill and recap rules — that is wave 5 (backlog 075).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §10 and §13
  (private plans repo).
- The parity comparison model and the drift-guard rule are already specified in §10. This
  item implements them; it does not redesign them.
