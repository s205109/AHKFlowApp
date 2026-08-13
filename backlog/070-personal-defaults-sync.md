# 070 - Keep personal-defaults.md in sync with the web preferences box

## Metadata

- **Difficulty**: moderate
- **Stage**: 6-verify

## Problem

The same content lives in three places and drifts independently:

- `.github/instructions/personal-defaults.md` — read by GitHub Copilot (`applyTo: "**"`)
- `AGENTS.md` and `.claude/CLAUDE.md` — read by Claude Code
- The Claude web preferences box — not version controlled, not readable by any tool

Found on 2026-08-10: the repo file says `explicit use cases (IUseCase/IUseCaseHandler)`.
The web box still said `MediatR`. No MediatR package exists in `Directory.Packages.props`.
The repo copy was corrected at some point; the web copy was not. Every chat outside this
repository used the wrong stack description.

## Approach

Make the repo file canonical. Make an edit to it impossible to forget about.

Reuse the hash-parity pattern from `tests/CodexSkillsHashParity.Tests.ps1`. Record a content
hash in the file. A change to the body without a change to the recorded hash fails the suite.
Updating the hash is the moment you also paste the file into the web box.

## Acceptance criteria

- [x] `.github/instructions/personal-defaults.md` carries a sync marker: the content hash of
      the body, and the date it was last pasted into the web preferences box.
- [x] `tests/PersonalDefaultsSyncMarker.Tests.ps1` fails when the body hash and the recorded
      hash differ. The failure message names the file and says to update the web box.
- [x] The suite runs under `pwsh .\scripts\test-fast.ps1 -Mode PowerShell` with the other
      suites. No separate invocation.
- [x] AGENTS.md names `.github/instructions/personal-defaults.md` as the single source for
      personal defaults, and says the web box is a copy.
- [x] The MediatR line is gone from all copies. The repo copy is already correct — check it,
      do not re-edit.

## Out of scope

The suite cannot read the web preferences box. Nothing can. It proves the repo file changed
deliberately; it cannot prove the paste happened. That gap is accepted — the failing test is
the reminder, not the enforcement.

Do not extend this to the ASD-STE100 output style. That file lives at
`~/.claude/output-styles/`, outside any repository. Pulling it in would put a machine-local
path under repo test control.

## Notes / dependencies

The sync marker belongs in an HTML comment, not frontmatter. The file already carries
`applyTo: "**"` for Copilot, and adding keys there risks changing how Copilot loads it.
