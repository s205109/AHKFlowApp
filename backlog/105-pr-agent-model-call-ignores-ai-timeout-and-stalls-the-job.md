# 105 - PR-Agent model call ignores ai_timeout and stalls the job

## Metadata

- **Epic**: CI/CD
- **Type**: Bug
- **Interfaces**: CI
- **Difficulty**: to-be-determined
- **Stage**: 0-intake

## Summary

One PR-Agent model call ran about 14 minutes with no completion, no error, and
no fallback, although the same run reported `ai_timeout: 120`. Backlog 104
raised the job timeout, which stops a working review being cut off. It does
nothing for a stalled call. Find out why the call never returned.

## User story

As a maintainer relying on the PR-Agent GitHub Action, I want a model call that
stops responding to fail fast and fall back, so a review either posts findings
or reports an error instead of burning a runner in silence.

## Evidence

Run `https://github.com/s205109/AHKFlowApp/actions/runs/32022710084`, `/review`
on PR #314:

| Time | Line |
| --- | --- |
| 10:59:29 | `Generating prediction with openrouter/deepseek/deepseek-v4-flash-0731` |
| 10:59:50 | `Tokens: 119092, total tokens over limit: 64000, pruning diff.` |
| 10:59:50 | `After pruning, added_list_str: ...` — last PR-Agent line |
| 11:14:07 | `Cleaning up orphan processes` — the runner cancelling the job |

The run's own config dump printed `"ai_timeout": 120`. Only one
`Generating prediction` line appears in the whole log, so the run did not spend
its budget on several review passes.

## Acceptance criteria

- [ ] The 14-minute silence is explained with evidence, not a guess. Name the
      layer that swallows the timeout: the provider, litellm, PR-Agent's retry
      wrapper, or the pinned image's own settings.
- [ ] Reproduce, or say plainly that reproduction failed and why. A single
      unreproduced run does not close this item.
- [ ] A stalled model call ends in a bounded time and either falls back or
      writes an error line to the log.
- [ ] A `/review` on a pull request the size of #314 (57 files) posts findings,
      with the run URL recorded as proof.
- [ ] `.github/workflows/pr-agent.yml` is revisited once the stall is bounded.
      Its comment currently says 45 minutes is a backstop, not a fix, and
      points at this item.

## Out of scope

- Changing `model`, `custom_model_max_tokens`, or `max_model_tokens`.
- Rewriting `extra_instructions`. Backlog 104 did that.
- Upgrading the pinned PR-Agent image, unless the investigation shows the fix
  lives there. Then it becomes the point of the item, not a side effect.

## Notes / dependencies

- Comes from a review of PR #317. Backlog 104 shipped the job-timeout raise and
  explicitly did not claim to fix this.
- Related: `backlog/done/104-pr-agent-config-and-timeout-fix.md`.
- Pinned image:
  `pragent/pr-agent@sha256:ec267eb168375c150d75efc024e2b10e0e2768ad0c000f15fd2378fe63abfe98`
  (tag `0.41.1-github_action`).
- Spec: none yet — Difficulty is to-be-determined, so Design decides.
- Plan: none yet — write one at Stage 3.
