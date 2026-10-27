# 197 - The CLI quickstart prints commands that do not run

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI | CLI
- **Difficulty**: moderate
- **Stage**: 7-document

## Summary

The CLI quickstart card on the home page prints two commands the CLI does not define. Each one
has its own Copy button, so an owner copies a command that fails.

## User story

As an owner, I want every command on the CLI quickstart card to run, so that I can trust what the
app tells me.

## Acceptance criteria

- [x] Every command on the CLI quickstart card runs as printed against the current CLI, for a
  signed-in owner who has the profile the command names. The card tells the owner to replace
  `work` with an existing profile name.
- [x] A test or a check proves each quickstart command names a command the CLI actually defines.

## Out of scope

- The product name and the page names. Backlog 170 owns them.
- New CLI commands. The card changes to match the CLI, not the other way round.

## Notes / dependencies

- Split from backlog 170 at its Pickup on 2026-10-26. Item 170 asked for one pull request per
  outcome, and for this outcome to ship first: a printed command that fails is worse than a name
  spelled four ways.
- Found by the acceptance sweep on 2026-10-13, finding F1 (S2). Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F1, the quickstart card.** `Components/Home/CliQuickstartCard.razor` prints
  `ahkflow new "yw" "you're welcome" --profile work` and `ahkflow list --profile work --grep
  "typo"`. The CLI's own `--help` defines four commands: `login`, `logout`, `hotstring` and
  `download`. There is no root `new` and no root `list`, and `NewHotstringCommand` takes
  `--trigger` and `--replacement` as options, never as positional arguments. The third line,
  `ahkflow download ahk --profile work`, is correct.
- The correct forms are `ahkflow hotstring new --trigger "yw" --replacement "you're welcome"
  --profile work` and `ahkflow hotstring list --profile work --grep "typo"`. On 2026-10-26,
  `ListHotstringCommand.cs` defines `--grep` as an alias of `--search`, and `AhkDownloadCommand.cs`
  defines `--profile`.
- The app already documents the right syntax elsewhere. `changelog.json` says
  "`ahkflow hotstring list` shows a Kind column". Only the quickstart card is wrong.
- The plan review on 2026-10-27 narrowed criterion 1. Every owner starts with one profile, named
  `Default`, so a new owner who copies a `--profile work` line gets exit code 2. The criterion used
  to promise that every line runs for everyone. It now states the prerequisite, and the card says
  what to replace.
- **How criterion 1 was checked, on 2026-10-27.** Nobody ran the three printed strings against a
  live API. A parse test (`CliQuickstartCardTests.cs`) proves that each printed line parses against
  `RootCli.Build` with no error and reaches a command with an action. The CLI integration tests run
  the same options against a real API: `-p` for `hotstring new`, `--profile` and `--search` for
  `hotstring list`, and `--profile` for `download ahk`. That `--grep` is an alias of `--search`
  rests on reading `ListHotstringCommand.cs`, not on a test that passes `--grep`.
- Spec: none — the CLI's own command tree already defines the correct commands.
- Plan: `docs/superpowers/plans/2026-10-27-cli-quickstart-commands-plan-197.md`
