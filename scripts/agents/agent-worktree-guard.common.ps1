#Requires -Version 5.1
# Shared policy core for the cross-agent Git guardrails.
#
# Agent adapters (Claude, Codex, Copilot) normalize their native PreToolUse payloads and
# responses; every path classification, mutation-detection, bypass-precedence, and message
# decision lives here so the three integrations cannot drift apart.
#
# This file is dot-sourced, so it deliberately does not set strict mode or
# $ErrorActionPreference - those belong to the calling entrypoint.

# scripts/worktree-git.common.ps1 stays the single definition of "a linked worktree" for the
# worktree scripts, but it is deliberately not dot-sourced here: Resolve-GitPath and
# Test-LinkedWorktree each spawn their own `git rev-parse`, and this file runs on every candidate
# command. Get-ManagedWorktreeState makes the identical git-dir/common-dir comparison from one
# batched rev-parse instead. Keep the two in step if that definition ever changes.

$script:AgentGuardShellToolNames = @('bash', 'shell', 'shell_command', 'sh', 'powershell', 'pwsh')

$script:AgentGuardProtectedCommonDirCache = @{}

# Characters a backslash may escape inside double quotes (POSIX), and outside quotes. Compared
# with IndexOf, not -contains: -contains on a string tests the whole string, never a character.
$script:AgentGuardDoubleQuoteEscapables = '$`"\'
$script:AgentGuardUnquotedEscapables = '$`"\;&|()' + "'"

# Commands that move the shell's working directory, so a later `git` in the same chain does not
# run where the hook payload said it would. pushd/popd are tracked separately because they form a
# stack: treating popd as an unrecognized command left the guard believing the shell was still in
# whatever pushd last selected.
$script:AgentGuardChangeDirectoryCommands = @('cd', 'chdir', 'set-location')
$script:AgentGuardPushDirectoryCommands = @('pushd', 'push-location')
$script:AgentGuardPopDirectoryCommands = @('popd', 'pop-location')

# A leading NAME=value assignment is a prefix, not the command being run.
$script:AgentGuardEnvAssignmentPattern = '^[A-Za-z_][A-Za-z0-9_]*='

function New-AgentGuardDecision {
    [CmdletBinding()]
    param(
        [ValidateSet('Allow', 'Warn', 'Deny')]
        [string] $Action = 'Allow',
        [string] $Rule = 'none',
        [string] $Message = ''
    )

    return [pscustomobject]@{
        Action  = $Action
        Rule    = $Rule
        Message = $Message
    }
}

<#
.SYNOPSIS
Runs a git probe and returns its trimmed stdout, or '' when the probe fails.

.DESCRIPTION
Windows PowerShell 5.1 turns native stderr into a terminating error while
$ErrorActionPreference is 'Stop' (the entrypoint sets exactly that). Probing a directory that
is not a repository is an expected outcome here, not a fault, so stderr is suppressed locally.
#>
function Invoke-AgentGuardGitProbe {
    param([string[]] $GitArguments)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& git @GitArguments 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0) { return '' }
        return $output.Trim()
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Test-AgentGuardProperty {
    param($InputObject, [string] $Name)

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -isnot [psobject]) { return $false }

    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function ConvertTo-AgentGuardNormalizedPath {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    $trimmed = $Path.Trim()
    try {
        $resolved = Resolve-Path -LiteralPath $trimmed -ErrorAction Stop
        return $resolved.Path.TrimEnd('\', '/')
    }
    catch {
        return $trimmed.TrimEnd('\', '/')
    }
}

<#
.SYNOPSIS
Normalizes a native agent PreToolUse payload into { Adapter, ToolName, Command, Cwd }.

.DESCRIPTION
Adapter 'Auto' infers Copilot from a top-level 'toolArgs' key and Claude otherwise; Codex
always supplies an explicit override. Throws on malformed JSON so the caller can fail open.
#>
function ConvertFrom-AgentHookInput {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'Claude', 'Codex', 'Copilot')]
        [string] $Adapter = 'Auto',
        [string] $InputJson
    )

    if ([string]::IsNullOrWhiteSpace($InputJson)) {
        throw 'Agent hook payload was empty.'
    }

    $payload = $InputJson | ConvertFrom-Json

    $resolvedAdapter = $Adapter
    if ($resolvedAdapter -eq 'Auto') {
        $resolvedAdapter = if (Test-AgentGuardProperty $payload 'toolArgs') { 'Copilot' } else { 'Claude' }
    }

    $rawToolName = ''
    $command = ''

    if ($resolvedAdapter -eq 'Copilot') {
        if (Test-AgentGuardProperty $payload 'toolName') { $rawToolName = [string] $payload.toolName }

        if (Test-AgentGuardProperty $payload 'toolArgs') {
            $toolArgs = $payload.toolArgs
            if ($toolArgs -is [string]) {
                # Copilot delivers toolArgs as an embedded JSON string.
                if (-not [string]::IsNullOrWhiteSpace($toolArgs)) {
                    $parsedArgs = $toolArgs | ConvertFrom-Json
                    if (Test-AgentGuardProperty $parsedArgs 'command') { $command = [string] $parsedArgs.command }
                }
            }
            elseif (Test-AgentGuardProperty $toolArgs 'command') {
                $command = [string] $toolArgs.command
            }
        }
    }
    else {
        if (Test-AgentGuardProperty $payload 'tool_name') { $rawToolName = [string] $payload.tool_name }

        if (Test-AgentGuardProperty $payload 'tool_input') {
            $toolInput = $payload.tool_input
            if (Test-AgentGuardProperty $toolInput 'command') { $command = [string] $toolInput.command }
        }
    }

    $cwd = ''
    if (Test-AgentGuardProperty $payload 'cwd') { $cwd = [string] $payload.cwd }

    $normalizedToolName = $rawToolName
    if ($script:AgentGuardShellToolNames -contains $rawToolName.ToLowerInvariant()) {
        $normalizedToolName = 'shell'
    }

    return [pscustomobject]@{
        Adapter  = $resolvedAdapter
        ToolName = $normalizedToolName
        Command  = $command
        Cwd      = (ConvertTo-AgentGuardNormalizedPath $cwd)
    }
}

