# 028 - CLI download command

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: CLI

## Summary

Provide a CLI command to download the generated `.ahk` script for a profile via the API.

## User story

As a power user, I want to download scripts via the CLI so that I can automate updates across machines.

## Acceptance criteria

- [ ] `ahkflowapp download ahk --profile <name>` downloads the script.
- [ ] CLI supports choosing an output path or printing to stdout.
- [ ] Authentication is handled consistently (see 012).
- [ ] Unit tests for CLI download command argument handling and output behavior.
- [ ] Integration tests validate download behavior against a test API (including headers and file content).

## Out of scope

- Downloading additional artifacts.

## Notes / dependencies

- Depends on 027.
