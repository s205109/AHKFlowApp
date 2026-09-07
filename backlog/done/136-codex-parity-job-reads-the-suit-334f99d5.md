# 136 - Codex parity job reads the suite manifest

## Metadata

- **Epic**: Testing infrastructure
- **Type**: Chore
- **Interfaces**: none (CI workflow, test runner scripts)
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

`tests/powershell-suites.json` is meant to be the one record of which CI job runs which suite.
The `codex-skills-hash-parity` job does not read it. That job runs its suite directly, so the
manifest's `codex-parity` entry is read by nothing. Make the job go through the runner.

## User story

As a developer adding a suite to the `codex-parity` job, I want the manifest to be the only
place I write that down, so that a suite cannot be listed in one place and run from another.

## Acceptance criteria

- [x] `.github/workflows/ci.yml` runs the `codex-skills-hash-parity` job through
      `scripts/run-powershell-suites.ps1`, selecting the manifest's `codex-parity` set.
- [x] A test fails when the job would run any suite outside the manifest's `codex-parity` set,
      or would miss one inside it.
- [x] The job still runs on `ubuntu-latest`, and the item records why. The current reason is
      that the bash setup script the suite compares against refuses under Windows Git Bash.
- [x] `CodexSkillsHashParity.Tests.ps1` carries `platform: ["linux"]` in the manifest, and the
      runner honours it, so a Windows run does not try to run it.
- [x] The job's log still names the suite that ran, so a failure is as easy to read as it is
      today.

## Out of scope

- Changing what `CodexSkillsHashParity.Tests.ps1` asserts.
- Moving that job to Windows.
- Adding suites to the `codex-parity` job.

## Notes / dependencies

- This item exists because backlog 127's grilling round found the gap. 127 makes the
  `repo-invariants` job read the manifest and leaves this job alone on purpose, to keep 127 to
  one concern.
- Depends on backlog 127. That item adds the runner's `-Job` parameter and the `platform` field.
  Do not start this one before 127 merges, or the parameter this item calls will not exist.
- The suite is one file and the job runs it directly today, so the drift this closes is small.
  The value is that the manifest becomes true for all three jobs rather than two.
- Spec: none — the change is mechanical once 127 ships.
- Plan: `docs/superpowers/plans/2026-09-06-codex-parity-job-manifest-plan-136.md`
- The job stays on `ubuntu-latest`. `scripts/agents/setup-cross-agent-skills.sh` refuses to run
  under Windows Git Bash, and the suite compares that script's hash against the PowerShell one.
  Both bash and pwsh are preinstalled on the ubuntu runner.
- Criteria 4 and 5 were already true when this item started; backlog 127 shipped both. The
  runner refuses the codex-parity job on Windows, naming the suite it dropped, and it wraps each
  suite in a group marker carrying that suite's name inside GitHub Actions.
