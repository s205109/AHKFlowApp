#Requires -Version 7.0
<#
.SYNOPSIS
    Every process rule must link to a stage that exists in workflow.md.
.DESCRIPTION
    A rule that carries its own narrative becomes a second normative source. Requiring an
    anchor keeps the narrative in one place.

    A section runs from its heading to the next heading of the SAME OR A HIGHER level, so a
    sub-section stays in scope. Stopping at the next heading of any level would fail open:
    adding a sub-heading would silently hide every rule under it.

    Only top-level bullets are rules - a line matching '^- ' at column 1. Table rows,
    numbered items, nested bullets, fenced code and paragraphs carry reference data.
.PARAMETER WorkflowPath
    The source to read the stage list from. Defaults to docs/development/workflow.md.
.PARAMETER ScanFile
    Check one file instead of the built-in list. Requires -Section.
.PARAMETER Section
    The single section heading to scan, used with -ScanFile.
#>
[CmdletBinding()]
param(
    [string] $WorkflowPath,
    [string] $ScanFile,
    [string] $Section
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process-workflow.common.ps1')

if (-not $WorkflowPath) { $WorkflowPath = Join-Path $repoRoot 'docs/development/workflow.md' }

$targets = if ($ScanFile) {
    @(@{ Path = $ScanFile; Sections = @($Section) })
}
else {
    @(
        @{ Path = Join-Path $repoRoot 'AGENTS.md'; Sections = @('Debugging', 'Plans', 'Verification After Implementation', 'Git Workflow') }
        @{ Path = Join-Path $repoRoot '.claude/CLAUDE.md'; Sections = @('Plan before you edit', 'Create the worktree before you write the plan') }
    )
}

$anchors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($id in (Get-WorkflowStage -Path $WorkflowPath).Keys) { [void]$anchors.Add("stage-$id") }

$problems = New-Object System.Collections.Generic.List[string]

foreach ($target in $targets) {
    $lines = (Get-NormalizedText -Path $target.Path) -split "`n"
    # One fence map for the file, used by both loops below. Finding the section heading without
    # it read a fenced '## Git Workflow' as the section start, and the real heading then ended
    # that section at once, so every real rule went unchecked.
    $fenced = Get-FenceLineMap -Lines $lines

    foreach ($heading in $target.Sections) {
        $start = -1
        $level = 0
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($fenced[$i]) { continue }
            if ($lines[$i] -match '^(#{1,6})\s+(.+?)\s*$' -and $Matches[2] -eq $heading) {
                $start = $i
                $level = $Matches[1].Length
                break
            }
        }
        if ($start -lt 0) {
            $problems.Add("$($target.Path): section '$heading' not found. Fix this script or restore the section.")
            continue
        }

        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            # Fence state comes first. A '## Example' inside a fenced block is sample text, not
            # the end of the section, and testing the heading first ended the scan there and let
            # every rule below the fence through unread.
            if ($fenced[$i]) { continue }

            # Same or higher level ends the section. A deeper sub-heading stays in scope.
            if ($line -match '^(#{1,6})\s+' -and $Matches[1].Length -le $level) { break }
            if ($line -notmatch '^- ') { continue }

            $found = [regex]::Matches($line, 'docs/development/workflow\.md#(stage-[0-9a-z-]+)')
            if ($found.Count -eq 0) {
                $problems.Add("$($target.Path):$($i + 1) top-level bullet carries no workflow.md stage anchor: $($line.Substring(0, [Math]::Min(90, $line.Length)))")
                continue
            }
            foreach ($m in $found) {
                if (-not $anchors.Contains($m.Groups[1].Value)) {
                    $problems.Add("$($target.Path):$($i + 1) anchor '#$($m.Groups[1].Value)' does not exist in workflow.md")
                }
            }
        }
    }
}

''
if ($problems.Count) {
    $problems | ForEach-Object { $_ }
    ''
    "RESULT: $($problems.Count) process rule(s) without a live stage anchor."
    exit 1
}

'RESULT: every process rule links to a stage that exists'
