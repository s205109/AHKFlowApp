# 101 - pr-agent config and timeout fix

## Metadata

- **Epic**: CI/CD
- **Type**: Chore
- **Interfaces**: CI
- **Stage**: 6-verify

## Summary

Fix PR-Agent runs so they stop hanging past the job timeout on large PRs, and
tighten `.pr_agent.toml` so `/review` and `/improve` return fewer, more
actionable findings without killing the run on a provider error.

## User story

As a maintainer relying on the PR-Agent GitHub Action, I want reviews to
finish inside the job timeout and to post focused findings, so a large PR
does not silently get zero review and reviewers do not have to sort noise.

## Acceptance criteria

- [x] Root cause confirmed: run 32022710084 was killed by
      `.github/workflows/pr-agent.yml:45` `timeout-minutes: 15`, not by a code
      or test failure — job started 10:58:57, cancelled 11:14:07, mid model
      call after diff pruning (119k tokens over the 64000 `max_model_tokens`
      cap).
- [x] `timeout-minutes` in `.github/workflows/pr-agent.yml` raised to give
      headroom for multi-pass review on large PRs (handoff txt suggests 45).
- [x] Every `.pr_agent.toml` key touched is confirmed against the installed
      PR-Agent's own `settings/configuration.toml` before use, not against web
      docs. Unverified keys are removed, not guessed.
- [x] `fallback_models` keeps exactly one entry
      (`openrouter/tencent/hy3`) as the default.
- [x] `[pr_reviewer]` and `[pr_code_suggestions]` `extra_instructions` blocks
      differ. The `/improve` block forbids new files, new tests, and
      cross-file refactors.
- [x] `commitable_code_suggestions = false` set under `[pr_code_suggestions]`.
      `num_code_suggestions` does not exist in the installed 0.41.1 image's
      `[pr_code_suggestions]` (confirmed against
      `pragent/pr-agent@sha256:ec267eb168375c150d75efc024e2b10e0e2768ad0c000f15fd2378fe63abfe98`
      — that section has `num_code_suggestions_per_chunk` and
      `max_number_of_calls` instead, different semantics), so this change is
      dropped and reported open, per the handoff doc's own no-guess rule.
- [x] `persistent_comment = true` set under `[pr_reviewer]`, or its absence
      reported as an open item if the key does not exist in the installed
      version.
- [x] `model`, `custom_model_max_tokens`, and `max_model_tokens` unchanged.
- [x] `.pr_agent.toml` parses (checked with a TOML load, not by eye).

## Out of scope

- Changing the model or `custom_model_max_tokens` / `max_model_tokens`.
- Adding TOML sections not present today (`[pr_description]`,
  `[github_app]`, etc.).
- Changing the workflow trigger, webhook config, or any action besides the
  timeout value.
- Tuning `ai_timeout` or dropping review passes (`require_security_review`
  etc.) — optional follow-up noted in the timeout analysis, not required here.

## Notes / dependencies

- Source docs (local, not in repo): `pr-agent-toml-handoff.md` (target TOML
  and key-verification steps) and `pr-agent timeout.txt` (root-cause analysis
  of run 32022710084).
- Spec: none — moderate difficulty, no design judgment call, straight to plan
- Plan: docs/superpowers/plans/2026-08-17-pr-agent-config-timeout-plan-101.md
