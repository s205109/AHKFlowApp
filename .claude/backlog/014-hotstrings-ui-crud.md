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

- [x] List hotstrings for the active profile.
- [x] Create and edit hotstrings with validation feedback.
- [x] Delete hotstrings with a confirmation step.
- [x] UI handles API errors consistently (see 016).
- [x] Unit/component tests cover the main UI components (list, create, edit) including validation states.
- [x] Integration/E2E tests exercise the create/list/delete flows against a running test API.

## Out of scope

- Advanced formatting/preview.

## Notes / dependencies

- Depends on 013.
- Assumes at least one profile exists (a seeded default is fine until 024 is implemented).

---

**Completed:** 2026-04-29
