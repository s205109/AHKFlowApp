# 057 - The Downloads page leaves a row disabled when the file save fails

## Metadata

- **Epic**: Script generation & download
- **Type**: Defect
- **Interfaces**: UI

## Summary

`DownloadProfileAsync` in `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Downloads.razor:111-131` does not
catch a failure from `IFileSaver.SaveAsync`. `JsFileSaver` calls into JavaScript
(`src/Frontend/AHKFlowApp.UI.Blazor/Services/JsFileSaver.cs:11`), so a browser that refuses the
write raises a `JSException`.

The `finally` block clears `_busyProfileId`, but the event task ends faulted. Blazor's
`ComponentBase` skips its own re-render after a faulted event task, so the row's Download button
stays drawn as disabled. The user sees a dead button and no message. Any later render fixes it, so
the state is stale rather than permanent.

The Profiles page already handles this: `src/Frontend/AHKFlowApp.UI.Blazor/Pages/Profiles.razor:363`
catches `JSException` and shows "Saving the file failed.". The Downloads page was left alone on
purpose, because backlog 055 put changes to that page out of scope. The two pages now differ.

## Acceptance criteria

- [ ] A failed file save on the Downloads page shows an error message
- [ ] The row's Download button works again straight after the failure
- [ ] Both pages report a failed save with the same wording
- [ ] A bUnit test covers the failing save on the Downloads page

## Out of scope

- Changing what `ProfileScriptDownloader` does. It lets the exception travel on by design, so each
  page decides how to report it

## Notes / dependencies

- Found while reviewing backlog 055
- The same fix shape as `Profiles.razor:363` — a `catch (JSException)` beside the existing
  cancellation catch
