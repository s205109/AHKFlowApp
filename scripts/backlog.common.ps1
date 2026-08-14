#Requires -Version 7.0
# Shared helpers for backlog item numbering, dot-sourced by new-backlog-item.ps1 and
# tests/BacklogNumbering.Tests.ps1.
#
# A backlog item's number is not only a unique key. Items, docs, and code comments cite each
# other by bare number, so a duplicate number makes an existing reference ambiguous. See
# backlog 061.

Set-StrictMode -Version Latest

# The slug rule lives in its own file so new-worktree.ps1 can use it too. That script requires
# PowerShell 5.1 and this one requires 7.0, so it cannot dot-source this file. See backlog 080.
. (Join-Path $PSScriptRoot 'slug.common.ps1')

function Get-BacklogItem {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $root = (Resolve-Path -LiteralPath $BacklogRoot).Path
    $repoRoot = Split-Path -Parent $root

    # Every folder that holds a real item must be scanned, or its number stops counting as taken
    # and the duplicate check below goes blind to it. 'done' is finished work; 'blocked' is work
    # blocked on something outside this repository. Both keep their numbers reserved.
    $files = @(Get-ChildItem -LiteralPath $root -Filter '*.md' -File)
    foreach ($subfolder in @('done', 'blocked')) {
        $subfolderPath = Join-Path $root $subfolder
        if (Test-Path -LiteralPath $subfolderPath) {
            $files += Get-ChildItem -LiteralPath $subfolderPath -Filter '*.md' -File
        }
    }

    foreach ($file in $files) {
        $key = $null
        $number = $null
        if ($file.BaseName -match '^(?<num>\d{3})(?<suffix>[a-z]?)-') {
            $key = "$($Matches.num)$($Matches.suffix)"
            $number = [int] $Matches.num
        }

        # One read serves both the heading and the Stage field. Everything parsed out of an item's
        # text belongs here, so a caller never opens the file a second time.
        $lines = @(Get-Content -LiteralPath $file.FullName)

        $headingKey = $null
        if ($lines.Count -gt 0 -and $lines[0] -match '^#\s*(?<head>\S+)\s*-') {
            $headingKey = $Matches.head
        }

        # An array, not a single value: the Stage check has to tell a missing line from a repeated
        # one, and both are problems with different messages.
        $stages = @($lines |
            Select-String -Pattern '^- \*\*Stage\*\*:\s*(?<stage>\S+)\s*$' |
            ForEach-Object { $_.Matches[0].Groups['stage'].Value })

        $relativePath = $file.FullName.Substring($repoRoot.Length + 1) -replace '\\', '/'

        [PSCustomObject]@{
            Key          = $key
            Number       = $number
            Path         = $file.FullName
            RelativePath = $relativePath
            # 'done', 'blocked', or the backlog root's own folder name. Read from the path rather
            # than from RelativePath, which is cut against the backlog root's parent and so starts
            # with a temp folder's name under a test root.
            Folder       = Split-Path -Leaf (Split-Path -Parent $file.FullName)
            HeadingKey   = $headingKey
            Stages       = $stages
        }
    }
}

