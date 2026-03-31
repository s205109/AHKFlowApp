# 025 - Header templates per profile

## Metadata

- **Epic**: Profiles
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Allow users to define an AHK header template per profile that is prepended to generated `.ahk` scripts.

## User story

As a user, I want a header template per profile so that generated scripts include consistent metadata and setup code.

## Acceptance criteria

- [ ] Store a header template per profile.
- [ ] UI provides an editor for the template.
- [ ] Script generation prepends the header (if configured).
- [ ] Validation enforces reasonable size limits.
- [ ] Unit tests for template storage, validation, and size limits.
- [ ] Integration tests ensure generated scripts include the header when configured.

## Out of scope

- Template versioning.

## Notes / dependencies

- Depends on 024.
