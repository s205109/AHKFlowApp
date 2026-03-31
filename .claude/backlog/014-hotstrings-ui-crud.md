# 014 - Hotstrings UI CRUD

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: UI

## Summary

Implement Web UI screens/components to create, edit, delete, and list hotstrings per profile.

## User story

As a user, I want to manage hotstrings in the Web UI so that I can maintain my automation without a CLI.

## Acceptance criteria

- [ ] List hotstrings for the active profile.
- [ ] Create and edit hotstrings with validation feedback.
- [ ] Delete hotstrings with a confirmation step.
- [ ] UI handles API errors consistently (see 016).
- [ ] Unit/component tests cover the main UI components (list, create, edit) including validation states.
- [ ] Integration/E2E tests exercise the create/list/delete flows against a running test API.

## Out of scope

- Advanced formatting/preview.

## Notes / dependencies

- Depends on 013.
- Assumes at least one profile exists (a seeded default is fine until 024 is implemented).
