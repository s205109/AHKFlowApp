# 088 - Worktree removal watcher flashes a console window

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: trivial
- **Stage**: 0-intake

## Summary

Every worktree removal spawns a detached watcher process through WMI, and WMI gives that
process its own console window. The window is hidden a few milliseconds later, so the user
sees a black window flash. A full PowerShell suite run drives at least five removals, so it
flashes at least five times, which interrupts typing.

## Root cause

`scripts/remove-worktree-local-dev.ps1:672` spawns the watcher like this:

```powershell
$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine      = $watcherCmd      # powershell.exe ... -WindowStyle Hidden ...
    CurrentDirectory = $tempDir
}
```

`Win32_Process.Create` receives no `ProcessStartupInformation`, so Windows creates a new
console window for the new process. `-WindowStyle Hidden` is a PowerShell host argument: the
host hides the window only after it has started. The gap between the two is the flash.

Measured with `GetConsoleWindow()` from a session whose own console handle is `0`:

| Spawn path | Console handle |
|---|---|
| Normal child process (`pwsh -NoProfile -File probe.ps1`) | `0` — no console, no window |
| `Win32_Process.Create`, as the script does it | `11864952` — a real console window |

So the WMI call is the only path that creates a window. A normal child inherits "no console"
and stays invisible.

The script uses WMI on purpose: it needs the watcher to survive outside the Claude job object,
which a plain `Start-Process` does not. The fix must keep that property.

## User story

As a developer running the PowerShell suites or removing a worktree, I want no window to
appear, so that my typing is never interrupted.

## Acceptance criteria

- [ ] Removing a worktree creates no visible window, not even for a few milliseconds.
- [ ] The watcher still runs outside the Claude job object, so it survives the session that
      started it. This is why the script uses WMI, and it must stay true.
- [ ] `tests/WorktreeRemoveHook.Tests.ps1` and `tests/WorktreeMergedCleanup.Tests.ps1` stay
      green.

## Proposed fix

Pass a second argument to `Win32_Process.Create`: a `Win32_ProcessStartup` instance with
`CreateFlags = 0x08000000` (`CREATE_NO_WINDOW`). The process still gets a console, so it stays
detached from the job object, but no window is ever created, so there is nothing to hide.

`ShowWindow = 0` (`SW_HIDE`) is the weaker alternative. It hides the window at creation rather
than after the host starts, which removes the flash but still creates the window.

## Out of scope

- Replacing the WMI spawn with something else. The detachment it buys is the reason it is
  there.
- The `Start-Process -WindowStyle Hidden` fallback at `scripts/remove-worktree-local-dev.ps1:688`.
  It runs only when WMI fails, and `-NoNewWindow` cannot be used there because the watcher must
  outlive the caller.

## Notes / dependencies

- Found while running `scripts/run-powershell-suites.ps1` during backlog 080.
- The five removals in one suite run come from `tests/WorktreeMergedCleanup.Tests.ps1` (four)
  and `tests/WorktreeRemoveHook.Tests.ps1` (one). Real worktree removals flash once each.
