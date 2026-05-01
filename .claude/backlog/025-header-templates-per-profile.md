# 025 - Header & footer templates per profile

## Metadata

- **Epic**: Profiles
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Per-profile `HeaderTemplate` and `FooterTemplate` text fields, editable in the Profiles UI. Generated `.ahk` scripts are `{HeaderTemplate} + {generated rules} + {FooterTemplate}`.

## User story

As a user, I want each profile to carry its own AHK header and footer so I can customize boilerplate (e.g., a Gaming profile with different `SetCapsLockState` than Work).

## Acceptance criteria

- [ ] `HeaderTemplate` (≤8000 chars) and `FooterTemplate` (≤4000 chars) on the `Profile` entity (defined in 024).
- [ ] New profile defaults: `HeaderTemplate` seeded from `old_project_reference/AHKFlowOldMAUI/AHKFlow.API/Templates/header_template.txt`; `FooterTemplate=""`.
- [ ] UI provides a textarea editor for both fields on the Profile detail/edit view (large, monospace).
- [ ] API validates length limits and returns 400 with ProblemDetails on overflow.
- [ ] Unit tests cover validation/length limits. Integration tests verify round-trip and that `GET /profiles/{id}` returns both fields.

## Out of scope

- Template versioning / history.
- Per-user (cross-profile) default that overrides the seed.

## Notes / dependencies

- This item is largely absorbed into **024** (templates land with the Profile entity in one PR). Kept as a backlog entry for the explicit "footer template" delta from the original 025 scope (header only).
- Depends on **024**.
- Design spec: `C:\Users\btase\.claude\plans\start-your-work-on-validated-walrus.md` (Phase 1, decision D3).
