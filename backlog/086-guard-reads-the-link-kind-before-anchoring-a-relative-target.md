# 086 - Guard reads the link kind before anchoring a relative target

## Metadata

- **Epic**: Agent guardrails
- **Type**: Feature
- **Interfaces**: none (agent git guard)
- **Stage**: 1-pickup
- **Difficulty**: moderate

## Summary

The guard offers a relative link target three ways, because it does not know whether the command
creates a symbolic link or a hard link. Reading the kind first would let each form keep only the
anchor that matches how the operating system resolves it. That removes a refusal that stops
ordinary work, without giving up any denial the guard makes today.

## User story

As an agent working in a worktree, I want a relative link that stays inside my own worktree to be
allowed, so that I do not have to rewrite ordinary link commands to get past the guard.

## Detail

`Add-AgentLinkTargetCandidate` in `scripts/agents/agent-worktree-guard.common.ps1` adds three
candidates for a relative target: as written, joined to the link path, and joined to the link
path's parent. Each anchor is correct for one case and wrong for the other:

- Windows resolves a **symbolic** link target against the directory that holds the link. The two
  joined anchors are correct. The as-written anchor is not.
- A **hard** link resolves its source against the working directory. The as-written anchor is
  correct. The two joined anchors are not.

Keeping all three fails closed, which is the right default. It also refuses work that is allowed:

```powershell
# From the worktree root. The link stays inside the worktree, and the guard refuses it.
ln -s ../src/a.cs deep/bait.md
```

The as-written anchor resolves that target to `<main>\.claude\worktrees\src\a.cs`, which is in
the main checkout, so Deny wins. The refusal message then names a path that no write would have
landed on.

The as-written anchor cannot simply be dropped. This hard link is denied by that anchor alone:

```powershell
# The source is <main>\.claude\worktrees\README.md - a file in the main checkout.
ln ../README.md deep/bait.md
```

Both behaviours are pinned in `tests/AgentWorktreeGuard.Tests.ps1` under "Link creation".

Every command form already carries its kind, so the guard can read it:

| Command | Symbolic | Hard | Junction |
|---|---|---|---|
| `ln` | `-s`, `--symbolic`, or a cluster holding `s` | no `-s` | n/a |
| `cp` | `-s` | `-l` | n/a |
| `mklink` | default | `/H` | `/J` |
| `New-Item` | `-ItemType SymbolicLink` | `HardLink` | `Junction` |

## Acceptance criteria

- [ ] A relative symbolic-link target uses the two link-relative anchors only
- [ ] A relative hard-link source uses the working-directory anchor only
- [ ] A command whose kind the guard cannot read keeps all three anchors and stays fail-closed
- [ ] `ln -s ../src/a.cs deep/bait.md` inside a worktree is allowed, and the test that pins today's
      Deny is rewritten to expect Allow
- [ ] Every link denial the suite makes today still denies

## Out of scope

- Any change to the absolute-target path, which means one file from every directory
- Reading the kind for commands the guard does not treat as link commands today

## Notes / dependencies

- Found in review of pull request #296 (backlog 083 redelivery)
- The reasoning lives in the `Add-AgentLinkTargetCandidate` comment; keep the two in step
