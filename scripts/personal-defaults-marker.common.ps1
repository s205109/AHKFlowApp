#Requires -Version 5.1
# The one definition of the personal defaults sync marker.
#
# .github/instructions/personal-defaults.md is the single source for personal defaults. The Claude
# web preferences box holds a copy that no tool can read. The marker records the hash of the file
# body, so a body change with a stale hash fails tests/PersonalDefaultsSyncMarker.Tests.ps1.
# Updating the hash is the moment you also paste the file into the web box. See backlog 070.
#
# This file requires 5.1, not 7.0, because a #Requires inside a dot-sourced file is enforced, and
# scripts/test-fast.ps1 supports Windows PowerShell 5.1.

Set-StrictMode -Version Latest

$script:PersonalDefaultsMarkerPrefix = '<!-- sync-marker '
$script:PersonalDefaultsMarkerPattern = '^<!-- sync-marker body-sha256=(?<hash>[0-9a-f]{64}) pasted-to-web=(?<pasted>\d{4}-\d{2}-\d{2}) -->$'

function Get-PersonalDefaultsMarkerLine {
    param(
        [Parameter(Mandatory)][string] $Hash,
        [Parameter(Mandatory)][string] $Pasted
    )

    return "<!-- sync-marker body-sha256=$Hash pasted-to-web=$Pasted -->"
}

# Splits file text into its marker lines and its body lines. CRLF and LF give the same result, so a
# line-ending change is never reported as drift.
function Split-PersonalDefaultsText {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $lines = ($Text -replace "`r`n", "`n") -split "`n"
    return [pscustomobject]@{
        Markers   = @($lines | Where-Object { $_.StartsWith($script:PersonalDefaultsMarkerPrefix) })
        BodyLines = @($lines | Where-Object { -not $_.StartsWith($script:PersonalDefaultsMarkerPrefix) })
    }
}

function Get-PersonalDefaultsBodyHashFromText {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $body = (Split-PersonalDefaultsText -Text $Text).BodyLines -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    # SHA256.Create plus ComputeHash, not the static HashData: this file also runs under Windows
    # PowerShell 5.1, and .NET Framework has no HashData.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    return (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-PersonalDefaultsBodyHash {
    param([Parameter(Mandatory)][string] $Path)

    return Get-PersonalDefaultsBodyHashFromText -Text ([System.IO.File]::ReadAllText($Path))
}

function Read-PersonalDefaultsMarker {
    param([Parameter(Mandatory)][string] $Path)

    $markers = (Split-PersonalDefaultsText -Text ([System.IO.File]::ReadAllText($Path))).Markers
    $hash = $null
    $pasted = $null
    if ($markers.Count -eq 1 -and $markers[0] -match $script:PersonalDefaultsMarkerPattern) {
        $hash = $Matches['hash']
        $pasted = $Matches['pasted']
    }

    return [pscustomobject]@{
        Count  = $markers.Count
        Hash   = $hash
        Pasted = $pasted
        Lines  = $markers
    }
}

# Returns one string per problem. An empty array means the file and its marker agree.
function Test-PersonalDefaultsMarker {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return , @("Personal defaults file not found: $Path")
    }

    $marker = Read-PersonalDefaultsMarker -Path $Path
    if ($marker.Count -eq 0) {
        return , @("$Path has no sync marker. Run 'pwsh ./scripts/update-personal-defaults-marker.ps1' to add one, and paste the file into the Claude web preferences box.")
    }

    if ($marker.Count -gt 1) {
        return , @("$Path has $($marker.Count) sync marker lines. Keep exactly one.")
    }

    if (-not $marker.Hash) {
        return , @("$Path has a malformed sync marker: $($marker.Lines[0]). Expected '<!-- sync-marker body-sha256=<64 hex characters> pasted-to-web=YYYY-MM-DD -->'.")
    }

    $failures = @()

    $parsed = [datetime]::MinValue
    $parsedOk = [datetime]::TryParseExact(
        $marker.Pasted,
        'yyyy-MM-dd',
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $parsed)
    if (-not $parsedOk) {
        $failures += "$Path records pasted-to-web=$($marker.Pasted), which is not a real date in YYYY-MM-DD form."
    }

    $current = Get-PersonalDefaultsBodyHash -Path $Path
    if ($current -ne $marker.Hash) {
        $failures += @(
            "$Path changed, but its sync marker still records the old body hash.",
            "  recorded body-sha256=$($marker.Hash)",
            "  current  body-sha256=$current",
            "Paste the file into the Claude web preferences box, then run: pwsh ./scripts/update-personal-defaults-marker.ps1"
        ) -join [Environment]::NewLine
    }

    return , $failures
}
