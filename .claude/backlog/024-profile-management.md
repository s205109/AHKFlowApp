# 024 - Profile management (CRUD + default + templates)

## Metadata

- **Epic**: Profiles
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Introduce the `Profile` entity and its CRUD API/UI. A profile groups hotstrings/hotkeys and carries the `HeaderTemplate` + `FooterTemplate` text used during script generation.

## User story

As a user, I want to create and manage profiles — each with its own AHK header and footer templates — so I can group automation by context (Work, Personal, Gaming) and customize the script boilerplate per group.

## Acceptance criteria

- [ ] `Profile` entity: `Id`, `OwnerOid`, `Name` (≤100, unique per owner), `IsDefault` (exactly one true per owner), `HeaderTemplate` (≤8000), `FooterTemplate` (≤4000), timestamps.
- [ ] On first sign-in, a default profile is seeded for the user (`Name="Default"`, `IsDefault=true`, `HeaderTemplate` seeded with the standard AHK v2 boilerplate defined in the design spec, `FooterTemplate=""`).
- [ ] API endpoints: GET list, GET by id, POST create, PUT update, DELETE — all scoped to the authenticated user.
- [ ] Setting `IsDefault=true` on one profile clears it on others (single-default invariant).
- [ ] DELETE blocked while the profile still has hotkey/hotstring associations (returns 409); user must detach first or use cascade in UI.
- [ ] UI: `Pages/Profiles.razor` lists profiles with inline edit; expand-row textareas for `HeaderTemplate` + `FooterTemplate` (large, monospace font).
- [ ] Unit tests cover invariants (unique name per owner, single-default, delete blocked when associations exist).
- [ ] Integration tests cover CRUD flows + default seeding on first sign-in.

## Out of scope

- Many-to-many profile association of hotkeys/hotstrings (see 024b).
- Profile import/export.
- Template versioning.
- A global "active profile" selector — there is no global selection; profiles are picked per-row when creating hotkeys/hotstrings, or via the "Any" toggle.

## Notes / dependencies

- Combines what was previously split across 024 (entity + CRUD) and 025 (header templates) — templates land with the entity in one PR. Item 025 is now narrowed to "footer template addition" (already covered here) and is effectively absorbed; see 025 note.
- Required for 022, 022b, 024b, 026, 027.
- Design spec: `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 1).
