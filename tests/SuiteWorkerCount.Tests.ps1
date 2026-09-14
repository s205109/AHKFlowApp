#Requires -Version 7.0
<#
.SYNOPSIS
Proves that the suite worker sizing rule has one portable definition.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$helperPath = Join-Path $repoRoot 'scripts/suite-worker-count.common.ps1'
$legacyPath = Join-Path $repoRoot 'scripts/powershell-suites.common.ps1'
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

function Get-FunctionDefinitions {
    param([string] $Path, [string] $Name)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $null, [ref] $null)
    return @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $Name
            }, $true))
}

function Invoke-HostLoadCheck {
    param([string] $HostPath)

    $escapedHelper = $helperPath.Replace("'", "''")
    $command = ". '$escapedHelper'; " + '$result = Get-DefaultSuiteWorkerCount -PhysicalCoreCount 8 -LogicalProcessorCount 16; if ($result -ne 6) { throw ''Expected six workers.'' }'
    $output = & $HostPath -NoProfile -NonInteractive -Command $command 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Host $HostPath could not load the helper. Output: $($output -join [Environment]::NewLine)"
}

$movedFunctions = @(
    'Get-PhysicalCoreShare'
    'Get-DefaultSuiteWorkerCount'
    'Get-DefaultSuiteWorkerReason'
    'ConvertFrom-ProcCpuInfoCoreCount'
    'Get-WindowsPhysicalCoreCount'
    'Get-LinuxPhysicalCoreCount'
    'Get-PhysicalCoreCount'
)

Invoke-TestCase 'Each sizing function has one definition in the extracted helper' {
    Assert-True (Test-Path -LiteralPath $helperPath) "The extracted helper must exist at $helperPath."
    foreach ($name in $movedFunctions) {
        $definitions = @(
            @(Get-FunctionDefinitions -Path $helperPath -Name $name) +
            @(Get-FunctionDefinitions -Path $legacyPath -Name $name)
        )
        Assert-True ($definitions.Count -eq 1) "Expected one definition of $name across both modules, found $($definitions.Count)."
        Assert-True ($definitions[0].Extent.File -eq $helperPath) "$name must be defined in the extracted helper."
    }
}

Invoke-TestCase 'The physical-core reader keeps unsupported platforms on the zero fallback' {
    $definitions = @(Get-FunctionDefinitions -Path $helperPath -Name 'Get-PhysicalCoreCount')
    Assert-True ($definitions.Count -eq 1) "Expected one Get-PhysicalCoreCount definition, found $($definitions.Count)."

    $body = $definitions[0].Body.Extent.Text
    Assert-True ($body -match [regex]::Escape('[System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)')) 'The non-Windows branch must identify Linux precisely.'
    Assert-True ($body -notmatch 'DirectorySeparatorChar\s+-eq\s+[''"]/[''"]') 'A slash separator must not classify every Unix host as Linux.'
    Assert-True ($body -match 'return\s+0\s*\r?\n\s*\}$') 'An unsupported platform must reach the zero fallback.'
}

Invoke-TestCase 'The existing common module still exposes the sizing rule' {
    . $legacyPath
    Assert-True ((Get-DefaultSuiteWorkerCount -PhysicalCoreCount 8 -LogicalProcessorCount 16) -eq 6) 'The old module caller must still reach the sizing rule.'
    Assert-True ((Get-DefaultSuiteWorkerReason -PhysicalCoreCount 8 -LogicalProcessorCount 2) -match 'capped at 2 available processors') 'The old module caller must still reach the reason rule.'
}

Invoke-TestCase 'The current host loads the extracted helper' {
    Invoke-HostLoadCheck -HostPath ([System.Diagnostics.Process]::GetCurrentProcess().Path)
}

if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    Invoke-TestCase 'Windows PowerShell 5.1 loads the extracted helper' {
        $windowsPowerShell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
        Assert-True (-not [string]::IsNullOrWhiteSpace($windowsPowerShell)) 'Windows PowerShell 5.1 must be installed for this compatibility check.'
        Invoke-HostLoadCheck -HostPath $windowsPowerShell
    }
} else {
    Write-Host '  SKIP  Windows PowerShell 5.1 load check (Windows only)' -ForegroundColor Yellow
}

Invoke-TestCase 'Synthetic processor counts keep the established sizing results' {
    . $helperPath

    $cases = @(
        @{ Physical = 8; Logical = 16; All = $false; Expected = 6 }
        @{ Physical = 5; Logical = 16; All = $false; Expected = 3 }
        @{ Physical = 16; Logical = 32; All = $false; Expected = 8 }
        @{ Physical = 8; Logical = 2; All = $false; Expected = 2 }
        @{ Physical = 1; Logical = 16; All = $false; Expected = 1 }
        @{ Physical = 0; Logical = 4; All = $false; Expected = 4 }
        @{ Physical = 0; Logical = 16; All = $false; Expected = 8 }
        @{ Physical = 2; Logical = 4; All = $true; Expected = 4 }
    )

    foreach ($case in $cases) {
        $actual = Get-DefaultSuiteWorkerCount -PhysicalCoreCount $case.Physical -LogicalProcessorCount $case.Logical -AllProcessors:$case.All
        Assert-True ($actual -eq $case.Expected) "Physical=$($case.Physical), Logical=$($case.Logical), All=$($case.All): expected $($case.Expected), got $actual."
    }
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Suite worker count tests passed.' -ForegroundColor Green
exit 0
