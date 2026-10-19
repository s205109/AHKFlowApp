#Requires -Version 7.0
# Evidence that a Suite passed, keyed by everything it reads. Backlog 188.
#
# The Suite runner may skip a Suite whose inputs have not changed since it last passed. This file
# decides what "inputs" means, turns them into one key, and stores one small evidence file per
# key. A key is SHA-256 over the format version, the Suite, the job, the platform, the execution,
# the Lane role, the tool versions, and the path and hash of every file the Suite and the runner
# read. Change any one of them and the key changes, so the old evidence is never found again.
#
# Dot-source it from a runner:  . "$PSScriptRoot\gate-evidence.common.ps1"
#
#   Get-SuiteInputList    every file a script reads, or Resolved = $false with the reasons
#   Get-GateToolVersion   the pwsh, dotnet and git versions, read once per run
#   Get-SuiteReuseKey     the key, or $null when either input list is unresolved
#   Read-GateEvidence     the evidence for a key, or $null; it never throws
#   Write-GateEvidence    store the evidence through a temporary file
#   Get-GateEvidenceRoot  where the evidence lives
#
# This file targets 7.0 because run-powershell-suites.ps1 does. It does not call Set-StrictMode:
# that call leaks from a dot-sourced file into the caller's scope, and the runner sets it itself.

$script:GateEvidenceFormatVersion = 1

# A token that names a file the script may read. The list may hold too much; it must never miss a
# path written out in the text.
$script:GateEvidencePathPattern = '[A-Za-z0-9_.\-/]+\.(?:ps1|psm1|psd1|json|md|yml|csv|txt|xml|trx)\b'
$script:GateEvidenceScriptExtension = @('.ps1', '.psm1', '.psd1')

function ConvertTo-GateRelativePath {
    # The path relative to Root, with forward slashes, or $null when it lies outside Root.
    param([string] $FullPath, [string] $Root)
    $relative = [System.IO.Path]::GetRelativePath($Root, $FullPath)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith('../') -or $relative.StartsWith('..\')) {
        return $null
    }
    return $relative.Replace('\', '/')
}

function Resolve-GateTextPath {
    <#
      Every existing file a text token can name. A token such as PSScriptRoot/x.ps1, taken from
      "$PSScriptRoot\x.ps1", does not exist as written, so each tail after a slash is tried too,
      against Root and against the folder of the file that holds the token.
    #>
    param([string] $Token, [string] $Root, [string] $Folder)
    $candidates = [System.Collections.Generic.List[string]]::new()
    $text = $Token.Replace('\', '/')
    $candidates.Add($text)
    for ($i = $text.IndexOf('/'); $i -ge 0; $i = $text.IndexOf('/', $i + 1)) {
        if ($i + 1 -lt $text.Length) { $candidates.Add($text.Substring($i + 1)) }
    }

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        foreach ($base in @($Root, $Folder)) {
            $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $candidate))
            if ([System.IO.File]::Exists($full) -and -not $found.Contains($full)) { $found.Add($full) }
        }
    }
    return , $found
}

function Get-GateLiteralText {
    # The text of every string constant inside an AST node.
    param([System.Management.Automation.Language.Ast] $Ast)
    $strings = $Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
        }, $true)
    return @($strings | ForEach-Object { $_.Value })
}

