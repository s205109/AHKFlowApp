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

- [x] API supports query parameters for text search and case-insensitive flag when listing hotkeys.
- [x] UI provides search input scoped to the current user's hotkeys. *(filter toggles + active-profile scoping intentionally non-goals — see below.)*
- [x] Search results are paginated or limited to prevent very large responses.
- [x] Unit tests cover search/filter logic and parameter parsing.
- [x] Integration tests verify search behavior and pagination against seeded test data.

---

**Completed:** 2026-05-08 (shipped incidentally with Phase 3 / 022b — mirrors 019)

Implementation:
- `ListHotkeysQuery` LIKE-filters on `Description`, `Key`, `Parameters`; respects M2M `profileId` (junction OR `AppliesToAllProfiles=true` per 024b).
- `HotkeysController.List` accepts `search`, `ignoreCase`, `page`, `pageSize`.
- `Pages/Hotkeys.razor` ships a debounced search box wired to `ListAsync`.
- Tests: `ListHotkeysQueryHandlerTests` (search by Key/Description/Parameters), `HotkeysEndpointsTests` (search-by-key, search-too-long 400, page+pageSize, pageSize-too-large 400).

Deliberate non-goals (mirrors 019):
- **Filter toggles** (Ctrl/Alt/Shift/Win/Action). YAGNI — no signal anyone wants per-modifier filtering; search box already finds by key/description/parameters.
- **Active-profile scoping** in UI. The app has no global "active profile" concept on any page; introducing one only here would create UX inconsistency with Hotstrings.

Known no-op (cross-cutting, not 023):
- `ignoreCase` query param exists but is unused — SQL Server's default collation is already CI. Same defect on Hotstrings. Either remove or implement properly as a separate cleanup.

## Out of scope

- CLI support for hotkey search (hotkey CLI management is out of scope).
- Full-text indexing or advanced ranking.

## Notes / dependencies

- Depended on **022b** (Hotkey schema rebuild) and **022** (redesigned Hotkeys UI). Search operates on the new structured fields (`Description`, `Key`, `Parameters`) and respects M2M profile filtering (junction OR `AppliesToAllProfiles=true` per **024b**).
