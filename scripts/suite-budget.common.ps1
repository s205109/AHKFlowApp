#Requires -Version 7.0
# A time budget per Suite. Backlog 188.
#
# The budget is the Suite's committed baselineSeconds in tests/powershell-suites.json. A Gate run
# that takes more than 1.3 times the budget prints a warning. A Suite that warns in two runs in a
# row, counting only the runs that executed it, gets a suggestion to audit it again. Nothing here
# fails a run, and the audit never starts by itself.
#
# Dot-source it from a runner:  . "$PSScriptRoot\suite-budget.common.ps1"
#
#   Get-SuiteBudgetWarning    the warning text for one Suite's time, or $null
#   Update-SuiteBudgetStreak  update the streak file and return the Suites that warned twice
#
# This file targets 7.0 because run-powershell-suites.ps1 does. It does not call Set-StrictMode:
# that call leaks from a dot-sourced file into the caller's scope, and the runner sets it itself.

$script:SuiteBudgetFactor = 1.3

# A budget below this is too small to measure against: start-up noise alone can pass 30 percent.
$script:SuiteBudgetMinimumSeconds = 5

function Get-SuiteBudgetWarning {
    # A warning text, or $null. A budget under 5 s, or a null budget, never warns.
    param([object] $Entry, [double] $Seconds)

    $budget = $Entry.BaselineSeconds
    if ($null -eq $budget -or [double] $budget -lt $script:SuiteBudgetMinimumSeconds) { return $null }
    if ($Seconds -le [double] $budget * $script:SuiteBudgetFactor) { return $null }

    $over = [math]::Round(($Seconds / [double] $budget - 1) * 100)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    return 'BUDGET {0}: {1} s against a budget of {2} s (+{3} %)' -f $Entry.Name,
        $Seconds.ToString('0.0', $culture), ([double] $budget).ToString('0.0', $culture), $over
}

function Update-SuiteBudgetStreak {
    <#
      Updates the streak file and returns the Suite names that warned in two executed runs in a
      row. An executed Suite that warned adds one to its streak; one that did not goes back to 0. A
      Suite that was not executed, because the run reused its result, keeps its streak.
    #>
    param([string] $Path, [string[]] $Executed, [string[]] $Warned)

    $streak = @{}
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $stored = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($property in $stored.PSObject.Properties) { $streak[$property.Name] = [int] $property.Value }
        }
    } catch {
        # An unreadable file is no history. The streak only ever delays a suggestion.
        $streak = @{}
    }

    $warnedSet = [System.Collections.Generic.HashSet[string]]::new([string[]] @($Warned), [System.StringComparer]::OrdinalIgnoreCase)
    $suggest = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($Executed)) {
        if ($warnedSet.Contains($name)) {
            $streak[$name] = 1 + $(if ($streak.ContainsKey($name)) { $streak[$name] } else { 0 })
            if ($streak[$name] -ge 2) { $suggest.Add($name) }
        } else {
            $streak[$name] = 0
        }
    }

    try {
        $folder = Split-Path -Parent $Path
        if ($folder -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $ordered = [ordered]@{}
        foreach ($name in ($streak.Keys | Sort-Object)) { $ordered[$name] = $streak[$name] }
        Set-Content -LiteralPath $Path -Value ($ordered | ConvertTo-Json) -Encoding utf8
    } catch {
        Write-Warning "Could not save the budget streak to $Path. $($_.Exception.Message)"
    }

    # Unrolled on purpose: a caller wraps the call in @(), and an empty result must stay empty.
    return @($suggest | Sort-Object)
}
