# 108 - PR-Agent ai_timeout is not enforced

## Metadata

- **Epic**: CI/CD
- **Type**: Bug
- **Interfaces**: CI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

PR-Agent reports `ai_timeout: 120`, but a single model call runs for eight
minutes or more and nothing stops it. The setting reaches the call and bounds
nothing. Three `/review` runs were cancelled at the old 15-minute job cap and
posted nothing to the pull request, so reviewers saw silence and read it as a
clean review.

This item gives the call a bound we control, and makes an unfinished run say
so on the pull request.

## User story

As a maintainer relying on the PR-Agent GitHub Action, I want a review that
does not finish to say so on the pull request inside a known time, so silence
never reads as "no findings".

## Words used in this item

- **not enforced** — the setting reaches the call and bounds nothing.
- **over-run** — the call passes our step cap and the runner kills the step.
- **cancel** — GitHub kills the whole job at the job cap.

## Evidence

Run `https://github.com/s205109/AHKFlowApp/actions/runs/31832272275`
succeeded in 522 seconds. Its log holds one model call that took 8 minutes
2 seconds and returned normally:

```
19:13:48 DEBUG Prompts
19:21:50 DEBUG AI response:
```

The same run printed `ai_timeout: 120` in its own config dump. A call that
returns after 482 seconds under a 120-second setting proves the setting is
not enforced. No reproduction is needed, and the proof does not rest on a
missing log line.

### Every run of this workflow

Read 2026-08-17 with `gh run list --workflow pr-agent.yml --limit 30`:

| Conclusion | Durations (seconds) |
| --- | --- |
| success | 43, 95, 470, 522, 622, 792, 838 |
| cancelled | 918, 919, 923 |

The three cancelled runs (`31704604168`, `31731784778`, `32022710084`) died
at the 15-minute job cap in force at the time. The longest success is 838
seconds, which is 14 minutes. Runs `31684838097` and `31604321952` also go
silent for about 13 minutes after their last log line and then finish.

So the cancelled runs were not a different failure. They sat on the wrong
side of a cap the successful runs were already brushing. Backlog 104 raised
that cap to 45 minutes; no run has reached the new cap yet.

### What is actually wrong

1. Nothing we control bounds the call. A call that never returns now holds a
   runner for 45 minutes.
2. A cancelled job posts nothing to the pull request. Silence reads as a
   clean review.

## Acceptance criteria

- [x] The workflow caps the PR-Agent step at 20 minutes, below the 45-minute
      job cap, so an over-run fails the step instead of cancelling the job.
- [x] An unfinished run posts one comment on the pull request that names the
      run URL and says the pull request is unreviewed.
- [x] The comment above `timeout-minutes` in
      `.github/workflows/pr-agent.yml` states that `ai_timeout` is not
      enforced, and points at this item, backlog 108.
- [x] The four stale references to backlog 105 in
      `backlog/done/104-pr-agent-config-and-timeout-fix.md` name 108.
      Shipped in PR #320.
- [x] PR #320 carries a title and body that match this framing, not the
      earlier stall reading. PR #320 merged on 2026-08-19 under the title
      `fix: bound the PR-Agent model call, ai_timeout is not enforced
      (backlog 108)`.
- [x] A `/review` on an open pull request, after this change reaches `main`,
      either posts findings or posts the unfinished-run comment, with the run
      URL recorded here. Run
      `https://github.com/s205109/AHKFlowApp/actions/runs/32398853750/job/96521973552`
      on PR #326 succeeded in 579 seconds, well under the 20-minute step cap,
      and posted a findings comment
      (`https://github.com/s205109/AHKFlowApp/pull/326#issuecomment-5359637726`),
      not the unfinished-run comment.

## Out of scope

- Changing `model`, `custom_model_max_tokens`, or `max_model_tokens`. The
  latency belongs to the model, and attacking it is a separate item.
- Rewriting `extra_instructions`. Backlog 104 did that.
- Upgrading the pinned PR-Agent image, or moving off OpenRouter.
- Proving why `ai_timeout` is not enforced. See the note below.
- A `/review` on a pull request the size of #314. That pull request is
  merged, and the workflow only runs on an open one. The large-diff path
  already has a green witness: run `31604321952` pruned a 67 814-token diff
  and succeeded.

## Notes / dependencies

- Comes from a review of PR #317. Backlog 104 shipped the job-timeout raise
  and explicitly did not claim to fix this.
- Related: `backlog/done/104-pr-agent-config-and-timeout-fix.md`.
- Pinned image:
  `pragent/pr-agent@sha256:ec267eb168375c150d75efc024e2b10e0e2768ad0c000f15fd2378fe63abfe98`
  (tag `0.41.1-github_action`).
- Why `ai_timeout` is not enforced is still unknown. The leading guess is
  that litellm hands the value to the HTTP client as a per-read timeout,
  which keepalive bytes keep resetting. Not chased and not filed upstream,
  because the fix would live inside the pinned image or at the provider, and
  both are out of scope here.
- Spec: none — a grilling round with domain modelling settled the design, and
  the decisions are recorded in the plan.
- Plan: `docs/superpowers/plans/2026-08-17-pr-agent-ai-timeout-not-enforced-plan-108.md`
- The plan aimed the live run at PR #320. That pull request merged on
  2026-08-19, and the workflow only runs on an open one, so the run moves to
  another open pull request.
- The live run can only happen after this change reaches `main`. GitHub loads
  the workflow file for an `issue_comment` event from the default branch, so a
  `/review` on this branch's own pull request would still run the old file.
- The live run happened on PR #326, an unrelated open pull request based on
  `main`. See the last acceptance box for the run and comment URLs.
