#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptsDir = Join-Path $suiteRoot 'scripts'
. (Join-Path $scriptsDir 'worktree-log.common.ps1')

function Assert-True {
    param($Condition, [string] $Message)
    if ($Condition -isnot [bool]) {
        $caller = (Get-PSCallStack)[1]
        $typeName = if ($null -eq $Condition) { 'null' } else { $Condition.GetType().FullName }
        throw ("Assert-True needs a boolean. Got [$typeName] with $(@($Condition).Count) value(s) " +
            "from line $($caller.ScriptLineNumber): $(@($Condition) -join ' | '). Original message: $Message")
    }
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Message)
    if (-not [string]::Equals([string] $Expected, [string] $Actual, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function New-TempDir {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ahkflow-logtest-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

$temp = New-TempDir
try {
    # --- reason sanitizing -------------------------------------------------
    $multiline = "held by an agent`r`nsecond line`nthird"
    $flat = Format-WorktreeLogReason -Text $multiline
    Assert-True (-not $flat.Contains("`n")) 'Sanitized reason must hold no line feed'
    Assert-True (-not $flat.Contains("`r")) 'Sanitized reason must hold no carriage return'

    $long = 'x' * 500
    $truncated = Format-WorktreeLogReason -Text $long
    Assert-True ($truncated.Length -le 300) "Sanitized reason must be at most 300 chars, got $($truncated.Length)"
    Assert-True ($truncated.EndsWith([char] 0x2026)) 'A truncated reason must end with a horizontal ellipsis'

    $empty = Format-WorktreeLogReason -Text $null
    Assert-Equal 'no reason given' $empty 'A null reason must read "no reason given"'

    # --- one line per write, and the diagnostics sibling -------------------
    $outcomeLog = Join-Path $temp 'worktree-removal.log'
    Write-WorktreeLog -LogPath $outcomeLog -Worktree 'wt-probe' -Message 'Removed.'
    $lines = @(Get-Content -LiteralPath $outcomeLog)
    Assert-Equal 1 $lines.Count 'One write must produce exactly one line'

    $diagPath = Get-WorktreeDiagnosticsPath -OutcomeLogPath $outcomeLog
    Assert-Equal (Join-Path $temp 'worktree-removal-diagnostics.log') $diagPath 'Diagnostics sits beside the outcome log'

    Write-WorktreeDiagnostic -LogPath $diagPath -Worktree 'wt-probe' -Message 'PID=1234'
    Assert-True (Test-Path -LiteralPath $diagPath) 'Diagnostics file must be created on first write'
    Assert-Equal 1 (@(Get-Content -LiteralPath $outcomeLog)).Count 'A diagnostic must not touch the outcome log'

    # --- a message carrying a newline still writes one line ----------------
    Write-WorktreeLog -LogPath $outcomeLog -Worktree 'wt-probe' -Message "Kept: the worktree is locked (a`r`nb)."
    Assert-Equal 2 (@(Get-Content -LiteralPath $outcomeLog)).Count 'A message with CRLF must still be one line'

    # --- rotation ----------------------------------------------------------
    $rotateLog = Join-Path $temp 'rot-diagnostics.log'
    Set-Content -LiteralPath $rotateLog -Value ('y' * (5 * 1024 * 1024 + 10)) -NoNewline
    Write-WorktreeDiagnostic -LogPath $rotateLog -Worktree 'wt-probe' -Message 'after rotation'
    Assert-True (Test-Path -LiteralPath "$rotateLog.1") 'Oversized diagnostics must rotate to .1'
    $rotated = @(Get-Content -LiteralPath $rotateLog)
    Assert-Equal 1 $rotated.Count 'The new diagnostics file holds only the line written after rotation'

    # --- concurrent writers lose nothing -----------------------------------
    $concurrentLog = Join-Path $temp 'concurrent.log'
    $helper = Join-Path $scriptsDir 'worktree-log.common.ps1'
    $jobs = 1..4 | ForEach-Object {
        $index = $_
        Start-Job -ScriptBlock {
            param($HelperPath, $LogPath, $Index)
            . $HelperPath
            1..25 | ForEach-Object {
                Write-WorktreeLog -LogPath $LogPath -Worktree "wt-$Index" -Message "Removed. run=$Index-$_"
            }
        } -ArgumentList $helper, $concurrentLog, $index
    }
    $jobs | Wait-Job -Timeout 120 | Out-Null
    $jobs | Remove-Job -Force
    $written = @(Get-Content -LiteralPath $concurrentLog)
    Assert-Equal 100 $written.Count "Four writers of 25 lines must produce 100 lines, got $($written.Count)"

    Write-Host 'Worktree removal log tests passed.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