function Get-BacklogProblem {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $items = @(Get-BacklogItem -BacklogRoot $BacklogRoot)
    $problems = @()

    # --- Bad file name: does not match NNN-slug.md or NNNx-slug.md ---
    foreach ($item in $items | Where-Object { $null -eq $_.Key }) {
        $problems += "Bad backlog file name: $($item.RelativePath). Expected NNN-slug.md or NNNx-slug.md."
    }

    # --- Duplicate key across backlog/, backlog/done/, and backlog/blocked/ ---
    $byKey = $items | Where-Object { $null -ne $_.Key } | Group-Object -Property Key
    foreach ($group in $byKey | Where-Object { $_.Count -gt 1 }) {
        $names = ($group.Group | Select-Object -ExpandProperty RelativePath) -join ', '
        $problems += "Duplicate backlog number '$($group.Name)': $names"
    }

    # --- Heading drift: '# NNN - Title' heading number must match the file name number ---
    foreach ($item in $items | Where-Object { $null -ne $_.Key }) {
        if ((Split-Path -Leaf $item.Path) -eq '000-backlog-item-template.md') {
            continue
        }

        if ($item.HeadingKey -ne $item.Key) {
            $problems += "Heading number mismatch in $($item.RelativePath): file name says '$($item.Key)' but heading says '$($item.HeadingKey)'."
        }
    }

    # --- Stage field: exactly one line, a real stage name, and 9-ship for anything shipped ---
    #
    # docs/development/workflow.md:78 makes this field the durable record of where the work stands,
    # and :482 has Ship set 9-ship in the same change that moves the item to done/. Nothing checked
    # it before backlog 087, so an item reached done/ still reading 4-execute.
    #
    # The template is not excluded here, unlike the heading check above. It carries
    # '- **Stage**: 0-intake' and lives in backlog/ rather than done/, so it passes, and including
    # it keeps the line in the template instead of merely putting it there once.
    $stageNames = @(
        '0-intake', '1-pickup', '2-design', '3-plan', '4-execute', '5-simplify',
        '6-verify', '7-document', '8-review', '9-ship', '10-cleanup'
    )

    foreach ($item in $items | Where-Object { $null -ne $_.Key }) {
        if ($item.Stages.Count -ne 1) {
            $problems += "Stage field problem in $($item.RelativePath): expected exactly one '- **Stage**: <stage>' line, found $($item.Stages.Count)."
            continue
        }

        $stage = $item.Stages[0]

        if ($stage -notin $stageNames) {
            $problems += "Unknown stage '$stage' in $($item.RelativePath). Expected one of: $($stageNames -join ', ')."
        }
        elseif ($item.Folder -eq 'done' -and $stage -ne '9-ship') {
            $problems += "Shipped item $($item.RelativePath) reads 'Stage: $stage'. An item in backlog/done/ must read 'Stage: 9-ship'."
        }
    }

    return $problems
}

# The eleven stage ids, in the order docs/development/workflow.md:31-43 defines them. The order
# matters: the check compares by index, never as a string, because '10-cleanup' sorts below
# '4-execute' as a string and a finished item would slip through.
$script:BacklogStageOrder = @(
    '0-intake', '1-pickup', '2-design', '3-plan', '4-execute', '5-simplify',
    '6-verify', '7-document', '8-review', '9-ship', '10-cleanup'
)

# Stage 3's exit condition is 'Plan committed', so 4-execute is the first stage that owes a plan
# pointer.
$script:BacklogPointerTriggerIndex = 4

function Get-BacklogNotesLine {
    # A backlog item is mostly blank lines, so both the empty array and the empty string must be
    # legal input here.
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Line)

    $inside = $false
    $notes = @()
    foreach ($text in $Line) {
        if ($text -match '^##\s') {
            if ($inside) { break }
            if ($text -match '^##\s+Notes\s*/\s*dependencies\s*$') { $inside = $true }
            continue
        }
        if ($inside) { $notes += $text }
    }

    return $notes
}

function Test-BacklogPlanPath {
    param([Parameter(Mandatory)][string] $Value)

    # A backtick-quoted path, one segment under docs/superpowers/plans/, ending .md, with nothing
    # after the closing backtick except an optional full stop.
    if ($Value -notmatch '^`docs/superpowers/plans/[^/`]+\.md`\.?$') { return $false }
    if ($Value -match '\.\.') { return $false }
    return $true
}

function Test-BacklogPlanNone {
    param([Parameter(Mandatory)][string] $Value)

    # 'none — <reason>', with a reason that is not empty after trimming. \u2014 is the em
    # dash; spelling it as an escape keeps the file's encoding out of the match.
    if ($Value -notmatch '^none\s+\u2014\s+(.+)$') { return $false }
    return -not [string]::IsNullOrWhiteSpace($Matches[1])
}

