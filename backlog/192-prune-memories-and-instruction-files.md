# 192 - Prune memories and instruction files

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (memory files, repository instruction files)
- **Difficulty**: moderate
- **Stage**: 8-review

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

- [x] The `~/.claude` repository holds a commit of the memory folder
      `~/.claude/projects/c--Dev-segocom-github-AHKFlowApp/memory/` as it was before this item,
      and the item records that commit's hash.
- [x] The user approved the removal list before any memory file was deleted, and the item records
      that approval.
- [x] A memory that moved into docs went to a file that is not always loaded.
- [x] A rule that a script already enforces keeps one line in the instruction files that names the
      rule and its check. Its reasons sit in the check's own docs or in an ADR.
- [x] `AGENTS.md` and `.claude/CLAUDE.md` no longer repeat text that `workflow.md` holds.
      Ticked at Review on 2026-10-28. The reviewer ruled that the shared plans-repository commit
      command counted as repeated text. It now lives only in `workflow.md`, under **Two-repo
      transitions**; `AGENTS.md` **Plans** and `.claude/CLAUDE.md` link to it. Measured
      afterwards: no line of either file shares an 8-word run with `workflow.md`.
- [x] The user-level files `~/.claude/CLAUDE.md`, `RTK.md` and `CLI-TOOLS.md` are unchanged. The
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

## Memory cleanup result

Measured 2026-10-27. Before is the baseline commit `ee203e1a`.

| | Before | After |
|---|---:|---:|
| Memory files, `MEMORY.md` excluded | 52 | 19 |
| Their total size, bytes | 114,154 | 24,272 |
| `MEMORY.md`, characters | 10,349 | 3,742 |

- Deleted: the 33 approved files. The auto mode classifier refused the agent's delete, so the
  user runs it from a handed-over script. The After column counts the folder after that run.
  Merged: `project_entered_worktree_blocks_pwsh` into
  `project_worktree_guard_blocks_git_not_file_writes`.
- Shrunk: the 7 files the plan names. Kept: 12 files, with `[[links]]` to removed memories
  replaced by the doc that now holds the fact, or dropped.
- `project_blazor_auth_csp_eval` now says the live header is
  `Content-Security-Policy-Report-Only`.
- `MEMORY.md` has one line per file that stays, 19 lines.

## Findings for user-level files

None of these files changed. Each is a suggestion for the user.

- **F1** `~/.claude/RTK.md` ends with "Refer to CLAUDE.md for full command reference.", but
  `~/.claude/CLAUDE.md` holds no rtk reference. Drop the `@RTK.md` import, or the line.
- **F2** `~/.claude/CLAUDE.md` Skill Routing repeats the `custom-review-findings` description,
  which already says it replaces `superpowers:receiving-code-review`. Shorten it to one line.
- **F3** `~/.claude/CLAUDE.md` Long-Running Background Commands covers the same ground as
  `.claude/CLAUDE.md` Watch a background run. Keep one of the two.
- **F4** `~/.claude/settings.json` has two `ask` rules (`Bash(gh pr create *)`,
  `Bash(rtk gh pr create *)`) that may never prompt. They measured inert on Claude Code
  2.1.233. Retest, then drop them or replace them with a hook.
- **F5** Two kept memories, `feedback_new_plan_goes_to_repo_plus_reviewer_handoff` and
  `feedback_user_claude_folder_commits`, are user-level rules. Add each as one line under Commit
  Workflow in `~/.claude/CLAUDE.md`, then delete the memories.
- **F6** These files load in every session of every project. Measured 2026-10-27, in
  characters: `~/.claude/CLAUDE.md` 4,678, `RTK.md` 987, `CLI-TOOLS.md` 1,151. Total 6,816.

## Size record

Characters, measured 2026-10-27. Before is `a3b4deae`, the branch head before Task 1.

| File | Before | After | Always loaded |
|---|---:|---:|---|
| `AGENTS.md` | 34,519 | 25,554 | yes |
| `.claude/CLAUDE.md` | 9,259 | 4,731 | yes |
| `MEMORY.md` | 10,349 | 3,742 | yes |
| `docs/development/workflow.md` | 76,265 | 79,931 | no |

The three always-loaded files drop from 54,127 to 34,027 characters. (`AGENTS.md` and
`.claude/CLAUDE.md` were re-measured on 2026-10-28, after the review fixes.) `workflow.md` grows by
3,666, because Stage 3 now holds the fabrication check and the citation rules.

## Notes / dependencies

- Filed by backlog 188 at its Plan stage. Spec section 4.2.
- The audit behind the sort is in
  `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-research-188/memory-and-instructions.md`.
  Its sort is a list of candidates, not decisions.
- Spec: `docs/superpowers/specs/2026-10-18-speed-up-the-development-cycle-design-188.md`
- Plan: `docs/superpowers/plans/2026-10-27-prune-memories-and-instruction-files-plan-192.md`
