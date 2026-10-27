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

## Memory baseline

- Date: 2026-10-27
- Commit in the `~/.claude` repository: `ee203e1a72d680e5d5f6c6c4da8ab81c24a059f6`
- Files: 53 in `projects/c--Dev-segocom-github-AHKFlowApp/memory`, `MEMORY.md` included. All
  tracked, none modified.

The `~/.claude` repository holds the memory folder as it was before this item. Any removal can be
undone from this commit.

## Removal approval

- Date: 2026-10-27
- Answer: "Approve all", given to the question "Approve deleting these 33 memory files?"
- Every row was checked first by its disposition. All 33 passed, so no row became `keep`.

The final list, 33 files:

- Documented (16): `feedback_bang_prefix_breaks_in_real_terminal`,
  `feedback_branch_completion_pr_default`, `feedback_check_plans_dir_before_implementing`,
  `feedback_local_review_before_pr`, `feedback_spec_plan_location`, `feedback_suggest_next_step`,
  `project_backlog_134_declined_on_settled_numbers`, `project_backlog_number_reuse_across_folders`,
  `project_key_vault_planned`, `project_unfiled_pdf_regeneration`,
  `project_swa_custom_domain_reminder`, `reference_claude_hook_permission_precedence`,
  `reference_claude_p_quota_refusal_exit_zero`, `reference_claude_settings_flag_loses_to_user_layer`,
  `reference_notification_sound_split`, `reference_skill_deny_ignores_typed_slash_commands`
- Obsolete (5): `feedback_guard_blocked_commit_handoff`, `feedback_line_citations_drift_in_own_edit`,
  `project_local_suite_runner_tuning`, `project_plans_repo_citation_check_fails_prepush`,
  `project_test_measurement_needs_warmup_discard`
- Planned, moved into docs (11): `feedback_closure_ticks_read_criteria_literally`,
  `feedback_git_mv_drops_unstaged_edit`, `feedback_plans_repo_commit_needs_pathspec`,
  `project_adr_numbers_collide_across_branches`, `project_agents_flat_skill_layout`,
  `project_citation_check_skips_plans_by_default`, `project_citation_phrase_rejects_quotes`,
  `project_merging_main_breaks_plan_citations`, `project_unfiled_nested_worktree_creation`,
  `reference_ahk_docs_source`, `reference_xunit_theory_id_tooling`
- Merged (1): `project_entered_worktree_blocks_pwsh`, into
  `project_worktree_guard_blocks_git_not_file_writes`

## Notes / dependencies

- Filed by backlog 188 at its Plan stage. Spec section 4.2.
- The audit behind the sort is in
  `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/memory-and-instructions.md`.
  Its sort is a list of candidates, not decisions.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: `docs/superpowers/plans/2026-10-27-prune-memories-and-instruction-files-plan-192.md`
