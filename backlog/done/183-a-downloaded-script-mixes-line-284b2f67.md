# 183 - A downloaded script mixes line endings and has no byte-order mark

## Metadata

- **Epic**: Script generation & download
- **Type**: Bug
- **Interfaces**: UI | API | CLI
- **Difficulty**: moderate
- **Stage**: 9-ship

## Summary

A generated script mixes CRLF and LF line endings, and it starts with no byte-order mark. Both are
decisions about the bytes of a downloaded file. Backlog 171 split them off from its file-name fix.

## User story

As an owner, I want a downloaded script to use one kind of line ending and to open in my editor
with the right encoding, so that the file stays clean when I edit it or put it under version
control.

## Acceptance criteria

- [x] A downloaded script uses one line ending throughout.
- [x] The byte-order mark decision is recorded, either by writing one or by writing down why not.

## Out of scope

- The file name of a downloaded script. Backlog 171 owns it.
- Running a generated `.ahk` file. The project never runs scripts.

## Notes / dependencies

- Split from backlog 171 at its Pickup on 2026-10-15. The notes of 171 asked for one pull request
  per outcome. This item holds outcomes 2 and 3, which may ship together, because both change the
  bytes an owner's editor sees.
- Filed on the branch of 171, not in its own worktree. It reaches `main` when 171 merges.
- Found by the acceptance sweep on 2026-10-13, findings F30 and F31 (S4). Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
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
- The zip download writes its entries in a second place. `GenerateAllProfileScriptsZipQueryHandler`
  uses a `StreamWriter` with `new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)`. So each
  decision must reach both the single download and the zip.
- Spec: none — two small decisions, each with its evidence written above.
- Plan: `docs/superpowers/plans/2026-10-16-download-line-endings-bom-plan-183.md`
- **Ticked at Document, 2026-10-16, against `4ccd60cf`.** At Review the branch merged `main` at
  `b7a1953b`, and the line numbers below were updated to the merged tree. Evidence for each
  criterion:
  1. The line ending is LF. `AhkScriptGenerator.Generate` turns every CRLF and every lone CR in
     the finished script into LF at
     (`src/Backend/AHKFlowApp.Application/Services/AhkScriptGenerator.cs:57`, "return string.Join(").
     The single download, the zip, and the profile preview all call it. The tests:
     - The generator, for templates and the paste helper:
       (`tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs:1390`, "public void Generate_TemplatesWithCrlfAndLoneCr_EmitsLfOnly()")
       and (`tests/AHKFlowApp.Application.Tests/Services/AhkScriptGeneratorTests.cs:1408`, "public void Generate_ClipboardHelper_EmitsLfOnly()").
     - The API, for the single download and for every zip entry:
       (`tests/AHKFlowApp.API.Tests/Downloads/DownloadsEndpointsTests.cs:208`, "public async Task GET_per_profile_body_is_bom_then_the_script_with_lf_only()")
       and (`tests/AHKFlowApp.API.Tests/Downloads/DownloadsEndpointsTests.cs:228`, "public async Task GET_zip_every_entry_is_bom_then_its_own_script_with_lf_only()").
     - The CLI, for a saved file and for standard output:
       (`tests/AHKFlowApp.CLI.Tests/Integration/DownloadCliIntegrationTests.cs:92`, "public async Task Ahk_Default_WritesFileWithSeededHotstringContent()")
       and (`tests/AHKFlowApp.CLI.Tests/Integration/DownloadCliIntegrationTests.cs:161`, "public async Task Ahk_OutputDash_WritesBytesToInjectedStream()").
     - The web UI, for a file the browser saves:
       (`tests/AHKFlowApp.E2E.Tests/ProfileScriptDownloadFlowTests.cs:17`, "public async Task DownloadFromProfilesPage_SavesThatProfilesScript()").

     The hotstring and hotkey edit dialogs still show the paste helper with CRLF. Those previews
     are text on screen, not a downloaded script, and the plan keeps them out of scope.
  2. The decision is to write a byte-order mark. It is recorded in
     (`docs/development/ahk-v2-syntax.md:120`, "**Byte-order mark.**"), under the section
     (`docs/development/ahk-v2-syntax.md:93`, "### The bytes of a downloaded file").
     One method writes it,
     (`src/Backend/AHKFlowApp.Application/Services/AhkFileEncoding.cs:12`, "public static byte[] GetBytes(string script) =>"),
     and both download paths call it:
     (`src/Backend/AHKFlowApp.API/Controllers/DownloadsController.cs:38`, "byte[] bytes = AhkFileEncoding.GetBytes(result.Value.Content);")
     and (`src/Backend/AHKFlowApp.Application/Queries/Downloads/GenerateAllProfileScriptsZipQuery.cs:41`, "await entryStream.WriteAsync(AhkFileEncoding.GetBytes(script.Content), ct);").
     The tests in criterion 1 check the mark too. The import dialog drops it when it reads a
     downloaded file back:
     (`tests/AHKFlowApp.UI.Blazor.Tests/Components/Hotstrings/HotstringImportDialogTests.cs:209`, "public async Task SelectingFileWithByteOrderMark_PreviewsTheTextWithoutIt()").
