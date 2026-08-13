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

# Claude's file-writing tools. These carry a literal path rather than a command, so they are
# classified by Get-AgentFileEditWriteDecision instead of the command evaluators.
$script:AgentGuardFileEditToolNames = @('edit', 'write', 'notebookedit')

$script:AgentGuardProtectedCommonDirCache = @{}

# Characters a backslash may escape inside double quotes (POSIX), and outside quotes. Compared
# with IndexOf, not -contains: -contains on a string tests the whole string, never a character.
$script:AgentGuardDoubleQuoteEscapables = '$`"\'
# '>' and '<' are here so `printf x\>y` reads as a literal '>', not a redirect. Neither character
# is legal in a Windows path, so no path the guard has to classify is affected.
$script:AgentGuardUnquotedEscapables = '$`"\;&|()<>' + "'"

# Characters that end an unquoted heredoc delimiter word. These are the same separators the
# tokenizer treats as segment boundaries, so `<<EOF; echo x` reads EOF and keeps the rest.
$script:AgentGuardHeredocDelimiterStops = ';&|`()<>'

# Commands that move the shell's working directory, so a later `git` in the same chain does not
# run where the hook payload said it would. pushd/popd are tracked separately because they form a
# stack: treating popd as an unrecognized command left the guard believing the shell was still in
# whatever pushd last selected.
$script:AgentGuardChangeDirectoryCommands = @('cd', 'chdir', 'set-location')
$script:AgentGuardPushDirectoryCommands = @('pushd', 'push-location')
$script:AgentGuardPopDirectoryCommands = @('popd', 'pop-location')

# A transparent command wrapper runs the rest of the command line as a child process.
# It does not change the shell's own state, such as its working directory.
# The guard reads past the wrapper to classify the command the wrapper runs.
# Adding a wrapper to this list can only expose more of a command to classification.
# It must never let the guard allow something the bare command would deny.
$script:AgentGuardTransparentWrappers = @('rtk', 'rtk.exe')
# rtk subcommands that take a raw command as their remaining arguments.
# Confirmed against rtk 0.43.0 --help. proxy and run were the original two.
# err, summary, and test also run a raw command, showing only part of its output.
# rtk's global options never consume a following token: -v/--verbose, --ultra-compact,
# --skip-env, -h/--help, -V/--version. So the generic leading-option scan below does not
# need to skip any of them separately.
$script:AgentGuardWrapperPassThroughSubcommands = @('proxy', 'run', 'err', 'summary', 'test')

# A leading NAME=value assignment is a prefix, not the command being run.
$script:AgentGuardEnvAssignmentPattern = '^[A-Za-z_][A-Za-z0-9_]*='