<#
.SYNOPSIS
Ports the original pre-bash-guard.sh destructive-command rules without broadening them.

.DESCRIPTION
These run before any location logic and are never relaxed by AHKFLOW_ALLOW_MAIN, so they are
classified from the parsed git subcommand and its arguments rather than from regexes over the
raw string. Regexes over the unnormalized command missed every ordinary variant that puts
something between `git` and the subcommand - `git -C . reset --hard`, `git.exe reset --hard`,
`git --no-pager checkout .` - which let AHKFLOW_ALLOW_MAIN=1 downgrade a destructive command to
a warning. The rm and dotnet rules read the same parsed segments, so a `rm -rf`/`dotnet run`
pattern that only appears inside a quoted argument - a commit message or a `git log --grep`
needle - is no longer mistaken for an invocation.
#>
function Get-AgentCommandSafetyDecision {
    [CmdletBinding()]
    param([string] $Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return New-AgentGuardDecision -Action Allow
    }

    $gitDecision = Get-AgentGitSafetyDecision -Command $Command
    if ($gitDecision.Action -ne 'Allow') { return $gitDecision }

    # rm/dotnet are classified from the same parsed segments, so a pattern that only appears inside
    # a quoted argument - a commit message or a `git log --grep` needle mentioning `rm -rf` - is not
    # read as an invocation. Only a segment's leading command word is inspected. A wrapped
    # `sudo rm -rf` hides exactly the way `sh -c 'git ...'` already does: the documented wrapper
    # gap, not a new one.
    $segments = @((Get-AgentCommandSegment -Command $Command).Segments)

    foreach ($segment in $segments) {
        if ((Get-AgentOtherCommandLeaf -Segment $segment) -ne 'rm') { continue }
        if (Test-AgentDangerousRmArguments -Arguments @($segment.Tokens | Select-Object -Skip 1)) {
            return New-AgentGuardDecision -Action Deny -Rule 'dangerous-rm' -Message `
                'WARNING: rm -rf detected in a project directory. Verify the target path is intentional.'
        }
    }

    foreach ($segment in $segments) {
        if ((Get-AgentOtherCommandLeaf -Segment $segment) -ne 'dotnet') { continue }
        $dotnetArgs = @(Get-AgentGitPositionals -Arguments @($segment.Tokens | Select-Object -Skip 1))
        if ($dotnetArgs.Count -gt 0 -and $dotnetArgs[0] -ieq 'run') {
            return New-AgentGuardDecision -Action Warn -Rule 'dotnet-run' -Message `
                'WARNING: dotnet run detected. Ensure launchSettings.json exists and the correct profile is selected.'
        }
    }

    return New-AgentGuardDecision -Action Allow
}

<#
.SYNOPSIS
Returns the lowercased leaf command word of an 'Other' segment, or '' for any other kind.

.DESCRIPTION
Git/cd/pushd/popd segments are classified elsewhere; only a plain command segment carries its
executable in Tokens[0]. Matching on the leaf keeps `/usr/bin/rm` and `rm` equivalent, while a
quoted `rm` inside a git argument - which never becomes its own segment - is never inspected.
#>
function Get-AgentOtherCommandLeaf {
    param([object] $Segment)

    if ($Segment.Kind -ne 'Other') { return '' }
    $tokens = @($Segment.Tokens)
    if ($tokens.Count -eq 0) { return '' }

    $name = ([string] $tokens[0]).ToLowerInvariant()
    return ($name -split '[\\/]')[-1]
}

<#
.SYNOPSIS
True when an rm argument list carries a clustered recursive-force flag aimed at a non-throwaway
target.

.DESCRIPTION
Mirrors the original raw-string rule (a single `-rf`/`-fr`/`-Rf`-style flag) but reads it from
parsed tokens. The build-output allow-list is compared against the target's final path component,
so `node_modules`, `bin`, `obj`, `TestResults`, `.vs`, and `/tmp` stay allowed. An rm carrying the
flag with no visible target is treated as dangerous.
#>
function Test-AgentDangerousRmArguments {
    param([string[]] $Arguments)

    $hasRecursiveForce = @($Arguments | Where-Object {
            $_ -match '^-[a-z]*r[a-z]*f' -or $_ -match '^-[a-z]*f[a-z]*r'
        }).Count -gt 0
    if (-not $hasRecursiveForce) { return $false }

    $positionals = @(Get-AgentGitPositionals -Arguments $Arguments)
    if ($positionals.Count -eq 0) { return $true }

    $leaf = (([string] $positionals[0]) -split '[\\/]')[-1]
    $allowedTargets = @('node_modules', 'bin', 'obj', 'testresults', '.vs', 'tmp')
    return $allowedTargets -notcontains $leaf.ToLowerInvariant()
}

<#
.SYNOPSIS
Applies the destructive git rules to every parsed git invocation in a command.

