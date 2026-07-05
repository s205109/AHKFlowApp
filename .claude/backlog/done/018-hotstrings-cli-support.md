# 018 - Hotstrings CLI support (create/list + JSON)

## Metadata

- **Epic**: Hotstrings
- **Type**: Feature
- **Interfaces**: CLI

## Summary

Provide a CLI that consumes the API to create and list hotstrings, including a `--json` output option.

## User story

As a power user, I want a CLI to manage hotstrings so that I can script and automate changes.

## Acceptance criteria

- [x] `ahkflow hotstring new` creates a hotstring in a profile.
- [x] `ahkflow hotstring list` lists hotstrings for a profile.
- [x] `--json` emits structured JSON.
- [x] CLI uses the same contracts and validation behavior as the API (see 015).
- [x] Unit tests cover CLI argument parsing, command handlers, and output formatting.
- [x] Integration tests validate CLI commands against a test API (or via API mocks) verifying end-to-end behavior.

## Out of scope

- Hotkey management via CLI.

## Notes / dependencies

- Depends on 012, 013, 015, 017.

**Completed:** 2026-05-09
