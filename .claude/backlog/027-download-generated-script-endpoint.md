# 027 - Download generated script endpoint (per profile)

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: UI | API

## Summary

Authenticated endpoint that returns the generated `.ahk` for a specific profile, plus a Downloads page in the UI listing profiles with a per-row Download button.

## User story

As a user, I want to download the generated script for a profile so that I can install/use it locally.

## Acceptance criteria

- [x] `GET /api/v1/downloads/{profileId}` returns `text/plain` (or `application/octet-stream`) with `Content-Disposition: attachment; filename="ahkflow_{profile_name}.ahk"`.
- [x] Endpoint is authenticated (per 012) and scoped to the user's own profiles (404 for other users' profileId).
- [x] UI: `Pages/Downloads.razor` lists every profile with a per-row Download button that triggers the endpoint.
- [x] Integration tests: content-type, content-disposition filename, auth challenge, owner scoping (other-user profileId returns 404).
- [x] Unit test on the controller wiring `AhkScriptGenerator` → bytes → response headers.

---

**Completed:** 2026-05-08 (PR #109)

## Format decisions (locked in plan 2026-05-07, Phase 5)

- **Content type**: `text/plain; charset=utf-8` (AHK templates may include non-ASCII; `Content-Disposition: attachment` forces download).
- **Filename**: `ahkflow_{safe_stem}.ahk`. `safe_stem` = profile name with `[^A-Za-z0-9._-]` replaced by `_`, runs of `_` collapsed, leading/trailing `_` trimmed, truncated to 64 chars; empty → `profile`.
- **Auth + scoping**: `[Authorize]` + `RequiredScope("access_as_user")`. 404 for non-existent or other-user `profileId` (no separate 403 for foreign ids — matches Profiles convention).
- **UI**: rebuilds placeholder `Pages/Download.razor` → `Pages/Downloads.razor`; route changes from `/download` to `/downloads`. Auth-aware browser save uses JS interop blob save (anchor href doesn't carry bearer token).

## Out of scope

- Bulk zip download (covered in **027b**).
- Caching / ETag.
- Multi-variant scripts (e.g., compressed, signed).

## Notes / dependencies

- Depends on **026** (script generation).
- Design spec: `docs/superpowers/specs/2026-04-30-ahkflow-alignment-design.md` (Phase 5).
