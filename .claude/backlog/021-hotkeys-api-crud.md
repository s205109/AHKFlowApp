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

- [ ] Endpoints: create, update, delete, get-by-id, list-by-profile.
- [ ] Endpoints are secured (see 012).
- [ ] Input validation and problem details are consistent with hotstrings.
- [ ] Unit tests for hotkey controller/service logic and validation.
- [ ] Integration tests for API endpoints verifying auth, validation, and database behavior.

## Out of scope

- Hotkey CLI support.
- Hotkey blacklisting rules (explicitly planned for future).

## Notes / dependencies

- Depends on 003 and 012.
- Assumes profiles exist (a seeded default is fine until 024 is implemented).
