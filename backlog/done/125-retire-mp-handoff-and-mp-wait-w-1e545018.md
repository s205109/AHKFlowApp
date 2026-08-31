# 125 - Retire mp-handoff and mp-wait-what skills

## Metadata

- **Epic**: Agent tooling
- **Type**: Chore
- **Interfaces**: none
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

Delete the `mp-handoff` and `mp-wait-what` skills from the repository. Both are vendored
copies of upstream `mattpocock/skills` with no adaptation, and both are human-only. The
upstream plugin now serves them at user level instead.

## User story

As an agent working in this repository, I want the skill list to hold only skills this
repository has adapted, so that every `mp-*` skill I see is one worth reading here.

## Acceptance criteria

- [x] `.agents/` holds eight `mp-*` directories, and neither `mp-handoff` nor `mp-wait-what`
      is among them
- [x] `.claude/skills/`, `.github/skills/`, and `plugins/ahkflowapp/skills/` hold no entry
      named `mp-handoff` or `mp-wait-what`
- [x] `.agents/ATTRIBUTION.md` lists eight adapted skill names, carries no `mp-wait-what`
      paragraph, and carries a retirement note for the two skills in the same shape as the
      existing `mp-setup-matt-pocock-skills` paragraph
- [x] `pwsh ./scripts/run-powershell-suites.ps1` passes

## Out of scope

- Any change to the other eight `mp-*` skills
- The user-level permission fence in `.claude/settings.local.json` — that is personal
  config, done separately
- History files that name the two skills: `backlog/done/109-*.md` and the two plans under
  `docs/superpowers/plans/`. Editing them would falsify the record

## Notes / dependencies

- The personal plan behind this item:
  `docs/superpowers/personal/plans/2026-08-31-mattpocock-skills-personal-move-plan.md`,
  Part B
- Depends on the upstream plugin staying reachable inside this repository. The project
  `deny` fence deliberately omits `mattpocock-skills:handoff` and
  `mattpocock-skills:wait-what`
- Spec: none — the personal plan carries the reasoning
- Plan: `docs/superpowers/plans/2026-08-31-retire-mp-handoff-wait-what-plan-125.md`
