# 138 - SkillParity compares skill names case-insensitively

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (test suite)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

`tests/SkillParity.Tests.ps1` compares skill directory names, and the file paths inside them, with
`-notcontains`. That operator ignores letter case on every platform. A Linux filesystem does not.
Two skills, or two files inside one skill, that differ only in letter case pass the parity check
while being different files.

## User story

As a developer trusting the skill parity check, I want it to compare names the way the filesystem
does, so that two copies differing only in letter case are reported as a difference rather than
passed as a match.

## Acceptance criteria

- [ ] The skill name comparison distinguishes letter case. Two skill directories whose names
      differ only in case are reported as two different skills, not as one match.
- [ ] The file path comparison inside a skill distinguishes letter case in the same way.
- [ ] A test proves each comparison fails on a case-only difference. A fixture folder is enough;
      the check does not need to run against the repository's real skills.
- [ ] The item records whether a case-only difference can exist in this repository at all, and
      what a Windows checkout does when one exists.

## Out of scope

- Changing which directories the check reads, or the layout under `.agents/`.
- The `-notcontains` comparisons elsewhere in the repository. This item covers this suite only.
- Renaming any existing skill.

## Notes / dependencies

- Spec: none — backlog 127 found this while reading the five invariant suites for platform
  dependencies, and recorded it as a follow-up rather than fixing it there.
- Plan: docs/superpowers/plans/2026-09-06-skillparity-case-sensitive-plan-138.md
- Four `-notcontains` comparisons report the differences. Two compare skill names
  (`tests/SkillParity.Tests.ps1:30`, "foreach ($name in ($canonicalNames | Where-Object { $pluginNames -notcontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:33`, "foreach ($name in ($pluginNames | Where-Object { $canonicalNames -notcontains $_ })) {").
  Two compare file paths inside a skill
  (`tests/SkillParity.Tests.ps1:55`, "    foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -notcontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:58`, "    foreach ($rel in ($pluginFiles | Where-Object { $canonicalFiles -notcontains $_ })) {").
- `-cnotcontains` is the case-sensitive operator. Backlog 127 used it for the manifest's
  `platform` values, so there is a recent example in the repository to follow.
- **Pickup finding, measured 2026-09-06. A case-only difference can exist here, and it does not
  need a Linux checkout.** The intake note said it did. That was wrong. The two names this suite
  compares live in different roots, `.agents/<skill>` and `plugins/ahkflowapp/skills/<skill>`, so
  the pair never collides on one filesystem and Windows checks out both. A probe committed
  `.agents/Foo/SKILL.md` beside `plugins/skills/foo/SKILL.md` in a fresh Windows repository, and
  `git status` stayed clean afterwards.
- **How the repository would reach that state.** A case-only rename of a skill. Plain
  `git mv .agents/foo .agents/Foo` fails on Windows with "Invalid argument", but the two-step
  rename through a temporary name works and git records it. Re-running
  `scripts/agents/setup-cross-agent-skills.ps1` then rewrites the mirror directory's case on disk,
  and `core.ignorecase = true` keeps git from noticing, so the mirror stays committed under the
  old case.
- **What each platform does with one.** Windows reports nothing. `Get-SkillNames` returns `Foo`
  from one root and `foo` from the other, every comparison calls them equal, the byte loop opens
  the mirror as `Foo`, NTFS resolves that to `foo`, and the bytes match. Linux does not pass
  either. It throws `ItemNotFoundException: Cannot find path .../plugin/Foo because it does not
  exist` inside `Get-SkillFiles`, and `$ErrorActionPreference = 'Stop'` turns that into a suite
  crash that never mentions parity. So the suite is silent on Windows and unreadable on Linux.
- **Pickup verdict: the case-sensitive operator, and it covers six comparisons, not four.** The
  two `-contains` comparisons that choose which skills and files reach the byte loop must change
  as well
  (`tests/SkillParity.Tests.ps1:48`, "foreach ($skillName in ($canonicalNames | Where-Object { $pluginNames -contains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:62`, "    foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -contains $_ })) {").
  Left case-insensitive they still send the mismatched pair into the byte loop, which is exactly
  the Linux crash above. With all six changed, the fixture reports two plain failures on both
  platforms and reads the same on each.
- **The other option was considered and rejected.** A check that refuses two paths differing only
  in case anywhere under one skill root cannot see the case this item is about, because that case
  spans two roots. It would only catch `.agents/Foo` beside `.agents/foo`, and a Windows checkout
  holds one of that pair at most, so the check could never fire on the platform this repository is
  developed on. The operator compares strings already in memory, so it behaves the same on both.
- The case-sensitive comparison passes against the real skill tree today: 26 canonical skills, 26
  mirrored, zero differences. So the change reports nothing new on a clean tree.
- The suite runs in both CI jobs, on both platforms
  (`tests/powershell-suites.json:34`, "SkillParity.Tests.ps1"), so a change here must pass on
  Windows and on Linux. `docs/development/testing-workflow.md` explains that record.
- Separator handling is already settled and only letter case is open: the path-splitting helper
  trims either separator
  (`tests/SkillParity.Tests.ps1:42`, "        ForEach-Object { $_.FullName.Substring($SkillDir.Length).TrimStart('\', '/') })").
