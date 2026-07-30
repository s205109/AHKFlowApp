# 039 - Agent Git guard is bypassed by a command-rewriting wrapper hook

## Metadata

- **Epic**: Agent tooling
- **Type**: Bug
- **Interfaces**: None (agent guardrails / repo tooling)

## Summary

A `PreToolUse` hook registered outside this repository rewrites `git ...` into `rtk git ...`, and
the agent Git guard identifies a git invocation from each command segment's leading word. That word
becomes `rtk`, so the guard finds no git invocation and allows the command. Every location rule is
bypassed, including the `git commit` hard denial.

## User story

As the owner of the main checkout, I want the Git guard to keep protecting my HEAD, index, and
working tree even when an agent's git commands pass through a wrapper, so that the guard's
protection does not depend on how the shell command happens to be spelled.

## Detail

Found while trying to run the manual `Ask`-path verification for the guard-scope change
(PR #235). Measured directly against the policy core, `Cwd` = the main checkout:

| Command | Action | Rule |
|---|---|---|
| `git worktree repair` | Ask | `agent-main-git-mutation` |
| `rtk git worktree repair` | **Allow** | `none` |
| `git commit -m x` | Deny | `agent-main-git-mutation` |
| `rtk git commit -m x` | **Allow** | `none` |
| `git branch -D topic` | Ask | `agent-main-git-mutation` |
| `rtk git branch -D topic` | **Allow** | `none` |

The wrapper here is `rtk hook claude`, registered as a `PreToolUse` Bash hook in the user-level
`~/.claude/settings.json` — outside this repository, so the repo cannot see or version it.

This is **not** a regression from PR #235. The old guard behaves identically, because segment
classification by leading word predates that change. `docs/agents/cross-agent-git-guardrails.md`
already lists wrappers under accepted limitations. What makes this worth an item is scale: the
limitation was written for a user deliberately invoking a wrapper script, whereas here the wrapper
is the **default path for every git command** in the environment, which leaves the guard largely
inert rather than occasionally bypassable.

Only the first word of a command gets the prefix, so safety rules that match a later segment still
fire — a `gh pr create` whose body text contained recursive-force delete flags was correctly caught
by `dangerous-rm` during the same session.

## Acceptance criteria

- [ ] Decide the approach: teach the guard to look through a known wrapper prefix, or exclude `git`
      from the wrapper's rewrite (or both). Record the decision and its reasoning.
- [ ] A wrapped mutating command targeting the main checkout gets the same decision as its bare
      equivalent — in particular `rtk git commit -m x` from main is denied.
- [ ] Regression tests in `tests/AgentWorktreeGuard.Tests.ps1` cover the wrapped form for at least
      one Tier 2 allow, one Tier 1a Ask, and the Tier 1b `commit` denial.
- [ ] If prefix-skipping is chosen, the allowed prefix list is explicit and narrow — a wrapper must
      not be able to escalate what the guard permits, only stay transparent to it.
- [ ] `docs/agents/cross-agent-git-guardrails.md` accepted-limitations wording updated: an
      externally registered command-rewriting hook can silently neutralise the guard, which differs
      from a user knowingly invoking a wrapper.

## Out of scope

- Changing the tier model or any tier boundary — PR #235 settled those.
- Guarding file edits in main (`Edit`/`Write`), already recorded as a separate accepted limitation.
- Any change to `rtk` itself beyond repo-side configuration, if the chosen fix is configuration.

## Notes / dependencies

- Discovered during PR #235; full writeup is in that PR's comments.
- **Separate unexplained observation, needs its own investigation before or alongside this work:** a
  path-qualified probe (`"C:/Program Files/Git/cmd/git.exe" -C <main> worktree repair`), which the
  wrapper's matcher should not rewrite, also completed with no prompt and no denial — although both
  the pre-PR-235 copy (Deny) and the PR-235 copy (Ask) classify it as blocking when evaluated in
  process. Why the decision did not reach the harness is not established. It may share a root cause
  with this item or may be independent.
- Also relevant to anyone testing guard behaviour by hand: `.claude/settings.json` pre-approves
  `Bash(git branch *)`, `Bash(git checkout *)`, `Bash(git add *)`, `Bash(git commit *)`, and
  `Bash(git stash *)`. Most Tier 1a commands are therefore pre-approved and may never prompt
  regardless of what the guard returns, so a manual probe must use a non-allow-listed command.
- Consequence for PR #235: the live `Ask` prompt render was never verified. The per-adapter payload
  shape is asserted in process by the guard test suite, but no manual run confirmed that Claude
  turns `permissionDecision: "ask"` into a visible prompt. Worth confirming once this item lands.
