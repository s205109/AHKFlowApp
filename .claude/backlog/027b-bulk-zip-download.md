# 027b - Bulk download (zip of every profile script)

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

A single endpoint and UI button that returns a zip containing one `.ahk` per profile owned by the user.

## User story

As a user with several profiles, I want to download all my generated scripts in one zip so I don't have to click each profile individually.

## Acceptance criteria

- [ ] `GET /api/v1/downloads/zip` returns `application/zip` with `Content-Disposition: attachment; filename="ahkflow_scripts.zip"`.
- [ ] Zip contains one entry per profile, named `ahkflow_{profile_name}.ahk` (sanitized to remove path-unsafe characters).
- [ ] Endpoint authenticated; only the calling user's profiles are included.
- [ ] UI: top-of-page button on `Pages/Downloads.razor` labelled "Download all (zip)".
- [ ] Integration test: seed two profiles, hit the endpoint, assert zip entry count + filenames + content matches per-profile generator output.

## Out of scope

- Selecting a subset of profiles to zip.
- Streaming for very large profile sets (we'll buffer; revisit if profile count grows).

## Notes / dependencies

- Depends on **026** and **027** (reuses the per-profile generator + endpoint behavior).
- Design spec: `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 5, decision D5).
