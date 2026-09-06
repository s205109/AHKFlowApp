# 138 - SkillParity compares skill names case-insensitively

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (test suite)
- **Difficulty**: moderate
- **Stage**: 0-intake

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
- Plan: none — the change is small, but it alters what a repository invariant accepts, so it is
  not `trivial`.
- Four comparisons are affected. Two compare skill names
  (`tests/SkillParity.Tests.ps1:30`, "foreach ($name in ($canonicalNames | Where-Object { $pluginNames -notcontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:33`, "foreach ($name in ($pluginNames | Where-Object { $canonicalNames -notcontains $_ })) {").
  Two compare file paths inside a skill
  (`tests/SkillParity.Tests.ps1:55`, "    foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -notcontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:58`, "    foreach ($rel in ($pluginFiles | Where-Object { $canonicalFiles -notcontains $_ })) {").
- `-cnotcontains` is the case-sensitive operator. Backlog 127 used it for the manifest's
  `platform` values, so there is a recent example in the repository to follow.
- **This is a latent hole, not a live defect.** For it to bite, two paths differing only in case
  must exist. Git on Windows cannot check out both, so they could only be created from a Linux
  checkout, and this repository is developed on Windows. Backlog 127's Linux probe ran this suite
  and did not trip it.
- That narrowness is why the item is worth doing but not urgent. Decide at Pickup whether the
  honest fix is the case-sensitive operator on those four lines, or a check that refuses two paths
  differing only in case anywhere under the skill roots. The second catches the cause rather than
  one symptom, and it fails on Windows too, where the operator alone would never notice.
- The suite runs in both CI jobs, on both platforms
  (`tests/powershell-suites.json:35`, "SkillParity.Tests.ps1"), so a change here must pass on
  Windows and on Linux. `docs/development/testing-workflow.md` explains that record.
- Separator handling is already settled and only letter case is open: the path-splitting helper
  trims either separator
  (`tests/SkillParity.Tests.ps1:42`, "        ForEach-Object { $_.FullName.Substring($SkillDir.Length).TrimStart('\', '/') })").
