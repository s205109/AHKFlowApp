# An unreadable command is refused by every policy layer

The Guard's tokenizer marks a Reading **Ambiguous** when a quote or an escape was left open, or
when a heredoc or here-string is incomplete. Nothing in the command can be trusted after that: no
command word, no write target, no `cd`.

The Guard's three policy layers gave that one condition three different answers. The safety layer
allowed it. The location layer refused it, with rule `ambiguous-git-command`. The write layer
allowed it, while the write-target reader it calls reported the target list as incomplete and told
its callers to fail closed.

Only the order of the layers hid the disagreement. `Invoke-AgentGuardPolicyForReading` returns the
first layer that does not say Allow, and the location layer runs before the write layer.

**An Ambiguous Reading now refuses the command at every layer, inside the commands that layer is
already responsible for.** One shared helper builds that decision, so the three layers cannot drift
apart again, and all three return the same rule name and the same message. The rule is renamed
`ambiguous-command`, because it fires on commands holding no git at all.

The scope wording is load-bearing for one layer. `Get-AgentWorktreeWriteDecision` is the worktree
write-isolation rule, and it answers Allow for any session that is not in a managed worktree,
before it parses anything. That test stays in front of the ambiguity check. Refusing an unreadable
command from a main-checkout session is the location layer's job, and it already does it for every
session.

## Considered options

**One hoisted check in the orchestrator was rejected.** Reading `Ambiguous` once in
`Invoke-AgentGuardPolicyForReading`, and never inside a layer, is less code. It protects the
orchestrator only. All three layers are public and separately tested, and backlog 111 is about to
replace first-non-Allow with strongest-of-three, which makes every layer run on every command. A
layer that allows a command it could not read is wrong on its own terms, not only in a chain.

**Documenting the disagreement instead of fixing it was rejected.** It matches today's measured
behaviour exactly and changes nothing. It leaves the safer of two opposite answers reachable only
by luck of ordering.

**Narrowing the refusal to git commands was rejected, and can never be right.** The rule's old name
and message both said "git", and it fires on any command. The mismatch cannot be fixed by narrowing
it: a command the tokenizer could not read cannot be shown to hold no git.

## Consequences

The same commands are refused before and after, and the shared message means the answer is
identical whichever layer produces it. Two things a person sees do change: the rule name, which
the hook prints as a diagnostic, and the wording of the refusal. The Action stays Deny and the
adapter transport is unchanged.

`AHKFLOW_ALLOW_MAIN=1` does not relax this refusal. That was already true — the location layer
refused before it read the override flag — and it is now pinned by a test and stated in
`docs/agents/cross-agent-git-guardrails.md`.

The adapter protocol is unchanged. `ambiguous-command` is not in `$locationDecisionRules`, so a
refusal keeps the legacy stderr and exit 2 path for Claude, exactly as a safety refusal does.

The way past a refusal is to close the open quote or escape, or complete the heredoc or
here-string. There is no override, and no message advising one.

ADR 0008 rejected marking every unquoted backtick and parenthesis ambiguous, and one of its two
reasons was that ambiguity "fails *open* in the write decision". That reason is now void. The other
reason stands on its own: marking them ambiguous would stop a bash subshell from splitting at all,
which is the part the old behaviour got right.
