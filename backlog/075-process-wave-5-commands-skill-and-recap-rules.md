# 075 - Process wave 5 - commands skill and recap rules

## Metadata

- **Epic**: Development process
- **Type**: Process / documentation
- **Interfaces**: none (skills, agent instructions)
- **Difficulty**: complex
- **Stage**: 1-pickup
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
- [ ] The recap rule is enforced: every finished piece of work ends with a short recap and
      one or two concrete next steps.

## Out of scope

- Parity check and drift guard — wave 2 (backlog 072).
- Cleanup user experience — wave 3 (backlog 073).

## Notes / dependencies

- Spec: `docs/superpowers/specs/2026-08-10-development-process-design-071.md` §13
  (private plans repo).
- Target: directory-bound commands handed to the human drop to zero, and next-step asks
  drop further, as a direction, not a percentage: backlog 072 has no established baseline yet.