.DESCRIPTION
An unparseable command yields Allow here; Get-AgentWorktreeGuardDecision denies it separately
with the ambiguous-git-command rule, so nothing slips through by returning Allow.
#>
function Get-AgentGitSafetyDecision {
    [CmdletBinding()]
    param([string] $Command)

    $parsed = Get-AgentGitInvocation -Command $Command
    if ($parsed.Ambiguous) { return New-AgentGuardDecision -Action Allow }

    foreach ($tokens in $parsed.Invocations) {
        $parts = Get-AgentGitParts -Tokens $tokens
        $subcommand = ([string] $parts.Subcommand).ToLowerInvariant()
        $arguments = $parts.Args

        switch ($subcommand) {
            'push' {
                # -f may be bundled (-fu, -uf), and a leading '+' on a refspec forces that ref
                # without any flag at all. Matching only exact -f/--force left both spellings at
                # safety Allow, so AHKFLOW_ALLOW_MAIN=1 could downgrade them to a location warning.
                $forced =
                (Test-AgentGitArgsContainAny -Arguments $arguments -Options @('-f', '--force')) -or
                @($arguments | Where-Object { $_ -ilike '--force-*' }).Count -gt 0 -or
                @($arguments | Where-Object { $_ -cmatch '^-[a-zA-Z]*f' }).Count -gt 0 -or
                @(Get-AgentGitPositionals -Arguments $arguments | Where-Object { $_ -like '+*' }).Count -gt 0

                if ($forced) {
                    return New-AgentGuardDecision -Action Deny -Rule 'force-push' -Message `
                        'BLOCKED: Force push detected. Use regular push or discuss with the user first.'
                }
            }
            'reset' {
                if (Test-AgentGitArgsContainAny -Arguments $arguments -Options @('--hard')) {
                    return New-AgentGuardDecision -Action Deny -Rule 'git-reset-hard' -Message `
                        'BLOCKED: git reset --hard will discard all uncommitted changes. Discuss with the user first.'
                }
            }
            'clean' {
                # -f may be bundled into a short cluster such as -xdf.
                if (@($arguments | Where-Object { $_ -ieq '--force' -or $_ -cmatch '^-[a-zA-Z]*f' }).Count -gt 0) {
                    return New-AgentGuardDecision -Action Deny -Rule 'git-clean-force' -Message `
                        'BLOCKED: git clean -f will permanently delete untracked files. Discuss with the user first.'
                }
            }
            'checkout' {
                if (@(Get-AgentGitPositionals -Arguments $arguments) -contains '.') {
                    return New-AgentGuardDecision -Action Deny -Rule 'git-checkout-dot' -Message `
                        'BLOCKED: git checkout . will discard all unstaged changes. Discuss with the user first.'
                }
            }
        }
    }

    return New-AgentGuardDecision -Action Allow
}

<#
.SYNOPSIS
Splits a command string into tokenized top-level segments using a small shell-quoting model.

.DESCRIPTION
Walks the string one character at a time through None/SingleQuoted/DoubleQuoted/Escaped states,
so a separator inside quotes stays part of a single argument. A segment ends at an unquoted
newline, ';', '&', '|', '`', '(' or ')'; that is what makes `cd X && git commit` two segments
rather than one opaque string. Double-quote escaping follows POSIX (a backslash is literal
unless it precedes $, `, ", \, or newline), which keeps quoted Windows paths such as
"C:\some;path" intact. Outside quotes a backslash only escapes a metacharacter or whitespace,
so an unquoted C:\Dev\repo survives too.

Returns { Segments = @(string[]); Ambiguous = bool }. Ambiguous means the string ended inside an
unterminated quote or escape, which makes every segment boundary in it untrustworthy.
This is intentionally not a complete shell parser.
#>
function Split-AgentCommandSegment {
    [CmdletBinding()]
    param([string] $Command)

    $segments = New-Object System.Collections.Generic.List[object]
    $tokens = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $hasCurrent = $false
    $state = 'None'
    $returnState = 'None'

    for ($i = 0; $i -lt $Command.Length; $i++) {
        $ch = $Command[$i]

        if ($state -eq 'Escaped') {
            [void] $current.Append($ch)
            $hasCurrent = $true
            $state = $returnState
            continue
        }

        if ($state -eq 'SingleQuoted') {
            if ($ch -eq "'") { $state = 'None' }
            else { [void] $current.Append($ch); $hasCurrent = $true }
            continue
        }

        if ($state -eq 'DoubleQuoted') {
            if ($ch -eq '\' -and ($i + 1) -lt $Command.Length -and
                $script:AgentGuardDoubleQuoteEscapables.IndexOf($Command[$i + 1]) -ge 0) {
                $returnState = 'DoubleQuoted'
                $state = 'Escaped'
            }
            elseif ($ch -eq '"') { $state = 'None' }
            else { [void] $current.Append($ch); $hasCurrent = $true }
            continue
        }

        # None state. A backslash only escapes a metacharacter or whitespace here; treating it as
        # a universal escape would shred every unquoted Windows path the guard has to classify.
        if ($ch -eq '\' -and ($i + 1) -lt $Command.Length -and
            ($script:AgentGuardUnquotedEscapables.IndexOf($Command[$i + 1]) -ge 0 -or
            [char]::IsWhiteSpace($Command[$i + 1]))) {
            $returnState = 'None'
            $state = 'Escaped'
            continue
        }
        if ($ch -eq "'") { $state = 'SingleQuoted'; $hasCurrent = $true; continue }
        if ($ch -eq '"') { $state = 'DoubleQuoted'; $hasCurrent = $true; continue }

        if ($ch -eq "`n" -or $ch -eq "`r" -or $ch -eq ';' -or $ch -eq '&' -or $ch -eq '|' -or
            $ch -eq '`' -or $ch -eq '(' -or $ch -eq ')') {
            if ($hasCurrent) { [void] $tokens.Add($current.ToString()); [void] $current.Clear(); $hasCurrent = $false }
            if ($tokens.Count -gt 0) { [void] $segments.Add($tokens.ToArray()); $tokens.Clear() }
            continue
        }

        if ([char]::IsWhiteSpace($ch)) {
            if ($hasCurrent) { [void] $tokens.Add($current.ToString()); [void] $current.Clear(); $hasCurrent = $false }
            continue
        }

        [void] $current.Append($ch)
        $hasCurrent = $true
    }

    if ($state -ne 'None') {
        return [pscustomobject]@{ Segments = @(); Ambiguous = $true }
    }

    if ($hasCurrent) { [void] $tokens.Add($current.ToString()) }
    if ($tokens.Count -gt 0) { [void] $segments.Add($tokens.ToArray()) }

    return [pscustomobject]@{
        Segments  = $segments.ToArray()
        Ambiguous = $false
    }
}