function New-AgentGuardDecision {
    [CmdletBinding()]
    param(
        [ValidateSet('Allow', 'Warn', 'Deny', 'Ask')]
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
Normalizes a native agent PreToolUse payload into
{ Adapter, ToolName, Command, TargetPath, Cwd, AgentId, AgentType }.

.DESCRIPTION
Adapter 'Auto' infers Copilot from a top-level 'toolArgs' key and Claude otherwise; Codex
always supplies an explicit override. Throws on malformed JSON so the caller can fail open.

A shell tool name normalizes to 'shell' and fills Command. A file-writing tool name normalizes to
'file-edit' and fills TargetPath from file_path, or from notebook_path for NotebookEdit. Any other
tool name is returned unchanged, and both fields stay empty.
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
    $targetPath = ''
    $agentId = ''
    $agentType = ''

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
            if (Test-AgentGuardProperty $toolInput 'file_path') { $targetPath = [string] $toolInput.file_path }
            elseif (Test-AgentGuardProperty $toolInput 'notebook_path') { $targetPath = [string] $toolInput.notebook_path }
        }

        # agent_id is present at the top level only when the call originates inside a subagent
        # call; agent_type is present for a subagent call OR an --agent session
        # (https://code.claude.com/docs/en/hooks). Codex's payload shape may not carry either at
        # all - Test-AgentGuardProperty returns $false and both stay ''.
        if (Test-AgentGuardProperty $payload 'agent_id') { $agentId = [string] $payload.agent_id }
        if (Test-AgentGuardProperty $payload 'agent_type') { $agentType = [string] $payload.agent_type }
    }

    $cwd = ''
    if (Test-AgentGuardProperty $payload 'cwd') { $cwd = [string] $payload.cwd }

    $normalizedToolName = $rawToolName
    if ($script:AgentGuardShellToolNames -contains $rawToolName.ToLowerInvariant()) {
        $normalizedToolName = 'shell'
    }
    elseif ($script:AgentGuardFileEditToolNames -contains $rawToolName.ToLowerInvariant()) {
        $normalizedToolName = 'file-edit'
    }

    return [pscustomobject]@{
        Adapter    = $resolvedAdapter
        ToolName   = $normalizedToolName
        Command    = $command
        TargetPath = $targetPath
        Cwd        = (ConvertTo-AgentGuardNormalizedPath $cwd)
        AgentId    = $agentId
        AgentType  = $agentType
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
Recursive and force are collected separately and across every argument, so the clustered `-rf`,
the split `-r -f`, and the long `--recursive --force` all read the same. Collecting them per
token instead would only catch the clustered spelling. The build-output allow-list is compared
against the target's final path component, so `node_modules`, `bin`, `obj`, `TestResults`, `.vs`,
and `/tmp` stay allowed. An rm carrying both flags with no visible target is treated as dangerous.
#>
function Test-AgentDangerousRmArguments {
    param([string[]] $Arguments)

    $hasRecursive = $false
    $hasForce = $false
    foreach ($argument in @($Arguments)) {
        $token = [string] $argument
        if ($token -ieq '--recursive') { $hasRecursive = $true; continue }
        if ($token -ieq '--force') { $hasForce = $true; continue }

        # A short-option cluster only. '--something-else' and operands are not flag carriers.
        if ($token -notmatch '^-[a-zA-Z]+$') { continue }
        $letters = $token.Substring(1)
        # rm spells recursive '-r' or '-R', and force '-f'. '-F' is not an rm flag.
        if ($letters -cmatch '[rR]') { $hasRecursive = $true }
        if ($letters -cmatch 'f') { $hasForce = $true }
    }
    if (-not ($hasRecursive -and $hasForce)) { return $false }

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
Reads the delimiter word of a heredoc opener, starting just past '<<' or '<<-'.

.DESCRIPTION
bash allows whitespace between the operator and the word. It also allows the word to be quoted
('EOF', "EOF") or backslash-quoted (\EOF). All four spellings name the same terminator: quoting
only suppresses expansion inside the body, and the guard never expands anything. A backslash is
handled here rather than through the tokenizer's own escape table, which keeps a literal
backslash in an unquoted Windows path and would otherwise read the delimiter as \EOF.

The word ends at whitespace or at one of $script:AgentGuardHeredocDelimiterStops. A newline or
the end of the string before any character is a bash syntax error, and so is an unterminated
quoted delimiter; both return $null so the caller can fail closed.

Returns @{ Word = string; NextIndex = int }, or $null when there is no readable delimiter.
#>
function Read-AgentHeredocDelimiter {
    [CmdletBinding()]
    param([string] $Command, [int] $StartIndex)

    $word = New-Object System.Text.StringBuilder
    $i = $StartIndex

    while ($i -lt $Command.Length -and ($Command[$i] -eq ' ' -or $Command[$i] -eq "`t")) { $i++ }

    while ($i -lt $Command.Length) {
        $ch = $Command[$i]

        if ([char]::IsWhiteSpace($ch)) { break }
        if ($script:AgentGuardHeredocDelimiterStops.IndexOf($ch) -ge 0) { break }

        if ($ch -eq '\' -and ($i + 1) -lt $Command.Length) {
            [void] $word.Append($Command[$i + 1])
            $i += 2
            continue
        }

        if ($ch -eq "'" -or $ch -eq '"') {
            $quote = $ch
            $i++
            while ($i -lt $Command.Length -and $Command[$i] -ne $quote) {
                [void] $word.Append($Command[$i])
                $i++
            }
            if ($i -ge $Command.Length) { return $null }
            $i++
            continue
        }

        [void] $word.Append($ch)
        $i++
    }

    if ($word.Length -eq 0) { return $null }

    return @{ Word = $word.ToString(); NextIndex = $i }
}

<#
.SYNOPSIS
Consumes queued heredoc bodies that start at $StartIndex, one per queued delimiter, in order.

.DESCRIPTION
A body ends at a line equal to its delimiter. '<<-' strips leading TAB characters from the
candidate line before the comparison. It never strips spaces, so a space-indented terminator
leaves the body open, exactly as bash leaves it. The comparison is ordinal and case-sensitive.

A trailing carriage return is removed before the comparison, so a command that arrives with CRLF
line endings closes on the same terminator line a LF command closes on.

Returns the index of the first character after the last body, or -1 when a body never closes.
#>
function Read-AgentHeredocBodyEnd {
    [CmdletBinding()]
    param([string] $Command, [int] $StartIndex, [object[]] $Pending)

    $position = $StartIndex

    foreach ($heredoc in $Pending) {
        $closed = $false

        while ($position -lt $Command.Length) {
            $lineEnd = $Command.IndexOf("`n", $position)
            if ($lineEnd -lt 0) { $lineEnd = $Command.Length }

            $line = $Command.Substring($position, $lineEnd - $position)
            if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }

            if ($lineEnd -lt $Command.Length) { $position = $lineEnd + 1 }
            else { $position = $Command.Length }

            $candidate = $line
            if ($heredoc.StripTabs) { $candidate = $candidate.TrimStart("`t") }

            if ([string]::Equals($candidate, $heredoc.Delimiter, [System.StringComparison]::Ordinal)) {
                $closed = $true
                break
            }
        }

        if (-not $closed) { return -1 }
    }

    return $position
}

<#
.SYNOPSIS
True when the character at $QuoteIndex opens a PowerShell here-string.

.DESCRIPTION
PowerShell allows nothing but the line ending after a here-string header: it reports "No
characters are allowed after a here-string header but before the end of the line." So a line
whose last non-whitespace characters are @' or @" opens a body, and anything else - such as
Write-Output a@'b' - is an ordinary argument.
#>
function Test-AgentHereStringHeader {
    [CmdletBinding()]
    param([string] $Command, [int] $QuoteIndex)

    for ($i = $QuoteIndex + 1; $i -lt $Command.Length; $i++) {
        if ($Command[$i] -eq "`n") { return $true }
        if (-not [char]::IsWhiteSpace($Command[$i])) { return $false }
    }

    # The header runs to the end of the command. PowerShell calls that an unterminated
    # here-string; the caller turns it into an ambiguous parse.
    return $true
}

<#
.SYNOPSIS
Finds the end of a PowerShell here-string body opened by the quote at $QuoteIndex.

.DESCRIPTION
The body ends at a line whose first two characters are the matching terminator, '@ or "@. A
leading space disqualifies the line: PowerShell reports "White space is not allowed before the
string terminator." Code may follow the terminator on the same line, so the returned index is
the character right after the two terminator characters, not the next line.

Returns -1 when the body never closes, which the caller turns into an ambiguous parse.
#>
function Read-AgentHereStringBodyEnd {
    [CmdletBinding()]
    param([string] $Command, [int] $QuoteIndex)

    $terminator = [string] $Command[$QuoteIndex] + '@'

    $lineEnd = $Command.IndexOf("`n", $QuoteIndex)
    if ($lineEnd -lt 0) { return -1 }

    $position = $lineEnd + 1
    while ($position -lt $Command.Length) {
        if (($position + 1) -lt $Command.Length -and
            $Command.Substring($position, 2) -ceq $terminator) {
            return $position + 2
        }

        $nextEnd = $Command.IndexOf("`n", $position)
        if ($nextEnd -lt 0) { return -1 }
        $position = $nextEnd + 1
    }

    return -1
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

Two block forms carry data rather than commands, and both are skipped. A bash heredoc opener
(<<WORD, <<-WORD) queues its delimiter; the queued bodies are consumed at the newline that ends
that line, and each body ends at a line equal to its delimiter. A PowerShell here-string opener
(@' or @" as the last characters on a line) skips to its terminator at the start of a later line.
A body produces no tokens at all, so nothing inside it can be read as a redirect, a pipeline, or
a command. Each opener still produces one token, which keeps the segment's argument count honest.
An opener whose body never closes makes the whole parse ambiguous, exactly like an unterminated
quote.

Returns { Segments = @([pscustomobject]@{ Tokens = string[]; Masks = string[]; PipedFrom = bool });
Ambiguous = bool }.
Each mask runs parallel to its token, one character per token character: 'u' where the character
was unquoted, 'q' where it came from quotes or an escape. That is what lets a later scan tell a
real redirect from a literal '>' the tokenizer already stripped the quotes from.

PipedFrom is $true when an unquoted '|' separated this segment from the one before it. The
segment boundary itself carries no other record of which separator ran, and a pipeline sink acts
on paths that never appear in its own arguments.

Ambiguous means the string ended inside an unterminated quote or escape, which makes every
segment boundary in it untrustworthy. This is intentionally not a complete shell parser.
#>
function Split-AgentCommandSegment {
    [CmdletBinding()]
    param([string] $Command)

    $segments = New-Object System.Collections.Generic.List[object]
    $tokens = New-Object System.Collections.Generic.List[string]
    $masks = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $currentMask = New-Object System.Text.StringBuilder
    $hasCurrent = $false
    $state = 'None'
    $returnState = 'None'
    # True while the segment being built follows an unquoted '|'. A pipeline sink reads its input
    # from the segment before it, so a command that names no path of its own may still act on one.
    $piped = $false
    # Heredoc openers met on the current line, in order. Their bodies are consumed at the newline
    # that ends the line, which is where bash starts reading them.
    $pendingHeredocs = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $Command.Length; $i++) {
        $ch = $Command[$i]

        if ($state -eq 'Escaped') {
            [void] $current.Append($ch)
            [void] $currentMask.Append('q')
            $hasCurrent = $true
            $state = $returnState
            continue
        }

        if ($state -eq 'SingleQuoted') {
            if ($ch -eq "'") { $state = 'None' }
            else {
                [void] $current.Append($ch); [void] $currentMask.Append('q'); $hasCurrent = $true
            }
            continue
        }

        if ($state -eq 'DoubleQuoted') {
            if ($ch -eq '\' -and ($i + 1) -lt $Command.Length -and
                $script:AgentGuardDoubleQuoteEscapables.IndexOf($Command[$i + 1]) -ge 0) {
                $returnState = 'DoubleQuoted'
                $state = 'Escaped'
            }
            elseif ($ch -eq '"') { $state = 'None' }
            else {
                [void] $current.Append($ch); [void] $currentMask.Append('q'); $hasCurrent = $true
            }
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

        # A PowerShell here-string opener. The body is data and produces no tokens; the opener
        # stays as one 'q'-masked token so the segment keeps its argument count. The guard is
        # never told which shell will run the string, so a bash line ending in @' has its body
        # skipped too. That text is already invisible today - the tokenizer swallows it into one
        # quoted token - so this only makes the behaviour the same every time.
        if ($ch -eq '@' -and ($i + 1) -lt $Command.Length -and
            ($Command[$i + 1] -eq "'" -or $Command[$i + 1] -eq '"') -and
            (Test-AgentHereStringHeader -Command $Command -QuoteIndex ($i + 1))) {
            $bodyEnd = Read-AgentHereStringBodyEnd -Command $Command -QuoteIndex ($i + 1)
            if ($bodyEnd -lt 0) {
                return [pscustomobject]@{ Segments = @(); Ambiguous = $true }
            }

            [void] $current.Append($Command.Substring($i, 2))
            [void] $currentMask.Append('qq')
            $hasCurrent = $true
            $i = $bodyEnd - 1
            continue
        }

        # A heredoc opener. The third character decides: '<<<' is a bash here-string taking one
        # word, not a heredoc. All three characters of a '<<<' are consumed here, because leaving
        # the second one to the next pass would read '<<' + '<...' as an opener after all. The
        # opener stays as one token so the segment keeps its argument count, and the delimiter is
        # masked 'q' so a delimiter such as <<'a>b' never reads as a redirect. The body itself
        # produces no tokens.
        if ($ch -eq '<' -and ($i + 1) -lt $Command.Length -and $Command[$i + 1] -eq '<' -and
            ($i + 2) -lt $Command.Length -and $Command[$i + 2] -eq '<') {
            [void] $current.Append('<<<')
            [void] $currentMask.Append('uuu')
            $hasCurrent = $true
            $i += 2
            continue
        }

        if ($ch -eq '<' -and ($i + 1) -lt $Command.Length -and $Command[$i + 1] -eq '<') {
            $stripTabs = ($i + 2) -lt $Command.Length -and $Command[$i + 2] -eq '-'
            $delimiterStart = $i + 2
            if ($stripTabs) { $delimiterStart++ }

            $delimiter = Read-AgentHeredocDelimiter -Command $Command -StartIndex $delimiterStart
            if ($null -eq $delimiter) {
                return [pscustomobject]@{ Segments = @(); Ambiguous = $true }
            }

            $opener = '<<'
            if ($stripTabs) { $opener = '<<-' }
            [void] $current.Append($opener)
            [void] $currentMask.Append('u' * $opener.Length)
            [void] $current.Append($delimiter.Word)
            [void] $currentMask.Append('q' * $delimiter.Word.Length)
            $hasCurrent = $true

            [void] $pendingHeredocs.Add([pscustomobject]@{
                    Delimiter = $delimiter.Word; StripTabs = $stripTabs
                })
            $i = $delimiter.NextIndex - 1
            continue
        }

        if ($ch -eq "`n" -or $ch -eq "`r" -or $ch -eq ';' -or $ch -eq '&' -or $ch -eq '|' -or
            $ch -eq '`' -or $ch -eq '(' -or $ch -eq ')') {
            if ($hasCurrent) {
                [void] $tokens.Add($current.ToString())
                [void] $masks.Add($currentMask.ToString())
                [void] $current.Clear(); [void] $currentMask.Clear(); $hasCurrent = $false
            }
            # Read before the flush: it says whether this separator ended a real command. A '|'
            # that ends one starts a pipeline; a '|' with nothing before it is the second half of
            # a '||', which is bash's OR and hands over no objects.
            $endedCommand = $tokens.Count -gt 0
            if ($endedCommand) {
                [void] $segments.Add([pscustomobject]@{
                        Tokens = $tokens.ToArray(); Masks = $masks.ToArray(); PipedFrom = $piped
                    })
                $tokens.Clear(); $masks.Clear()
            }
            $piped = ($ch -eq '|' -and $endedCommand)

            # bash reads a queued body from the line after the opener, so consume at '\n' only. A
            # CRLF command reaches this branch at '\r' first; consuming there would read the '\n'
            # as an empty first body line.
            if ($ch -eq "`n" -and $pendingHeredocs.Count -gt 0) {
                $bodyEnd = Read-AgentHeredocBodyEnd -Command $Command -StartIndex ($i + 1) `
                    -Pending $pendingHeredocs.ToArray()
                if ($bodyEnd -lt 0) {
                    return [pscustomobject]@{ Segments = @(); Ambiguous = $true }
                }
                $pendingHeredocs.Clear()
                $i = $bodyEnd - 1
            }
            continue
        }

        if ([char]::IsWhiteSpace($ch)) {
            if ($hasCurrent) {
                [void] $tokens.Add($current.ToString())
                [void] $masks.Add($currentMask.ToString())
                [void] $current.Clear(); [void] $currentMask.Clear(); $hasCurrent = $false
            }
            continue
        }

        [void] $current.Append($ch)
        [void] $currentMask.Append('u')
        $hasCurrent = $true
    }

    # An unterminated quote, an unterminated escape, or an opener whose body never started makes
    # every segment boundary untrustworthy.
    if ($state -ne 'None' -or $pendingHeredocs.Count -gt 0) {
        return [pscustomobject]@{ Segments = @(); Ambiguous = $true }
    }

    if ($hasCurrent) {
        [void] $tokens.Add($current.ToString())
        [void] $masks.Add($currentMask.ToString())
    }
    if ($tokens.Count -gt 0) {
        [void] $segments.Add([pscustomobject]@{
                Tokens = $tokens.ToArray(); Masks = $masks.ToArray(); PipedFrom = $piped
            })
    }

    return [pscustomobject]@{
        Segments  = $segments.ToArray()
        Ambiguous = $false
    }
}

<#
.SYNOPSIS
Strips a leading transparent-wrapper prefix (currently just rtk) so the guard classifies the
command the wrapper actually runs, not the wrapper itself.

.DESCRIPTION
rtk rewrites `git ...` into `rtk git ...`. It does not change the shell's own state. Without this
function, the guard saw `rtk` as the leading word. It never recognized the git invocation
underneath.

This matches on the leaf of the leading token. It uses the same check as the git leaf check a few
lines below. So `rtk`, `rtk.exe`, and a full path like `C:\tools\rtk.exe` all match.

The function skips every leading option token first (any token starting with `-`). Then it looks
for one pass-through subcommand: `proxy`, `run`, `err`, `summary`, or `test`. Then it repeats this
whole process. A repeated wrapper such as `rtk rtk git commit` loses both copies of `rtk`. The
function skips any `-*` token, not a fixed list of known options. This means a future rtk global
option cannot make the guard permit more than it does today.

The function never strips a wrapper ahead of a directory-change command: `cd`, `chdir`,
`set-location`, `pushd`, `push-location`, `popd`, or `pop-location`. rtk cannot move the calling
shell's own working directory. If the guard treated `rtk cd X` as a real directory change, it
would track an effective working directory the shell never actually reached. That is the only way
this function could relax a decision, instead of just reading past a wrapper.

When the function stops before a directory-change command, it returns the tokens it already
stripped, not the original list. For `rtk rtk cd X`, it returns `rtk cd X`, because the outer `rtk`
was already removed on an earlier pass. This is still safe. The returned leading token (`rtk`) is
still a wrapper name, so the caller classifies the segment as `Other`, not as a directory change.

The function does not model a wrapper option that consumes the next token as its value (for
example, a hypothetical `rtk --out foo git commit`). It inspects the token after the option for a
pass-through subcommand. If that fails, the token becomes the new leading word instead. rtk has no
such option today. This is a documented, deliberately accepted gap, not a bug.
#>
function Remove-AgentWrapperPrefix {
    [CmdletBinding()]
    param([string[]] $Tokens)

    return (Remove-AgentWrapperPrefixDetailed -Tokens $Tokens).Tokens
}

<#
.SYNOPSIS
Same as Remove-AgentWrapperPrefix, but also reports how many leading tokens were removed.

.DESCRIPTION
The mask array runs parallel to the token array, so it must be sliced by the same count. The
original function returns only the surviving tokens, which is not enough to slice the masks.
#>
function Remove-AgentWrapperPrefixDetailed {
    [CmdletBinding()]
    param([string[]] $Tokens)

    $current = @($Tokens)
    $removed = 0

    while ($current.Count -gt 0) {
        $leaf = (([string] $current[0]).ToLowerInvariant() -split '[\\/]')[-1]
        if ($script:AgentGuardTransparentWrappers -notcontains $leaf) { break }

        $index = 1
        while ($index -lt $current.Count -and ([string] $current[$index]) -like '-*') { $index++ }

        if ($index -lt $current.Count) {
            $subcommand = ([string] $current[$index]).ToLowerInvariant()
            if ($script:AgentGuardWrapperPassThroughSubcommands -contains $subcommand) { $index++ }
        }

        if ($index -ge $current.Count) {
            return [pscustomobject]@{ Tokens = @(); Removed = ($removed + $current.Count) }
        }

        $remainder = @($current[$index..($current.Count - 1)])
        $remainderName = ([string] $remainder[0]).ToLowerInvariant()
        if ($script:AgentGuardChangeDirectoryCommands -contains $remainderName -or
            $script:AgentGuardPushDirectoryCommands -contains $remainderName -or
            $script:AgentGuardPopDirectoryCommands -contains $remainderName) {
            break
        }

        $current = $remainder
        $removed += $index
    }

    return [pscustomobject]@{ Tokens = $current; Removed = $removed }
}

<#
.SYNOPSIS
Classifies each top-level segment as a git invocation, a directory change, or something else.

.DESCRIPTION
Returns { Segments = @(objects); Ambiguous = bool }. Each segment carries Kind
(Git | ChangeDirectory | Other), Tokens (leading NAME=value assignments removed), Masks (quote
provenance, one character per token character, parallel to Tokens), and - for
ChangeDirectory - Directory plus Unresolved. Unresolved marks a target the guard cannot expand
literally (`cd -`, `cd $HOME`, bare `cd`), so a following mutation is treated as untargetable
rather than silently classified against a stale directory.

PipedFrom rides through from Split-AgentCommandSegment unchanged: it is $true when an unquoted
'|' separated this segment from the one before it.
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

    foreach ($entry in $split.Segments) {
        $tokens = @($entry.Tokens)
        $entryMasks = @($entry.Masks)
        $pipedFrom = [bool] $entry.PipedFrom

        # Drop NAME=value prefixes so `AHKFLOW_ALLOW_MAIN=1 git commit` still reads as git.
        $start = 0
        while ($start -lt $tokens.Count -and $tokens[$start] -match $script:AgentGuardEnvAssignmentPattern) { $start++ }
        if ($start -ge $tokens.Count) { continue }

        $effective = @($tokens[$start..($tokens.Count - 1)])
        $effectiveMasks = @($entryMasks[$start..($entryMasks.Count - 1)])

        # Strip a transparent wrapper (rtk) after the NAME=value prefix, not before: order
        # matters so `SKIP_COVERAGE_HOOK=1 rtk git push` loses the assignment first, then rtk.
        $stripped = Remove-AgentWrapperPrefixDetailed -Tokens $effective
        $effective = @($stripped.Tokens)
        if ($effective.Count -eq 0) { continue }
        $effectiveMasks = @($effectiveMasks | Select-Object -Skip $stripped.Removed)

        $name = ([string] $effective[0]).ToLowerInvariant()
        $leaf = ($name -split '[\\/]')[-1]

        if ($leaf -eq 'git' -or $leaf -eq 'git.exe') {
            # @() around the slice: a bare `git` has no tail, and 1..0 counts backwards.
            $tail = if ($effective.Count -gt 1) { @($effective[1..($effective.Count - 1)]) } else { @() }
            $tailMasks = if ($effectiveMasks.Count -gt 1) { @($effectiveMasks[1..($effectiveMasks.Count - 1)]) } else { @() }
            [void] $classified.Add([pscustomobject]@{
                    Kind       = 'Git'
                    Tokens     = $tail
                    Masks      = $tailMasks
                    Directory  = ''
                    Unresolved = $false
                    PipedFrom  = $pipedFrom
                })
            continue
        }

        if ($script:AgentGuardPopDirectoryCommands -contains $name) {
            [void] $classified.Add([pscustomobject]@{
                    Kind       = 'PopDirectory'
                    Tokens     = $effective
                    Masks      = $effectiveMasks
                    Directory  = ''
                    Unresolved = $false
                    PipedFrom  = $pipedFrom
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
                    Masks      = $effectiveMasks
                    Directory  = $directory
                    Unresolved = $unresolved
                    PipedFrom  = $pipedFrom
                })
            continue
        }

        [void] $classified.Add([pscustomobject]@{
                Kind       = 'Other'
                Tokens     = $effective
                Masks      = $effectiveMasks
                Directory  = ''
                Unresolved = $false
                PipedFrom  = $pipedFrom
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

$script:AgentGuardAskMessage = @'
This command changes Git state in the main checkout you are working in: {0}
Approve only if you want it to run here. To run it in an isolated workspace instead, create one
with scripts/new-worktree.ps1 or the agent WorktreeCreate tool.
Read-only Git and ordinary edit/build/test commands are unaffected.
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
True when any argument carries a force flag, including a clustered short option.

.DESCRIPTION
Test-AgentGitArgsContainAny only matches a complete option token or opt=*, so it misses a
clustered short option such as -df or -fd. This inspects each argument independently for
--force, --force-*, or any short-option cluster containing a lowercase f. Case-sensitive
(-c operators): -F is a different option to git in several subcommands, matching the discipline
the safety rules already use at common.ps1:300 and :316.
#>
function Test-AgentGuardHasForceFlag {
    param([string[]] $Arguments)
    foreach ($arg in $Arguments) {
        if ($arg -ceq '--force') { return $true }
        if ($arg -clike '--force-*') { return $true }
        if ($arg -cmatch '^-[a-zA-Z]*f') { return $true }
    }
    return $false
}

<#
.SYNOPSIS
True when a cp invocation carries a flag that makes it create a link instead of a copy.

.DESCRIPTION
cp -l / --link makes a hard link and cp -s / --symbolic-link makes a symbolic one, so a cp
carrying either aims at a path the way ln does. Shaped exactly like Test-AgentGuardHasForceFlag
above, and for the same reason: short options cluster, so `cp -al src dst` carries -l inside a
token that equals neither '-l' nor '--link', and a literal list of spellings would miss it.

The cluster match is deliberately loose - any cp cluster holding 'l' or 's' sends the command
down the link branch. Every cp operand is a path, so the worst outcome is that a plain copy
reports its sources as well as its destination, which is the same over-report mv already makes.

Case-sensitive: -S is --suffix, a different option that takes a value and names no link.
#>
function Test-AgentGuardHasLinkFlag {
    param([string[]] $Arguments)
    foreach ($arg in $Arguments) {
        if ($arg -ceq '--link') { return $true }
        if ($arg -ceq '--symbolic-link') { return $true }
        if ($arg -cmatch '^-[a-zA-Z]*[ls]') { return $true }
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
True when a mutating git invocation is Tier 2: safe to run from the main checkout with no prompt,
because it cannot disturb the owner's HEAD, index, or working tree.

.DESCRIPTION
Every rule here is force-conditional except worktree prune and remote prune, which have no force
variant that changes their risk. `-D` is git's own shorthand for "-d --force" on `branch`, so it
is checked explicitly and case-sensitively alongside the generic force-cluster helper - a plain
case-insensitive match would treat -D as equal to -d and wrongly allow it.
#>
function Test-AgentGitTier2Allowed {
    [CmdletBinding()]
    param([string] $Subcommand, [string[]] $Arguments)

    $subcommand = $Subcommand.ToLowerInvariant()
    $positionals = @(Get-AgentGitPositionals -Arguments $Arguments)
    $first = if ($positionals.Count -gt 0) { ([string] $positionals[0]).ToLowerInvariant() } else { '' }

    switch ($subcommand) {
        'worktree' {
            if ($first -eq 'prune') { return $true }
            if ($first -eq 'add') {
                # -B is git's own force spelling for worktree add (resets an existing branch's tip
                # to the given commit-ish, unlike -b which refuses if the branch already exists) -
                # the same discard/move-history risk -D already covers for branch below. worktree
                # add does not accept clustered short options, so a plain case-sensitive exact match
                # is enough; -b (lowercase, the safe non-destructive form) stays Tier 2-eligible.
                if (@($Arguments | Where-Object { $_ -ceq '-B' }).Count -gt 0) { return $false }
                return -not (Test-AgentGuardHasForceFlag -Arguments $Arguments)
            }
            if ($first -eq 'remove') {
                return -not (Test-AgentGuardHasForceFlag -Arguments $Arguments)
            }
            return $false
        }
        'branch' {
            $hasForce = (Test-AgentGuardHasForceFlag -Arguments $Arguments) -or
                (@($Arguments | Where-Object { $_ -ceq '-D' }).Count -gt 0)
            $hasDelete = @($Arguments | Where-Object {
                    $_ -ceq '-d' -or $_ -ceq '--delete' -or $_ -clike '--delete=*'
                }).Count -gt 0
            $hasOtherFlag = @($Arguments | Where-Object {
                    $_ -like '-*' -and $_ -cne '-d' -and $_ -cne '--delete' -and $_ -cnotlike '--delete=*'
                }).Count -gt 0

            if ($hasDelete -and -not $hasForce -and -not $hasOtherFlag) { return $true }

            # Plain create: only the branch name (and optional start-point), no flags at all.
            $hasAnyFlag = @($Arguments | Where-Object { $_ -like '-*' }).Count -gt 0
            if (-not $hasAnyFlag -and $positionals.Count -ge 1) { return $true }

            return $false
        }
        'remote' {
            return $first -eq 'prune'
        }
        default {
            return $false
        }
    }
}

<#
.SYNOPSIS
The nearest existing ancestor of a directory, or '' when none exists.

.DESCRIPTION
A target that does not exist yet (e.g. `git init newsub`) is classified by its nearest existing
ancestor: git would walk up to that enclosing repository too.
#>
function Get-AgentGuardProbeDirectory {
    param([string] $Path)

    $probeDir = $Path
    while (-not [string]::IsNullOrWhiteSpace($probeDir) -and -not (Test-Path -LiteralPath $probeDir)) {
        $parent = Split-Path -Parent $probeDir
        if ($parent -eq $probeDir) { break }
        $probeDir = $parent
    }
    if ([string]::IsNullOrWhiteSpace($probeDir) -or -not (Test-Path -LiteralPath $probeDir)) { return '' }
    return $probeDir
}

# Working directory -> that directory's git top level. One hook process can classify several
# chained commands, so the probe is cached rather than re-spawning git per link.
$script:AgentGuardTopLevelCache = @{}

<#
.SYNOPSIS
The git top level containing a session's working directory, falling back to that directory.

.DESCRIPTION
The fallback only applies when git cannot answer - the directory is gone, or it is not in a
repository at all. Callers use the result as the session's own worktree, so it must be the
worktree ROOT and not the subdirectory the session happens to have started in.
#>
function Get-AgentSessionWorktreeRoot {
    [CmdletBinding()]
    param([string] $Cwd)

    if ($script:AgentGuardTopLevelCache.ContainsKey($Cwd)) { return $script:AgentGuardTopLevelCache[$Cwd] }

    $result = ConvertTo-AgentGuardNormalizedPath $Cwd
    $probeDir = Get-AgentGuardProbeDirectory -Path $Cwd
    if (-not [string]::IsNullOrWhiteSpace($probeDir)) {
        $topLevel = Invoke-AgentGuardGitProbe @(
            '-C', $probeDir, 'rev-parse', '--path-format=absolute', '--show-toplevel')
        if (-not [string]::IsNullOrWhiteSpace($topLevel)) {
            $result = ConvertTo-AgentGuardNormalizedPath $topLevel
        }
    }

    $script:AgentGuardTopLevelCache[$Cwd] = $result
    return $result
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

    $probeDir = Get-AgentGuardProbeDirectory -Path $Cwd
    if ([string]::IsNullOrWhiteSpace($probeDir)) {
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

# ── Write-target grammar ────────────────────────────────────────────────────────────────────
# The tokenizer yields segments, not write targets. These tables and functions turn a segment
# into the list of paths it would write, move, or delete. Over-reporting a target is safe: it
# only ever produces a denial for a path that already resolves under the main checkout.
# Under-reporting silently disables the rule, so keep every list a superset.

$script:AgentGuardWriteEveryPositional = @(
    'rm', 'unlink', 'shred', 'truncate', 'touch', 'mkdir', 'rmdir', 'tee'
)
$script:AgentGuardWriteLastPositional = @('cp', 'mv', 'install')

# Commands that CREATE a link. Both endpoints are write targets: the path the link is created
# at, and the path it points to. A write through the link lands on the second one, and the guard
# would otherwise see only the first. ln leaves the last-positional table above for this reason.
$script:AgentGuardLinkCommands = @('ln', 'mklink')

# The New-Item item types that make a link. Matched without case, because -ItemType is not
# case-sensitive.
$script:AgentGuardLinkItemTypes = @('symboliclink', 'hardlink', 'junction')

# Cmdlet name -> the parameter naming its write target. Positional fallbacks are handled below.
$script:AgentGuardWriteCmdlets = @{
    'set-content'   = @('Path', 'LiteralPath')
    'add-content'   = @('Path', 'LiteralPath')
    'clear-content' = @('Path', 'LiteralPath')
    'out-file'      = @('FilePath', 'LiteralPath', 'Path')
    'new-item'      = @('Path')
    'remove-item'   = @('Path', 'LiteralPath')
}
$script:AgentGuardWriteDestinationCmdlets = @('copy-item', 'move-item', 'rename-item')

# Commands that REMOVE their source as well as writing their destination. A move into an allowed
# path is still a delete of the path it came from, so the source is a write target too. cp,
# install and ln are deliberately absent: they leave the source where it is.
$script:AgentGuardMoveCommands = @('mv')
$script:AgentGuardMoveCmdlets = @('move-item', 'rename-item')

<#
.SYNOPSIS
True when a cmdlet parameter name is one that names a move's SOURCE.

.DESCRIPTION
Move-Item and Rename-Item take their source from -Path or -LiteralPath. PowerShell binds any
unambiguous prefix, so -pa is -Path and -li is -LiteralPath, and this accepts every prefix of
either name. A prefix short enough to be ambiguous, such as -p, is accepted too: PowerShell
would reject the command outright, and reading one extra token as a source only ever
over-reports, which is the safe direction for this grammar.
#>
function Test-AgentMoveSourceParameterName {
    param([string] $Name)

    return (Test-AgentParameterNamePrefix -Name $Name -Candidates @('path', 'literalpath'))
}

<#
.SYNOPSIS
True when a cmdlet parameter name is a prefix of any candidate name.

.DESCRIPTION
PowerShell binds any unambiguous prefix, so -Dest is -Destination and -pa is -Path. Comparing
against the full name only would miss every abbreviation. A prefix short enough to be ambiguous
is accepted as well: PowerShell would reject such a command outright, and reading one extra
token as a write target only ever over-reports, which is the safe direction for this grammar.
#>
function Test-AgentParameterNamePrefix {
    param([string] $Name, [string[]] $Candidates)

    $lower = ([string] $Name).ToLowerInvariant()
    if ($lower -eq '') { return $false }
    foreach ($candidate in @($Candidates)) {
        if (([string] $candidate).ToLowerInvariant().StartsWith($lower, [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

# Parameters of Move-Item / Rename-Item that consume the token after them. Their values are not
# files the command touches, so the operand reader must skip them rather than read them as
# sources. Switches (-Force, -Confirm, -WhatIf, -PassThru) take no value and are absent here.
$script:AgentGuardMoveValueParameters = @(
    'path', 'literalpath', 'destination', 'newname', 'filter', 'include', 'exclude', 'credential'
)

# The same list for the content-writing cmdlets in AgentGuardWriteCmdlets. Every name here
# consumes the token after it, so none of those tokens is a path the command writes. The common
# parameters are on the list because `Set-Content -ErrorAction Stop <path>` hides a path behind
# 'Stop' exactly as `-Encoding utf8` hides one behind 'utf8'.
#
# Switches are absent on purpose: -Force, -Confirm, -WhatIf, -PassThru, -Append, -NoClobber,
# -NoNewline, -Recurse, -UseTransaction, -Verbose, -Debug. Listing one would consume the path
# that follows it and lose the target. No full switch name here is a prefix of a listed name,
# so the prefix match cannot confuse the two; an abbreviation short enough to match both, such
# as -F, is ambiguous to PowerShell too and the command does not run.
$script:AgentGuardWriteCmdletValueParameters = @(
    'path', 'literalpath', 'filepath', 'value', 'itemtype', 'type', 'name', 'target',
    'encoding', 'filter', 'include', 'exclude', 'stream', 'delimiter', 'inputobject',
    'width', 'credential', 'erroraction', 'warningaction', 'informationaction',
    'errorvariable', 'warningvariable', 'informationvariable', 'outvariable', 'outbuffer',
    'pipelinevariable'
)

<#
.SYNOPSIS
An option's value, rejoined across the tokens an array value splits into.

.DESCRIPTION
PowerShell writes an array value as `-Path a.md, b.md`, which the tokenizer hands over as
'a.md,' then 'b.md'. Reading one token would take 'a.md,' and lose the rest. A trailing comma is
what says the value continues, so tokens are joined until one does not end in a comma. Returns
the joined text and the index of the last token consumed.
#>
function Get-AgentOptionValueSpan {
    param([string[]] $List, [int] $Index)

    $parts = New-Object System.Collections.Generic.List[string]
    $i = $Index
    while ($i -lt $List.Count) {
        $token = [string] $List[$i]
        [void] $parts.Add($token)
        if (-not $token.TrimEnd().EndsWith(',')) { break }
        $i++
    }
    return [pscustomobject]@{ Value = ($parts -join ''); LastIndex = [Math]::Min($i, $List.Count - 1) }
}

<#
.SYNOPSIS
The true positional operands of a cmdlet, with option values removed.

.DESCRIPTION
Get-AgentGitPositionals drops every '-*' token but keeps the token AFTER it, so the value of
`-Filter *.tmp` is left behind and read as though it were a file the command touches. This
reader consumes each value-taking option together with its value.

The two callers fail in opposite directions without it. A move over-reports a target and
refuses ordinary in-worktree moves. A content write does worse: `Set-Content -Encoding utf8
<main>\README.md hello` reads 'utf8' as operand 0, so the real path is never scanned and the
write into the main checkout is ALLOWED. So ValueParameters is per caller, and each list holds
only parameters that consume a value - a switch such as -Force takes none and must stay out.
#>
function Get-AgentCmdletOperand {
    param([string[]] $Arguments, [string[]] $ValueParameters)

    $operands = New-Object System.Collections.Generic.List[string]
    $list = @($Arguments)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $argument = [string] $list[$i]

        # The colon form carries its own value, so it consumes no following token.
        if ($argument -match '^-[A-Za-z]+:') { continue }

        if ($argument -match '^-([A-Za-z]+)$') {
            $name = [string] $Matches[1]
            if (Test-AgentParameterNamePrefix -Name $name -Candidates $ValueParameters) {
                # Consume the whole value, including the tokens an array value splits into.
                if (($i + 1) -lt $list.Count) {
                    $i = (Get-AgentOptionValueSpan -List $list -Index ($i + 1)).LastIndex
                }
                else { $i++ }
            }
            continue
        }

        [void] $operands.Add($argument)
    }
    return $operands.ToArray()
}

<#
.SYNOPSIS
Value of the first parameter whose name is a prefix of any given name, or $null.

.DESCRIPTION
Both the `-Name value` and `-Name:value` forms are read, and the name may be any prefix of a
candidate. Needed because `-Dest:<path>` names a destination that no positional fallback can
recover: the colon token is dropped as an option, so the target would simply go unreported.
#>
function Get-AgentPrefixedParameterValue {
    param([string[]] $Arguments, [string[]] $Names)

    $list = @($Arguments)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $argument = [string] $list[$i]
        if ($argument -notmatch '^-([A-Za-z]+)(:(.*))?$') { continue }

        # Capture before anything else can overwrite $Matches.
        $name = [string] $Matches[1]
        $hasColonForm = $Matches.ContainsKey(2)
        $colonValue = if ($hasColonForm) { [string] $Matches[3] } else { '' }
        if (-not (Test-AgentParameterNamePrefix -Name $name -Candidates $Names)) { continue }

        if ($hasColonForm) { return $colonValue }
        if (($i + 1) -lt $list.Count) { return [string] $list[$i + 1] }
        return $null
    }
    return $null
}

<#
.SYNOPSIS
Index of the first unquoted '>' in a token, or -1 when the token carries no redirect.
#>
function Find-AgentUnquotedRedirectIndex {
    param([string] $Token, [string] $Mask)

    for ($i = 0; $i -lt $Token.Length; $i++) {
        if ($Token[$i] -ne '>') { continue }
        if ($i -lt $Mask.Length -and $Mask[$i] -eq 'u') { return $i }
    }
    return -1
}

<#
.SYNOPSIS
Lowercased leaf of a command word, with any .exe/.cmd/.bat suffix removed.
#>
function Get-AgentCommandLeafName {
    param([string] $Word)

    $leaf = (([string] $Word).ToLowerInvariant() -split '[\\/]')[-1]
    return ($leaf -replace '\.(exe|cmd|bat|ps1)$', '')
}

<#
.SYNOPSIS
How one token spells -t / --target-directory, or $null when it spells neither.

.DESCRIPTION
Four spellings reach this reader: `-t DIR`, `--target-directory DIR`, `--target-directory=DIR`,
and the attached short form `-tDIR`. Short options cluster, so `-rt DIR` and `-vtDIR` count too.
The returned object carries TakesNextToken, which is $true when the directory is the following
token, and Value, which holds the directory when the token already carries it.

A short cluster ends at its FIRST 't': everything after that letter is the option value, exactly
as getopt reads it. `-tout` is therefore -t with the value 'out', not a bare -t cluster. Reading
the LAST 't' instead treated `-tout` as bare, swallowed the next token as the directory, and lost
the real destination.

The `t` test is case-sensitive: `-T` is --no-target-directory, a different option that names
nothing.
#>
function Read-AgentTargetDirectoryToken {
    param([string] $Argument)

    if ($Argument -ilike '--target-directory=*') {
        return [pscustomobject]@{
            TakesNextToken = $false
            Value          = $Argument.Substring('--target-directory='.Length)
        }
    }

    if ($Argument -ieq '--target-directory') {
        return [pscustomobject]@{ TakesNextToken = $true; Value = $null }
    }

    # '*?' is lazy, so the match stops at the first 't' in the cluster.
    if ($Argument -cmatch '^-([a-zA-Z]*?)t(.*)$') {
        $attached = [string] $Matches[2]
        if ($attached.Length -eq 0) {
            return [pscustomobject]@{ TakesNextToken = $true; Value = $null }
        }
        return [pscustomobject]@{ TakesNextToken = $false; Value = $attached }
    }

    return $null
}

<#
.SYNOPSIS
The directory named by -t / --target-directory, or $null when the arguments carry neither.

.DESCRIPTION
cp, mv, install, and ln all accept this option, and it changes which argument is the
destination. Read-AgentTargetDirectoryToken decides how each token spells the option.
#>
function Get-AgentTargetDirectoryOption {
    param([string[]] $Arguments)

    $list = @($Arguments)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $argument = [string] $list[$i]

        $spelling = Read-AgentTargetDirectoryToken -Argument $argument
        if ($null -eq $spelling) { continue }

        if (-not $spelling.TakesNextToken) { return $spelling.Value }
        if (($i + 1) -lt $list.Count) { return [string] $list[$i + 1] }
        return $null
    }
    return $null
}

<#
.SYNOPSIS
A move's options and its operands, with '--' honoured.

.DESCRIPTION
Get-AgentGitPositionals drops every token that starts with '-', so `mv -- -a.md dest` loses the
source entirely. A move deletes what it reads, so losing a source hides a delete. This reader
keeps everything after '--' whatever it looks like, and hands back the options separately:
Get-AgentTargetDirectoryOption does not stop at '--' either, and would read `-tracked.md` as a
clustered -t. Only -t / --target-directory consume the following token; every other option mv
accepts is a flag.
#>
function Get-AgentMoveArgumentSet {
    param([string[]] $Arguments)

    $options = New-Object System.Collections.Generic.List[string]
    $operands = New-Object System.Collections.Generic.List[string]
    $list = @($Arguments)
    $afterDoubleDash = $false

    for ($i = 0; $i -lt $list.Count; $i++) {
        $argument = [string] $list[$i]

        if ($afterDoubleDash) { [void] $operands.Add($argument); continue }
        if ($argument -ceq '--') { $afterDoubleDash = $true; continue }

        if ($argument -like '-*') {
            [void] $options.Add($argument)
            $spelling = Read-AgentTargetDirectoryToken -Argument $argument
            if ($null -ne $spelling -and $spelling.TakesNextToken) {
                if (($i + 1) -lt $list.Count) { [void] $options.Add([string] $list[$i + 1]) }
                $i++
            }
            continue
        }

        [void] $operands.Add($argument)
    }

    return [pscustomobject]@{ Options = $options.ToArray(); Operands = $operands.ToArray() }
}

<#
.SYNOPSIS
Which kind of link a command creates: 'Symbolic', 'Hard', or 'Unknown'.

.DESCRIPTION
The kind decides how the operating system anchors a RELATIVE target, so
Add-AgentLinkTargetCandidate below cannot pick its anchors without it. Every command form the
guard treats as a link command carries the kind in its own arguments:

  ln       -s, --symbolic, or a cluster holding 's'; a hard link otherwise
  cp       -s / --symbolic-link, or -l / --link
  mklink   /h hard, /j junction, /d or nothing symbolic

'Unknown' is the fail-closed answer, and three things produce it: a junction, whose anchor this
guard has not proved; two kind flags in one command; and any other leaf. Add-AgentLinkTargetCandidate
keeps every anchor for 'Unknown', which is what the guard did for every kind before it could read
one.

The short-option matches are case-sensitive, for the reason Test-AgentGuardHasLinkFlag is: -S is
--suffix and -L is --dereference, and neither names a link. The walk stops at '--' and steps over
the value of -t, so an operand named '-s.md' is not read as an option.
#>
function Get-AgentLinkKind {
    param([string] $Leaf, [string[]] $Arguments)

    $list = @($Arguments)

    if ($Leaf -eq 'mklink') {
        # Matched without case: cmd accepts /H and /h alike, and a Git Bash caller writes /D.
        $hard = @($list | Where-Object { $_ -ieq '/h' }).Count -gt 0
        $junction = @($list | Where-Object { $_ -ieq '/j' }).Count -gt 0
        $directory = @($list | Where-Object { $_ -ieq '/d' }).Count -gt 0

        if ($junction) { return 'Unknown' }
        if ($hard -and $directory) { return 'Unknown' }
        if ($hard) { return 'Hard' }
        return 'Symbolic'
    }

    if ($Leaf -ne 'ln' -and $Leaf -ne 'cp') { return 'Unknown' }

    $symbolic = $false
    $hard = $false
    $afterDoubleDash = $false

    for ($i = 0; $i -lt $list.Count; $i++) {
        $argument = [string] $list[$i]

        if ($afterDoubleDash) { continue }
        if ($argument -ceq '--') { $afterDoubleDash = $true; continue }
        if ($argument -notlike '-*') { continue }

        # -t takes the next token as its value, so that token is not an option of its own.
        $spelling = Read-AgentTargetDirectoryToken -Argument $argument
        if ($null -ne $spelling -and $spelling.TakesNextToken) { $i++ }

        if ($argument -ceq '--symbolic' -or $argument -ceq '--symbolic-link') { $symbolic = $true; continue }
        if ($argument -ceq '--link') { $hard = $true; continue }

        # Any other long option is a name, not a cluster: --suffix must not read as -s.
        if ($argument -clike '--*') { continue }

        if ($argument -cmatch '^-[a-zA-Z]*s') { $symbolic = $true }
        if ($Leaf -eq 'cp' -and $argument -cmatch '^-[a-zA-Z]*l') { $hard = $true }
    }

    if ($symbolic -and $hard) { return 'Unknown' }
    if ($symbolic) { return 'Symbolic' }
    if ($hard) { return 'Hard' }

    # ln without -s makes a hard link. cp only reaches this reader with a link flag, so no flag
    # here means the flag was spelled in a way this walk did not read: fail closed.
    if ($Leaf -eq 'ln') { return 'Hard' }
    return 'Unknown'
}

<#
.SYNOPSIS
Adds every path a link target could mean to a write-target list.

.DESCRIPTION
A RELATIVE link target names different files for different link kinds, and the resolver this
guard uses anchors every relative write target to the working directory. So the anchor has to be
chosen here, from the kind Get-AgentLinkKind read:

  Symbolic   Windows resolves the target against the directory holding the link, so the target
             is joined to the link path and to the link path's parent. One of the two is right,
             and which one depends on whether the link path names a directory or the link file
             itself, which the guard cannot know. Without these anchors
             `ln -s ../../../../../README.md deep/dir/x` walks ABOVE the checkout from the
             working directory and INTO it from the link's own directory, and would be allowed.
  Hard       A hard link names an existing file when it is created, so the target resolves
             against the working directory. That is what the as-written anchor is:
             `ln ../README.md deep/bait.md` names <main>\.claude\worktrees\README.md, and only
             this anchor reaches it.
  Unknown    Every anchor, which is what the guard emitted for every kind before it read the
             kind. It over-reports paths, which is the safe direction for this grammar.

Two cases stay fail-closed whatever the kind. An absolute target means the same file from every
directory, so it is added once. A blank link path leaves nothing to join to, so the as-written
anchor is added rather than nothing - emitting nothing would drop the target from the scan
entirely, and an under-report silently disables the rule.
#>
function Add-AgentLinkTargetCandidate {
    param(
        [string] $LinkPath,
        [string] $Target,
        [ValidateSet('Symbolic', 'Hard', 'Unknown')]
        [string] $Kind = 'Unknown',
        [System.Collections.Generic.List[string]] $Sink
    )

    $target = [string] $Target
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    # Tested with a pattern rather than [System.IO.Path]::IsPathRooted, which throws on Windows
    # PowerShell 5.1 for characters that host rejects outright. A throw here would escape into the
    # entrypoint's catch, and that catch ALLOWS the write.
    $isAbsolute = $target -match '^([A-Za-z]:|[\\/])'

    $link = [string] $LinkPath

    # Nothing to anchor to, or nothing to anchor: one candidate, whatever the kind.
    if ($isAbsolute -or [string]::IsNullOrWhiteSpace($link)) {
        [void] $Sink.Add($target)
        return
    }

    if ($Kind -ne 'Symbolic') { [void] $Sink.Add($target) }
    if ($Kind -eq 'Hard') { return }

    # The link path names a directory the link is created inside.
    [void] $Sink.Add((Join-Path $link $target))

    # The link path names the link file itself, so its parent holds the link.
    $parent = Split-Path -Parent $link
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void] $Sink.Add((Join-Path $parent $target))
    }
}

<#
.SYNOPSIS
Every path a link-creation command would write or aim at.

.DESCRIPTION
ln has three forms - `ln TARGET LINK_NAME`, `ln TARGET... DIRECTORY`, and
`ln -t DIRECTORY TARGET...` - and every operand of all three is a path. So every operand is
reported, and each link target is expanded through Add-AgentLinkTargetCandidate.

Get-AgentMoveArgumentSet does the option/operand split. Its name says move; its behaviour is the
general split these commands share, including honouring '--' and consuming the -t value.
#>
function Get-AgentLinkWriteTarget {
    param([string] $Leaf, [string[]] $Arguments)

    $found = New-Object System.Collections.Generic.List[string]
    $kind = Get-AgentLinkKind -Leaf $Leaf -Arguments $Arguments

    if ($Leaf -eq 'mklink') {
        # mklink [[/d] | [/h] | [/j]] <link> <target>. All three options are switches: none of
        # them consumes the token that follows, so the reader drops the option and reads on. The
        # '-*' test stays because Get-AgentGitPositionals cannot be reused here - it keeps
        # '/'-prefixed tokens, and they would be read as the link and the target.
        $linkOperands = @($Arguments | Where-Object { $_ -notlike '-*' -and $_ -notlike '/*' })
        if ($linkOperands.Count -ge 1) { [void] $found.Add([string] $linkOperands[0]) }
        if ($linkOperands.Count -ge 2) {
            Add-AgentLinkTargetCandidate -LinkPath ([string] $linkOperands[0]) `
                -Target ([string] $linkOperands[1]) -Kind $kind -Sink $found
        }
        return $found.ToArray()
    }

    $set = Get-AgentMoveArgumentSet -Arguments $Arguments
    $operands = @($set.Operands)
    $targetDirectory = Get-AgentTargetDirectoryOption -Arguments $set.Options

    # With -t the named directory holds every link, so no operand is the link path.
    if ($null -ne $targetDirectory) {
        [void] $found.Add($targetDirectory)
        foreach ($operand in $operands) {
            Add-AgentLinkTargetCandidate -LinkPath $targetDirectory -Target ([string] $operand) `
                -Kind $kind -Sink $found
        }
        return $found.ToArray()
    }

    if ($operands.Count -eq 0) { return $found.ToArray() }

    # One operand names a link in the working directory. There is no target to expand.
    if ($operands.Count -eq 1) {
        [void] $found.Add([string] $operands[0])
        return $found.ToArray()
    }

    $linkPath = [string] $operands[$operands.Count - 1]
    [void] $found.Add($linkPath)
    foreach ($operand in ($operands | Select-Object -SkipLast 1)) {
        Add-AgentLinkTargetCandidate -LinkPath $linkPath -Target ([string] $operand) `
            -Kind $kind -Sink $found
    }
    return $found.ToArray()
}

<#
.SYNOPSIS
The path a New-Item link points at, or nothing when the command creates no link.

.DESCRIPTION
Target is an ALIAS for the Value parameter, and Type an alias for ItemType. So -Target and
-Value are one parameter with two spellings, and the value is a path only when the item type
says a link is being created. On a File the same value is content:
`New-Item -ItemType File -Path notes.md -Value 'cost is $5'` would otherwise be read as a path,
meet AgentGuardUnexpandablePattern, and be refused as an unresolved write target.

Three things decide the gate. A named link kind reads the value. A named non-link kind does not.
An ItemType the guard cannot expand - a variable - could still be a link, so it reads the value
and fails closed. No -ItemType at all creates a file, so it reads nothing.

The item type also names the anchor for a relative target. New-Item stores a SymbolicLink target
as written - `-Target .\Notice.txt` reads back as `.\Notice.txt` - so Windows resolves it against
the directory holding the link. A HardLink names an existing file, so its value resolves against
the working directory. A Junction, and an item type the guard cannot expand, both fall to
'Unknown', which keeps every anchor.
#>
function Get-AgentNewItemLinkTarget {
    param([string[]] $Arguments, [string] $LinkPath)

    $found = New-Object System.Collections.Generic.List[string]

    $itemType = Get-AgentPrefixedParameterValue -Arguments $Arguments -Names @('ItemType', 'Type')
    if ($null -eq $itemType) { return $found.ToArray() }

    # The tokenizer strips quotes, so this trim only ever matters for a spelling it kept.
    $kind = ([string] $itemType).Trim().Trim("'", '"').ToLowerInvariant()
    $canExpand = $kind -notmatch $script:AgentGuardUnexpandablePattern
    if ($canExpand -and ($script:AgentGuardLinkItemTypes -notcontains $kind)) {
        return $found.ToArray()
    }

    $linkTarget = Get-AgentPrefixedParameterValue -Arguments $Arguments -Names @('Target', 'Value')
    if ($null -eq $linkTarget) { return $found.ToArray() }

    $linkKind = switch ($kind) {
        'symboliclink' { 'Symbolic' }
        'hardlink' { 'Hard' }
        default { 'Unknown' }
    }

    Add-AgentLinkTargetCandidate -LinkPath $LinkPath -Target $linkTarget -Kind $linkKind -Sink $found
    return $found.ToArray()
}

<#
.SYNOPSIS
Every path one command segment would write, move, or delete.

.DESCRIPTION
Two independent sources are scanned. Redirects are read from the token/mask pair, so only an
unquoted '>' counts. Destination arguments are read from the leading command word using the
tables above. A segment can produce both, for example `cp a b > log.txt`.
#>
function Get-AgentSegmentWriteTarget {
    [CmdletBinding()]
    param([string[]] $Tokens, [string[]] $Masks)

    $targets = New-Object System.Collections.Generic.List[string]
    $tokens = @($Tokens)
    $masks = @($Masks)
    if ($tokens.Count -eq 0) { return @() }

    # --- Redirects -------------------------------------------------------------------------
    $consumedByRedirect = @{}
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string] $tokens[$i]
        $mask = if ($i -lt $masks.Count) { [string] $masks[$i] } else { '' }

        $gt = Find-AgentUnquotedRedirectIndex -Token $token -Mask $mask
        if ($gt -lt 0) { continue }

        $end = $gt
        while ($end -lt $token.Length -and $token[$end] -eq '>') { $end++ }
        $rest = $token.Substring($end)

        if (-not [string]::IsNullOrWhiteSpace($rest)) {
            [void] $targets.Add($rest)
        }
        elseif (($i + 1) -lt $tokens.Count) {
            [void] $targets.Add([string] $tokens[$i + 1])
            $consumedByRedirect[$i + 1] = $true
        }
    }

    # --- Destination arguments -------------------------------------------------------------
    $leaf = Get-AgentCommandLeafName -Word $tokens[0]

    # A token consumed as a redirect target is not also a positional argument of the command.
    $arguments = @()
    for ($i = 1; $i -lt $tokens.Count; $i++) {
        if ($consumedByRedirect.ContainsKey($i)) { continue }
        $token = [string] $tokens[$i]
        $mask = if ($i -lt $masks.Count) { [string] $masks[$i] } else { '' }
        if ((Find-AgentUnquotedRedirectIndex -Token $token -Mask $mask) -ge 0) { continue }
        $arguments += $token
    }
    $positionals = @(Get-AgentGitPositionals -Arguments $arguments)

    # First in the chain on purpose. cp is in the last-positional table below, so a link branch
    # placed after that one would never run for a linking cp: the elseif would win every time and
    # the rule would be dead rather than wrong.
    if (($script:AgentGuardLinkCommands -contains $leaf) -or
        ($leaf -eq 'cp' -and (Test-AgentGuardHasLinkFlag -Arguments $arguments))) {
        foreach ($target in (Get-AgentLinkWriteTarget -Leaf $leaf -Arguments $arguments)) {
            [void] $targets.Add($target)
        }
    }
    elseif ($script:AgentGuardWriteEveryPositional -contains $leaf) {
        foreach ($positional in $positionals) { [void] $targets.Add($positional) }
    }
    elseif ($script:AgentGuardWriteLastPositional -contains $leaf) {
        # A move reads its own operands, because a moved file may be named '-something' and only
        # a '--'-aware reader keeps it. cp and install do not delete, so they keep the older
        # positional reader.
        $isMove = $script:AgentGuardMoveCommands -contains $leaf
        $moveSet = if ($isMove) { Get-AgentMoveArgumentSet -Arguments $arguments } else { $null }
        $optionArguments = if ($isMove) { $moveSet.Options } else { $arguments }
        $operands = if ($isMove) { @($moveSet.Operands) } else { $positionals }

        # -t/--target-directory moves the destination off the last operand: with it, every
        # operand is a SOURCE and the named directory is the only thing written.
        $targetDirectory = Get-AgentTargetDirectoryOption -Arguments $optionArguments
        if ($null -ne $targetDirectory) { [void] $targets.Add($targetDirectory) }
        elseif ($operands.Count -ge 1) { [void] $targets.Add($operands[$operands.Count - 1]) }

        # A move also removes every source it names. With -t every operand is a source; without
        # it the last operand is the destination, so drop it.
        if ($isMove) {
            $sources = if ($null -ne $targetDirectory) { @($operands) }
            else { @($operands | Select-Object -SkipLast 1) }
            foreach ($source in $sources) { [void] $targets.Add($source) }
        }
    }
    elseif ($leaf -eq 'sed') {
        $inPlace = @($arguments | Where-Object { $_ -ceq '-i' -or $_ -clike '-i*' -or $_ -ceq '--in-place' }).Count -gt 0
        if ($inPlace) {
            # With -e or -f the script is an option value, so every positional is a file.
            # Without them the first positional IS the script, so skip it.
            $hasScriptOption = @($arguments | Where-Object { $_ -ceq '-e' -or $_ -ceq '-f' }).Count -gt 0
            $files = if ($hasScriptOption) { $positionals } else { @($positionals | Select-Object -Skip 1) }
            foreach ($file in $files) { [void] $targets.Add($file) }
        }
    }
    elseif ($leaf -eq 'dd') {
        foreach ($argument in $arguments) {
            if ($argument -ilike 'of=*') { [void] $targets.Add($argument.Substring(3)) }
        }
    }
    elseif ($script:AgentGuardWriteCmdlets.ContainsKey($leaf)) {
        # Operands with option values removed. Reading $positionals here was a hole rather than a
        # wart: `Set-Content -Encoding utf8 <main>\README.md hello` left 'utf8' in operand 0, so
        # the guard reported a relative path inside the worktree, never scanned the real target,
        # and ALLOWED a write into the main checkout.
        $cmdletOperands = @(Get-AgentCmdletOperand -Arguments $arguments `
                -ValueParameters $script:AgentGuardWriteCmdletValueParameters)

        # Prefix-aware: `Set-Content -Pa:<path>` names the same target as `-Path <path>`, and the
        # colon token is dropped as an option, so no positional fallback could recover it.
        $named = Get-AgentPrefixedParameterValue -Arguments $arguments -Names $script:AgentGuardWriteCmdlets[$leaf]
        $linkPath = ''
        if ($null -ne $named) {
            [void] $targets.Add($named)
            $linkPath = [string] $named
        }
        elseif ($cmdletOperands.Count -ge 1) {
            [void] $targets.Add($cmdletOperands[0])
            $linkPath = [string] $cmdletOperands[0]
        }

        if ($leaf -eq 'new-item') {
            # -Name reads through its own call: Get-AgentPrefixedParameterValue returns the FIRST
            # match and stops, so one call naming both Path and Name would drop whichever came
            # second. The -Path value stays the anchor for a relative link target, because in this
            # parameter set it is the directory holding the link.
            $itemName = Get-AgentPrefixedParameterValue -Arguments $arguments -Names @('Name')
            if ($null -ne $itemName -and $linkPath -ne '') {
                [void] $targets.Add((Join-Path $linkPath $itemName))
            }
            elseif ($null -ne $itemName) {
                [void] $targets.Add($itemName)
            }

            foreach ($target in (Get-AgentNewItemLinkTarget -Arguments $arguments -LinkPath $linkPath)) {
                [void] $targets.Add($target)
            }
        }
    }
    elseif ($script:AgentGuardWriteDestinationCmdlets -contains $leaf) {
        # Operands with option values removed, so `-Filter *.tmp` does not look like a file.
        $cmdletOperands = @(Get-AgentCmdletOperand -Arguments $arguments `
                -ValueParameters $script:AgentGuardMoveValueParameters)

        $named = Get-AgentPrefixedParameterValue -Arguments $arguments -Names @('Destination', 'NewName')
        if ($null -ne $named) { [void] $targets.Add($named) }
        elseif ($cmdletOperands.Count -ge 2) { [void] $targets.Add($cmdletOperands[1]) }

        # Move-Item and Rename-Item remove the paths they read. Copy-Item does not, so it is not
        # in the move table. -Path takes an array, so read every operand rather than one token,
        # and split on the comma PowerShell leaves attached to each element.
        if ($script:AgentGuardMoveCmdlets -contains $leaf) {
            foreach ($operand in $cmdletOperands) {
                foreach ($piece in ($operand -split ',')) {
                    $source = $piece.Trim()
                    if ($source -ne '' -and -not $targets.Contains($source)) { [void] $targets.Add($source) }
                }
            }

            # Read the parameters that actually name a source: -Path and -LiteralPath. The
            # positional loop above cannot see them in either of two shapes. PowerShell's
            # attached-colon form (-Path:value, and abbreviations such as -pa:value) packs the
            # value into one dash-prefixed token, and a source whose own name starts with a dash
            # (-Path -tracked.md) puts a dash-prefixed token in the value slot. Get-AgentGitPositionals
            # drops every '-*' token, so both vanish.
            #
            # Selecting on the parameter NAME is what makes this correct. An earlier version
            # harvested every colon-attached token and then filtered by VALUE, skipping $true and
            # $false to avoid switch parameters. That was wrong in both directions: it dropped a
            # real source named by -Path:$false, and it harvested -Force:$myVar, which the
            # resolver cannot expand, so an ordinary in-worktree move was refused.
            for ($i = 0; $i -lt $arguments.Count; $i++) {
                $argument = [string] $arguments[$i]
                if ($argument -notmatch '^-([A-Za-z]+)(:(.*))?$') { continue }

                # Capture before anything else can overwrite $Matches.
                $parameterName = [string] $Matches[1]
                $hasColonForm = $Matches.ContainsKey(2)
                $colonValue = if ($hasColonForm) { [string] $Matches[3] } else { '' }
                if (-not (Test-AgentMoveSourceParameterName -Name $parameterName)) { continue }

                # `-Path value` puts the value in the next token; `-Path:value` carries its own.
                # An array value spans several tokens, so take the whole span, not one token.
                $value = if ($hasColonForm) { $colonValue }
                elseif (($i + 1) -lt $arguments.Count) {
                    (Get-AgentOptionValueSpan -List $arguments -Index ($i + 1)).Value
                }
                else { '' }

                foreach ($piece in ($value -split ',')) {
                    $source = $piece.Trim()
                    if ($source -ne '' -and -not $targets.Contains($source)) { [void] $targets.Add($source) }
                }
            }
        }
    }

    return $targets.ToArray()
}

# Cmdlets that DELETE whatever the pipeline hands them, and that bind that input to their own
# source parameter, split by how many operands prove the source is written out. Copy-Item and
# Set-Content are absent from both: they consume pipeline input too, but they leave every path
# they receive where it is.
#
# Every built-in alias is listed. PowerShell resolves `Get-Item x | ri` to Remove-Item and
# deletes x, so reading the full cmdlet names alone left every aliased spelling allowed. That
# includes `rm` and `mv`: both are Remove-Item and Move-Item in PowerShell, whatever they mean
# in bash. Denying a bash `... | rm` costs nothing, because coreutils rm reads no path from
# standard input, so that pipeline deletes nothing either way.
$script:AgentGuardPipelineRemoveSinks = @(
    'remove-item', 'ri', 'rd', 'rmdir', 'del', 'erase', 'rm'
)
$script:AgentGuardPipelineMoveSinks = @(
    'move-item', 'mi', 'move', 'mv', 'rename-item', 'rni', 'ren'
)
$script:AgentGuardPipelineSinkCmdlets =
$script:AgentGuardPipelineRemoveSinks + $script:AgentGuardPipelineMoveSinks

<#
.SYNOPSIS
True when a pipeline sink deletes paths that its own arguments never name.

.DESCRIPTION
Move-Item, Rename-Item and Remove-Item take their source from the pipeline when no -Path or
-LiteralPath reaches them. The guard classifies one segment at a time and never runs the
upstream command, so it cannot know which paths arrive that way. Reporting no source at all let
`Get-Item <main>\README.md | Move-Item -Destination <worktree>\README.md` through, and that
command deletes a tracked file in the main checkout.

A named -Path or -LiteralPath, in any spelling PowerShell binds, proves the source is written
out. Positional operands prove it too, but the count differs by cmdlet. Remove-Item takes one
positional source. Move-Item and Rename-Item take the source first and the destination second,
so a single operand is ambiguous under a pipe: PowerShell binds it to -Path, which then leaves
the piped input with nowhere to go. Two operands are needed before the source is provably
written out.

The leaf is matched against every built-in alias too, because PowerShell resolves one to the same
cmdlet: `Get-Item <main>\README.md | ri` deletes the file exactly as `| Remove-Item` does.
#>
function Test-AgentPipelineBoundSource {
    param([string[]] $Tokens)

    $tokens = @($Tokens)
    if ($tokens.Count -eq 0) { return $false }

    $leaf = Get-AgentCommandLeafName -Word $tokens[0]
    if ($script:AgentGuardPipelineSinkCmdlets -notcontains $leaf) { return $false }

    # Assigned in two statements, not from an `if` expression: an `if` whose branch is `@()`
    # produces an empty pipeline, and PowerShell assigns $null from that. A bare `Remove-Item`
    # then handed one $null element to the operand reader, which counted it as a written-out
    # source and let the piped delete through.
    $arguments = @()
    if ($tokens.Count -gt 1) { $arguments = @($tokens[1..($tokens.Count - 1)]) }

    foreach ($argument in $arguments) {
        if ([string] $argument -notmatch '^-([A-Za-z]+)(:.*)?$') { continue }
        if (Test-AgentMoveSourceParameterName -Name ([string] $Matches[1])) { return $false }
    }

    # Option values are consumed with their option, so `-Destination x` leaves no false operand.
    $operands = @(Get-AgentCmdletOperand -Arguments $arguments `
            -ValueParameters $script:AgentGuardMoveValueParameters)
    $needed = if ($script:AgentGuardPipelineRemoveSinks -contains $leaf) { 1 } else { 2 }
    return ($operands.Count -lt $needed)
}

# Interpreters whose quoted argument is itself a command line. `-File` and `/k`-style script
# paths are deliberately absent: those point at a file, and the guard never reads files.
$script:AgentGuardInterpreterSpecs = @(
    @{ Leaf = 'sh'; Flags = @('-c') },
    @{ Leaf = 'bash'; Flags = @('-c') },
    @{ Leaf = 'zsh'; Flags = @('-c') },
    @{ Leaf = 'pwsh'; Flags = @('-command', '-c') },
    @{ Leaf = 'powershell'; Flags = @('-command', '-c') },
    # '//c' and '//k' are how Git Bash writes these: MSYS rewrites a leading '//' to '/' on the
    # way to cmd, and this guard reads the command text before that rewrite happens.
    @{ Leaf = 'cmd'; Flags = @('/c', '/k', '//c', '//k') }
)

$script:AgentGuardMaxInterpreterDepth = 2

<#
.SYNOPSIS
Write targets carried by the inner command of an interpreter invocation.

.DESCRIPTION
Two shapes reach an interpreter, and each needs its own reader.

Quoted - `cmd /c "mklink /D a b"` - hands the whole inner command over as ONE token, so it is
re-tokenized through Get-AgentCommandWriteTarget.

Unquoted - `cmd /c mklink /D a b` - leaves the inner command as the rest of THIS segment, already
split into tokens. Reading only the token after the flag would see 'mklink' and lose every
operand. Re-joining the tokens into a string would break any path holding a space. So the slice
travels whole, with the masks that say which characters were quoted: Get-AgentSegmentWriteTarget
reads them to tell an unquoted '>' from a quoted one, and a regenerated mask would call quoted
text unquoted.

The two do not double-count. A quoted inner command leaves nothing after the flag, so the
remainder slice is empty; an unquoted one leaves a first token whose leaf matches no table.

This lives in one function because the policy core needs the same logic, and two copies of a
security rule drift silently.
#>
function Get-AgentInterpreterInnerTarget {
    [CmdletBinding()]
    param([string[]] $Tokens, [string[]] $Masks, [int] $Depth)

    $found = New-Object System.Collections.Generic.List[string]
    $unresolved = $false
    $tokens = @($Tokens)
    $masks = @($Masks)

    if ($tokens.Count -lt 3) {
        return [pscustomobject]@{ Targets = $found.ToArray(); Unresolved = $false }
    }

    $leaf = Get-AgentCommandLeafName -Word $tokens[0]
    $spec = $script:AgentGuardInterpreterSpecs | Where-Object { $_.Leaf -eq $leaf } | Select-Object -First 1
    if ($null -eq $spec) {
        return [pscustomobject]@{ Targets = $found.ToArray(); Unresolved = $false }
    }

    for ($i = 1; $i -lt $tokens.Count - 1; $i++) {
        if ($spec.Flags -notcontains ([string] $tokens[$i]).ToLowerInvariant()) { continue }

        # The depth test lives here, not at the top: a segment that is not an interpreter carrying
        # an inner command was already scanned in full by the caller, so it must not be reported
        # as unresolved just because the recursion budget ran out.
        if ($Depth -ge $script:AgentGuardMaxInterpreterDepth) {
            $unresolved = $true
            break
        }

        $inner = Get-AgentCommandWriteTarget -Command ([string] $tokens[$i + 1]) -Depth ($Depth + 1)
        foreach ($target in $inner.Targets) { [void] $found.Add($target) }
        if ($inner.Unresolved) { $unresolved = $true }

        $last = $tokens.Count - 1
        if (($i + 1) -lt $last) {
            $restTokens = @($tokens[($i + 1)..$last])
            $maskEnd = [Math]::Min($last, $masks.Count - 1)
            $restMasks = if (($i + 1) -le $maskEnd) { @($masks[($i + 1)..$maskEnd]) } else { @() }
            foreach ($target in (Get-AgentSegmentWriteTarget -Tokens $restTokens -Masks $restMasks)) {
                [void] $found.Add($target)
            }
        }
        break
    }

    return [pscustomobject]@{ Targets = $found.ToArray(); Unresolved = $unresolved }
}

<#
.SYNOPSIS
Every write target in a command string, following nested interpreter arguments.

.DESCRIPTION
Returns { Targets = @(string[]); Unresolved = bool }. Unresolved means some inner command was
never scanned, so the target list is incomplete and the caller must fail closed rather than read
an empty list as "writes nothing". Two things set it: an inner command the tokenizer could not
split safely, and nesting deeper than AgentGuardMaxInterpreterDepth.

Recursion is scoped to the write-target scan alone. Git classification still treats a quoted
nested command as opaque, which stays a documented accepted limitation of this guard.
#>
function Get-AgentCommandWriteTarget {
    [CmdletBinding()]
    param([string] $Command, [int] $Depth = 0)

    $targets = New-Object System.Collections.Generic.List[string]

    $parsed = Get-AgentCommandSegment -Command $Command
    if ($parsed.Ambiguous) {
        return [pscustomobject]@{ Targets = $targets.ToArray(); Unresolved = $true }
    }

    $unresolved = $false

    foreach ($segment in $parsed.Segments) {
        foreach ($target in (Get-AgentSegmentWriteTarget -Tokens $segment.Tokens -Masks $segment.Masks)) {
            [void] $targets.Add($target)
        }

        # A sink that deletes what the pipeline hands it names a path this scan cannot see, so the
        # target list is incomplete in exactly the way Unresolved reports.
        if ($segment.PipedFrom -and (Test-AgentPipelineBoundSource -Tokens $segment.Tokens)) {
            $unresolved = $true
        }

        $inner = Get-AgentInterpreterInnerTarget -Tokens $segment.Tokens -Masks $segment.Masks -Depth $Depth
        foreach ($target in $inner.Targets) { [void] $targets.Add($target) }
        if ($inner.Unresolved) { $unresolved = $true }
    }

    return [pscustomobject]@{ Targets = $targets.ToArray(); Unresolved = $unresolved }
}

# Characters that make a path component impossible to expand from the command text alone.
$script:AgentGuardUnexpandablePattern = '[\$%`]'

# The exact shape Split-AgentCommandSegment leaves behind for a skipped heredoc or here-string
# opener: a here-string opener is exactly @' or @"; a heredoc opener is << or <<- immediately
# followed by its delimiter word, with nothing else in the token. A write target that is nothing
# but one of these names no real path - the body the opener introduces is what names one, and the
# tokenizer already skipped that body without producing any tokens for it.
#
# The heredoc branch accepts any text after << or <<-, including whitespace, because a quoted
# delimiter can contain a space (<<'E F'), and the opener token then carries that space too. This
# stays safe: '<' is not a legal character in a Windows file name, so no real path this check has
# to classify can start with << or <<-.
$script:AgentGuardOpenerTokenPattern = '^(@[''"]|<<-?.+)$'

<#
.SYNOPSIS
Replaces every reparse point in a path with its target, walking from the root down.

.DESCRIPTION
Windows PowerShell 5.1 has no ResolveLinkTarget, so this uses (Get-Item -Force).Target, which
both supported hosts provide. 5.1 types that property as string[] and pwsh 7 as string, so the
array form is normalized. The iteration cap stops a symlink cycle from hanging the hook.

A relative target is anchored to the directory holding the link, which is how Windows resolves
one. Anchoring it to the process working directory instead classified the wrong file, and a
worktree link pointing at `..\..\..\README.md` then looked like a path outside the checkout.
#>
function Resolve-AgentSymlinkPath {
    [CmdletBinding()]
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $result = $Path
    for ($pass = 0; $pass -lt 16; $pass++) {
        $changed = $false

        $parts = $result -split '[\\/]'
        if ($parts.Count -eq 0) { break }

        $accumulated = $parts[0]
        for ($i = 1; $i -lt $parts.Count; $i++) {
            if ([string]::IsNullOrEmpty($parts[$i])) { continue }
            $accumulated = Join-Path $accumulated $parts[$i]

            if (-not (Test-Path -LiteralPath $accumulated)) { continue }

            $item = Get-Item -LiteralPath $accumulated -Force -ErrorAction SilentlyContinue
            if ($null -eq $item) { continue }
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { continue }

            $target = $item.Target
            if ($target -is [array]) { $target = $target[0] }
            if ([string]::IsNullOrWhiteSpace($target)) { continue }

            # A link that IS the last component has no remainder. Taking the slice anyway asks
            # for index $parts.Count, which strict mode rejects outright and which otherwise
            # produces a DESCENDING range that hands back the leaf a second time.
            $remainder = @()
            if ($i + 1 -le $parts.Count - 1) {
                $remainder = @($parts[($i + 1)..($parts.Count - 1)]) | Where-Object { $_ }
            }

            # A symlink target may be relative. Windows resolves it against the directory holding
            # the link, never against the process working directory. Anchoring it here is what
            # keeps `..\..\..\README.md` inside a worktree from classifying as outside the
            # protected checkout. The repository tracks such a link at .github\AGENTS.md.
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $linkParent = Split-Path -Parent $accumulated
                if (-not [string]::IsNullOrWhiteSpace($linkParent)) {
                    $target = Join-Path $linkParent $target
                }
            }

            $result = $target
            foreach ($piece in $remainder) { $result = Join-Path $result $piece }
            # Collapse the '..' segments the substitution just introduced, so the next pass walks
            # a real path. GetFullPath is lexical; it does not touch the filesystem.
            try { $result = [System.IO.Path]::GetFullPath($result) } catch { }
            $changed = $true
            break
        }

        if (-not $changed) { break }
    }

    return $result
}

<#
.SYNOPSIS
Turns one raw write target into an absolute path, or marks it unresolved.

.DESCRIPTION
A glob is classified on the literal prefix before it: a glob cannot match `..` or an absolute
path, so it cannot change which repository the path falls in, and `./obj/*` classifies on
`./obj`. A variable, a percent expansion, or a command substitution can expand to anything,
including `../..` or a rooted path, so ONE anywhere in the target makes the whole target
unresolved. A leading literal prefix proves nothing about it: `./scripts/$DEST` reaches main
when DEST is `../../../../README.md`.

Mirrors the precedent at Get-AgentCommandSegment, where a cd target matching [\$%] marks the
following git mutation untargetable rather than guessing where it lands.

Pass -Literal for a path that came from a tool call rather than a command line. That skips the
shell-expansion rule, and it keeps the target byte for byte: no quote stripping and no whitespace
trimming, because those are legal Windows file name characters and the tool will open the path
exactly as given. Rooting, `..` collapsing, and symlink resolution are unchanged.
#>
function Get-AgentWriteTargetResolution {
    [CmdletBinding()]
    param([string] $Target, [string] $BaseDirectory, [switch] $Literal)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    # A target that is nothing but a heredoc or here-string opener token carries no real path.
    # Get-AgentSegmentWriteTarget can only report the bare opener as a write command's own target
    # when the tokenizer already skipped the body that names the real path, for example
    # `Remove-Item @'<a path>'@`. Resolving the two- or three-character opener as if it were a
    # literal relative path let that command through; treating it as unresolved denies it instead,
    # matching how a command carrying an unexpandable path component is already handled below.
    # Checked before the quote-trim just below: trimming a here-string opener's own quote
    # character would erase the exact shape this matches. A tool-call path never carries this
    # shape, so -Literal skips it the same way it skips the other shell-only checks.
    if (-not $Literal -and $Target.Trim() -match $script:AgentGuardOpenerTokenPattern) {
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    # A command-line target still carries the shell's quoting, so quotes and outer whitespace are
    # stripped off it. A tool call carries the path exactly as the tool will open it, and a quote
    # or a leading space is a legal Windows file name character. Stripping there classified a
    # different file: "'\..\..\..\q.tmp" became the drive-rooted "\..\..\..\q.tmp", which lands
    # outside the checkout and was allowed.
    $trimmed = if ($Literal) { $Target } else { $Target.Trim().Trim('"', "'") }
    if ($trimmed.StartsWith('~')) {
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    # A provider-qualified path such as 'FileSystem::C:\repo\file' names a real location, but
    # IsPathRooted below reads it as relative and joins it to the session's own directory. That
    # turns a main-checkout path into an allowed worktree one. No valid Windows path contains
    # '::', so failing closed here costs nothing and cannot be worked around by spelling the
    # provider differently.
    if ($trimmed -match '::') {
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    # A tool call carries one literal path and no shell runs over it, so '$', '%' and backtick are
    # ordinary file name characters there. Applying the shell rule would refuse a real edit inside
    # the session's own worktree. A '~' still fails closed under -Literal: nothing in the payload
    # says which home directory it means.
    if (-not $Literal -and $trimmed -match $script:AgentGuardUnexpandablePattern) {
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    $parts = @($trimmed -split '[\\/]')
    # Named literalParts, not literal: PowerShell variable names are case-insensitive, so a plain
    # $literal here would be the -Literal switch parameter above.
    $literalParts = New-Object System.Collections.Generic.List[string]
    foreach ($part in $parts) {
        if ($part -match '[\*\?]') { break }
        [void] $literalParts.Add($part)
    }

    if ($literalParts.Count -eq 0) {
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    $candidate = $literalParts -join '\'
    try {
        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            if ([string]::IsNullOrWhiteSpace($BaseDirectory)) {
                return [pscustomobject]@{ Path = ''; Unresolved = $true }
            }
            $candidate = Join-Path $BaseDirectory $candidate
        }

        # GetFullPath collapses '..' segments; it does not touch the filesystem.
        $candidate = [System.IO.Path]::GetFullPath($candidate)
    }
    catch {
        # Windows PowerShell 5.1 runs on .NET Framework, whose path APIs reject characters such
        # as '"' outright, and IsPathRooted throws before GetFullPath is ever reached. A path
        # this host cannot parse is one the guard cannot classify, so report it unresolved. The
        # caller then denies. Letting the exception escape would instead reach the entrypoint's
        # catch and allow the write.
        return [pscustomobject]@{ Path = ''; Unresolved = $true }
    }

    $resolved = Resolve-AgentSymlinkPath -Path $candidate
    return [pscustomobject]@{
        Path       = (ConvertTo-AgentGuardNormalizedPath $resolved)
        Unresolved = $false
    }
}

# Path components that are build output or third-party content, never source the human owns.
$script:AgentGuardThrowawayComponents = @('bin', 'obj', 'testresults', '.vs', 'node_modules')

$script:AgentGuardWriteDenialMessage = @'
BLOCKED: this session is isolated in a worktree, so it cannot write into the main checkout at {0}
Read from here. Write from the main checkout.
To override, a human must set AHKFLOW_ALLOW_MAIN=1 in the shell environment before starting the
agent session.
'@

$script:AgentGuardPlansDenialMessage = @'
BLOCKED: {0} is the root of the private plans repository, and this session is isolated in a
worktree.
Files inside it are writable from here. The root itself is not: every worktree links to it, so
deleting or renaming it breaks all of them.
Write inside docs/superpowers instead, or run this from the main checkout.
'@

$script:AgentGuardUnresolvedWriteMessage = @'
BLOCKED: this session is isolated in a worktree, and the guard cannot expand this write target, so
it cannot tell whether the write lands in the main checkout.
Write the path out literally instead of using a variable, or run the command from the main checkout.
'@

$script:AgentGuardPipedSourceMessage = @'
BLOCKED: this session is isolated in a worktree, and {0} takes the paths it deletes from the
pipeline. The guard reads the command text and never runs it, so it cannot tell which paths
arrive that way, or whether any of them sit in the main checkout.
Name the paths in the command itself, with -Path or as arguments, instead of piping them in.
'@

<#
.SYNOPSIS
True when a resolved path is one the session may write despite sitting under the main checkout.
#>
function Test-AgentWriteTargetAllowed {
    [CmdletBinding()]
    param([string] $ResolvedPath, [string] $MainCheckout, [string] $WorktreeRoot)

    $path = $ResolvedPath.TrimEnd('\', '/')
    $main = $MainCheckout.TrimEnd('\', '/')
    $worktree = $WorktreeRoot.TrimEnd('\', '/')

    # The session's own worktree, and anything inside it.
    if ($path -ieq $worktree -or $path.StartsWith($worktree + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    # Anything outside the protected checkout entirely.
    if (-not ($path -ieq $main -or $path.StartsWith($main + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
        return $true
    }

    # The removal log, by exact path. Its parent directory stays refused, so a sibling worktree
    # is not writable just because the log lives beside it.
    $removalLog = Join-Path $main '.claude\worktrees\worktree-removal.log'
    if ($path -ieq (ConvertTo-AgentGuardNormalizedPath $removalLog)) { return $true }

    # The private plans repo. It is a separate repository that the public repo git-ignores and
    # links into every worktree, so a write here cannot touch the protected checkout's tracked
    # files. Design and Plan produce their artifacts from the worktree; without this they would
    # hand every spec and plan edit to a main-checkout session.
    #
    # Strictly under the root, never the root itself: deleting or renaming docs\superpowers would
    # break the link every worktree depends on. A move INTO this subtree is still refused when its
    # source sits elsewhere in main, because a move reports both endpoints.
    #
    # The repository's own .git is excluded as well. The exception exists so a session can edit
    # plans and commit them, and destroying .git destroys the repository itself, including history
    # that was never pushed. Remove-Item is not the 'rm' the destructive-command tier matches, so
    # this boundary is the only thing that refuses it.
    # This refuses outright rather than falling through. The build-output allow-list below clears
    # any path with a 'bin' or 'obj' component, and a git ref may be named either, so
    # docs\superpowers\.git\refs\heads\bin would otherwise walk straight back out of this boundary.
    $plansRepo = ConvertTo-AgentGuardNormalizedPath (Join-Path $main 'docs\superpowers')
    $plansGit = ConvertTo-AgentGuardNormalizedPath (Join-Path $plansRepo '.git')
    if (($path -ieq $plansGit) -or
        $path.StartsWith($plansGit + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ($path.StartsWith($plansRepo + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    # The protected checkout's own .git, for the same reason and against the same reopening. A
    # branch may be named 'bin' or 'obj', which puts a throwaway component in .git\refs\heads, and
    # .git\worktrees holds one directory per managed worktree, so either name can appear there too.
    $mainGit = ConvertTo-AgentGuardNormalizedPath (Join-Path $main '.git')
    if (($path -ieq $mainGit) -or
        $path.StartsWith($mainGit + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    # Build output and third-party content.
    $relative = $path.Substring($main.Length).Trim('\', '/')
    foreach ($component in ($relative -split '[\\/]')) {
        if ($script:AgentGuardThrowawayComponents -contains $component.ToLowerInvariant()) { return $true }
    }

    return $false
}

<#
.SYNOPSIS
Refuses a shell write into the main checkout from a session isolated in a managed worktree.

.DESCRIPTION
Only fires when the session's own working directory is a managed worktree. A main-checkout
session is unaffected, which keeps the AGENTS.md rule that agents may edit, build, test, and
format in main. Segments are walked in order so an earlier cd moves where a later write lands,
matching Get-AgentGitLocationDecision.
#>
function Get-AgentWorktreeWriteDecision {
    [CmdletBinding()]
    param(
        [string] $Command,
        [string] $Cwd,
        [string] $ProtectedRepoRoot,
        [bool] $AllowMain = $false
    )

    $sessionState = Get-ManagedWorktreeState -Cwd $Cwd -ProtectedRepoRoot $ProtectedRepoRoot
    if ($sessionState -ne 'ManagedWorktree') { return New-AgentGuardDecision -Action Allow }

    $parsed = Get-AgentCommandSegment -Command $Command
    if ($parsed.Ambiguous) { return New-AgentGuardDecision -Action Allow }

    $protectedCommonDir = Invoke-AgentGuardGitProbe @(
        '-C', $ProtectedRepoRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if ([string]::IsNullOrWhiteSpace($protectedCommonDir)) { return New-AgentGuardDecision -Action Allow }
    $mainCheckout = ConvertTo-AgentGuardNormalizedPath (Split-Path -Parent (
            ConvertTo-AgentGuardNormalizedPath $protectedCommonDir))
    # The session's own worktree is its git top level, not the directory it happens to sit in. A
    # session started in <worktree>\src would otherwise treat src as the whole worktree and refuse
    # a write to the worktree's own root, which is inside main and so fails the outside-main test.
    $worktreeRoot = Get-AgentSessionWorktreeRoot -Cwd $Cwd

    $effectiveCwd = $Cwd
    $unresolvedDirectory = $false
    $directoryStack = New-Object System.Collections.Generic.List[string]
    $blockingPath = ''
    $unresolvedBlock = $false
    $pipedSourceCommand = ''

    foreach ($segment in $parsed.Segments) {
        if ($segment.Kind -eq 'PopDirectory') {
            if ($directoryStack.Count -gt 0) {
                $effectiveCwd = $directoryStack[$directoryStack.Count - 1]
                $directoryStack.RemoveAt($directoryStack.Count - 1)
                $unresolvedDirectory = $false
            }
            continue
        }

        if ($segment.Kind -eq 'ChangeDirectory' -or $segment.Kind -eq 'PushDirectory') {
            # A cd the guard cannot expand leaves the shell somewhere unknown, so every later
            # RELATIVE write is untargetable. Dropping the move and keeping the old directory
            # classified `cd "$MAIN_ROOT"; printf x > x.tmp` against the worktree and allowed a
            # write that landed in main. Mirrors Get-AgentGitLocationDecision.
            if ($segment.Unresolved) {
                $unresolvedDirectory = $true
                continue
            }
            $candidate = if ([System.IO.Path]::IsPathRooted($segment.Directory)) { $segment.Directory }
            elseif (-not [string]::IsNullOrWhiteSpace($effectiveCwd)) { Join-Path $effectiveCwd $segment.Directory }
            else { '' }
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                $unresolvedDirectory = $true
                continue
            }
            # A cd to a path that does not exist fails, leaving the shell where it already was.
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
            if ($segment.Kind -eq 'PushDirectory') { [void] $directoryStack.Add($effectiveCwd) }
            $effectiveCwd = $candidate
            $unresolvedDirectory = $false
            continue
        }

        $targets = @(Get-AgentSegmentWriteTarget -Tokens $segment.Tokens -Masks $segment.Masks)

        # A sink that deletes what the pipeline hands it names a source no scan of this segment
        # can find. An empty source list is not "deletes nothing", so fail closed on it. This gets
        # its own flag rather than reusing $unresolvedBlock: the fix is to write the paths out as
        # arguments, not to expand a variable, so the two denials must not share a message.
        if ($segment.PipedFrom -and (Test-AgentPipelineBoundSource -Tokens $segment.Tokens)) {
            # The word as typed, not the lowercased leaf: the message quotes it back to the reader.
            if ($pipedSourceCommand -eq '') { $pipedSourceCommand = [string] $segment.Tokens[0] }
        }

        # Nested interpreters, quoted and unquoted alike. Same reader as
        # Get-AgentCommandWriteTarget uses, so the two cannot drift.
        $nested = Get-AgentInterpreterInnerTarget -Tokens $segment.Tokens -Masks $segment.Masks -Depth 0
        $targets += @($nested.Targets)
        # An inner command that was never scanned is not an inner command that writes nothing.
        # Fail closed on it.
        if ($nested.Unresolved) { $unresolvedBlock = $true }

        foreach ($target in $targets) {
            # A relative target after an unexpandable cd cannot be placed. Passing no base
            # directory is what makes Get-AgentWriteTargetResolution report that; an absolute
            # target ignores the base and still classifies exactly.
            $baseDirectory = if ($unresolvedDirectory) { '' } else { $effectiveCwd }
            $resolution = Get-AgentWriteTargetResolution -Target $target -BaseDirectory $baseDirectory
            if ($resolution.Unresolved) {
                if (-not $unresolvedBlock -and $blockingPath -eq '') { $unresolvedBlock = $true }
                continue
            }

            if (Test-AgentWriteTargetAllowed -ResolvedPath $resolution.Path `
                    -MainCheckout $mainCheckout -WorktreeRoot $worktreeRoot) {
                continue
            }

            if ($blockingPath -eq '') { $blockingPath = $resolution.Path }
        }
    }

    if ($blockingPath -eq '' -and -not $unresolvedBlock -and $pipedSourceCommand -eq '') {
        return New-AgentGuardDecision -Action Allow
    }

    if ($AllowMain) {
        $overrideTarget = if ($blockingPath -ne '') { $blockingPath }
        elseif ($pipedSourceCommand -ne '') { "a source piped into $pipedSourceCommand" }
        else { 'an unexpandable target' }
        return New-AgentGuardDecision -Action Warn -Rule 'agent-worktree-main-write-overridden' -Message `
        ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the worktree write-isolation rule for: $overrideTarget")
    }

    # A named blocking path outranks both. It says exactly which file the command touches, which
    # is more use than either "the guard could not tell".
    if ($blockingPath -eq '' -and $pipedSourceCommand -ne '') {
        return New-AgentGuardDecision -Action Deny -Rule 'agent-worktree-main-write' -Message `
        ([string]::Format($script:AgentGuardPipedSourceMessage, $pipedSourceCommand))
    }

    if ($blockingPath -eq '') {
        return New-AgentGuardDecision -Action Deny -Rule 'agent-worktree-main-write' -Message `
            $script:AgentGuardUnresolvedWriteMessage
    }

    # Anything strictly under $plansRoot is allowed unconditionally (Test-AgentWriteTargetAllowed
    # above), so a blocked path can never be a StartsWith match here — only the exact root can
    # reach this denial. Testing only -ieq keeps that reachable case and drops the dead half.
    $plansRoot = ConvertTo-AgentGuardNormalizedPath (Join-Path $mainCheckout 'docs\superpowers')
    $template = if ($blockingPath -ieq $plansRoot) {
        $script:AgentGuardPlansDenialMessage
    }
    else {
        $script:AgentGuardWriteDenialMessage
    }

    return New-AgentGuardDecision -Action Deny -Rule 'agent-worktree-main-write' -Message `
    ([string]::Format($template, $blockingPath))
}

<#
.SYNOPSIS
Refuses an Edit, Write, or NotebookEdit tool call that lands in the main checkout from a session
isolated in a managed worktree.

.DESCRIPTION
Get-AgentWorktreeWriteDecision has to parse a command line before it can find a write target. A
tool call carries one literal path instead, so this function shares that rule's path resolution,
allow-list, and refusal messages but none of its parsing. Like the shell rule, it only fires when
the session's own working directory is a managed worktree, which keeps the AGENTS.md rule that
agents may edit, build, test, and format in the main checkout.
#>
function Get-AgentFileEditWriteDecision {
    [CmdletBinding()]
    param(
        [string] $TargetPath,
        [string] $Cwd,
        [string] $ProtectedRepoRoot,
        [bool] $AllowMain = $false
    )

    # A payload with no path is malformed. The tool rejects it anyway, so there is nothing here to
    # protect.
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return New-AgentGuardDecision -Action Allow }

    $sessionState = Get-ManagedWorktreeState -Cwd $Cwd -ProtectedRepoRoot $ProtectedRepoRoot
    if ($sessionState -ne 'ManagedWorktree') { return New-AgentGuardDecision -Action Allow }

    $protectedCommonDir = Invoke-AgentGuardGitProbe @(
        '-C', $ProtectedRepoRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if ([string]::IsNullOrWhiteSpace($protectedCommonDir)) { return New-AgentGuardDecision -Action Allow }
    $mainCheckout = ConvertTo-AgentGuardNormalizedPath (Split-Path -Parent (
            ConvertTo-AgentGuardNormalizedPath $protectedCommonDir))
    # The session's own worktree is its git top level, not the directory it happens to sit in.
    $worktreeRoot = Get-AgentSessionWorktreeRoot -Cwd $Cwd

    $resolution = Get-AgentWriteTargetResolution -Target $TargetPath -BaseDirectory $Cwd -Literal

    if (-not $resolution.Unresolved) {
        if (Test-AgentWriteTargetAllowed -ResolvedPath $resolution.Path `
                -MainCheckout $mainCheckout -WorktreeRoot $worktreeRoot) {
            return New-AgentGuardDecision -Action Allow
        }
    }

    if ($AllowMain) {
        $overrideTarget = if ($resolution.Unresolved) { 'an unexpandable target' } else { $resolution.Path }
        return New-AgentGuardDecision -Action Warn -Rule 'agent-worktree-main-write-overridden' -Message `
        ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the worktree write-isolation rule for: $overrideTarget")
    }

    if ($resolution.Unresolved) {
        return New-AgentGuardDecision -Action Deny -Rule 'agent-worktree-main-write' -Message `
            $script:AgentGuardUnresolvedWriteMessage
    }

    # Anything strictly under $plansRoot is allowed unconditionally (Test-AgentWriteTargetAllowed
    # above), so a blocked path can never be a StartsWith match here — only the exact root can
    # reach this denial. Testing only -ieq keeps that reachable case and drops the dead half.
    $plansRoot = ConvertTo-AgentGuardNormalizedPath (Join-Path $mainCheckout 'docs\superpowers')
    $template = if ($resolution.Path -ieq $plansRoot) {
        $script:AgentGuardPlansDenialMessage
    }
    else {
        $script:AgentGuardWriteDenialMessage
    }

    return New-AgentGuardDecision -Action Deny -Rule 'agent-worktree-main-write' -Message `
    ([string]::Format($template, $resolution.Path))
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
    # Tracks whether ANY blocking segment in the whole chain is a commit, independent of which
    # segment blocked first. commit must never resolve to Ask under any condition (see the
    # Deny-vs-Ask branch below), so the scan cannot stop at the first block: an earlier `git add .`
    # blocking first must not hide a `git commit` blocking later in the same command.
    $commitBlocks = $false

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

        if (Test-AgentGitTier2Allowed -Subcommand $parts.Subcommand -Arguments $parts.Args) {
            continue
        }

        if ($parts.UsesGitDirOrWorkTree) {
            if ($blockingState -eq '') {
                $blockingState = 'ExplicitGitDir'
                $blockingTarget = $Cwd
            }
            if ($parts.Subcommand -ieq 'commit') { $commitBlocks = $true }
            continue
        }

        # Only an absolute `git -C <path>` re-anchors the target independently of the shell's cwd.
        # A relative -C is joined onto the (now-stale) base, so after an untrackable cd it resolves
        # to a path the command would never actually use - deny rather than classify a guess. Once
        # any -C in the chain is absolute, git discards the base, so the result is cwd-independent.
        $dashCReanchors = @($parts.DashC | Where-Object { [System.IO.Path]::IsPathRooted($_) }).Count -gt 0
        if ($unresolvedDirectory -and -not $dashCReanchors) {
            if ($blockingState -eq '') {
                $blockingState = 'UnresolvedDirectoryChange'
                $blockingTarget = $Cwd
            }
            if ($parts.Subcommand -ieq 'commit') { $commitBlocks = $true }
            continue
        }

        $targetDir = Resolve-AgentGitTargetDirectory -Parts $parts -BaseCwd $effectiveCwd
        $state = Get-ManagedWorktreeState -Cwd $targetDir -ProtectedRepoRoot $ProtectedRepoRoot

        if ($state -inotin $script:AgentGuardAllowedStates) {
            if ($blockingState -eq '') {
                $blockingState = $state
                $blockingTarget = $targetDir
            }
            if ($parts.Subcommand -ieq 'commit') { $commitBlocks = $true }
            continue
        }
    }

    if ($blockingState -eq '') {
        return New-AgentGuardDecision -Action Allow
    }

    # Commit dominates regardless of scan order. If a commit blocks anywhere in the chain, the
    # overall decision is Tier 1b (Deny), never Ask - even when a different segment (e.g. `git add
    # .`) blocked first and supplied the message/target above. Approving an Ask here would let the
    # earlier mutation run, then commit would die at the separate pre-commit backstop, leaving the
    # owner's index staged with the agent's files - exactly the failure mode Ask must never produce.
    $isTier1b = $commitBlocks

    if ($blockingState -eq 'ExplicitGitDir') {
        if ($AllowMain) {
            return New-AgentGuardDecision -Action Warn -Rule 'agent-git-dir-override-overridden' -Message `
            ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the --git-dir/--work-tree restriction for: $blockingTarget")
        }
        $action = if ($isTier1b) { 'Deny' } else { 'Ask' }
        $message = if ($isTier1b) {
            ('BLOCKED: agent Git mutations with --git-dir or --work-tree are not allowed; the ' +
                'target cannot be verified. Run the command from inside a managed linked worktree instead.')
        }
        else {
            ('This command uses --git-dir or --work-tree, so the guard cannot verify its target ' +
                'from the command text alone. Approve only if you want it to run here. To avoid ' +
                'the ambiguity, run it from inside a managed linked worktree instead.')
        }
        return New-AgentGuardDecision -Action $action -Rule 'agent-git-dir-mutation' -Message $message
    }

    if ($blockingState -eq 'UnresolvedDirectoryChange') {
        if ($AllowMain) {
            return New-AgentGuardDecision -Action Warn -Rule 'agent-unresolved-cd-overridden' -Message `
            ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode an unverifiable directory change before a git mutation.")
        }
        $action = if ($isTier1b) { 'Deny' } else { 'Ask' }
        $message = if ($isTier1b) {
            ('BLOCKED: this command changes directory to a target the guard cannot expand, so the ' +
                'git mutation cannot be verified. Run git from a managed linked worktree, or pass an ' +
                'explicit `git -C <path>`.')
        }
        else {
            ('This command changes directory to a target the guard cannot expand, so it cannot ' +
                'verify where the git mutation would run. Approve only if you want it to run here ' +
                'anyway. To avoid the ambiguity, pass an explicit `git -C <path>`, or run it from ' +
                'inside a managed linked worktree.')
        }
        return New-AgentGuardDecision -Action $action -Rule 'agent-unresolved-git-target' -Message $message
    }

    if ($AllowMain) {
        return New-AgentGuardDecision -Action Warn -Rule 'agent-main-git-mutation-overridden' -Message `
        ("WARNING: AHKFLOW_ALLOW_MAIN=1 overrode the managed-worktree location rule " +
            "($blockingState) for: $blockingTarget")
    }

    if ($isTier1b) {
        $message = [string]::Format($script:AgentGuardDenialMessage, $blockingTarget)
        return New-AgentGuardDecision -Action Deny -Rule 'agent-main-git-mutation' -Message $message
    }

    $message = [string]::Format($script:AgentGuardAskMessage, $blockingTarget)
    return New-AgentGuardDecision -Action Ask -Rule 'agent-main-git-mutation' -Message $message
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

    try {
        $write = Get-AgentWorktreeWriteDecision -Command $Command -Cwd $Cwd `
            -ProtectedRepoRoot $ProtectedRepoRoot -AllowMain $AllowMain
    }
    catch {
        # Fail open, same as the location rule: keep the shell usable, but say so loudly.
        return New-AgentGuardDecision -Action Warn -Rule 'write-guard-error' -Message `
        ("WARNING: the agent worktree write guard could not evaluate this command: $($_.Exception.Message)")
    }

    if ($write.Action -ne 'Allow') { return $write }

    return $safety
}
