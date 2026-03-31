# 026 - Generate .ahk script per profile

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: API

## Summary

Generate valid AutoHotkey `.ahk` output per profile from stored hotstrings/hotkeys and header template.

## User story

As a user, I want an `.ahk` script generated per profile so that I can download and run a single script representing my definitions.

## Acceptance criteria

- [ ] Generation is profile-scoped.
- [ ] Output includes hotstrings and hotkeys defined in that profile.
- [ ] Output prepends the header template if configured (see 025).
- [ ] Output ordering is deterministic.
- [ ] Unit tests for generation logic to validate formatting and deterministic ordering.
- [ ] Integration tests generate scripts from seeded data and assert expected content and ordering.

## Out of scope

- Runtime execution of AutoHotkey.

## Notes / dependencies

- Depends on 013, 021, 025.