<#
.SYNOPSIS
Classifies each top-level segment as a git invocation, a directory change, or something else.

.DESCRIPTION
Returns { Segments = @(objects); Ambiguous = bool }. Each segment carries Kind
(Git | ChangeDirectory | Other), Tokens (leading NAME=value assignments removed), and - for
ChangeDirectory - Directory plus Unresolved. Unresolved marks a target the guard cannot expand
literally (`cd -`, `cd $HOME`, bare `cd`), so a following mutation is treated as untargetable
rather than silently classified against a stale directory.
#>
function Get-AgentCommandSegment {
    [CmdletBinding()]
    param([string] $Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return [pscustomobject]@{ Segments = @(); Ambiguous = $false }
    }

    $split = Split-AgentCommandSegment -Command $Command
    if ($split.Ambiguous) {
        return [pscustomobject]@{ Segments = @(); Ambiguous = $true }
    }

    $classified = New-Object System.Collections.Generic.List[object]

    foreach ($tokens in $split.Segments) {
        # Drop NAME=value prefixes so `AHKFLOW_ALLOW_MAIN=1 git commit` still reads as git.
        $start = 0
        while ($start -lt $tokens.Count -and $tokens[$start] -match $script:AgentGuardEnvAssignmentPattern) { $start++ }
        if ($start -ge $tokens.Count) { continue }

        $effective = @($tokens[$start..($tokens.Count - 1)])
        $name = ([string] $effective[0]).ToLowerInvariant()
        $leaf = ($name -split '[\\/]')[-1]

        if ($leaf -eq 'git' -or $leaf -eq 'git.exe') {
            # @() around the slice: a bare `git` has no tail, and 1..0 counts backwards.
            $tail = if ($effective.Count -gt 1) { @($effective[1..($effective.Count - 1)]) } else { @() }
            [void] $classified.Add([pscustomobject]@{
                    Kind       = 'Git'
                    Tokens     = $tail
                    Directory  = ''
                    Unresolved = $false
                })
            continue
        }

        if ($script:AgentGuardPopDirectoryCommands -contains $name) {
            [void] $classified.Add([pscustomobject]@{
                    Kind       = 'PopDirectory'
                    Tokens     = $effective
                    Directory  = ''
                    Unresolved = $false
                })
            continue
        }

        $isPush = $script:AgentGuardPushDirectoryCommands -contains $name
        if ($isPush -or $script:AgentGuardChangeDirectoryCommands -contains $name) {
            # First non-option token is the target; that also skips Set-Location -LiteralPath.
            $target = @($effective | Select-Object -Skip 1 | Where-Object { $_ -notlike '-*' } | Select-Object -First 1)
            $directory = if ($target.Count -gt 0) { [string] $target[0] } else { '' }
            # A bare `pushd` swaps the top two stack entries rather than moving somewhere named,
            # so it is untrackable in the same way an unexpandable target is.
            $unresolved = [string]::IsNullOrWhiteSpace($directory) -or $directory -match '[\$%]'

            [void] $classified.Add([pscustomobject]@{
                    Kind       = if ($isPush) { 'PushDirectory' } else { 'ChangeDirectory' }
                    Tokens     = $effective
                    Directory  = $directory
                    Unresolved = $unresolved
                })
            continue
        }

        [void] $classified.Add([pscustomobject]@{
                Kind       = 'Other'
                Tokens     = $effective
                Directory  = ''
                Unresolved = $false
            })
    }

    return [pscustomobject]@{
        Segments  = $classified.ToArray()
        Ambiguous = $false
    }
}

<#
.SYNOPSIS
Extracts every direct git invocation in a command string.

.DESCRIPTION
Returns { Invocations = @(string[]); Ambiguous = bool }, where each invocation is the token list
after the `git` word itself. Ambiguous means an unbalanced quote made the string impossible to
tokenize safely.
#>
function Get-AgentGitInvocation {
    [CmdletBinding()]
    param([string] $Command)

    $parsed = Get-AgentCommandSegment -Command $Command
    if ($parsed.Ambiguous) {
        return [pscustomobject]@{ Invocations = @(); Ambiguous = $true }
    }

    $invocations = @(
        $parsed.Segments |
            Where-Object { $_.Kind -eq 'Git' } |
            ForEach-Object { , $_.Tokens }
    )

    return [pscustomobject]@{
        Invocations = $invocations
        Ambiguous   = $false
    }
}

<#
.SYNOPSIS
Location and Git-mutation policy for one normalized command.

