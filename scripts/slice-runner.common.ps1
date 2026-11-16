#Requires -Version 5.1

# Backlog 204. The Slice runner. A Slice is one 'dotnet test' process over one test project. The
# coverage step and the Integration Mode of test-fast.ps1 hand their Slices to this file. It
# decides how many may run at once and in which order they start, starts each one with its own
# log, and ends every process it started when a run stops early.
#
# This file must load in Windows PowerShell 5.1, because test-fast.ps1 runs there. So it uses no
# ternary operator, no '??', no [Type]::new() and no three-argument Join-Path. The caller
# dot-sources test-lanes.common.ps1 first.

# The budget is the most Slices one run may start at once. A run that owns its Lanes may use every
# Lane it holds. A nested run, or a run with Lanes off, holds none of its own, so it takes half of
# the machine's proposal, the same share a Half run would get (D3).
function Get-AhkFlowSliceBudget {
    param(
        [Parameter(Mandatory = $true)][object] $LaneRun,
        [int] $Proposal
    )
    if ($LaneRun.Role -eq 'owner') {
        return [int]@($LaneRun.Lanes.Streams).Count
    }
    if (-not $PSBoundParameters.ContainsKey('Proposal')) { $Proposal = Get-AhkFlowLaneProposal }
    return [int](Get-AhkFlowLaneShareCount -Share Half -Capacity $Proposal)
}

# Turns the -SlicesAtOnce value into a number. 'Budget', in any case, means the whole budget. A
# whole number above the budget is lowered to the budget (D8).
function Resolve-AhkFlowSlicesAtOnce {
    param(
        [AllowEmptyString()][string] $Requested,
        [Parameter(Mandatory = $true)][int] $Budget
    )
    if ($null -eq $Requested) { $Requested = '' }
    $value = 0
    if ($Requested -ieq 'Budget') {
        $value = $Budget
    }
    elseif ($Requested -match '^[1-9][0-9]*$') {
        $parsed = 0
        if ([int]::TryParse($Requested, [ref]$parsed) -and $parsed -lt $Budget) { $value = $parsed }
        else { $value = $Budget }
    }
    else {
        throw "-SlicesAtOnce takes a whole number of at least 1, or Budget. Got: '$Requested'."
    }
    Write-Host "Slices at once: $value (asked for $Requested, budget $Budget)"
    return [int]$value
}

function New-AhkFlowSlice {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Command,
        [AllowEmptyString()][string[]] $Argument = @(),
        [Parameter(Mandatory = $true)][string] $LogPath
    )
    return [pscustomobject]@{ Name = $Name; Command = $Command; Argument = @($Argument); LogPath = $LogPath }
}

# At the value 1 the Slices start in the given order, so a sequential run behaves as it did before
# this file existed. Side by side, the longest Slice starts first, so it does not start last and
# hold up the end of the run. A Slice with no stored seconds counts as the longest. A stored name
# with no Slice changes nothing (D5). Equal seconds keep the given order. Sort-Object is not
# trusted to be stable in 5.1, so the input position is an explicit second key.
function Get-AhkFlowSliceOrder {
    param(
        [Parameter(Mandatory = $true)][object[]] $Slice,
        [System.Collections.IDictionary] $History,
        [Parameter(Mandatory = $true)][int] $SlicesAtOnce
    )
    if ($SlicesAtOnce -le 1) { return , @($Slice) }

    $keyed = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $Slice.Count; $index++) {
        $seconds = [double]::MaxValue
        if ($null -ne $History -and $History.Contains($Slice[$index].Name)) { $seconds = [double]$History[$Slice[$index].Name] }
        $keyed.Add([pscustomobject]@{ Seconds = $seconds; Position = $index; Slice = $Slice[$index] })
    }

    # Insertion sort on (seconds, highest first; position, lowest first). The lists are short.
    $sorted = New-Object System.Collections.Generic.List[object]
    foreach ($item in $keyed) {
        $at = $sorted.Count
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $other = $sorted[$i]
            if ($item.Seconds -gt $other.Seconds -or ($item.Seconds -eq $other.Seconds -and $item.Position -lt $other.Position)) {
                $at = $i
                break
            }
        }
        $sorted.Insert($at, $item)
    }
    return , @($sorted | ForEach-Object { $_.Slice })
}

