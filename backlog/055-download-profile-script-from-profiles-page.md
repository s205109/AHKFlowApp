# 055 - Download a profile script from the Profiles page

## Metadata

- **Epic**: Script generation & download
- **Type**: Feature
- **Interfaces**: UI

## Summary

The Profiles page (`/profiles`) already shows a profile's generated script in its **Script preview**
panel, but offers no way to save it. To save it an owner must go to the Downloads page
(`/downloads`), which lists the same profiles a second time. Add a per-row download button to the
Profiles page, so the download sits with the profile.

## User story

As a profile owner, I want to download a profile's `.ahk` script from the Profiles page so that I do
not have to find the same profile again on a second page.

## Acceptance criteria

- [ ] A download button sits in each Profiles row, between expand and edit
- [ ] Pressing it saves the same file the Downloads page saves for that profile — same content, same
      filename. Both pages call one shared `ProfileScriptDownloader`, so the two cannot drift
- [ ] The button is disabled while the row is being edited, and on the unsaved new-profile row. The
      server builds the script from saved data, so downloading mid-edit would hand back a file that
      does not hold the unsaved change
- [ ] A disabled button explains itself. MudBlazor sets `pointer-events: none` on disabled buttons,
      so the reason rides on a `MudTooltip` wrapper and on the button's own `aria-label`
- [ ] While one download runs, every row's download button is disabled, and the running row shows a
      spinner. All rows become usable again after success, after failure, and after cancellation
- [ ] Cancelling by leaving the page shows no snackbar
- [ ] The Actions column keeps its shape when a row enters edit mode — the button is present in both
      action groups
- [ ] An end-to-end test downloads from `/profiles` and asserts the saved text is that profile's
      script

## Out of scope

- Any change to the Downloads page's own behaviour. It keeps its per-row Download and its
  **Download all (zip)**
- Bulk download from the Profiles page, and multi-select
- Deleting the Downloads page. Keeping both pages was chosen deliberately — it is the smaller
  change, and it moves no bulk feature

## Notes / dependencies

- No backend work. `GET /api/v1/downloads/{profileId}` already exists
  (`src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs:28-34`), and `Profiles.razor:178`
  already injects `IDownloadsApiClient` for the preview panel
- Design: `docs/superpowers/specs/2026-08-05-profiles-page-download-design.md`
- Plan: `docs/superpowers/plans/2026-08-05-profiles-page-download-plan.md`
- The extraction moves `SafeStem` out of `Downloads.razor` and changes one edge case on purpose: the
  stem is now truncated to 64 characters **before** trailing `_` is trimmed, not after. Today's
  order can leave a trailing `_` on a long name. See spec §5.2
- Backlog 053 was found while writing the spec — the same MudBlazor disabled-button rule, in
  `KnownShortcutUseActions.razor`. Separate item, not part of this work
