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

- [ ] API supports query parameters for text search and case-insensitive flag when listing hotstrings.
- [ ] UI provides search input and filter toggles scoped to the active profile.
- [ ] CLI supports `--grep` and `--ignore-case` flags matching the UI behavior and returns JSON when `--json` is used.
- [ ] Search results are paginated or limited to prevent very large responses.
- [ ] Unit tests cover search/filter logic and parameter parsing.
- [ ] Integration tests verify search behavior and pagination against seeded test data.

## Out of scope

- Full-text indexing or advanced ranking.

## Notes / dependencies

- Depends on 013 (list-by-profile endpoint) and 018 (CLI support).
