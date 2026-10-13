# 171 - One profile downloads under two different file names

## Metadata

- **Epic**: Script generation & download
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Two copies of the file-name rule run their steps in opposite orders, so the same profile is
`ahkflow_<stem>_.ahk` inside the zip and `<timestamp>_ahkflow_<stem>.ahk` when downloaded on its
own. The generated script also mixes CRLF and LF line endings and carries no byte-order mark.

## User story

As an owner, I want one profile to have one file name and one kind of line ending, so that my
downloaded scripts are consistent wherever they come from.

## Acceptance criteria

- [ ] One rule decides a profile's file stem, and both the API and the UI use it.
- [ ] A profile whose stem has an underscore at character 64 downloads under the same stem from
      the single download and from the zip.
- [ ] A unit test covers the truncate-then-trim case that produces the trailing underscore.
- [ ] A downloaded script uses one line ending throughout.
- [ ] `DownloadsApiClient`'s `ahkflow_profile.ahk` fallback is either reached by some path or
      removed.
- [ ] The byte-order mark decision is recorded, either by writing one or by writing down why not.

## Out of scope

- Changing the timestamp prefix on the UI download. That is a separate choice.
- Running a generated `.ahk` file. The project never runs scripts.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F29 (S3), F30 and F31 (S4). Full evidence
  in `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
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
- **F30, the line endings.** Measured on one generated script: 160 line breaks, of which 23 are
  CRLF. The 23 are the ten header lines and the thirteen lines of the clipboard helper, both of
  which come from C# string literals that `.gitattributes` checks out with CRLF. Every line the
  generator builds itself is joined with `"\n"`, because `AhkScriptGenerator.Generate` ends with
  `string.Join` over `"\n"`. AutoHotkey reads both, so no script breaks; the cost falls on an
  owner who opens the file in an editor or puts it under version control.
- The repository already holds this view for stored definition text. `ahk-v2-syntax.md` says a
  Raw definition is normalised on save, and that step converts CRLF and lone CR to LF.
- **F31, the byte-order mark.** `DownloadsController` builds the file with
  `Encoding.UTF8.GetBytes`, which never writes the preamble, so the file starts with its first
  real character. **The script still works**: the official AutoHotkey v2 FAQ says v2 defaults to
  UTF-8 for all script files, and the arrow hotstring's bytes `E2 86 92` are correct UTF-8 for
  U+2192. The same documentation still recommends saving as UTF-8 with BOM when a file holds
  non-ASCII characters, because an editor otherwise has to guess. So the risk is on the editing
  side, not the running side, which is why this is S4. Four seeded hotstrings hold non-ASCII
  replacements.
- **Split at pickup, one pull request per outcome.** F29 is a defect with one correct answer. The
  other two are policy decisions about the bytes of a downloaded file, and they should not ride
  along with a bug fix:
  1. **One file name.** One rule for the stem, used by the API and the UI, plus the unit test for
     the truncate-then-trim case and the dead `ahkflow_profile.ahk` fallback. F29. Do this first.
  2. **One line ending.** Decide LF or CRLF for a downloaded script, then make the generator and
     the C# literals agree. F30.
  3. **The byte-order mark.** Write one, or write down why not. F31.
  Outcomes 2 and 3 both change the bytes an owner's editor sees, so they can ship together if
  that reads better than two small pull requests. Outcome 1 stays on its own.
- Spec: none — F29 has one correct answer already written down in the UI's comment.
- Plan: none — moderate work, goes straight to Plan at pickup.
