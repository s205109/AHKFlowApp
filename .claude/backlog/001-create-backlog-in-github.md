# 001 - Create backlog in GitHub (epics + initial items)

## Metadata

- **Epic**: Backlog setup
- **Type**: Feature
- **Interfaces**: (N/A)

## Summary

Create the epics and initial backlog items as GitHub Issues so planning and tracking can happen in a single source of truth.

## User story

As a product owner, I want the backlog represented in GitHub so that work can be planned, estimated, and tracked consistently.

## Acceptance criteria

- [ ] Epic labels exist in GitHub matching the product vision (Hotstrings, Hotkeys, Profiles, Script Generation & Download, Platform).
- [ ] Initial backlog items are created as GitHub Issues with titles, descriptions, and acceptance criteria matching this repository backlog.
- [ ] Items have a clear ordering (rank/stack order) via GitHub Project board.
- [ ] Labels and issue structure are agreed and applied.

## Out of scope

- Automated synchronization between Markdown and GitHub Issues.

## Notes / dependencies

- Use `docs/scripts/create-github-issues.ps1` to batch-create issues from backlog files via `gh` CLI.
