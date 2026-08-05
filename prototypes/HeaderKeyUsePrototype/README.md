# Header key use — prototype

**Throwaway.** Not in `AHKFlowApp.slnx`, so it never reaches CI. Delete it once the decision is folded into `src/`.

## The question

A Profile header template can define hotkeys. The Caps Lock layer preset writes `*CapsLock::` and
`*CapsLock up::` into the header (`HeaderPresetCatalog.cs:56,62`). A Hotkey row on the same key then
either gets eclipsed or lands on top of the same hotkey name, and the app says nothing.

This prototype answers two things:

1. Does the agreed parser rule pick out exactly the keys a header uses as hotkeys, and no others?
2. Does the warning sentence read right against real header text?

## Run it

```powershell
dotnet run --project prototypes/HeaderKeyUsePrototype
```

Keys: `[1|2|3]` focus a Profile, `[h]` cycle that Profile's header, `[k]` cycle the row's key,
`[m]` cycle the row's modifiers, `[a]` apply to all Profiles, `[space]` toggle membership, `[q]` quit.

To replay a fixed session without a terminal, pass the keystrokes as one argument:

```powershell
dotnet run --project prototypes/HeaderKeyUsePrototype -- "2hhhkkhkkk1h2hhmaq"
```

## What is worth keeping

| File | Fate |
|---|---|
| `HeaderKeyUses.cs` | Keep. Pure parser. Lifts into `src/Frontend/AHKFlowApp.UI.Blazor/Helpers/` |
| `HeaderUseText.cs` | Keep. Pure sentence composer. Sits beside `KnownShortcutWarning.cs` |
| `Fixtures.cs` | Throw away. Header text copied so the prototype needs no project reference |
| `Program.cs` | Throw away. Terminal shell only |

`HeaderUseText.TextFor` takes a `Func<string, string?> canonicalize` so the real app can pass
`IHotkeyKeyCatalog.CanonicalizeAsync`. The prototype passes a small fixed table instead.

## The rules being tested

Settled by grilling, recorded here so a later reader can check the code against the decision.

- Warn only. Never block the save, never write into the generated script
- Detect by parsing the header text, not by reading `HeaderPresetInserter` markers
- Match on the key alone. The row's modifiers are not consulted
- Read only modifier-free lines. Skip `;` comments, skip lines carrying `^ ! + # < >` before the
  key, skip custom combinations containing `&`
- `Key up::` and `Key::` use the same one key