function Test-GateLiteralResolves {
    param([string[]] $Text, [string] $Root, [string] $Folder)
    foreach ($value in $Text) {
        foreach ($match in [regex]::Matches($value.Replace('\', '/'), $script:GateEvidencePathPattern)) {
            if ((Resolve-GateTextPath -Token $match.Value -Root $Root -Folder $Folder).Count -gt 0) { return $true }
        }
    }
    return $false
}

function Get-SuiteInputList {
    <#
      Every file a Suite reads, found from its text. Returns
      [pscustomobject]@{ Resolved = [bool]; Inputs = [string[]]; Unresolved = [string[]] }.

      Inputs are relative to Root, with forward slashes, sorted ordinally, without duplicates.
      Resolved is $false when an extra input is missing, when a file lies outside Root, or when a
      script dot-sources something the resolver cannot follow. A caller must then run the Suite.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Root,
        [string[]] $ExtraInput = @()
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $files = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $unresolved = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()

    $addFile = {
        param([string] $Full)
        if ($null -eq (ConvertTo-GateRelativePath -FullPath $Full -Root $rootFull)) {
            $unresolved.Add("$($Full.Replace('\', '/')) lies outside $($rootFull.Replace('\', '/'))")
            return
        }
        if ($files.Add($Full) -and $script:GateEvidenceScriptExtension -contains [System.IO.Path]::GetExtension($Full).ToLowerInvariant()) {
            $queue.Enqueue($Full)
        }
    }

    $start = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($start)) {
        $unresolved.Add("$($Path.Replace('\', '/')) does not exist")
    }
    else {
        & $addFile $start
    }

    foreach ($extra in $ExtraInput) {
        $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $extra))
        if ([System.IO.Directory]::Exists($full)) {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($full, '*', [System.IO.SearchOption]::AllDirectories)) {
                & $addFile $file
            }
        }
        elseif ([System.IO.File]::Exists($full)) {
            & $addFile $full
        }
        else {
            $unresolved.Add("extra input $extra does not exist")
        }
    }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $folder = [System.IO.Path]::GetDirectoryName($current)
        $text = [System.IO.File]::ReadAllText($current)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($current, [ref] $tokens, [ref] $errors)

        # Step 2: every path written out in the text, here-strings included. Comments are blanked
        # first: a comment never makes a script read a file, and following the paths that comments
        # name pulled most of tests/ into the runner's own list.
        $code = [System.Text.StringBuilder]::new($text)
        foreach ($token in $tokens) {
            if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) {
                $start = $token.Extent.StartOffset
                $null = $code.Remove($start, $token.Extent.EndOffset - $start).Insert($start, ' ' * ($token.Extent.EndOffset - $start))
            }
        }
        foreach ($match in [regex]::Matches($code.ToString().Replace('\', '/'), $script:GateEvidencePathPattern)) {
            foreach ($full in (Resolve-GateTextPath -Token $match.Value -Root $rootFull -Folder $folder)) {
                & $addFile $full
            }
        }

        # Step 3: every dot-source must name a literal that step 2 resolved, or a variable whose
        # assignment in this file holds one. Anything else could load a file nobody listed.
        $relativeScript = ConvertTo-GateRelativePath -FullPath $current -Root $rootFull
        $dotSources = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
            }, $true)

        foreach ($command in $dotSources) {
            $target = $command.CommandElements[0]
            $variable = $null
            if ($target -is [System.Management.Automation.Language.UsingExpressionAst]) {
                $target = $target.SubExpression
            }
            if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $variable = $target.VariablePath.UserPath
            }

            $followed = $false
            if ($null -ne $variable) {
                $assignments = $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $node.Left.VariablePath.UserPath -eq $variable
                    }, $true)
                $followed = @($assignments).Count -gt 0
                foreach ($assignment in $assignments) {
                    if (-not (Test-GateLiteralResolves -Text (Get-GateLiteralText $assignment.Right) -Root $rootFull -Folder $folder)) {
                        $followed = $false
                    }
                }
            }
            else {
                $followed = Test-GateLiteralResolves -Text (Get-GateLiteralText $target) -Root $rootFull -Folder $folder
            }

            if (-not $followed) {
                $unresolved.Add("${relativeScript}:$($command.Extent.StartLineNumber) dot-sources '$($target.Extent.Text)', which the resolver cannot follow")
            }
        }
    }

    $inputs = @($files | ForEach-Object { ConvertTo-GateRelativePath -FullPath $_ -Root $rootFull } |
            Where-Object { $null -ne $_ })
    [Array]::Sort($inputs, [System.StringComparer]::Ordinal)

    return [pscustomobject]@{
        Resolved   = ($unresolved.Count -eq 0)
        Inputs     = [string[]] $inputs
        Unresolved = [string[]] $unresolved.ToArray()
    }
}

function Get-GateToolVersion {
    <#
      The versions of the tools a reusable Suite may run. Read it once per run. dotnet runs in
      RunnerRoot, because a global.json there can change which SDK answers.
    #>
    param([string] $RunnerRoot = (Get-Location).Path)

    $read = {
        param([string] $Command, [string[]] $Arguments)
        try {
            Push-Location -LiteralPath $RunnerRoot
            try { $output = & $Command @Arguments 2>$null } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { return 'unavailable' }
            return ((@($output) -join ' ').Trim())
        }
        catch { return 'unavailable' }
    }

    return [ordered]@{
        pwsh   = $PSVersionTable.PSVersion.ToString()
        dotnet = & $read 'dotnet' @('--version')
        git    = & $read 'git' @('--version')
    }
}

function Get-GateInputHash {
    # [ordered] path and SHA-256 per input, in list order.
    param([string[]] $Inputs, [string] $Root)
    $hashes = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in $Inputs) {
        $hash = Get-FileHash -LiteralPath (Join-Path $Root $relative) -Algorithm SHA256
        $hashes.Add([ordered]@{ path = $relative; sha256 = $hash.Hash.ToLowerInvariant() })
    }
    return , $hashes.ToArray()
}

