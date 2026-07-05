# 021 - Hotkeys API CRUD

## Metadata

- **Epic**: Hotkeys
- **Type**: Feature
- **Interfaces**: API

## Summary

Provide REST endpoints to create, update, delete, and list hotkeys within a profile.

## User story

As a client (UI), I want a hotkey CRUD API so that hotkeys can be managed centrally.

## Acceptance criteria

- [x] Endpoints: create, update, delete, get-by-id, list-by-profile.
- [x] Endpoints are secured (see 012).
- [x] Input validation and problem details are consistent with hotstrings.
- [x] Unit tests for hotkey controller/service logic and validation.
- [x] Integration tests for API endpoints verifying auth, validation, and database behavior.

---

**Superseded:** initial shape implemented 2026-05-01 (PR #101); replaced by **022b** (PR #107, 2026-05-03) which rebuilt the schema from free-form `Trigger/Action/Description` to structured fields. Kept as historical record.

## Out of scope

- Hotkey CLI support.
- Hotkey blacklisting rules (explicitly planned for future).

## Notes / dependencies

- Depends on 003 and 012.
- Assumes profiles exist (a seeded default is fine until 024 is implemented).
- **Superseded by 022b** (Hotkey schema rebuild). The shape shipped here — free-form `Trigger` + `Action` strings + nullable single `ProfileId` — will be replaced by the structured schema (`Description/Key/Ctrl/Alt/Shift/Win/Action enum/Parameters` + M2M profile association). Kept in the backlog as a historical record.
