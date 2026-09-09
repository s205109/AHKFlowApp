# 149 - Improve PR-Agent review output

## Metadata

- **Epic**: Developer workflow
- **Type**: Feature
- **Interfaces**: Repository tooling
- **Difficulty**: moderate
- **Stage**: 5-simplify

## Summary

Upgrade PR-Agent and tune its review output. Reviews must identify the answering model, stay bounded, and publish only high-scoring inline suggestions.

## User story

As a maintainer, I want focused and attributable PR-Agent feedback so that automated reviews support human review without flooding pull requests.

## Acceptance criteria

- [x] The workflow pins the verified PR-Agent 0.45.0 image digest.
- [x] PR-Agent uses Pareto as its primary model and Hy3 as its fallback.
- [ ] Successful review output identifies the model that answered.
- [ ] `/review` returns at most five findings with risk, merge, and priority-file sections.
- [ ] `/improve` publishes suggestions scoring 8 or higher as persistent inline comments.
- [x] A cross-platform PowerShell invariant rejects unsupported settings, section typos, and policy drift.
- [x] The project plan defines post-merge `/review` and `/improve` checks with durable evidence.

## Out of scope

- Automatic reviews on every pull request event.
- Large-pull-request chunking before live timing data exists.
- Changes to the existing 20-minute PR-Agent step cap.

## Notes / dependencies

- The OpenRouter key must have enough credit for the configured completion cap.
- Spec: none — the approved design is bounded and needs no separate design record.
- Plan: `docs/superpowers/plans/2026-09-09-pr-agent-review-improvements-plan-149.md`
- Pull request: https://github.com/s205109/AHKFlowApp/pull/401
- Three acceptance points stay unticked on purpose: model attribution, the expanded `/review`
  sections, and score-8 inline publishing. GitHub loads `issue_comment` workflows and
  `.pr_agent.toml` from the default branch, so a `/review` or `/improve` comment before merge
  runs the old configuration. Plan Task 5 proves all three after merge and records the run and
  comment URLs. The configuration for all three is committed and checked by
  `tests/PrAgentConfiguration.Tests.ps1`.
