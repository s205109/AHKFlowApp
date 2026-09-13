#Requires -Version 7.0

# Backlog 140. One list says which folders under backlog/ hold a real item. Several checks read
# git rather than the working tree, so they cannot dot-source that list. They share one copy of
# it as a path pattern instead. This suite fails when that copy stops matching the list, or when a
# script writes the folders into a pattern of its own again.
#
# The failure this stops is quiet and expensive. A folder that the copy does not know about still
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
. (Join-Path $repoRoot 'scripts/worktree-git.common.ps1')

$failures = @()

# The canonical list, read from the script rather than repeated here. Repeating it would make this
# suite one more copy to keep in step, which is the very problem it exists to catch.
$canonical = @($script:BacklogItemSubfolder)

if ($canonical.Count -lt 1) {
    $failures += 'canonical list : $script:BacklogItemSubfolder is empty, so there is nothing to compare against'
}

# The shared copy must name exactly the canonical folders, in any order.
$copyShape = [regex] '^\(([a-z|/]+)\)\?$'
$copy = $copyShape.Match($WorktreeBacklogSubfolderPattern)
if (-not $copy.Success) {
    $failures += "`$WorktreeBacklogSubfolderPattern : '$WorktreeBacklogSubfolderPattern' is not the '(a/|b/)?' shape this suite reads"
}
else {
    $folders = @($copy.Groups[1].Value -split '\|' | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ })
    $missing = @($canonical | Where-Object { $_ -notin $folders })
    $extra = @($folders | Where-Object { $_ -notin $canonical })

    if ($missing.Count -gt 0) {
        $failures += "`$WorktreeBacklogSubfolderPattern does not list $($missing -join ', '). Items in that folder would be invisible to the git checks."
    }
    if ($extra.Count -gt 0) {
        $failures += "`$WorktreeBacklogSubfolderPattern lists $($extra -join ', '), which is not in `$script:BacklogItemSubfolder."
    }
}

# No script writes the folders into a path pattern of its own. A private copy is the drift this
# suite exists to stop, and only the shared value above is compared with the list.
$privateCopy = [regex] "\^backlog/\([a-z]+/\|"
foreach ($scriptFile in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter '*.ps1' -File) {
    if ($privateCopy.IsMatch((Get-Content -LiteralPath $scriptFile.FullName -Raw))) {
        $failures += "scripts/$($scriptFile.Name) : writes the backlog folders into its own path pattern. Build it on `$WorktreeBacklogSubfolderPattern instead."
    }
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

Write-Host "BacklogFolderParity.Tests.ps1: the shared folder pattern agrees with $($canonical -join ', ')." -ForegroundColor Green
