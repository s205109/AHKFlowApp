# 138 - SkillParity compares skill names case-insensitively

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (test suite)
- **Difficulty**: moderate
- **Stage**: 9-ship

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

- [x] The skill name comparison distinguishes letter case. Two skill directories whose names
      differ only in case are reported as two different skills, not as one match.
- [x] The file path comparison inside a skill distinguishes letter case in the same way.
- [x] A test proves each comparison fails on a case-only difference. A fixture folder is enough;
      the check does not need to run against the repository's real skills.
- [x] The item records whether a case-only difference can exist in this repository at all, and
      what a Windows checkout does when one exists.

## Out of scope

- Changing which directories the check reads, or the layout under `.agents/`.
- The `-notcontains` comparisons elsewhere in the repository. This item covers this suite only.
- Renaming any existing skill.

## Notes / dependencies

- Spec: none — backlog 127 found this while reading the five invariant suites for platform
  dependencies, and recorded it as a follow-up rather than fixing it there.
- Plan: `docs/superpowers/plans/2026-09-06-skillparity-case-sensitive-plan-138.md`
- Four `-cnotcontains` comparisons report the differences. They used `-notcontains` before this
  item. Two compare skill names
  (`tests/SkillParity.Tests.ps1:49`, "    foreach ($name in ($canonicalNames | Where-Object { $pluginNames -cnotcontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:52`, "    foreach ($name in ($pluginNames | Where-Object { $canonicalNames -cnotcontains $_ })) {").
  Two compare file paths inside a skill
  (`tests/SkillParity.Tests.ps1:69`, "        foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -cnotcontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:72`, "        foreach ($rel in ($pluginFiles | Where-Object { $canonicalFiles -cnotcontains $_ })) {").
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
  two `-contains` comparisons that choose which skills and files reach the byte loop changed as
  well, and are now
  (`tests/SkillParity.Tests.ps1:62`, "    foreach ($skillName in ($canonicalNames | Where-Object { $pluginNames -ccontains $_ })) {")
  and (`tests/SkillParity.Tests.ps1:76`, "        foreach ($rel in ($canonicalFiles | Where-Object { $pluginFiles -ccontains $_ })) {").
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
  (`tests/powershell-suites.json:38`, "SkillParity.Tests.ps1"), so a change here must pass on
  Windows and on Linux. `docs/development/testing-workflow.md` explains that record.
- Separator handling is already settled and only letter case is open: the path-splitting helper
  trims either separator
  (`tests/SkillParity.Tests.ps1:29`, "        ForEach-Object { $_.FullName.Substring($SkillDir.Length).TrimStart('\', '/') })").

## Verify evidence

Measured 2026-09-06 in this worktree. The mutation reverts the six operators to their
case-insensitive form; the restored run is the code that ships.

Mutated, Windows `pwsh`:

```
Skill parity comparison cases:
  PASS  roots that agree produce no failures
  FAIL  skill names differing only in case are two skills
        Expected 2 failures, got 0:
  FAIL  file names differing only in case are two files
        Expected 2 failures, got 0:
  PASS  a skill missing from the mirror is reported
  PASS  a file whose bytes differ is reported
```

Mutated, Linux PowerShell (`mcr.microsoft.com/powershell:latest`):

```
Skill parity comparison cases:
  PASS  roots that agree produce no failures
  FAIL  skill names differing only in case are two skills
        Cannot find path '/tmp/skillparity-0f99f7ad/plugin/Alpha' because it does not exist.
  FAIL  file names differing only in case are two files
        Exception calling "ReadAllBytes" with "1" argument(s): "Could not find file
        '/tmp/skillparity-b3b34d6d/plugin/alpha/Notes.md'.
  PASS  a skill missing from the mirror is reported
  PASS  a file whose bytes differ is reported
```

Restored, on Windows `pwsh`, Windows PowerShell 5.1, and Linux PowerShell:

```
Skill parity comparison cases:
  PASS  roots that agree produce no failures
  PASS  skill names differing only in case are two skills
  PASS  file names differing only in case are two files
  PASS  a skill missing from the mirror is reported
  PASS  a file whose bytes differ is reported
Skill parity tests passed.
```

Also green: `pwsh ./tests/CiPowerShellSuiteRunner.Tests.ps1`, both citation-freshness runs, and
`pwsh ./scripts/test-fast.ps1 -Mode PowerShell` (all 54 suites).

## Review round 1, 2026-09-06

- Finding: `New-SkillFixture` could leave a partial temporary directory when the build throws.
  The caller cannot clean it, because a throw means the function never returns the path. Fixed:
  the build now runs inside try/catch, removes the root, and rethrows.
- Proof: a probe called the function with a tree the build loop cannot read. The pre-fix copy
  left 1 directory in the system temp folder; the fixed copy left 0. No permanent test was added.
  This is internal test-harness cleanup with no observable surface, which is AGENTS.md
  verification exemption 2.
- Finding: the item stayed at `6-verify` until the gate ran. Correct, and the gate has now run,
  so the item moved to `7-document`.
- The stage move made `BacklogPlanPointer.Tests.ps1` start reading this item, and it failed: the
  `- Plan:` bullet had no backticks around the path. Fixed in the same round.

## Document verdict

Nothing to document. The change is internal to one test suite. No behaviour, vocabulary, or rule
moved, so no doc, README, `CONTEXT.md`, or skill needed an edit.

## Gate, 2026-09-06

- `dotnet build AHKFlowApp.slnx --configuration Release` - 17 projects, 0 errors, 0 warnings.
- `dotnet format AHKFlowApp.slnx --verify-no-changes` - clean.
- `pwsh ./scripts/test-fast.ps1 -Mode PowerShell` - all 54 suites passed.
- `pwsh ./scripts/test-fast.ps1 -Mode Coverage` - all per-assembly thresholds met. Line 94.6%,
  branch 82.8%.
- `git diff --check main...HEAD` and the bare form - both clean.
