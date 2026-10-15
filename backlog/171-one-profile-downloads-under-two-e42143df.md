# 171 - One profile downloads under two different file names

## Metadata

- **Epic**: Script generation & download
- **Type**: Bug
- **Interfaces**: UI | API | CLI
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Two copies of the file-name rule run their steps in opposite orders, so the same profile is
`ahkflow_<stem>_.ahk` inside the zip and `<timestamp>_ahkflow_<stem>.ahk` when downloaded on its
own.

## User story

As an owner, I want one profile to have one file name, so that my downloaded scripts are
consistent wherever they come from.

## Acceptance criteria

- [ ] One rule decides a profile's file stem, and both the API and the UI use it.
- [ ] A profile whose stem has an underscore at character 64 downloads under the same stem from
      the single download and from the zip.
- [ ] A unit test covers the truncate-then-trim case that produces the trailing underscore.
- [ ] `DownloadsApiClient`'s `ahkflow_profile.ahk` fallback is either reached by some path or
      removed.

## Out of scope

- Changing the timestamp prefix on the UI download. That is a separate choice.
- The line endings and the byte-order mark of a downloaded script. Backlog 183 owns them.
- Running a generated `.ahk` file. The project never runs scripts.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F29 (S3). Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F29, the two names.** Reproduced with a profile name of 63 letters, a space, then `bbb`, so
  the stem has an underscore at character 64 exactly. `ProfileRules` allows 100 characters, so
  this is reachable. The API's `Content-Disposition` header named it
  `ahkflow_aaa…a_.ahk` with a trailing underscore. The page's own message after the Download
  button said `Downloaded 20261013_033414_ahkflow_aaa…a.ahk` with no underscore.
- The cause is step order. `AhkFileNaming.ToSafeStem` collapses unsafe characters, then trims
  edge underscores, then truncates to 64. `ProfileScriptDownloader.SafeStem` collapses, then
  truncates to 64, then trims. The UI version's own comment explains why its order is the right
  one: the cut to 64 can leave a trailing underscore that an earlier trim never saw. The API uses
  exactly the order that comment calls out as wrong.
- Nobody noticed because the UI never uses the API's answer. `DownloadsApiClient` passes
  `ahkflow_profile.ahk` as a fallback and `GetFileAsync` stores the result in
  `FileDownload.FileName`, but `ProfileScriptDownloader.DownloadAsync` builds its own name and
  never reads that field. The zip path in `Pages/Downloads.razor` does the same. So the fallback
  can never reach an owner.
- The zip keeps the API's names, which is how both names end up in front of the same owner.
- The CLI also keeps the API's name. `ahkflow` reads the `Content-Disposition` header and saves
  the file under it, so a CLI download carries the same trailing underscore.
- **Split at pickup, one pull request per outcome.** The sweep found three outcomes. This item
  keeps outcome 1, the one file name, because it is a defect with one correct answer. Outcomes 2
  and 3, the line endings (F30) and the byte-order mark (F31), are policy decisions about the
  bytes of a downloaded file. They moved to backlog 183 at this item's Pickup on 2026-10-15.
- Spec: none — F29 has one correct answer already written down in the UI's comment.
- Plan: none — moderate work, goes straight to Plan at pickup.
