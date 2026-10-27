# 192 - Prune memories and instruction files

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (memory files, repository instruction files)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The always-loaded instructions are about 15,400 tokens, and the memory folder holds 50 files. An
audit sorted the memories into 7 keep, 8 update, 20 delete and 15 move into docs. This item
applies the sort after the user approves it, and trims the instruction files that repeat
`docs/development/workflow.md`.

## User story

As the developer of this repository, I want the memories and instructions that load into every
session to be short and current, so that sessions spend their context on the work.

## Acceptance criteria

Each criterion is refined in the spec named below. Tick a box only when its words hold literally.

- [ ] The `~/.claude` repository holds a commit of the memory folder
      `~/.claude/projects/c--Dev-segocom-github-AHKFlowApp/memory/` as it was before this item,
      and the item records that commit's hash.
- [ ] The user approved the removal list before any memory file was deleted, and the item records
      that approval.
- [ ] A memory that moved into docs went to a file that is not always loaded.
- [ ] A rule that a script already enforces keeps one line in the instruction files that names the
      rule and its check. Its reasons sit in the check's own docs or in an ADR.
- [ ] `AGENTS.md` and `.claude/CLAUDE.md` no longer repeat text that `workflow.md` holds.
- [ ] The user-level files `~/.claude/CLAUDE.md`, `RTK.md` and `CLI-TOOLS.md` are unchanged. The
      item lists findings about them for the user.

## Out of scope

- The stage merge and the review checkpoint (backlog 191).
- Any user-level file outside the memory folder.

## Notes / dependencies

- Filed by backlog 188 at its Plan stage. Spec section 4.2.
- The audit behind the sort is in
  `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/memory-and-instructions.md`.
  Its sort is a list of candidates, not decisions.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: `docs/superpowers/plans/2026-10-27-prune-memories-and-instruction-files-plan-192.md`
