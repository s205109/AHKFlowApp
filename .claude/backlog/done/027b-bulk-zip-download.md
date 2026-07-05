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

- [x] `GET /api/v1/downloads/zip` returns `application/zip` with `Content-Disposition: attachment; filename="ahkflow_scripts.zip"`.
- [x] Zip contains one entry per profile, named `ahkflow_{profile_name}.ahk` (sanitized to remove path-unsafe characters).
- [x] Endpoint authenticated; only the calling user's profiles are included.
- [x] UI: top-of-page button on `Pages/Downloads.razor` labelled "Download all (zip)".
- [x] Integration test: seed two profiles, hit the endpoint, assert zip entry count + filenames + content matches per-profile generator output.

---

**Completed:** 2026-05-08 (PR #109)

## Format decisions (locked in plan 2026-05-07, Phase 5)

- **Content type**: `application/zip` (binary; no charset).
- **Outer filename**: `ahkflow_scripts.zip` (constant).
- **Entry filenames**: `ahkflow_{safe_stem}.ahk` using the same sanitization rule as backlog 027.
- **Performance**: bulk handler loads `Profiles`, `Hotstrings.Include(Profiles)`, `Hotkeys.Include(Profiles)` once each for the owner and partitions in memory — three round-trips regardless of profile count, no N+1.
- **Collision handling**: when sanitization produces a duplicate entry name, append `_2`, `_3`, … to the stem. Profile names are unique per owner (Phase 1 unique constraint), so collisions only happen via lossy sanitization.
- **Zero-profile request**: returns an empty `application/zip` (200, zero entries). The Downloads page calls `/api/v1/profiles` first (which lazy-seeds the default profile), so this is rare in practice.

## Out of scope

- Selecting a subset of profiles to zip.
- Streaming for very large profile sets (we'll buffer; revisit if profile count grows).

## Notes / dependencies

- Depends on **026** and **027** (reuses the per-profile generator + endpoint behavior).
- Design spec: `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 5, decision D5).
