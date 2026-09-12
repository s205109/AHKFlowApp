#Requires -Version 7.0

# Backlog 140. One list says which folders under backlog/ hold a real item. Several checks read
# git rather than the working tree, so they cannot dot-source that list and carry their own copy
# of it as a path pattern. This suite fails when a copy stops matching the list.
#
# The failure this stops is quiet and expensive. A folder that one copy does not know about still
# holds items, and their numbers stop counting as taken, so two files can end up sharing one
# number. That is backlog 061 all over again, and nothing would report it.
#
# Run it by hand with:  pwsh ./tests/BacklogFolderParity.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/backlog.common.ps1')

$failures = @()

# The canonical list, read from the script rather than repeated here. Repeating it would make this
# suite one more copy to keep in step, which is the very problem it exists to catch.
$canonical = @($script:BacklogItemSubfolder)

if ($canonical.Count -lt 1) {
    $failures += 'canonical list : $script:BacklogItemSubfolder is empty, so there is nothing to compare against'
}

# Every file that writes the folder list out as a path pattern, with the pattern's shape. The
# alternation must name exactly the canonical folders, in any order.
$patternFile = @(
    'scripts/check-shipped-plan-ticked.ps1'
    'scripts/check-shipping-pr-closes-item.ps1'
    'scripts/worktree-git.common.ps1'
)

$patternRegex = [regex] "\^backlog/\(([a-z|/]+)\)\?"
$sitesFound = 0

foreach ($relative in $patternFile) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) {
        $failures += "$relative : missing, so its copy of the folder list cannot be checked"
        continue
    }

    $matched = $patternRegex.Matches((Get-Content -LiteralPath $path -Raw))
    if ($matched.Count -eq 0) {
        $failures += "$relative : no '^backlog/(...)?' pattern found. If the file stopped naming folders, remove it from this suite's list on purpose."
        continue
    }

    foreach ($one in $matched) {
        $sitesFound++
        $folders = @($one.Groups[1].Value -split '\|' | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ })
        $missing = @($canonical | Where-Object { $_ -notin $folders })
        $extra = @($folders | Where-Object { $_ -notin $canonical })

        if ($missing.Count -gt 0) {
            $failures += "$relative : pattern '$($one.Value)' does not list $($missing -join ', '). Items in that folder would be invisible to this check."
        }
        if ($extra.Count -gt 0) {
            $failures += "$relative : pattern '$($one.Value)' lists $($extra -join ', '), which is not in `$script:BacklogItemSubfolder."
        }
    }
}

if ($sitesFound -lt $patternFile.Count) {
    $failures += "expected at least one pattern in each of the $($patternFile.Count) files, found $sitesFound in total"
}

# The real repository agrees with the list: every subfolder that exists is one the list names.
$backlogRoot = Join-Path $repoRoot 'backlog'
foreach ($directory in Get-ChildItem -LiteralPath $backlogRoot -Directory) {
    if ($directory.Name -notin $canonical) {
        $failures += "backlog/$($directory.Name)/ exists but `$script:BacklogItemSubfolder does not name it, so its numbers are not reserved."
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }
    Write-Host "$($failures.Count) failure(s)." -ForegroundColor Red
    exit 1
}

Write-Host "BacklogFolderParity.Tests.ps1: $sitesFound pattern site(s) agree with $($canonical -join ', ')." -ForegroundColor Green
