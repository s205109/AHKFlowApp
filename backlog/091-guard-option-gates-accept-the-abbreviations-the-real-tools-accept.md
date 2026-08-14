# 091 - Guard option gates accept the abbreviations the real tools accept

## Metadata

- **Epic**: Agent guardrails
- **Type**: Bug
- **Interfaces**: none (agent git guard)
- **Stage**: 0-intake

## Summary

Two gates in the guard compare an option or a type name for exact equality, but the real tools
accept shorter spellings. A command that uses a short spelling walks past the gate, so the guard
never looks at the path the link points to. Both gates let a link into the main checkout.

## User story

As a person who owns the main checkout, I want the guard to read the short spellings of an
option, so that an agent cannot reach a protected file by abbreviating a flag.

## Detail

Both holes were found in review of pull request #304 (backlog 086), and both predate it.

**1. `cp` link flags.** `Test-AgentGuardHasLinkFlag` in
`scripts/agents/agent-worktree-guard.common.ps1` matches `--link` and `--symbolic-link` with
exact equality. GNU accepts any unambiguous abbreviation, so `cp --sy` creates a symbolic link.
The guard does not send that command down the link branch at all, so it reports only the
destination and never scans the link target:

```powershell
# Reports only 'b.md'. The link target is never checked.
cp --sy ../README.md b.md
```

`Get-AgentLinkKind` already reads abbreviations through `Test-AgentLongOptionPrefix`, added in
#304. The same helper closes this gate.

**2. `New-Item -ItemType`.** `Get-AgentNewItemLinkTarget` reads the link target only when the
item type is exactly `symboliclink`, `hardlink`, or `junction`. The FileSystem provider matches
the item type by prefix, so `New-Item -ItemType Sym` creates a real symbolic link. The guard
reads no target for it:

```powershell
# Reports only the link path. The absolute target into the main checkout is never scanned.
New-Item -ItemType Sym -Path bait.md -Target <main>\README.md
```

The kind switch added in #304 inherits the same exact-match assumption, so an abbreviated item
type would also read as an unknown kind.

## Acceptance criteria

- [ ] `cp --sy` and `cp --lin` reach the link branch and report the link target
- [ ] `New-Item -ItemType Sym` and `-ItemType hardl` report the link target
- [ ] An abbreviated item type reads as the kind it names, not as an unknown kind
- [ ] An item type the guard cannot expand still fails closed
- [ ] A test pins each of the four commands above at Deny when the target is in the main checkout

## Out of scope

- The anchoring rules for a relative target, which backlog 086 settled
- The junction anchor, which is still unproved and still fails closed

## Notes / dependencies

- Found in review of pull request #304 (backlog 086)
- `Test-AgentLongOptionPrefix` in `scripts/agents/agent-worktree-guard.common.ps1` already does
  the prefix match for long options; reuse it rather than writing a second one
- Check whether the FileSystem provider matches the item type by prefix or by something looser
  before you copy the assumption. Prove it against the running provider, not from memory
