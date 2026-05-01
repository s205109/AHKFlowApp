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

- [ ] `GET /api/v1/downloads/{profileId}` returns `text/plain` (or `application/octet-stream`) with `Content-Disposition: attachment; filename="ahkflow_{profile_name}.ahk"`.
- [ ] Endpoint is authenticated (per 012) and scoped to the user's own profiles (404 for other users' profileId).
- [ ] UI: `Pages/Downloads.razor` lists every profile with a per-row Download button that triggers the endpoint.
- [ ] Integration tests: content-type, content-disposition filename, auth challenge, owner scoping (other-user profileId returns 404).
- [ ] Unit test on the controller wiring `AhkScriptGenerator` → bytes → response headers.

## Out of scope

- Bulk zip download (covered in **027b**).
- Caching / ETag.
- Multi-variant scripts (e.g., compressed, signed).

## Notes / dependencies

- Depends on **026** (script generation).
- Design spec: `C:\Users\btase\.claude\plans\start-your-work-on-validated-walrus.md` (Phase 5).
