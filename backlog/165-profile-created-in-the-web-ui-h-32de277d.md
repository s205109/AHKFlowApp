# 165 - Profile created in the web UI has no script directives

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 1-pickup

## Summary

Every profile an owner creates in the web UI stores an empty header template, so its generated
script carries no `#Requires AutoHotkey v2.0` and no `SetTitleMatchMode 2`. The script may fail
to load on a machine that also has AutoHotkey v1, and window contexts match the wrong windows
when it does load.

## User story

As an owner, I want a profile I create to generate a script that loads and behaves like the
seeded Default profile, so that I do not have to know which directives a script needs.

## Acceptance criteria

- [ ] A profile created through the web UI generates a script whose first lines contain
      `#Requires AutoHotkey v2.0`, `#SingleInstance Force`, `SendMode "Input"` and
      `SetTitleMatchMode 2`.
- [ ] A profile created through `POST /api/v1/profiles` with `headerTemplate` set to an empty
      string generates the same header as one that omits the field.
- [ ] An integration test covers the empty-string case and fails when the fallback is skipped.
- [ ] Editing an existing profile still keeps the header the owner saved, including a header the
      owner cleared on purpose if the item keeps that option.

## Out of scope

- Changing what the default header contains.
- Running a generated `.ahk` file to confirm it loads. The project never runs scripts.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F21, the only S1 of 31 findings. Full
  evidence in `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and
  gitignored.
- Root cause, a three-step chain. `Validation/ProfileEditModel.cs` initialises
  `HeaderTemplate` and `FooterTemplate` to `""` rather than null. The model passes both straight
  into the create DTO. `Commands/Profiles/CreateProfileCommand.cs` then falls back to
  `DefaultProfileTemplates.Header` with `??`, which fires only on null. So the UI always sends
  an empty string, the fallback never runs, and the empty string is stored.
- Proven by comparing creation paths. A profile created through the API with `headerTemplate`
  omitted stored 277 header characters. A profile created in the web UI stored 0.
- Editing is not affected. `ProfileEditModel.FromDto` loads the stored template, and a rename
  preserved all 277 characters.
- The CLI has no profile command, so the web UI is the only way an owner creates a profile.
  Every owner-created profile is affected.
- **Open question for Design.** Coercing `""` to the default on the server would stop an owner
  ever clearing the header on purpose. The alternative is for `ProfileEditModel` to start from
  `DefaultProfileTemplates` so the owner sees and edits a real template. Decide which before
  writing code.
- Spec: none — pick one of the two options above at Design.
- Plan: none — moderate work, goes straight to Plan at pickup.
