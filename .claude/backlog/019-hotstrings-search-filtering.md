# 019 - Hotstrings search & filtering (grep, ignore-case)

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: UI | API | CLI

## Summary

Add search and filtering capabilities for hotstrings across UI, API, and CLI with optional case-insensitive matching.

## User story

As a user, I want to search and filter hotstrings so I can quickly find, edit, and manage relevant definitions.

## Acceptance criteria

- [x] API supports query parameters for text search and case-insensitive flag when listing hotstrings.
- [x] UI provides search input and filter toggles scoped to the active profile.
- [ ] CLI supports `--grep` and `--ignore-case` flags matching the UI behavior and returns JSON when `--json` is used. (Deferred to 029)
- [x] Search results are paginated or limited to prevent very large responses.
- [x] Unit tests cover search/filter logic and parameter parsing.
- [x] Integration tests verify search behavior and pagination against seeded test data.

---

**Completed:** 2026-04-29 (API + UI; CLI deferred to 029)

## Out of scope

- Full-text indexing or advanced ranking.

## Notes / dependencies

- Depends on 013 (list-by-profile endpoint) and 018 (CLI support).
- The `profileId` filter behavior changes once **024b** lands: filter must include rows whose junction matches OR `AppliesToAllProfiles=true`. Existing tests should be updated then.
