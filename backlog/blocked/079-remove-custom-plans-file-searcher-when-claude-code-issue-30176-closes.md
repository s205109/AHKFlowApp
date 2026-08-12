# 079 - Remove custom plans file searcher when claude-code issue 30176 closes

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (agent tooling)
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Blocked

**What would unblock this item:** claude-code issue 30176 is closed and the fix ships in a
released version.

Until then the custom searcher must stay. Removing it now would leave plans unfindable.

## Summary

This repository carries a custom searcher so agents can find plan files under
`docs/superpowers/`. It exists to work around claude-code issue 30176. When that issue is
closed and the fix ships, delete the workaround.

## User story

As a maintainer, I want the workaround removed once upstream fixes the bug so that the
repository carries no code it no longer needs.

## Acceptance criteria

- [ ] claude-code issue 30176 is closed and the fix is in a released version.
- [ ] The custom plans file searcher is deleted.
- [ ] Plan files under `docs/superpowers/` are still found by a fresh session. Prove it
      with one search.
- [ ] Any documentation that names the workaround is updated.

## Out of scope

- Any other change to how the private plans repository is linked into a worktree.

## Notes / dependencies

- Upstream issue: `anthropics/claude-code` issue 30176.
- Filed by backlog 071 (wave 1). Filing completed, so Intake succeeded; the `blocked/`
  folder carries the blocked state.
