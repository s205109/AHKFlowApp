# 075 - Process wave 5 - commands skill and recap rules

## Metadata

- **Epic**: Development process
- **Type**: Process / documentation
- **Interfaces**: none (skills, agent instructions)
- **Difficulty**: complex
- **Stage**: 4-execute
- **Depends on**: 072-process-wave-2-parity-drift-guard-templates

## Summary

Wave 5 of the development process. Agents still hand the human commands that only work in
one directory, and still end a turn without saying what comes next. This wave writes both
rules down as a skill and enforces them.

## User story

As a contributor, I want every command an agent hands me to run from any directory so
that I never have to work out where to stand first.

## Acceptance criteria

- [ ] A commands skill states that every handed-over command runs from any directory:
      `git -C <path>`, `gh --repo <owner>/<name>`, absolute paths everywhere else.
- [ ] The skill forbids the `!` prefix in a handed-over command. That prefix belongs to
      the Claude Code prompt; in a real shell it changes what the command does.
- [ ] The skill states that a pull request title carries its backlog number.
- [ ] The skill states that a pull request description carries the session id.
- [ ] The Next-step line is enforced in Claude Code: a `Stop` hook refuses the first stop of
      a turn that used a tool and ends without one. The Recap rule is written into
      `workflow.md`, and nothing checks it.

## Out of scope

- Parity check and drift guard — wave 2 (backlog 072).
- Cleanup user experience — wave 3 (backlog 073).
- A CI check on the pull request title or the `Sessions:` list. Only 7 of the last 30 merged
  pull requests (#388 to #418) used the exact `(backlog NNN)` title form, so a later item may
  want one.
- Re-running the friction counts, or changing the 072 metric's patterns.
- A `Stop` hook for Codex or Copilot. Both have a stop event that can make the agent continue
  (checked 2026-09-18). The hook's tool-use test reads Claude Code's transcript format, and
  nobody has checked the Codex or Copilot formats.
- Writing the `Sessions:` bullet with no model tokens. Backlog 081's transition script already
  owns the push, so it is the natural home. Here an agent adds its bullet once, at its first
  push, with one piped command.

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-09-18-commands-skill-and-recap-rules-design-075.md`
  (private plans repo). Parent: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §13.
- Plan: `docs/superpowers/plans/2026-09-18-commands-skill-and-recap-rules-plan-075.md`
- Target: the rules, not a count. Backlog 072 measured 179 directory-bound command lines and
  35 to 89 next-step asks over four weeks. Its command metric counts every command that names
  a directory, so a compliant `git -C <absolute path>` counts too. That metric cannot measure
  this rule, and this item does not re-run it.
