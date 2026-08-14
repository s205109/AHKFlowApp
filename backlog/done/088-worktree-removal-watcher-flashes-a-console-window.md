# 088 - Worktree removal watcher flashes a console window

## Metadata

- **Epic**: Development process
- **Type**: Tooling
- **Interfaces**: none (scripts)
- **Difficulty**: moderate
- **Stage**: 9-ship

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

- [x] Removing a worktree creates no visible window, not even for a few milliseconds.
- [x] The watcher still runs outside the Claude job object, so it survives the session that
      started it. This is why the script uses WMI, and it must stay true.
- [x] `tests/WorktreeRemoveHook.Tests.ps1` and `tests/WorktreeMergedCleanup.Tests.ps1` stay
      green.

## Fix that shipped

`Win32_Process.Create` now receives a second argument: a `Win32_ProcessStartup` instance with
`ShowWindow = 0` (`SW_HIDE`). The system applies that value when it creates the window, so the
window is never shown. The process still gets a console, so the PowerShell host starts
normally, and `WmiPrvSE.exe` still creates it, so it still escapes the job object.

`scripts/worktree-powershell.common.ps1` builds the instance in `New-HiddenProcessStartup`.
`tests/WorktreeWatcherWindow.Tests.ps1` spawns a probe the same way and asserts that no
visible window ever belongs to it.

### Why the originally proposed fix was wrong

This item first proposed `CreateFlags = 0x08000000` (`CREATE_NO_WINDOW`) and called
`ShowWindow = 0` the weaker alternative. Measurement reversed that.

| Variant | Result |
|---|---|
| No startup information (the old code) | Visible `PseudoConsoleWindow` about 215 ms after the spawn |
| `ShowWindow = 0` | No visible window |
| `CreateFlags = 8` (`Detached_Process`) | `Create` returns 0, but the child never runs: a PowerShell host with no console does nothing |
| `CreateFlags = 0x08000000` (`CREATE_NO_WINDOW`) | `Create` returns **21**, invalid parameter, and creates no process |

`CREATE_NO_WINDOW` is not in the accepted `CreateFlags` values that
[the `Win32_ProcessStartup` documentation](https://learn.microsoft.com/windows/win32/cimwin32prov/win32-processstartup)
lists. `ShowWindow = 0` is the
[documented way to run a process hidden through WMI](https://learn.microsoft.com/windows/win32/wmisdk/wmi-tasks--processes).

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
- Plan: `docs/superpowers/plans/2026-08-13-worktree-watcher-window-flash-plan.md`
