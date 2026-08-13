#Requires -Version 5.1
<#
.SYNOPSIS
  Rewrite the sync marker in .github/instructions/personal-defaults.md.
.DESCRIPTION
  Run this straight after you paste the file into the Claude web preferences box. It records the
  current body hash and today's date, which is what tests/PersonalDefaultsSyncMarker.Tests.ps1
  checks. Running it without pasting hides the drift the suite exists to catch.

  The marker goes under the frontmatter, never inside it. GitHub Copilot loads the file by its
  'applyTo' key, and an extra key there could change how it loads.
#>
[CmdletBinding()]
param(
    [string] $Path,

    [string] $Pasted = (Get-Date).ToString('yyyy-MM-dd')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'personal-defaults-marker.common.ps1')

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Join-Path $repoRoot '.github\instructions\personal-defaults.md'
}

$Path = (Resolve-Path -LiteralPath $Path).ProviderPath
$lines = @((Split-PersonalDefaultsText -Text ([System.IO.File]::ReadAllText($Path))).BodyLines)

# The marker goes after the frontmatter block when the file has one, otherwise at the top.
$insertAt = 0
if ($lines.Count -gt 0 -and $lines[0] -eq '---') {
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') {
            $insertAt = $i + 1
            break
        }
    }
}

$head = if ($insertAt -gt 0) { @($lines[0..($insertAt - 1)]) } else { @() }

# Skip the blank lines that already follow, then write exactly one on each side of the marker.
# Without this, every run leaves behind the blank line of the marker it replaced.
$tailStart = $insertAt
while ($tailStart -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$tailStart])) {
    $tailStart++
}

$tail = if ($tailStart -lt $lines.Count) { @($lines[$tailStart..($lines.Count - 1)])  } else { @() }

$rebuilt = New-Object System.Collections.Generic.List[string]
foreach ($line in $head) { $rebuilt.Add($line) }
if ($head.Count -gt 0) { $rebuilt.Add('') }

# A placeholder holds the marker's place while the body hash is computed. The hash ignores marker
# lines, so replacing the placeholder afterwards cannot change the value.
$placeholder = Get-PersonalDefaultsMarkerLine -Hash ('0' * 64) -Pasted $Pasted
$rebuilt.Add($placeholder)
$rebuilt.Add('')
foreach ($line in $tail) { $rebuilt.Add($line) }

$rebuiltText = ($rebuilt -join "`n")
$hash = Get-PersonalDefaultsBodyHashFromText -Text $rebuiltText
$finalText = $rebuiltText.Replace($placeholder, (Get-PersonalDefaultsMarkerLine -Hash $hash -Pasted $Pasted))

# LF, no byte order mark: .gitattributes sets '*.md text eol=lf'.
[System.IO.File]::WriteAllText($Path, $finalText, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Updated the sync marker in $Path (body-sha256=$hash, pasted-to-web=$Pasted)."
