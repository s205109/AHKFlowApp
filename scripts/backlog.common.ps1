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

        $headingKey = $null
        $firstLine = Get-Content -LiteralPath $file.FullName -TotalCount 1
        if ($firstLine -match '^#\s*(?<head>\S+)\s*-') {
            $headingKey = $Matches.head
        }

        $relativePath = $file.FullName.Substring($repoRoot.Length + 1) -replace '\\', '/'

        [PSCustomObject]@{
            Key          = $key
            Number       = $number
            Path         = $file.FullName
            RelativePath = $relativePath
            HeadingKey   = $headingKey
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
    # and :481 has Ship set 9-ship in the same change that moves the item to done/. Nothing checked
    # it before backlog 087, so an item reached done/ still reading 4-execute.
    #
    # The done/ test reads the parent directory's name, not RelativePath. RelativePath is cut
    # against the backlog root's parent (:19,46), so under a test temp root it starts with the temp
    # folder's name rather than 'backlog'. The leaf 'done' is the same in both.
    #
    # The template is not excluded here, unlike the heading check above. It carries
    # '- **Stage**: 0-intake' and lives in backlog/ rather than done/, so it passes, and including
    # it keeps the line in the template instead of merely putting it there once.
    $stageNames = @(
        '0-intake', '1-pickup', '2-design', '3-plan', '4-execute', '5-simplify',
        '6-verify', '7-document', '8-review', '9-ship', '10-cleanup'
    )

    foreach ($item in $items | Where-Object { $null -ne $_.Key }) {
        $stageLines = @(Get-Content -LiteralPath $item.Path |
            Select-String -Pattern '^- \*\*Stage\*\*:\s*(?<stage>\S+)\s*$')

        if ($stageLines.Count -ne 1) {
            $problems += "Stage field problem in $($item.RelativePath): expected exactly one '- **Stage**: <stage>' line, found $($stageLines.Count)."
            continue
        }

        $stage = $stageLines[0].Matches[0].Groups['stage'].Value
        $folder = Split-Path -Leaf (Split-Path -Parent $item.Path)

        if ($stage -notin $stageNames) {
            $problems += "Unknown stage '$stage' in $($item.RelativePath). Expected one of: $($stageNames -join ', ')."
        }
        elseif ($folder -eq 'done' -and $stage -ne '9-ship') {
            $problems += "Shipped item $($item.RelativePath) reads 'Stage: $stage'. An item in backlog/done/ must read 'Stage: 9-ship'."
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