function Get-BacklogPointerProblem {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $problems = @()

    foreach ($item in Get-BacklogItem -BacklogRoot $BacklogRoot) {
        if ((Split-Path -Leaf $item.Path) -eq '000-backlog-item-template.md') { continue }

        # backlog/done/ is out of scope. The failure this check prevents happens when a session
        # picks work up, and nobody picks up a finished item. See backlog 090.
        if ($item.RelativePath -match '/done/') { continue }

        $lines = @(Get-Content -LiteralPath $item.Path)
        $stageLines = @($lines | Where-Object { $_ -match '^\s*-\s+\*\*Stage\*\*:' })

        if ($stageLines.Count -eq 0) { continue }

        if ($stageLines.Count -gt 1) {
            $values = ($stageLines | ForEach-Object { ($_ -replace '^\s*-\s+\*\*Stage\*\*:\s*', '').Trim() }) -join ', '
            $problems += @"
Backlog $($item.Key) has more than one Stage line.
  File:   $($item.RelativePath)
  Found:  $values
  Fix:    keep exactly one '- **Stage**:' line.
"@
            continue
        }

        $stage = ($stageLines[0] -replace '^\s*-\s+\*\*Stage\*\*:\s*', '').Trim()
        $index = [array]::IndexOf($script:BacklogStageOrder, $stage)

        if ($index -lt 0) {
            $problems += @"
Backlog $($item.Key) has an unknown Stage value.
  File:   $($item.RelativePath)
  Found:  $stage
  Expect: one of $($script:BacklogStageOrder -join ', ')
"@
            continue
        }

        if ($index -lt $script:BacklogPointerTriggerIndex) { continue }

        $notes = @(Get-BacklogNotesLine -Line $lines)
        $planLines = @($notes | Where-Object { $_ -match '^\s*-\s+Plan:' })
        $values = @($planLines | ForEach-Object { ($_ -replace '^\s*-\s+Plan:\s*', '').Trim() })

        if ($values.Count -eq 0) {
            $problems += @"
Backlog $($item.Key) has no plan pointer.
  File:    $($item.RelativePath)
  Stage:   $stage
  Missing: a "- Plan:" bullet under "## Notes / dependencies"
  Write:   - Plan: ``docs/superpowers/plans/<file>.md``
  Or:      - Plan: none $([char]0x2014) <why this item has no plan>
"@
            continue
        }

        $paths = @($values | Where-Object { Test-BacklogPlanPath -Value $_ })
        $nones = @($values | Where-Object { Test-BacklogPlanNone -Value $_ })
        $bad = @($values | Where-Object { -not (Test-BacklogPlanPath -Value $_) -and -not (Test-BacklogPlanNone -Value $_) })

        if ($bad.Count -gt 0) {
            $problems += @"
Backlog $($item.Key) has a "- Plan:" bullet this check cannot read.
  File:    $($item.RelativePath)
  Found:   $($bad -join ' | ')
  Write:   - Plan: ``docs/superpowers/plans/<file>.md``
  Or:      - Plan: none $([char]0x2014) <why this item has no plan>
"@
            continue
        }

        if ($nones.Count -gt 0 -and $paths.Count -gt 0) {
            $problems += @"
Backlog $($item.Key) claims both a plan and no plan.
  File:    $($item.RelativePath)
  Fix:     keep the plan paths, and delete the 'none' bullet.
"@
            continue
        }

        if ($nones.Count -gt 1) {
            $problems += @"
Backlog $($item.Key) has more than one 'none' plan bullet.
  File:    $($item.RelativePath)
  Fix:     keep exactly one.
"@
        }
    }

    return $problems
}

function Get-NextBacklogNumber {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $items = @(Get-BacklogItem -BacklogRoot $BacklogRoot | Where-Object { $null -ne $_.Number })
    $max = [int] ($items | Measure-Object -Property Number -Maximum).Maximum
    return '{0:D3}' -f ($max + 1)
}

function New-BacklogFile {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Content
    )

    # FileMode.CreateNew makes the existence check and the write one atomic operation, so two
    # processes racing to create the same path cannot have the second one silently clobber the
    # first. A separate Test-Path check followed by a WriteAllText leaves a gap between them.
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    try {
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    }
    catch [System.IO.IOException] {
        throw "Refusing to overwrite existing file: $Path"
    }

    try {
        $writer = [System.IO.StreamWriter]::new($stream, $utf8NoBom)
        $writer.Write($Content)
        $writer.Dispose()
    }
    finally {
        $stream.Dispose()
    }
}
