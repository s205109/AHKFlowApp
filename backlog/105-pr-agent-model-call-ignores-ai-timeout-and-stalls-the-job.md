# 105 - PR-Agent model call ignores ai_timeout and stalls the job

## Metadata

- **Epic**: CI/CD
- **Type**: Bug
- **Interfaces**: CI
- **Difficulty**: to-be-determined
- **Stage**: 1-pickup

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

### The stall repeats, and it is not a size problem

Two earlier `/review` runs on PR #299 stalled the same way. Both sent a diff
small enough to skip pruning, so PR size is not the trigger.

| Run | Last PR-Agent line | Job cancelled | Silence |
| --- | --- | --- | --- |
| `31704604168` | 13:23:19 `Prompts` | 13:38:03 | 14 min 43 s |
| `31731784778` | 18:39:05 `Prompts` | 18:53:46 | 14 min 41 s |

Both logs end with:

```
Tokens: 14657, total tokens under limit: 64000, returning full diff.
PR diff
Prompts
```

### Where the process stops

`Prompts` is the last line PR-Agent writes before it awaits the model call, so
the silence starts inside that await.

- PR-Agent logs `Prompts` in `litellm_ai_handler.chat_completion`, then calls
  `_get_completion`, which calls `litellm.acompletion`.
- The call does carry the timeout:
  `kwargs = {..., "timeout": get_settings().config.ai_timeout, ...}` in
  `pr_agent/algo/ai_handlers/litellm_ai_handler.py` at tag `v0.41.1`.
- litellm resolves that value to a float and hands it to the provider client
  (`litellm/litellm_core_utils/completion_timeout.py`, `CompletionTimeout.resolve`,
  tag `v1.93.0`). It is an HTTP timeout, not a wall-clock guard on the await.

### What the missing log lines rule out

A timeout that fired would have written log lines, and none appear:

1. `chat_completion` catches every exception and logs
   `Unknown error during LLM inference`.
2. `tenacity` retries the call once (`MODEL_RETRIES = 2`).
3. `retry_with_fallback_models` logs `Failed to generate prediction with <model>`
   and then logs a second `Generating prediction` line for the fallback model
   `openrouter/tencent/hy3` (`pr_agent/algo/pr_processing.py`).

The logs show none of the three. So the await never returned and never raised.
The open question is which layer holds the socket open past 120 seconds:
litellm, the OpenAI client it wraps, or OpenRouter.

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