.DESCRIPTION
Runs after Get-AgentCommandSafetyDecision. Callers are expected to wrap this in a fail-open
try/catch: an unexpected classification error must not take the agent's shell away.
#>
function Get-AgentWorktreeGuardDecision {
    [CmdletBinding()]
    param(
        [string] $Command,
        [string] $Cwd,
        [string] $ProtectedRepoRoot,
        [bool] $AllowMain = $false
    )

    $parsed = Get-AgentCommandSegment -Command $Command

    if ($parsed.Ambiguous) {
        return New-AgentGuardDecision -Action Deny -Rule 'ambiguous-git-command' -Message `
        ('BLOCKED: the git command could not be parsed safely (unbalanced quote). ' +
            'Rewrite it with balanced quoting.')
    }

    if (@($parsed.Segments | Where-Object { $_.Kind -eq 'Git' }).Count -eq 0) {
        return New-AgentGuardDecision -Action Allow
    }

    return Get-AgentGitLocationDecision -Segments $parsed.Segments -Cwd $Cwd `
        -ProtectedRepoRoot $ProtectedRepoRoot -AllowMain $AllowMain
}

# Git subcommands that always mutate repository state. Conditional subcommands (branch, tag,
# worktree, config, remote, submodule, reflog, stash, notes, bisect, apply, init) are handled
# separately because they have genuinely read-only forms.
$script:AgentGuardMutatingSubcommands = @(
    'add', 'am', 'checkout', 'cherry-pick', 'clean', 'commit', 'gc', 'maintenance', 'merge',
    'mv', 'pull', 'push', 'rebase', 'repack', 'replace', 'reset', 'restore', 'revert', 'rm',
    'sparse-checkout', 'switch', 'update-index', 'update-ref'
)

# The override line is deliberately explicit about *where* the variable has to be set. This hook
# runs in its own process and inspects the command as text, so an inline `AHKFLOW_ALLOW_MAIN=1 git
# ...` prefix only ever reaches the child git process - never this evaluator. An agent therefore
# cannot self-apply the override, which is the point: the location rule is the human's to relax.
# (The pre-commit backstop is different - git spawns it, so it does inherit an inline prefix.)
$script:AgentGuardDenialMessage = @'
BLOCKED: agent Git mutations are allowed only in a managed linked worktree.
Current target: {0}
Create one with scripts/new-worktree.ps1 or the agent WorktreeCreate tool.
Read-only Git and ordinary edit/build/test commands are unaffected.
To override, a human must set AHKFLOW_ALLOW_MAIN=1 in the shell environment before starting the
agent session. An inline "AHKFLOW_ALLOW_MAIN=1 git ..." prefix does not work: this guard runs in
its own process and never sees it.
'@

# Global options that consume the following token, so the subcommand scan skips their argument.
$script:AgentGuardValueGlobalOptions = @('-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path')

<#
.SYNOPSIS
Splits a tokenized git invocation into its global options, subcommand, and post-subcommand args.

.DESCRIPTION
Returns { Subcommand; Args; DashC = @(paths in order); UsesGitDirOrWorkTree }. Args keeps
options and positionals in order so conditional subcommands can inspect them.
#>
function Get-AgentGitParts {
    [CmdletBinding()]
    param([string[]] $Tokens)

    $subcommand = ''
    $tail = New-Object System.Collections.Generic.List[string]
    $dashC = New-Object System.Collections.Generic.List[string]
    $usesGitDirOrWorkTree = $false

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = $Tokens[$i]

        if ($subcommand -eq '') {
            if ($token -ieq '-C') {
                if (($i + 1) -lt $Tokens.Count) { [void] $dashC.Add($Tokens[++$i]) }
                continue
            }
            if ($token -ieq '--git-dir' -or $token -ieq '--work-tree') {
                $usesGitDirOrWorkTree = $true
                if (($i + 1) -lt $Tokens.Count) { $i++ }
                continue
            }
            if ($token -like '--git-dir=*' -or $token -like '--work-tree=*') {
                $usesGitDirOrWorkTree = $true
                continue
            }
            if ($token -in $script:AgentGuardValueGlobalOptions) {
                if (($i + 1) -lt $Tokens.Count) { $i++ }
                continue
            }
            if ($token -like '-*') { continue }

            $subcommand = $token
            continue
        }

        [void] $tail.Add($token)
    }

    return [pscustomobject]@{
        Subcommand           = $subcommand
        Args                 = $tail.ToArray()
        DashC                = $dashC.ToArray()
        UsesGitDirOrWorkTree = $usesGitDirOrWorkTree
    }
}

function Get-AgentGitPositionals {
    param([string[]] $Arguments)
    return @($Arguments | Where-Object { $_ -notlike '-*' })
}

function Test-AgentGitArgsContainAny {
    param([string[]] $Arguments, [string[]] $Options)
    foreach ($arg in $Arguments) {
        foreach ($option in $Options) {
            if ($arg -ieq $option -or $arg -ilike "$option=*") { return $true }
        }
    }
    return $false
}

<#
.SYNOPSIS
True when the tokenized git invocation mutates repository state.

