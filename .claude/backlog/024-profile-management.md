# 024 - Profile management (CRUD + select default)

## Metadata

- **Epic**: Profiles
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Create and manage profiles to organize hotstrings/hotkeys and drive per-profile script generation.

## User story

As a user, I want to create and manage profiles so that I can group automation definitions by context (e.g., work vs personal).

## Acceptance criteria

- [ ] Create, rename/update, list, and delete profiles.
- [ ] Select an active/default profile in the UI.
- [ ] API enforces unique profile names per user/tenant.
- [ ] Deleting a profile defines a clear behavior for attached hotstrings/hotkeys (block unless empty or cascade delete).
- [ ] Unit tests cover profile business rules (unique name enforcement, delete semantics).
- [ ] Integration tests verify profile CRUD flows and interactions with profile-scoped resources.

## Out of scope

- Profile import/export.

## Notes / dependencies

- Required for all profile-scoped features.
