# Plan progress: backlog 192

Plan: `docs/superpowers/plans/2026-10-27-prune-memories-and-instruction-files-plan-192.md`

- Task 1 (baseline and approval): done at ae794709. Tests: plan citation check passes; all 34 rows checked by disposition. Deferrals: none.
- Task 2 (facts into docs): done at bcbbf993. Tests: process parity, SkillParity, SkillLayout, citation freshness and CitationFreshness.Tests.ps1 pass; 13 moved-citation warnings in files this branch does not change. Deferrals: none.
- Task 3 (trim AGENTS.md and .claude/CLAUDE.md): done at 58838661. Tests: process anchors, ProcessAnchors, HandoverRules, GateWording, CitationFreshness pass. Deferrals: none.
- Task 4 (memory sort, findings, sizes): done at 00a77ee0. Tests: plan citation check passes; index matches the folder minus the 33 approved files. Deferrals: none left. The classifier refused the agent's delete, so the user ran it; `~/.claude` commits `ed5796a` and `22a10ff` hold the result.
