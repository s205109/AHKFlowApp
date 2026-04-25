# Debug Hook for Claude Code

## Context

The user wants a dedicated hook script for exploring and testing the Claude Code hook system. The project already has one active `PostToolUse` hook (`post-edit-format.sh`). This hook is explicitly for learning/debugging — not a production utility. It will demonstrate Windows notifications, status messages, structured logging, stdin inspection, env var visibility, and execution timing in one place.

---

## Files to Create / Modify

| Action | Path |
|--------|------|
| Create | `.claude/hooks/debug-hook.ps1` |
| Modify | `.claude/settings.json` — add PostToolUse entry |
| Modify | `.gitignore` — add `.claude/logs/` |

---

## Step 1 — Create `.claude/hooks/debug-hook.ps1`

Full script content:

```powershell
# debug-hook.ps1
# Purpose: Exploratory hook for testing Claude Code hook capabilities.
# Fires on every PostToolUse event.
# WARNING: Blocks on MessageBox until dismissed. Disable when not debugging.

$startTime = Get-Date

# --- Read and parse stdin ---
$stdinRaw = [Console]::In.ReadToEnd()
$data = $null
if ($stdinRaw.Trim()) {
    $data = $stdinRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
}

# --- Log file setup ---
$logDir = Join-Path $PSScriptRoot "..\logs"
$logFile = Join-Path $logDir "debug-hook.log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# --- Log rotation: trim to last ~100KB if file exceeds 500KB ---
if (Test-Path $logFile) {
    $fileSize = (Get-Item $logFile).Length
    if ($fileSize -gt 500KB) {
        $content = Get-Content $logFile -Raw
        $trimmed = $content.Substring([int]($content.Length / 2))
        Set-Content $logFile $trimmed -NoNewline
    }
}

# --- Invocation counter ---
$invocationCount = 1
if (Test-Path $logFile) {
    $invocationCount = (Select-String -Path $logFile -Pattern "^INVOCATION #" -AllMatches).Matches.Count + 1
}

# --- Collect system info ---
$now = Get-Date
$osCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$osVersion = [System.Environment]::OSVersion.VersionString
$hostname = $env:COMPUTERNAME
$username = $env:USERNAME
$pid = $PID
$workDir = (Get-Location).Path

# --- Collect CLAUDE_* env vars ---
$claudeVars = [System.Environment]::GetEnvironmentVariables() |
    ForEach-Object { $_.GetEnumerator() } |
    Where-Object { $_.Key -like "CLAUDE_*" } |
    Sort-Object Key

# --- Extract tool info ---
$toolName    = if ($data) { $data.tool_name }    else { "(no stdin)" }
$toolInput   = if ($data) { $data.tool_input   | ConvertTo-Json -Compress -Depth 5 -ErrorAction SilentlyContinue } else { "(none)" }
$toolResponse= if ($data) { $data.tool_response | ConvertTo-Json -Compress -Depth 3 -ErrorAction SilentlyContinue } else { "(none)" }

# --- Windows notification (blocks until dismissed) ---
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
[System.Windows.Forms.MessageBox]::Show(
    "Hook fired for tool: $toolName`nInvocation #$invocationCount",
    'Claude Code Debug Hook'
) | Out-Null

# --- 3-second pause so status message is visible ---
Start-Sleep -Seconds 3

# --- Measure total duration ---
$elapsed = [int]((Get-Date) - $startTime).TotalMilliseconds

# --- Build log entry ---
$separator = "=" * 80
$entry = @"
$separator
INVOCATION #$invocationCount  [$($now.ToString('yyyy-MM-dd HH:mm:ss.fff'))]
$separator
SYSTEM INFO
  Date/Time : $($now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC  /  $($now.ToString('yyyy-MM-dd HH:mm:ss')) local
  OS        : $osCaption  ($osVersion)
  Hostname  : $hostname
  User      : $username
  PID       : $pid
  WorkDir   : $workDir

STDIN (raw from Claude Code)
  tool_name     : $toolName
  tool_input    : $toolInput
  tool_response : $toolResponse

RAW STDIN (first 500 chars)
  $($stdinRaw.Substring(0, [Math]::Min(500, $stdinRaw.Length)).Replace("`n", "`n  "))

CLAUDE ENV VARS
$(if ($claudeVars) {
    ($claudeVars | ForEach-Object { "  $($_.Key)=$($_.Value)" }) -join "`n"
} else {
    "  (none found)"
})

TIMING
  Total hook execution: ${elapsed}ms  (includes 3s sleep + MessageBox wait)

"@

Add-Content -Path $logFile -Value $entry -Encoding UTF8

exit 0
```

---

## Step 2 — Add hook entry to `.claude/settings.json`

In the `"hooks"` → `"PostToolUse"` array, append a second entry (after the existing `Edit|Write` entry):

```json
{
  "matcher": ".*",
  "hooks": [
    {
      "type": "command",
      "command": "powershell -NoProfile -File .claude/hooks/debug-hook.ps1",
      "statusMessage": "Debug hook running..."
    }
  ]
}
```

Matcher `".*"` matches all tool names.

---

## Step 3 — Add `.claude/logs/` to `.gitignore`

Check the root `.gitignore`. If `.claude/logs/` is not already excluded, add:
```
.claude/logs/
```

---

## Verification

1. Trigger any tool use in Claude Code (e.g., ask Claude to read a file).
2. Observe:
   - Status message "Debug hook running..." appears in the UI.
   - MessageBox pops up with tool name + invocation count. Click OK.
   - After 3 seconds, hook completes.
3. Open `.claude/logs/debug-hook.log` — confirm one block was appended with correct system info, tool name, and any `CLAUDE_*` env vars.
4. Trigger a second tool use — confirm invocation count increments to `#2`.
5. Confirm `.claude/logs/` is not tracked by git (`git status` should not show the log file).

---

## Unresolved Questions

- Matcher `".*"` assumed to mean "all tools" — verify this is correct Claude Code regex behavior (vs. omitting the matcher field entirely).
- No known `CLAUDE_*` env vars documented publicly — the log will reveal what's actually injected.
