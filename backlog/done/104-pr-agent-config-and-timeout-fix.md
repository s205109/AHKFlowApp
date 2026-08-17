# 104 - pr-agent config and timeout fix

## Metadata

- **Epic**: CI/CD
- **Type**: Chore
- **Interfaces**: CI
- **Stage**: 9-ship

## Summary

Give the PR-Agent job enough wall-clock time to finish a review of a large PR,
and tighten `.pr_agent.toml` so `/review` and `/improve` return fewer, more
actionable findings without killing the run on a provider error.

This item raises the job timeout. It does **not** fix the stalled model call
seen in run 32022710084. Backlog 108 owns that investigation.

## User story

As a maintainer relying on the PR-Agent GitHub Action, I want reviews to
finish inside the job timeout and to post focused findings, so a large PR
does not silently get zero review and reviewers do not have to sort noise.

## Acceptance criteria

- [x] Proximate cause confirmed: GitHub cancelled run 32022710084 at the job
      timeout, not because of a code or test failure. The job started
      10:58:57 and was cancelled 11:14:07. The last log line is diff pruning
      at 10:59:50 (119k tokens over the 64000 `max_model_tokens` cap).
- [x] Underlying cause recorded as **not** confirmed and **not** fixed here.
      The log holds one `Generating prediction` line at 10:59:29 and no
      completion, no error, and no fallback before the job died 14 minutes
      later, although the same run printed `ai_timeout: 120`. Raising the job
      timeout lets a stalled run last longer; it does not stop the stall.
      Filed as backlog 108.
- [x] `timeout-minutes` in `.github/workflows/pr-agent.yml` raised to give
      headroom for multi-pass review on large PRs (handoff txt suggests 45)
      (`.github/workflows/pr-agent.yml:50`, "timeout-minutes: 45").
- [x] The comment above `timeout-minutes` does not claim PR-Agent caps each
      model call at 120 seconds. Run 32022710084 disproves that claim.
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
- Finding out why the single model call in run 32022710084 never returned and
  never fell back. Backlog 108 owns it.

## Notes / dependencies

- Source docs (local, not in repo): `pr-agent-toml-handoff.md` (target TOML
  and key-verification steps) and `pr-agent timeout.txt` (root-cause analysis
  of run 32022710084).
- Follow-up: renamed to backlog 108. See that item for the corrected reading:
  the call returns; `ai_timeout` is not enforced.
- Spec: docs/superpowers/specs/2026-08-17-pr-agent-config-timeout-design-104.md
- Plan: docs/superpowers/plans/2026-08-17-pr-agent-config-timeout-plan-104.md
