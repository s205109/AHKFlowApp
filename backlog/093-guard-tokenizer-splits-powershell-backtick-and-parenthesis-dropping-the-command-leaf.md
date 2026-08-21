# 093 - Guard tokenizer splits PowerShell backtick and parenthesis, dropping the command leaf

## Metadata

- **Epic**: Agent guardrails
- **Type**: Bug
- **Interfaces**: none (agent git guard)
- **Difficulty**: complex
- **Stage**: 4-execute

## Summary

The guard tokenizer treats a backtick and a parenthesis as command separators, because they are
separators in bash. They are not separators in PowerShell: a backtick escapes the character behind
it, and parentheses group an expression. A PowerShell command that holds either one is cut into
segments whose leading word is no longer the command, so the guard reads no write target for it
and allows the write.

## User story

As a person who owns the main checkout, I want the guard to read a PowerShell command as
PowerShell, so that an agent cannot reach a protected file by putting a backtick in front of it.

## Detail

The separator list is at `scripts/agents/agent-worktree-guard.common.ps1:717-718`. It puts
`` ` ``, `(`, and `)` beside `;`, `&`, and `|`.

Every command below was run through `Invoke-AgentGuardPolicy` with the working directory set to a
managed worktree and the protected root set to the main checkout. Each one returned **Allow**, with
no write targets and no `Unresolved` flag. The same command without the backtick returns Deny:

```powershell
# Deny, as it should be.
Set-Content -Path <main>\README.md -Value x

# Allow. Segment 1 is 'Set-Content -Path'; segment 2 leads with the path, so its leading word is
# not a command the guard knows, and no target is read.
Set-Content -Path `<main>\README.md -Value x
Set-Content -Path ('<main>' + '\README.md') -Value x
Remove-Item -LiteralPath `<main>\README.md
rm `<main>/README.md
```

The same shape defeats the link rules, which is where this was found:

```powershell
# Both create a real symbolic link into the main checkout. Both return Allow.
New-Item -ItemType `Sym -Path <managed>\bait.md -Target <main>\README.md
New-Item -ItemType ('Sym'+'bolicLink') -Path <managed>\bait.md -Target <main>\README.md
```

The link examples are not a link-rule bug. `Get-AgentNewItemLinkTarget` never receives the item
type, because the tokenizer removed it from the segment before the reader ran. The `Set-Content`
and `rm` examples above carry no item type and no link, and they fail the same way.

## Acceptance criteria

- [x] A PowerShell command holding a backtick is read as one command, or refused
- [x] A PowerShell command holding a parenthesised expression is read as one command, or refused
- [x] `rm` and `Set-Content` with a backtick before a main-checkout path report Deny
- [x] `New-Item -ItemType` with a backtick or a parenthesised expression reports Deny
- [x] A bash subshell `( ... )` and a bash backtick substitution still split into segments
- [x] A test pins each command in the Detail section above at Deny

## Out of scope

- The two option gates backlog 091 fixed. Those readers are correct; they are never reached
- Shell rewriting inside a token, which backlog 091 handles for `cp` with
  `Get-AgentShellLiteralHead`

## Notes / dependencies

- Found in review of the pull request for backlog 091. It predates that branch: the tokenizer is
  untouched by it, which `git diff main...HEAD` confirms
- The hard part is that one tokenizer serves both shells. A backtick really is command
  substitution in bash and really is an escape in PowerShell, so the fix likely needs to know
  which shell the command is bound for, or to refuse the ambiguity
- Refusing is allowed. `Get-AgentCommandSegment` already returns `Ambiguous = $true` for an
  unterminated quote (`scripts/agents/agent-worktree-guard.common.ps1:767-768`), and that path
  fails closed
- Spec: docs/superpowers/specs/2026-08-20-guard-both-shell-readings-design-093.md
- Plan: docs/superpowers/plans/2026-08-21-guard-both-shell-readings-plan-093.md