.DESCRIPTION
Always-mutating subcommands short-circuit. Conditional subcommands (branch, tag, worktree,
config, remote, submodule, reflog, stash, notes, bisect, apply, init) inspect their arguments.
Unknown subcommands are treated as non-mutating; that gap is recorded rather than papered over
with an allowlist.
#>
function Test-AgentGitMutation {
    [CmdletBinding()]
    param([string[]] $Tokens)

    $parts = Get-AgentGitParts -Tokens $Tokens
    $subcommand = $parts.Subcommand
    if ([string]::IsNullOrWhiteSpace($subcommand)) { return $false }
    $subcommand = $subcommand.ToLowerInvariant()

    if ($script:AgentGuardMutatingSubcommands -contains $subcommand) { return $true }

    $argTokens = $parts.Args
    # @(...) so a single positional stays an array; otherwise [0] would index into a string.
    $positionals = @(Get-AgentGitPositionals -Arguments $argTokens)
    $first = if ($positionals.Count -gt 0) { ([string] $positionals[0]).ToLowerInvariant() } else { '' }

    switch ($subcommand) {
        'branch' {
            # Create/delete/move/copy flags, an upstream change, or any positional branch target.
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @(
                    '-d', '-D', '--delete', '-m', '-M', '--move', '-c', '-C', '--copy',
                    '--set-upstream-to', '-u', '--unset-upstream', '--edit-description', '-f', '--force')) {
                return $true
            }
            # A query option makes the positional a filter pattern or a commit-ish, not a new
            # branch name: `git branch --list 'feature/*'` and `--contains HEAD` only read.
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @(
                    '-l', '--list', '--show-current', '--contains', '--no-contains', '--merged',
                    '--no-merged', '--points-at', '--format', '--sort')) {
                return $false
            }
            return $positionals.Count -gt 0
        }
        'tag' {
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @('-d', '--delete')) { return $true }
            # -v/--verify and -n only print; they take a tag name positionally.
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @(
                    '-l', '--list', '-v', '--verify', '-n', '--contains', '--no-contains',
                    '--points-at', '--merged', '--no-merged', '--format', '--sort')) {
                return $false
            }
            # A positional tagname without a query option creates a tag.
            return $positionals.Count -gt 0
        }
        'worktree' {
            return $first -in @('add', 'move', 'remove', 'repair', 'prune', 'lock', 'unlock')
        }
        'config' {
            # Git 2.46+ subcommand form: `git config get|list` reads, `set|unset|...` writes.
            if ($first -in @('get', 'list')) { return $false }
            if ($first -in @('set', 'unset', 'add', 'replace-all', 'rename-section', 'remove-section', 'edit')) {
                return $true
            }

            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @(
                    '--get', '--get-all', '--get-regexp', '--get-urlmatch', '--get-color', '--get-colorbool',
                    '-l', '--list', '--show-origin', '--show-scope', '--name-only')) {
                return $false
            }
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @(
                    '--unset', '--unset-all', '--add', '--replace-all', '--rename-section',
                    '--remove-section', '-e', '--edit')) {
                return $true
            }
            # A bare "name value" pair sets a value; a lone name is a (deprecated) read.
            return $positionals.Count -ge 2
        }
        'remote' {
            if ($positionals.Count -eq 0) { return $false }
            return $first -in @('add', 'remove', 'rm', 'rename', 'set-url', 'set-head', 'set-branches', 'prune', 'update')
        }
        'submodule' {
            if ($positionals.Count -eq 0) { return $false }
            return $first -in @('add', 'deinit', 'update', 'set-branch', 'set-url', 'sync', 'absorbgitdirs', 'init')
        }
        'reflog' {
            return $first -in @('delete', 'expire')
        }
        'stash' {
            if ($positionals.Count -eq 0) { return $true }
            return $first -notin @('list', 'show')
        }
        'notes' {
            if ($positionals.Count -eq 0) { return $false }
            return $first -notin @('list', 'show', 'get-ref')
        }
        'bisect' {
            return $first -in @('start', 'good', 'bad', 'new', 'old', 'reset', 'skip', 'run', 'replay')
        }
        'apply' {
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @('--apply')) { return $true }
            if (Test-AgentGitArgsContainAny -Arguments $argTokens -Options @('--check', '--stat', '--numstat', '--summary')) {
                return $false
            }
            return $true
        }
        'init' {
            # init always mutates; its effective target decides whether the location allows it.
            return $true
        }
        default {
            return $false
        }
    }
}

<#
.SYNOPSIS
Classifies a directory relative to the protected AHKFlowApp checkout.