# Builds one command line from separate arguments, so the child's runtime splits it back into the
# same values. These are the rules CommandLineToArgvW and the .NET runtime read: an argument that
# is empty or holds a space, a tab or a quote is quoted; a quote inside is written as \"; and the
# backslashes right before a quote, or at the end of a quoted argument, are doubled.
function ConvertTo-AhkFlowArgumentString {
    param([AllowEmptyString()][string[]] $Argument = @())
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Argument)) {
        if ($null -eq $value) { $value = '' }
        if ($value.Length -gt 0 -and $value.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) {
            $parts.Add($value)
            continue
        }
        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($character in $value.ToCharArray()) {
            if ($character -eq '\') {
                $backslashes++
                continue
            }
            if ($character -eq '"') {
                [void]$builder.Append('\', 2 * $backslashes + 1)
                [void]$builder.Append('"')
            }
            else {
                if ($backslashes -gt 0) { [void]$builder.Append('\', $backslashes) }
                [void]$builder.Append($character)
            }
            $backslashes = 0
        }
        if ($backslashes -gt 0) { [void]$builder.Append('\', 2 * $backslashes) }
        [void]$builder.Append('"')
        $parts.Add($builder.ToString())
    }
    return ($parts -join ' ')
}

function Get-AhkFlowCurrentHostPath {
    return [System.Diagnostics.Process]::GetCurrentProcess().Path
}

function ConvertTo-AhkFlowSingleQuoted {
    param([AllowEmptyString()][string] $Value)
    if ($null -eq $Value) { $Value = '' }
    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-AhkFlowEncodedCommand {
    param([Parameter(Mandatory = $true)][string] $Text)
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Text))
}

# Finds the program a Slice starts. Get-Command returns the command that runs when its name is
# typed, so a dotnet.ps1 stub that a suite puts first on PATH wins over dotnet.exe. A script stub
# runs through the current host with -EncodedCommand, not -File, because 'pwsh -File' splits a
# value such as '--collect:XPlat Code Coverage' in two. The first statement keeps 5.1 from writing
# progress records to standard error as CLIXML.
function Resolve-AhkFlowSliceStart {
    param(
        [Parameter(Mandatory = $true)][string] $Command,
        [AllowEmptyString()][string[]] $Argument = @()
    )
    $found = @(Get-Command -Name $Command -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($found.Count -eq 1) {
        $item = $found[0]
        if ($item.CommandType -eq 'Application') {
            return [pscustomobject]@{ FilePath = $item.Source; Arguments = (ConvertTo-AhkFlowArgumentString -Argument $Argument) }
        }
        if ($item.CommandType -eq 'ExternalScript') {
            $quoted = @(@($Argument) | ForEach-Object { ConvertTo-AhkFlowSingleQuoted -Value $_ })
            $call = (@(ConvertTo-AhkFlowSingleQuoted -Value $item.Source) + $quoted) -join ' '
            $text = "`$ProgressPreference = 'SilentlyContinue'; `$global:LASTEXITCODE = 0; try { & $call } catch { [Console]::Error.WriteLine(`$_.ToString()); exit 1 }; exit `$LASTEXITCODE"
            $encoded = ConvertTo-AhkFlowEncodedCommand -Text $text
            return [pscustomobject]@{ FilePath = (Get-AhkFlowCurrentHostPath); Arguments = "-NoProfile -NonInteractive -EncodedCommand $encoded" }
        }
    }
    throw "Cannot find the command '$Command' for a Slice."
}
