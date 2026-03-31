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

- [ ] `ahkflowapp new` creates a hotstring in a profile.
- [ ] `ahkflowapp list` lists hotstrings for a profile.
- [ ] `--json` emits structured JSON.
- [ ] CLI uses the same contracts and validation behavior as the API (see 015).
- [ ] Unit tests cover CLI argument parsing, command handlers, and output formatting.
- [ ] Integration tests validate CLI commands against a test API (or via API mocks) verifying end-to-end behavior.

## Out of scope

- Hotkey management via CLI.

## Notes / dependencies

- Depends on 012, 013, 015, 017.