.DESCRIPTION
Returns NotRepository, OutsideProtectedRepository, MainCheckout, ManagedWorktree, or
UnmanagedWorktree. Manifest validation (and the InvalidManifest state) is layered on later.
#>
function Get-ManagedWorktreeState {
    [CmdletBinding()]
    param(
        [string] $Cwd,
        [string] $ProtectedRepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($Cwd)) {
        return 'NotRepository'
    }

    # A target that does not exist yet (e.g. `git init newsub`) is classified by its nearest
    # existing ancestor: git would walk up to that enclosing repository too.
    $probeDir = $Cwd
    while (-not [string]::IsNullOrWhiteSpace($probeDir) -and -not (Test-Path -LiteralPath $probeDir)) {
        $parent = Split-Path -Parent $probeDir
        if ($parent -eq $probeDir) { break }
        $probeDir = $parent
    }
    if ([string]::IsNullOrWhiteSpace($probeDir) -or -not (Test-Path -LiteralPath $probeDir)) {
        return 'NotRepository'
    }

    # One rev-parse for all three target facts. This runs on every candidate command, so each
    # extra git process is a measurable share of the hook's latency budget.
    $probe = Invoke-AgentGuardGitProbe @(
        '-C', $probeDir, 'rev-parse', '--path-format=absolute',
        '--git-common-dir', '--git-dir', '--show-toplevel')

    $lines = @($probe -split "`r?`n" | Where-Object { $_ })
    if ($lines.Count -lt 3) {
        return 'NotRepository'
    }

    $targetCommonDir = ConvertTo-AgentGuardNormalizedPath $lines[0]
    $targetGitDir = ConvertTo-AgentGuardNormalizedPath $lines[1]
    $targetRoot = ConvertTo-AgentGuardNormalizedPath $lines[2]

    # The protected repository never changes within one hook process, but a chained command can
    # classify several targets. Cache it so only the target probe costs a git process per link.
    if ($script:AgentGuardProtectedCommonDirCache.ContainsKey($ProtectedRepoRoot)) {
        $protectedCommonDir = $script:AgentGuardProtectedCommonDirCache[$ProtectedRepoRoot]
    }
    else {
        $protectedCommonDir = Invoke-AgentGuardGitProbe @(
            '-C', $ProtectedRepoRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir')
        if ([string]::IsNullOrWhiteSpace($protectedCommonDir)) {
            throw "Could not resolve the protected repository's common git directory from '$ProtectedRepoRoot'."
        }

        $protectedCommonDir = ConvertTo-AgentGuardNormalizedPath $protectedCommonDir
        $script:AgentGuardProtectedCommonDirCache[$ProtectedRepoRoot] = $protectedCommonDir
    }

    if ($targetCommonDir -ine $protectedCommonDir) {
        return 'OutsideProtectedRepository'
    }

    # Same comparison Test-LinkedWorktree makes (see scripts/worktree-git.common.ps1, still the
    # single definition of record); applied to the batch above rather than re-spawning git twice.
    if ($targetGitDir -ieq $targetCommonDir) {
        return 'MainCheckout'
    }

    # core.hooksPath and the common dir both live in the main checkout, so derive main from there
    # rather than from $PSScriptRoot, which resolves to main from every linked worktree.
    $mainCheckout = ConvertTo-AgentGuardNormalizedPath (Split-Path -Parent $protectedCommonDir)
    $approvedParents = @(
        (Join-Path $mainCheckout '.claude\worktrees'),
        (Join-Path $mainCheckout '.worktrees')
    ) | ForEach-Object { ConvertTo-AgentGuardNormalizedPath $_ }

    $targetParent = ConvertTo-AgentGuardNormalizedPath (Split-Path -Parent $targetRoot)
    if ($approvedParents -inotcontains $targetParent) {
        return 'UnmanagedWorktree'
    }

    if (-not (Test-AgentWorktreeManifest -WorktreeRoot $targetRoot)) {
        return 'InvalidManifest'
    }

    return 'ManagedWorktree'
}

# Every key setup-worktree-local-dev.ps1 writes into scripts/.env.worktree. A managed worktree
# must carry exactly one value for each.
$script:AgentGuardManifestKeys = @(
    'AHKFLOW_API_PORT', 'AHKFLOW_UI_PORT', 'AHKFLOW_API_URL', 'AHKFLOW_UI_URL',
    'AHKFLOW_DB_NAME', 'AHKFLOW_SQL_PORT', 'AHKFLOW_COMPOSE_PROJECT', 'AHKFLOW_ROOT'
)

<#
.SYNOPSIS
Validates a managed worktree's scripts/.env.worktree manifest.

.DESCRIPTION
Returns $true only when the manifest exists, defines each required key exactly once, the three
ports parse as integers, the API/UI URLs carry the manifest ports, DB/compose values are
non-empty, and AHKFLOW_ROOT resolves back to this worktree root. A forged or partial manifest is
what separates an approved-location worktree from a genuinely managed one.
#>
function Test-AgentWorktreeManifest {
    [CmdletBinding()]
    param([string] $WorktreeRoot)

    $manifestPath = Join-Path $WorktreeRoot 'scripts\.env.worktree'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $false }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { continue }

        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()

        if ($script:AgentGuardManifestKeys -notcontains $key) { continue }
        if ($values.ContainsKey($key)) { return $false }  # duplicate key
        $values[$key] = $value
    }

    foreach ($key in $script:AgentGuardManifestKeys) {
        if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) { return $false }
    }

    $apiPort = 0; $uiPort = 0; $sqlPort = 0
    if (-not [int]::TryParse($values['AHKFLOW_API_PORT'], [ref] $apiPort)) { return $false }
    if (-not [int]::TryParse($values['AHKFLOW_UI_PORT'], [ref] $uiPort)) { return $false }
    if (-not [int]::TryParse($values['AHKFLOW_SQL_PORT'], [ref] $sqlPort)) { return $false }

    $apiUri = $null; $uiUri = $null
    if (-not [System.Uri]::TryCreate($values['AHKFLOW_API_URL'], [System.UriKind]::Absolute, [ref] $apiUri)) { return $false }
    if (-not [System.Uri]::TryCreate($values['AHKFLOW_UI_URL'], [System.UriKind]::Absolute, [ref] $uiUri)) { return $false }
    if ($apiUri.Port -ne $apiPort) { return $false }
    if ($uiUri.Port -ne $uiPort) { return $false }

    $manifestRoot = ConvertTo-AgentGuardNormalizedPath $values['AHKFLOW_ROOT']
    if ($manifestRoot -ine (ConvertTo-AgentGuardNormalizedPath $WorktreeRoot)) { return $false }

    return $true
}

$script:AgentGuardAllowedStates = @('NotRepository', 'OutsideProtectedRepository', 'ManagedWorktree')

<#
.SYNOPSIS
Resolves the effective directory a git invocation targets, honoring `git -C` and init's path.
#>
function Resolve-AgentGitTargetDirectory {
    [CmdletBinding()]
    param([object] $Parts, [string] $BaseCwd)

    $dir = $BaseCwd
    foreach ($cPath in $Parts.DashC) {
        if ([System.IO.Path]::IsPathRooted($cPath)) { $dir = $cPath }
        else { $dir = Join-Path $dir $cPath }
    }

    # `git init <path>` targets the positional path, not the invocation's working directory.
    if ($Parts.Subcommand -ieq 'init') {
        $positionals = @(Get-AgentGitPositionals -Arguments $Parts.Args)
        if ($positionals.Count -gt 0) {
            $initPath = $positionals[0]
            if ([System.IO.Path]::IsPathRooted($initPath)) { $dir = $initPath }
            else { $dir = Join-Path $dir $initPath }
        }
    }

    return $dir
}

<#
.SYNOPSIS
Maps every classified command segment to a single Allow/Warn/Deny decision.

