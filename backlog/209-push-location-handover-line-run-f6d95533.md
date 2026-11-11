# 209 - Push-Location handover line runs in the wrong folder

## Metadata

- **Epic**: Development process
- **Type**: Bug
- **Interfaces**: none (`docs/development/workflow.md`, the `handover-commands` skill)
- **Difficulty**: moderate
- **Stage**: 4-execute

## Summary

The handover rule gives a tool with no directory option one line
(`docs/development/workflow.md:1142`, "`Push-Location <absolute path>; <command>; Pop-Location`.").
In pwsh 7.6.9 that line runs the command in the wrong folder when the folder is missing, and it
leaves the terminal in the new folder when the command throws. This item replaces it with a line
that stops before the command and always returns to the folder where it started.

## User story

As the human who runs handed-over commands, I want the one-line folder form to stop when its
folder is missing and to return when its command fails, so that a command never runs in the wrong
repository and my terminal stays where I left it.

## Acceptance criteria

- [ ] The rule for a tool with no directory option in `docs/development/workflow.md` gives
      `Push-Location <absolute path> -ErrorAction Stop; try { <command> } finally { Pop-Location }`.
- [ ] Both copies of the `handover-commands` skill, `.agents/handover-commands/SKILL.md` and
      `plugins/ahkflowapp/skills/handover-commands/SKILL.md`, quote that rule word for word, and
      `tests/HandoverRules.Tests.ps1` passes.
- [ ] No handover rule in `docs/development/workflow.md` or in either skill copy still gives
      `Push-Location <absolute path>; <command>; Pop-Location`.

## Out of scope

- The specs and plans of backlog 075, which quote the old line as history.
- The rule's other bullets, such as the ban on `cd`, `Set-Location` and a leading `!`.

## Notes / dependencies

- Evidence from pwsh 7.6.9 on the build PC, 8 November 2026. Each case ran as one line, the way
  the console runs one pasted line:
  - Old line, missing folder: `Push-Location` wrote "Cannot find path ... because it does not
    exist.", and the line went on. The command printed "COMMAND RAN in C:\Users\btase", the
    folder the line started in.
  - Old line, a command that throws: the line stopped at the throw, so `Pop-Location` never ran.
    The terminal stayed in `C:\Windows`.
  - New line, missing folder: the line stopped before the command, and the folder did not change.
    One entry stays on the location stack (`Get-Location -Stack`), but no folder changes.
  - New line, a command that throws: `finally` ran, and the terminal returned to its start folder.
- A commit chained with `&&` goes inside `try`. Right after `finally { ... }`, `&&` fails to parse
  with "Unexpected token '&&' in expression or statement."
- Found while designing the personal skill `corries-pig-cycle-steps`, which uses the new line. Its
  design is outside this repository:
  `C:\Users\btase\.claude\docs\superpowers\specs\2026-11-08-stapjes-design.md`, under "The folder".
- Spec: none — a one-line rule change, with the evidence above.
- Pickup classification: moderate — filed items require a plan under the current workflow.
- Plan: `docs/superpowers/plans/2026-11-11-209-push-location-handover.md`
