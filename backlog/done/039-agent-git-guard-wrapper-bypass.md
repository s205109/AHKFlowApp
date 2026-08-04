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

- [x] Decide the approach: teach the guard to look through a known wrapper prefix, or exclude `git`
      from the wrapper's rewrite (or both). Record the decision and its reasoning.
- [x] A wrapped mutating command targeting the main checkout gets the same decision as its bare
      equivalent — in particular `rtk git commit -m x` from main is denied.
- [x] Regression tests in `tests/AgentWorktreeGuard.Tests.ps1` cover the wrapped form for at least
      one Tier 2 allow, one Tier 1a Ask, and the Tier 1b `commit` denial.
- [x] If prefix-skipping is chosen, the allowed prefix list is explicit and narrow — a wrapper must
      not be able to escalate what the guard permits, only stay transparent to it.
- [x] `docs/agents/cross-agent-git-guardrails.md` accepted-limitations wording updated: an
      externally registered command-rewriting hook can silently neutralise the guard, which differs
      from a user knowingly invoking a wrapper.

## Resolution

Two commits on `fix/wt-agent-git-guard-wrapper-bypass`:

1. `Remove-AgentWrapperPrefix` (commit `6b0164a7`) strips a leading `rtk`/`rtk.exe` prefix, its
   leading global options, and one pass-through subcommand, before the guard classifies the
   command. `$script:AgentGuardTransparentWrappers` and
   `$script:AgentGuardWrapperPassThroughSubcommands` are the explicit, narrow allow-lists — adding
   a name to either can only expose more of a command to classification, never permit more than the
   bare command would.
2. A review-cleanup commit (`c8d131f0`) added `err`, `summary`, and `test` to the pass-through list
   — rtk 0.43.0 ships five subcommands that run a raw command, not two — fixed a comment that
   misdescribed `Remove-AgentWrapperPrefix`'s return value on a multi-pass strip, replaced a
   vacuous test case, and pinned `rtk FOO=1 git commit -m x` as a documented remaining bypass.

Two smaller gaps stay deliberately unmodelled, each pinned by a test: a wrapper option that
consumes the next token as its value (rtk has none today), and a `NAME=value` assignment placed
after the wrapper. `docs/agents/cross-agent-git-guardrails.md` records both, plus the deeper risk
that any externally registered command-rewriting hook not on the transparent-wrapper list still
bypasses the guard exactly as before.

The path-qualified-probe observation in Notes below is **not** addressed by this item. It is still
open and needs its own investigation.

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