.DESCRIPTION
Walks the segments in order so a `cd` earlier in the chain moves the directory a later `git`
mutation is classified against; `cd <main> && git commit` is otherwise indistinguishable from a
commit in the payload's own worktree. Denies when any mutating invocation targets a non-managed
location. A mutating invocation that carries --git-dir/--work-tree, or that follows a directory
change the guard could not expand literally, is denied outright (unless AHKFLOW_ALLOW_MAIN=1)
because the simple tokenizer cannot safely infer where it would write.
#>
function Get-AgentGitLocationDecision {
    [CmdletBinding()]
    param(
        [object[]] $Segments,
        [string] $Cwd,
        [string] $ProtectedRepoRoot,
        [bool] $AllowMain = $false
    )

    $effectiveCwd = $Cwd
    $unresolvedDirectory = $false
    $directoryStack = New-Object System.Collections.Generic.List[string]
    $blockingState = ''
    $blockingTarget = ''

    foreach ($segment in $Segments) {
        if ($segment.Kind -eq 'PopDirectory') {
            # An empty stack makes popd fail and leaves the shell where it is.
            if ($directoryStack.Count -gt 0) {
                $effectiveCwd = $directoryStack[$directoryStack.Count - 1]
                $directoryStack.RemoveAt($directoryStack.Count - 1)
                $unresolvedDirectory = $false
            }
            continue
        }

        if ($segment.Kind -eq 'ChangeDirectory' -or $segment.Kind -eq 'PushDirectory') {
            if ($segment.Unresolved) {
                $unresolvedDirectory = $true
                continue
            }

            $candidate = if ([System.IO.Path]::IsPathRooted($segment.Directory)) {
                $segment.Directory
            }
            elseif (-not [string]::IsNullOrWhiteSpace($effectiveCwd)) {
                Join-Path $effectiveCwd $segment.Directory
            }
            else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($candidate)) {
                $unresolvedDirectory = $true
                continue
            }

            # A cd to a path that does not exist FAILS, leaving the shell where it already was -
            # so the following git runs there, not at the named target. Treating the move as
            # successful classified `cd C:\missing; git commit` against a harmless outside path
            # and allowed a commit that actually landed in main.
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                continue
            }

            if ($segment.Kind -eq 'PushDirectory') { [void] $directoryStack.Add($effectiveCwd) }
            $effectiveCwd = $candidate
            $unresolvedDirectory = $false
            continue
        }

        if ($segment.Kind -ne 'Git') { continue }

        $tokens = $segment.Tokens
        $parts = Get-AgentGitParts -Tokens $tokens

        if (-not (Test-AgentGitMutation -Tokens $tokens)) {
            continue
        }

        if ($parts.UsesGitDirOrWorkTree) {
            $blockingState = 'ExplicitGitDir'
            $blockingTarget = $Cwd
            break
        }

        # An explicit `git -C <path>` re-anchors the target, so it survives an untrackable cd.
        if ($unresolvedDirectory -and $parts.DashC.Count -eq 0) {
            $blockingState = 'UnresolvedDirectoryChange'
            $blockingTarget = $Cwd
            break
        }

        $targetDir = Resolve-AgentGitTargetDirectory -Parts $parts -BaseCwd $effectiveCwd
        $state = Get-ManagedWorktreeState -Cwd $targetDir -ProtectedRepoRoot $ProtectedRepoRoot

        if ($state -inotin $script:AgentGuardAllowedStates) {
            $blockingState = $state
            $blockingTarget = $targetDir
            break
        }
    }

    if ($blockingState -eq '') {
        return New-AgentGuardDecision -Action Allow
    }

    if ($blockingState -eq 'ExplicitGitDir') {
        if ($AllowMain) {
            return New-AgentGuardDecision -Action Warn -Rule 'agent-git-dir-override-overridden' -Message `
            ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the --git-dir/--work-tree restriction for: $blockingTarget")
        }
        return New-AgentGuardDecision -Action Deny -Rule 'agent-git-dir-mutation' -Message `
        ('BLOCKED: agent Git mutations with --git-dir or --work-tree are not allowed; the ' +
            'target cannot be verified. Run the command from inside a managed linked worktree instead.')
    }

    if ($blockingState -eq 'UnresolvedDirectoryChange') {
        if ($AllowMain) {
            return New-AgentGuardDecision -Action Warn -Rule 'agent-unresolved-cd-overridden' -Message `
            ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode an unverifiable directory change before a git mutation.")
        }
        return New-AgentGuardDecision -Action Deny -Rule 'agent-unresolved-git-target' -Message `
        ('BLOCKED: this command changes directory to a target the guard cannot expand, so the ' +
            'git mutation cannot be verified. Run git from a managed linked worktree, or pass an ' +
            'explicit `git -C <path>`.')
    }

    if ($AllowMain) {
        return New-AgentGuardDecision -Action Warn -Rule 'agent-main-git-mutation-overridden' -Message `
        ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the managed-worktree location rule " +
            "($blockingState) for: $blockingTarget")
    }

    $message = [string]::Format($script:AgentGuardDenialMessage, $blockingTarget)
    return New-AgentGuardDecision -Action Deny -Rule 'agent-main-git-mutation' -Message $message
}

<#
.SYNOPSIS
Single orchestration point: safety rules fail closed, location rules fail open.

.DESCRIPTION
Kept here rather than in the adapter entrypoint so both the entrypoint and the focused tests
exercise the same precedence, and so tests can shadow either policy function to inject a fault.
#>
function Invoke-AgentGuardPolicy {
    [CmdletBinding()]
    param(
        [string] $Command,
        [string] $Cwd,
        [string] $ProtectedRepoRoot,
        [bool] $AllowMain = $false
    )

    try {
        $safety = Get-AgentCommandSafetyDecision -Command $Command
    }
    catch {
        # Fail closed: an evaluator fault must not silently drop destructive-command protection.
        return New-AgentGuardDecision -Action Deny -Rule 'safety-guard-error' -Message `
        ("BLOCKED: the agent command safety guard failed to evaluate this command: $($_.Exception.Message)")
    }

    if ($safety.Action -eq 'Deny') { return $safety }

    try {
        $location = Get-AgentWorktreeGuardDecision -Command $Command -Cwd $Cwd `
            -ProtectedRepoRoot $ProtectedRepoRoot -AllowMain $AllowMain
    }
    catch {
        # Fail open: keep the shell usable, but say so loudly.
        return New-AgentGuardDecision -Action Warn -Rule 'location-guard-error' -Message `
        ("WARNING: the agent worktree location guard could not evaluate this command: $($_.Exception.Message)")
    }

    if ($location.Action -ne 'Allow') { return $location }

    return $safety
}