function Get-SuiteReuseKey {
    <#
      SHA-256 hex over everything the Suite's result depends on, or $null when either input list
      is unresolved or an input cannot be read.
    #>
    param(
        [object] $Entry,
        [object] $InputList,
        [object] $RunnerInputList,
        [System.Collections.IDictionary] $ToolVersion,
        [string] $Job,
        [string] $Platform,
        [string] $LaneRole,
        [string] $Root,
        [string] $RunnerRoot
    )

    if ($null -eq $InputList -or $null -eq $RunnerInputList -or -not $InputList.Resolved -or -not $RunnerInputList.Resolved) {
        return $null
    }

    try {
        $payload = [ordered]@{
            formatVersion = $script:GateEvidenceFormatVersion
            suite         = [string] $Entry.Name
            job           = $Job
            platform      = $Platform
            execution     = [string] $Entry.Execution
            laneRole      = $LaneRole
            tools         = [ordered]@{ pwsh = [string] $ToolVersion['pwsh']; dotnet = [string] $ToolVersion['dotnet']; git = [string] $ToolVersion['git'] }
            inputs        = Get-GateInputHash -Inputs $InputList.Inputs -Root $Root
            runnerInputs  = Get-GateInputHash -Inputs $RunnerInputList.Inputs -Root $RunnerRoot
        }
        $json = $payload | ConvertTo-Json -Compress -Depth 6
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json)) } finally { $sha.Dispose() }
        return -join ($bytes | ForEach-Object { $_.ToString('x2') })
    }
    catch {
        # An input that vanished or cannot be read since the list was built: no key, so the
        # Suite runs.
        return $null
    }
}

function Get-GateEvidencePath {
    param([string] $EvidenceRoot, [string] $SuiteName, [string] $Key)
    return Join-Path (Join-Path $EvidenceRoot $SuiteName) "$Key.json"
}

function Read-GateEvidence {
    <#
      The evidence for this Suite and key, or $null. Missing, unreadable, cut off, another format
      version, another key or another Suite: each is a miss, and none of them throws.
    #>
    param([string] $EvidenceRoot, [string] $SuiteName, [string] $Key)
    try {
        $path = Get-GateEvidencePath -EvidenceRoot $EvidenceRoot -SuiteName $SuiteName -Key $Key
        if (-not [System.IO.File]::Exists($path)) { return $null }
        $evidence = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
        if ($evidence -isnot [System.Management.Automation.PSCustomObject]) { return $null }
        foreach ($field in @('formatVersion', 'suite', 'key', 'passedAtUtc', 'seconds', 'inputs', 'runnerInputs')) {
            if ($null -eq $evidence.PSObject.Properties[$field]) { return $null }
        }
        if ($evidence.formatVersion -ne $script:GateEvidenceFormatVersion) { return $null }
        if ([string] $evidence.key -cne $Key -or [string] $evidence.suite -cne $SuiteName) { return $null }
        return $evidence
    }
    catch {
        return $null
    }
}

function Write-GateEvidence {
    <#
      Store the evidence that this Suite passed under this key. It writes a temporary file and
      moves it into place, so a run stopped halfway never leaves half a file under the real name.
      A write that fails only warns: the Suite already passed, and the next run simply runs it.
    #>
    param(
        [string] $EvidenceRoot,
        [string] $SuiteName,
        [string] $Key,
        [object] $InputList,
        [object] $RunnerInputList,
        [double] $Seconds
    )

    $path = Get-GateEvidencePath -EvidenceRoot $EvidenceRoot -SuiteName $SuiteName -Key $Key
    $temp = "$path.$PID.tmp"
    try {
        $folder = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }

        $payload = [ordered]@{
            formatVersion = $script:GateEvidenceFormatVersion
            suite         = $SuiteName
            key           = $Key
            passedAtUtc   = [DateTime]::UtcNow.ToString('o')
            seconds       = $Seconds
            inputs        = @($InputList.Inputs)
            runnerInputs  = @($RunnerInputList.Inputs)
        }
        Set-Content -LiteralPath $temp -Value ($payload | ConvertTo-Json -Depth 4) -Encoding UTF8

        # The same move as Save-ProgressTimings: File.Replace over an existing file is one step.
        if ([System.IO.File]::Exists($path)) {
            [System.IO.File]::Replace($temp, $path, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temp, $path)
        }
    }
    catch {
        Write-Warning "Could not save gate evidence to $path. $($_.Exception.Message)"
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Get-GateEvidenceRoot {
    # $env:AHKFLOW_GATE_EVIDENCE_ROOT when set, else <RepoRoot>/TestResults/gate-evidence. Git
    # ignores TestResults/, so evidence never leaves the worktree.
    param([string] $RepoRoot)
    if (-not [string]::IsNullOrWhiteSpace($env:AHKFLOW_GATE_EVIDENCE_ROOT)) {
        return $env:AHKFLOW_GATE_EVIDENCE_ROOT
    }
    return Join-Path $RepoRoot 'TestResults\gate-evidence'
}
