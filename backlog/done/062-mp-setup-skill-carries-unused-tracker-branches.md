# 062 - mp-setup-matt-pocock-skills carries unused tracker branches

## Metadata

- **Epic**: Agent tooling
- **Type**: Chore
- **Interfaces**: —
- **Stage**: 9-ship

## Summary

The `mp-setup-matt-pocock-skills` skill still offers issue-tracker choices this repo will never
pick, and points at three skills this repo never vendored. None of it runs today, so this is
cleanup, not a defect.

## User story

As a maintainer running the setup skill by hand, I want it to offer only the choices that apply
here, so that I am not asked to rule out options that were never possible.

## Background

The skill came from `mattpocock/skills` and was kept close to upstream on purpose. See
**mattpocock/skills** in `.agents/ATTRIBUTION.md` — the fork policy is manual-selective-merge, and
upstream prose stays intact so a future merge still lines up. Trimming the skill trades that
alignment for a shorter file. That trade may be worth making, but it should be a decision, not a
side effect of a sync.

Two reasons this is not urgent:

- The skill sets `disable-model-invocation: true`, so it never fires on its own. A human has to ask
  for it by name.
- The tracker question is already settled. `docs/agents/issue-tracker.md` records GitHub, and the
  git remote is GitHub, so the GitLab and local-markdown branches are unreachable in practice.

Raised in the review of commit `0b8bed15`, graded Low, and deferred there.

## Resolution

Deleted the whole skill instead of trimming it. Trimming assumed the skill still had a job. It did
not. It ran once during adoption and wrote the three `docs/agents/*.md` files. Those files are what
agents read, and they stay. The skill had no second job, so every unreachable branch inside it was
unreachable for the same reason: the skill itself was spent.

Deleting also settles the fork-policy tension the original item raised. There is no longer a file to
keep aligned with upstream.

## Acceptance criteria

- [x] Decide whether to trim the skill or keep it aligned with upstream. Record the decision in
      `.agents/ATTRIBUTION.md`.
- [x] Unreachable tracker branches gone — the whole skill is gone, including
      `issue-tracker-gitlab.md` and `issue-tracker-local.md`.
- [x] References to `to-tickets`, `to-spec`, and `/wayfinder` gone with it. The one live pointer
      into the skill, at `.agents/mp-triage/SKILL.md:48`, now points at
      `docs/agents/triage-labels.md` instead.
- [x] `pwsh tests/SkillParity.Tests.ps1` and `pwsh tests/SkillLayout.Tests.ps1` pass afterwards.

## Out of scope

- The other eight `mp-*` skills. They carry no unreachable branches.
- Changing the fork policy itself for skills other than this one.

## Notes / dependencies

- Fork policy and pinned commit: `.agents/ATTRIBUTION.md`
- Active tracker config: `docs/agents/issue-tracker.md`
- Regenerate the Codex mirror after any skill edit: `scripts/agents/setup-cross-agent-skills.ps1`
