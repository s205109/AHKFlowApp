# PLAN-PROGRESS — backlog 093

Plan: `docs/superpowers/plans/2026-08-21-guard-both-shell-readings-plan-093.md`

One line per task: task number, deliverable commit SHA (or `-`), tests state, deferrals.

| Task | Commit | Tests | Deferrals |
|---|---|---|---|
| 1 + 2 | 6de89dd9 | guard suite green | Merged into one commit. Separate commits break the agent's own shell: the hook loads this file, so a mandatory `-Reading` with no caller passing it fails every Bash call closed. The plan was wrong to split them. |
| 3 | d8fdc4cd | guard suite green | none |
| 4 + 5 | 0a67d345 | guard suite green | Merged. The combiner calls `Add-AgentPowerShellReadingNote`, so defining it a commit later would leave the guard throwing in between — and the guard gates this session's own shell. |
| 6 | 6b32e631 | all 8 item commands Deny; bash forms still split | none |
| 7 | 02d81f92 (public), aaa80a7 (plans) | citation check clean on both roots | 6 plan citations quote code the plan replaced, so they carry `citation-check:ignore` rather than a wrong line number |
