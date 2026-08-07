#Requires -Version 7.0
# Shared helpers for backlog item numbering, dot-sourced by new-backlog-item.ps1 and
# tests/BacklogNumbering.Tests.ps1.
#
# A backlog item's number is not only a unique key. Items, docs, and code comments cite each
# other by bare number, so a duplicate number makes an existing reference ambiguous. See
# backlog 061.

Set-StrictMode -Version Latest

function Get-BacklogItem {
    param([Parameter(Mandatory)][string] $BacklogRoot)

    $root = (Resolve-Path -LiteralPath $BacklogRoot).Path
    $repoRoot = Split-Path -Parent $root

    $files = @(Get-ChildItem -LiteralPath $root -Filter '*.md' -File)
    $doneDir = Join-Path $root 'done'
    if (Test-Path -LiteralPath $doneDir) {
        $files += Get-ChildItem -LiteralPath $doneDir -Filter '*.md' -File
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

    # --- Duplicate key across backlog/ and backlog/done/ ---
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

function ConvertTo-BacklogSlug {
    param([Parameter(Mandatory)][string] $Title)

    $slug = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}
