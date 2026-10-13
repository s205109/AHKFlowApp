# 165 - Profile created in the web UI has no script directives

## Metadata

- **Epic**: Profiles
- **Type**: Bug
- **Interfaces**: UI | API
- **Difficulty**: moderate
- **Stage**: 6-verify

## Summary

Every profile an owner creates in the web UI stores an empty header template, so its generated
script carries none of the four lines the seeded Default profile emits. Two of those lines change
how the script behaves. Without `#SingleInstance Force`, re-running the script asks the owner
whether to replace the running instance. Without `#Requires AutoHotkey v2.0`, a machine that has
both AutoHotkey v1 and v2 installed has to guess which version runs the script, and it asks the
owner when the guess fails.

## User story

As an owner, I want a profile I create to generate the same kind of script as the seeded Default
profile, so that I do not have to know which directives a script needs.

## Acceptance criteria

- [ ] A profile created in the web UI, without the owner changing its template, generates a script
      whose first lines contain `#Requires AutoHotkey v2.0`, `#SingleInstance Force`,
      `SendMode "Input"` and `SetTitleMatchMode 2`.
- [ ] An integration test covers that case and fails when the default header is not applied.
- [ ] Editing an existing profile still keeps the header the owner saved.
- [ ] The item records what an empty header means, and the shipped behaviour matches that record.
      The open question below is the decision, and making it is part of this work.
- [ ] Every profile that already stores an empty header gets the default header, in every
      environment. A profile whose header holds any text keeps that text exactly as it is.
- [ ] A test covers that repair. It proves an empty header is filled, and it proves a header the
      owner wrote is left alone.

## Out of scope

- Changing what the default header contains.
- Running a generated `.ahk` file to confirm it loads. The project never runs scripts.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, finding F21. The sweep filed it as the only S1 of
  31 findings. Review on 2026-10-13 lowered it to S2, because the missing header does not stop a
  script loading. See the next note. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **Two of the four lines restate an AutoHotkey v2 default**, so leaving those two out changes
  nothing at run time. The v2 documentation for `SetTitleMatchMode` says "The default match mode
  is 2 and the default speed is fast", and the documentation for `SendMode` says "The default
  sending mode is Input". The v1-to-v2 changes list says the same twice over: "SendMode defaults
  to Input instead of Event" and "Title matching mode defaults to 2 instead of 1".
- **The other two lines do change behaviour, and in different ways.**
  - `#Requires AutoHotkey v2.0`. The AutoHotkey launcher reads this directive to pick an
    interpreter. Without it the launcher checks the script's syntax for patterns that belong to one
    version only, and when that check cannot decide it shows a menu for the owner to pick a
    version. The launcher page also says a script with real syntax errors or mixed syntax "might be
    misidentified". So this only bites on a machine that has v1 installed as well.
  - `#SingleInstance Force`. This one is not a default, which is easy to get backwards. The
    v1-to-v2 changes list says "#SingleInstance prompt behaviour is default for all scripts;
    #SingleInstance on its own activates Force mode." So a header-less script asks the owner
    whether to replace the running instance, every time they re-run it, on every machine.
- So the honest claim is weaker than "a script AutoHotkey refuses to load", and it has two parts:
  a re-run prompt that affects every owner, and a version-selection risk that affects owners with
  both AutoHotkey versions installed.
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
- **Decision, taken at Plan on 2026-10-13.** An empty header means an empty header. The create API
  keeps the rule it already had: a null header means use the application default, and any supplied
  string is stored exactly as sent. The server is unchanged. The web UI stops sending an empty
  string by accident, because the Add form now starts from the default header. The owner sees it,
  edits it, or clears it on purpose. The alternative, coercing an empty string to the default
  inside the create handler, was rejected for two reasons. It would make an empty string mean one
  thing on create and another on update, because the update handler stores what it is given. It
  would also stop an owner ever creating a profile with an empty header.
- **Decision, taken at Plan on 2026-10-13.** Profiles the bug already damaged are repaired in this
  item, by a one-time database migration. Before the fix there was no way to tell a header the bug
  emptied from one an owner emptied on purpose, and the web UI was the only way an owner could
  create a profile, so almost every empty header is the bug. The repair fills a header that holds
  no characters at all, and never touches a header that holds any text. After it runs, an empty
  header comes from a deliberate act, or from a browser still running the old frontend, which the
  third decision below covers.
- **Decision, taken at Plan on 2026-10-13.** The rollout gap is accepted, not closed. The repair
  runs once, at deploy time. The API and the frontend deploy from two separate workflows that run
  in parallel, and the app is a PWA whose service worker serves cached files. So a browser can
  still hold the old frontend after the migration ran, and a profile it creates then still stores
  an empty header. That owner is in the state they were in before this item shipped. They fix it
  by editing the header, or by making the profile again once their browser has reloaded. The
  window closes by itself. The two ways to close it cost more than it does: coercing an empty
  string on the server contradicts the first decision, and a repair that ran on every startup
  would overwrite every header an owner cleared on purpose. This item adds no recurring repair.
  When this ships, let the frontend workflow finish before the API workflow's `migrate-db` job
  runs. That shrinks the window. It does not remove it, and no workflow change is in this item.
- Spec: none. The item is `moderate`, so it goes straight to Plan. The three decisions above were
  taken there.
- Plan: `docs/superpowers/plans/2026-10-13-profile-default-header-plan-165.md`.
