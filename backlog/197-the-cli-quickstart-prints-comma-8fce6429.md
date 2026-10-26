# 197 - The CLI quickstart prints commands that do not run

## Metadata

- **Epic**: Domain model adoption
- **Type**: Defect
- **Interfaces**: UI | CLI
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

The CLI quickstart card on the home page prints two commands the CLI does not define. Each one
has its own Copy button, so an owner copies a command that fails.

## User story

As an owner, I want every command on the CLI quickstart card to run, so that I can trust what the
app tells me.

## Acceptance criteria

- [ ] Every command on the CLI quickstart card runs as printed against the current CLI.
- [ ] A test or a check proves each quickstart command names a command the CLI actually defines.

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
- Spec: none — the CLI's own command tree already defines the correct commands.
- Plan: none — moderate work, goes straight to Plan at pickup.
