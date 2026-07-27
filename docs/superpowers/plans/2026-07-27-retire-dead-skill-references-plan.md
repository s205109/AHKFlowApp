# Retire dead skill references

## Context

Six `.agents/` directories held a `REFERENCE.md` file and no `SKILL.md`:

| Directory | Lines |
| --- | --- |
| `dck-testing` | 341 |
| `dck-error-handling` | 271 |
| `dck-httpclient-factory` | 143 |
| `dck-configuration` | 89 |
| `dck-serilog` | 85 |
| `dck-modern-csharp` | 81 |

That is 1010 lines in total. No agent loaded any of them. Claude Code, GitHub
Copilot, and the Codex plugin all skip a directory with no `SKILL.md`. A search
across the repository found no operational reference to these files. Only older
plan documents mention them.

They got into that state on purpose. Commit `45278aa` (2026-07-16) renamed each
`SKILL.md` to `REFERENCE.md` to switch the skill off. The commit message gives two
reasons:

> Ambient triggers ("use when writing C#") never fire — no discrete moment to load
> a reference. Content already in always-loaded AGENTS.md, so each was a second
> source of truth that could drift.

Both reasons were sound. The chosen mechanism was not. Parking a file keeps it in
the repository while nothing reads it, so it goes stale without anyone noticing.
That already happened. `dck-testing/REFERENCE.md` taught a per-class
`MsSqlContainer` that each test migrates by hand. The live suite uses a shared
`[Collection("WebApi")]` with `ApiTestFixture`
(`tests/AHKFlowApp.API.Tests/Hotstrings/HotstringsEndpointsTests.cs:12-15`).

The tooling encouraged the pattern. Both setup scripts carried a list of directory
names to ignore: `skills`, `plugins`, `skills.disabled`, `disabled`, `reference`,
`references`. Four of those six names are parking spots.

## Decision

Retiring a skill means deleting its directory. Git history is the archive.

There is no parking directory and no disabled state. A skill is either active with
a `SKILL.md`, or it is gone.

## Changes

1. Delete the six directories. The normative project rules they held were already
   moved into `AGENTS.md` by commit `45278aa`. All eight were checked and are
   present. Only general .NET teaching material is lost, and git history keeps it.

2. Trim the ignore list to `skills` and `plugins` in both setup scripts
   (`setup-cross-agent-skills.ps1` and `setup-cross-agent-skills.sh`). Update the
   header comments that described reference and disabled directories as normal.

3. Add `tests/SkillLayout.Tests.ps1`. It fails when any `.agents/` directory has no
   `SKILL.md`, apart from the two allowed names. The failure message explains the
   rule and shows how to read a deleted skill from git history.

4. Run the new test in the existing `worktree-powershell-tests` CI job. That job
   already runs `tests/SkillParity.Tests.ps1`, so it is the established home for
   skill-tree tests.

5. Rewrite the "Deactivated skills" section of `.claude/skills/README.md`. It
   documented `REFERENCE.md` as the official way to retire a skill, which the new
   test now blocks.

## Why no rule in AGENTS.md

`AGENTS.md` is always loaded, for every agent, in every session. A rule about
retiring a skill is needed perhaps once a year. Putting it there would pay context
cost forever for a rare event. That is the same ambient-trigger problem that
commit `45278aa` diagnosed in the first place.

The CI failure message carries the rule instead. It appears at the exact moment
someone breaks it, which is a discrete trigger rather than an ambient one.

## Guarding the allowlist

Three copies of the allowlist now exist: both setup scripts and the test. The test
reads the list out of each setup script and compares all three. If they ever
disagree, the test fails and names the file that is out of step.

## Verification

- `pwsh ./tests/SkillLayout.Tests.ps1` passes after the deletion. It reports 25
  active skills.
- A planted `.agents/dck-parked/REFERENCE.md` makes it fail and names the
  directory. The planted directory was then removed.
- Changing the bash allowlist to add `disabled` makes it fail and names the file.
  The change was then reverted.
- `pwsh ./scripts/agents/setup-cross-agent-skills.ps1` completes clean. No symlink
  or hard link changed, and the Codex plugin content hash is unchanged.

Verification exemption 1 does not apply, because this change adds a test script and
a CI step. The runs above are the evidence.

## Not in scope

The twelve surviving skills hold about 1511 lines of code templates that can drift
the same way `dck-testing` did. That drift is semantic, so no lint can catch it.
A separate GitHub issue tracks a rewrite that would cite live files instead of
inlining templates.

## Unresolved questions

None.
