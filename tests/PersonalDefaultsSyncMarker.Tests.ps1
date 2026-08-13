#Requires -Version 5.1

# The sync marker in .github/instructions/personal-defaults.md is the only thing standing between
# the repository copy of the personal defaults and the copy in the Claude web preferences box.
# Nothing can read that box, so nothing can prove the paste happened. This suite proves the
# smaller thing: the file body and the hash recorded in it agree, so a body change that never
# reached the box fails here. See backlog 070.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\personal-defaults-marker.common.ps1')

$personalDefaults = Join-Path $repoRoot '.github\instructions\personal-defaults.md'
$updateScript = Join-Path $repoRoot 'scripts\update-personal-defaults-marker.ps1'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$failures = @()
$fixtures = @()

# A fixture mirrors the real file's shape: frontmatter, then a body.
$sampleBody = @'
---
applyTo: "**"
---

# Sample Defaults

- first line
- second line
'@

function New-Fixture {
    param([Parameter(Mandatory)][string] $Text)

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('personal-defaults-' + [System.Guid]::NewGuid().ToString('N') + '.md')
    [System.IO.File]::WriteAllText($path, $Text, $utf8NoBom)
    return $path
}

function Assert-Failure {
    param(
        [Parameter(Mandatory)][string] $Case,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Actual,
        [Parameter(Mandatory)][string] $Expected
    )

    $joined = ($Actual -join [Environment]::NewLine)
    if ($joined -notlike "*$Expected*") {
        return "${Case}: expected a failure containing '$Expected', got '$joined'."
    }
    return $null
}

try {
    # Case: a file with no marker at all.
    $noMarker = New-Fixture $sampleBody
    $fixtures += $noMarker
    $result = @(Test-PersonalDefaultsMarker -Path $noMarker)
    $failures += (Assert-Failure -Case 'No marker' -Actual $result -Expected 'has no sync marker')

    # Case: two markers. The hash ignores marker lines, so a second one would otherwise pass.
    $line = Get-PersonalDefaultsMarkerLine -Hash ('0' * 64) -Pasted '2026-08-13'
    $twoMarkers = New-Fixture "$line`n$line`n$sampleBody"
    $fixtures += $twoMarkers
    $result = @(Test-PersonalDefaultsMarker -Path $twoMarkers)
    $failures += (Assert-Failure -Case 'Two markers' -Actual $result -Expected 'Keep exactly one')

    # Case: a marker whose hash is not 64 hex characters.
    $malformed = New-Fixture "<!-- sync-marker body-sha256=abc123 pasted-to-web=2026-08-13 -->`n$sampleBody"
    $fixtures += $malformed
    $result = @(Test-PersonalDefaultsMarker -Path $malformed)
    $failures += (Assert-Failure -Case 'Malformed marker' -Actual $result -Expected 'malformed sync marker')

    # Case: a date that matches the shape but is not a real day.
    $badDate = New-Fixture ((Get-PersonalDefaultsMarkerLine -Hash ('0' * 64) -Pasted '2026-02-30') + "`n$sampleBody")
    $fixtures += $badDate
    $result = @(Test-PersonalDefaultsMarker -Path $badDate)
    $failures += (Assert-Failure -Case 'Impossible date' -Actual $result -Expected 'not a real date')

    # Case: the marker records a hash, the body then changed. This is the drift the suite exists for.
    $stale = New-Fixture $sampleBody
    $fixtures += $stale
    $staleHash = Get-PersonalDefaultsBodyHashFromText -Text $sampleBody
    $staleText = (Get-PersonalDefaultsMarkerLine -Hash $staleHash -Pasted '2026-08-13') +
        "`n$sampleBody`n- a line added after the hash was recorded`n"
    [System.IO.File]::WriteAllText($stale, $staleText, $utf8NoBom)
    $result = @(Test-PersonalDefaultsMarker -Path $stale)
    $failures += (Assert-Failure -Case 'Stale hash' -Actual $result -Expected 'still records the old body hash')

    # Case: the same body with CRLF endings hashes the same, so a line-ending change is not drift.
    $lfText = "$sampleBody`n"
    $lfHash = Get-PersonalDefaultsBodyHashFromText -Text $lfText
    $crlfHash = Get-PersonalDefaultsBodyHashFromText -Text ($lfText -replace "`n", "`r`n")
    if ($lfHash -ne $crlfHash) {
        $failures += "Line endings: the LF body hashes to $lfHash and the CRLF body to $crlfHash. They must agree."
    }

    # Case: the update script makes a file verify, and records today.
    $stamped = New-Fixture $sampleBody
    $fixtures += $stamped
    & $updateScript -Path $stamped 6> $null
    $result = @(Test-PersonalDefaultsMarker -Path $stamped)
    if ($result.Count -gt 0) {
        $failures += "Update script: the stamped file still fails the check: $($result -join '; ')"
    }

    $stampedMarker = Read-PersonalDefaultsMarker -Path $stamped
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($stampedMarker.Pasted -ne $today) {
        $failures += "Update script: recorded pasted-to-web=$($stampedMarker.Pasted), expected $today."
    }

    # The marker sits under the frontmatter, and the frontmatter still opens the file. Copilot reads
    # .github/instructions/personal-defaults.md by its 'applyTo' key, so a marker written above the
    # frontmatter would break how the file loads.
    $stampedLines = ([System.IO.File]::ReadAllText($stamped) -replace "`r`n", "`n") -split "`n"
    if ($stampedLines[0] -ne '---') {
        $failures += "Update script: the first line is '$($stampedLines[0])', expected the frontmatter opener '---'."
    }
    if ($stampedLines[4] -notlike '<!-- sync-marker *') {
        $failures += "Update script: expected the marker on line 5, got '$($stampedLines[4])'."
    }

    # Case: running the script twice changes nothing the second time. Without this, each run leaves
    # behind the blank line of the marker it replaced.
    $firstRun = [System.IO.File]::ReadAllText($stamped)
    & $updateScript -Path $stamped 6> $null
    if ([System.IO.File]::ReadAllText($stamped) -ne $firstRun) {
        $failures += 'Update script: a second run changed the file. It must be idempotent on the same day.'
    }

    # Case: the real file is in sync. This is the check that fires in CI after somebody edits it.
    $result = @(Test-PersonalDefaultsMarker -Path $personalDefaults)
    if ($result.Count -gt 0) {
        $failures += ($result -join [Environment]::NewLine)
    }

    # Acceptance criterion from backlog 070: no copy still claims MediatR.
    if ([System.IO.File]::ReadAllText($personalDefaults) -match 'MediatR') {
        $failures += "$personalDefaults still names MediatR. This repository has no MediatR package."
    }
}
finally {
    foreach ($fixture in $fixtures) {
        if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force }
    }
}

$failures = @($failures | Where-Object { $_ })
if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Personal defaults sync marker tests passed.'
