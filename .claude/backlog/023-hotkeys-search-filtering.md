# 023 - Hotkeys search & filtering

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Add search and filtering capabilities for hotkeys across UI and API with optional case-insensitive matching.

## User story

As a user, I want to search and filter hotkeys so I can quickly find and manage relevant shortcuts within a profile.

## Acceptance criteria

- [ ] API supports query parameters for text search and case-insensitive flag when listing hotkeys.
- [ ] UI provides search input and filter toggles scoped to the active profile.
- [ ] Search results are paginated or limited to prevent very large responses.
- [ ] Unit tests cover search/filter logic and parameter parsing.
- [ ] Integration tests verify search behavior and pagination against seeded test data.

## Out of scope

- CLI support for hotkey search (hotkey CLI management is out of scope).
- Full-text indexing or advanced ranking.

## Notes / dependencies

- Depends on **022b** (Hotkey schema rebuild) and **022** (redesigned Hotkeys UI). Search must operate on the new structured fields (`Description`, `Key`, `Parameters`) and respect M2M profile filtering (junction OR `AppliesToAllProfiles=true` per **024b**).
