# A command is read as both shells, and the worst decision wins

The Guard's tokenizer treated a backtick and a parenthesis as command separators. That is right
for bash and wrong for PowerShell, where a backtick escapes the next character and parentheses
group an expression. A PowerShell command holding either one was cut into segments whose leading
word was no longer the command name. No write target was read for that segment, and the write was
allowed.

The Guard is never told which shell will run a command. So every command now gets two Readings:
one under bash quoting rules, one under PowerShell rules. Each policy layer runs once per Reading,
and the worst action wins.

## Considered options

**Learning the shell from the tool name was rejected.** The hint exists, and it is partial.
`AgentGuardShellToolNames` (`scripts/agents/agent-worktree-guard.common.ps1:17`, "$script:AgentGuardShellToolNames = @('bash', 'shell', 'shell_command', 'sh', 'powershell', 'pwsh')")
already lists both shells, but Copilot and Codex both send `shell`, which names neither one. An
agent can also run a PowerShell command through a bash tool with `pwsh -c`, so the hint can be
accurate about the tool and still wrong about the shell.

**Refusing the ambiguity was rejected, and it would have widened the hole.** Marking every
unquoted backtick and parenthesis ambiguous fails closed in the write-target reader, and fails
*open* in the write decision
(`scripts/agents/agent-worktree-guard.common.ps1:3267`, "    if ($parsed.Ambiguous) { return New-AgentGuardDecision -Action Allow }").
It would also stop a bash subshell from splitting at all, which is the part the old behaviour got
right.

**Merging the two segment lists was rejected.** The write and location decisions walk segments in
order while tracking an effective working directory, a directory stack, and a pipeline source.
Segments interleaved from two Readings make that tracked directory meaningless, so each Reading
has to stay whole.

## Consequences

The Guard parses every candidate command twice. It already spawns `git` per command, so the second
parse is not the cost that decides this.

The change is a one-way ratchet. A command that denies today still denies, and the only new
outcomes are denials. Some legitimate command holding a backtick will newly deny. The way out is
to rewrite the command, or to set `AHKFLOW_ALLOW_MAIN=1`.

A denial has to say which Reading produced it. Without that, the message describes a command the
reader did not type.

The PowerShell Reading reads a backtick followed by "n" as the letter n, where PowerShell produces
a newline. That can mis-name a path, and it can never hide a command leaf. Control characters are
illegal in Windows paths, so this is accepted rather than modelled.

Recursion into a nested interpreter deliberately carries no shell knowledge, even though
`AgentGuardInterpreterSpecs` (`scripts/agents/agent-worktree-guard.common.ps1:2790`, "$script:AgentGuardInterpreterSpecs = @(")
names the shell of `pwsh -c` exactly. Reading the inner text in one Reading instead of two could
only ever read less than both Readings do.
