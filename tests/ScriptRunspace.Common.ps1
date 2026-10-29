#Requires -Version 5.1

# A fresh session prevents the tested script from reading variables in its caller.
# Environment variables remain process-wide; callers set them with Invoke-WithEnvironment
# from LanePool.Common.ps1.
function Invoke-TestScriptRunspace {
    param([Parameter(Mandatory)][string] $Path, [hashtable] $Argument = @{})

    $shell = [powershell]::Create()
    try {
        $null = $shell.AddScript({
            param($ScriptPath, $ScriptArguments)
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'
            $global:LASTEXITCODE = 0
            $records = [System.Collections.Generic.List[object]]::new()
            try {
                & $ScriptPath @ScriptArguments *>&1 | ForEach-Object { $records.Add($_) }
                $code = $LASTEXITCODE
            } catch {
                $records.Add($_)
                $code = 1
            }
            [pscustomobject]@{ Output = ($records | Out-String); ExitCode = $code }
        }).AddArgument($Path).AddArgument($Argument)
        $result = $shell.Invoke()
        if ($shell.Streams.Error.Count -gt 0) { throw ($shell.Streams.Error | Out-String) }
        return $result[0]
    } finally {
        $shell.Dispose()
    }
}
