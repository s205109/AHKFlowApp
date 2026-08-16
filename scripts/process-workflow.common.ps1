#Requires -Version 7.0
<#
.SYNOPSIS
    Parses the process documents into one stage-machine shape.
.DESCRIPTION
    workflow.md is the source. The two HTML files carry data-* markers plus visible text that
    repeats the same values. Every process check reads through this file, so a format drift
    is found in one place rather than three.
#>

Set-StrictMode -Version Latest

function Get-NormalizedText {
    param([Parameter(Mandatory)][string] $Path)
    return ((Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n")
}

function Get-NormalizedHash {
    param([Parameter(Mandatory)][string] $Path)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-NormalizedText -Path $Path))
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '')
}

# The marker the generator writes into the PDF, and the check reads back out. Two hash
# sidecars only prove three files were written together; a person can refresh a sidecar by
# hand. This digest travels inside the PDF, so it proves which cheatsheet produced it.
$script:PdfSourceDigestMarker = 'AHKFLOW-SOURCE-SHA256:'

function Get-PdfSourceDigestMarker {
    param([Parameter(Mandatory)][string] $Digest)
    return "$script:PdfSourceDigestMarker$Digest"
}

function Test-PdfSourceDigest {
    param(
        [Parameter(Mandatory)][byte[]] $Bytes,
        [Parameter(Mandatory)][string] $Digest
    )
    $marker = Get-PdfSourceDigestMarker -Digest $Digest
    # A PDF writer stores a string either as bytes or as UTF-16 with a byte-order mark, so
    # read the file both ways rather than assuming one.
    $latin1 = [System.Text.Encoding]::Latin1.GetString($Bytes)
    if ($latin1.Contains($marker)) { return $true }
    return ([System.Text.Encoding]::BigEndianUnicode.GetString($Bytes)).Contains($marker)
}

# A dictionary that keeps insertion order and tells 'Success' from 'success'. The default
# [ordered]@{} is case-insensitive, so a drifted edge name matched the source and passed.
function New-OrdinalDictionary {
    return [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
}

function Get-LineNumber {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][int] $Index
    )
    # Count the newlines before the value, so a message names the line the value is on
    # rather than the line its stage starts on.
    return ($Text.Substring(0, $Index).Split("`n").Count)
}

# Strips tags and decodes entities, so a comparison reads what a person sees.
function ConvertTo-VisibleText {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Html)
    # <wbr> is a zero-width line-break hint, so it must vanish rather than become a space.
    # The cheatsheet holds '2-design/<wbr>3-plan/<wbr>4-execute'. Replacing it with a space
    # yields '2-design/ 3-plan/ 4-execute' and fails a cell that is actually correct.
    $text = $Html -replace '<wbr\s*/?>', ''
    $text = $text -replace '<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    return (($text -replace '\s+', ' ').Trim())
}

function Get-WorkflowStage {
    param([Parameter(Mandatory)][string] $Path)

    $workflow = Get-NormalizedText -Path $Path
    $stages = New-OrdinalDictionary
    $anchors = [regex]::Matches($workflow, '<a id="stage-([0-9a-z-]+)"></a>')

    for ($i = 0; $i -lt $anchors.Count; $i++) {
        $id = $anchors[$i].Groups[1].Value
        $start = $anchors[$i].Index
        $end = if ($i + 1 -lt $anchors.Count) { $anchors[$i + 1].Index } else { $workflow.Length }
        $block = $workflow.Substring($start, $end - $start)

        # A repeated stage id must be counted, never assigned over. Assigning by key left the
        # dictionary with 11 entries while the document held 12 blocks, so every comparison
        # passed and the second block was never read.
        if ($stages.Contains($id)) { $stages[$id].Occurrences++; continue }

        $edges = New-OrdinalDictionary
        $edgeLines = New-OrdinalDictionary
        $duplicates = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($block, '(?m)^\| (success|failure|blocked|not applicable|resume) \| [^|]+ \| ([^|]+) \|$')) {
            $word = $m.Groups[1].Value
            # A duplicate must be reported, never silently overwritten: a wrong row followed
            # by a correct one passed before the original checker grew this report. Carrying
            # the list here keeps that report alive after the parser was shared.
            if ($edges.Contains($word)) { $duplicates.Add($word); continue }
            $edges[$word] = $m.Groups[2].Value.Trim()
            $edgeLines[$word] = Get-LineNumber -Text $workflow -Index ($start + $m.Index)
        }

        $exitMatches = [regex]::Matches($block, '(?m)^- \*\*Exit\*\* — (.+)$')
        $exit = if ($exitMatches.Count -ge 1) { $exitMatches[0].Groups[1].Value.Trim() } else { '' }
        $exitLine = if ($exitMatches.Count -ge 1) { Get-LineNumber -Text $workflow -Index ($start + $exitMatches[0].Index) } else { Get-LineNumber -Text $workflow -Index $start }

        $stages[$id] = @{
            Exit        = $exit
            Edges       = $edges
            ExitCount   = $exitMatches.Count
            Duplicates  = $duplicates
            Occurrences = 1
            Line        = Get-LineNumber -Text $workflow -Index $start
            ExitLine    = $exitLine
            EdgeLines   = $edgeLines
        }
    }

    return $stages
}

function Get-HtmlStage {
    param([Parameter(Mandatory)][string] $Path)

    $html = Get-NormalizedText -Path $Path
    $stages = New-OrdinalDictionary

    $starts = [regex]::Matches($html, '<(?:section|tr) data-stage="([0-9a-z-]+)"')
    for ($i = 0; $i -lt $starts.Count; $i++) {
        $id = $starts[$i].Groups[1].Value
        $start = $starts[$i].Index
        $end = if ($i + 1 -lt $starts.Count) { $starts[$i + 1].Index } else { $html.Length }
        $block = $html.Substring($start, $end - $start)

        if ($stages.Contains($id)) { $stages[$id].Occurrences++; continue }

        # Line number of the block start, so a message can name the losing line.
        $line = Get-LineNumber -Text $html -Index $start

        $exitAttr = [regex]::Match($block, 'data-exit="([^"]*)"')
        $exitElement = [regex]::Match($block, '<(p|td)[^>]*data-exit="[^"]*"[^>]*>(.*?)</\1>', 'Singleline')
        $visibleExit = ConvertTo-VisibleText -Html $exitElement.Groups[2].Value
        $visibleExit = ($visibleExit -replace '^Exit:\s*', '')
        $exitLine = if ($exitAttr.Success) { Get-LineNumber -Text $html -Index ($start + $exitAttr.Index) } else { $line }

        $edges = New-OrdinalDictionary
        $visibleEdges = New-OrdinalDictionary
        $edgeLines = New-OrdinalDictionary
        $duplicates = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($block, '<(li|td)[^>]*data-next="([^:]+):([^"]*)"[^>]*>(.*?)</\1>', 'Singleline')) {
            $word = $m.Groups[2].Value
            if ($edges.Contains($word)) { $duplicates.Add($word); continue }
            $edges[$word] = $m.Groups[3].Value.Trim()
            $edgeLines[$word] = Get-LineNumber -Text $html -Index ($start + $m.Index)
            # workflow.html renders the target in a trailing '<span class="target">-> target</span>';
            # the cheatsheet cell holds the bare target. Read the span when it is there. A plain
            # search for an arrow is wrong: a condition may itself contain one, as stage
            # 4-execute's failure edge does, and the first arrow is then not the target's.
            $targetSpan = [regex]::Match($m.Groups[4].Value, '<span class="target"[^>]*>(.*?)</span>', 'Singleline')
            $visible = ConvertTo-VisibleText -Html $(if ($targetSpan.Success) { $targetSpan.Groups[1].Value } else { $m.Groups[4].Value })
            $arrow = [regex]::Match($visible, '→\s*([^→]+)$')
            $visibleEdges[$word] = if ($arrow.Success) { $arrow.Groups[1].Value.Trim() } else { $visible }
        }

        $summary = [regex]::Match($block, '<summary[^>]*>(.*?)</summary>', 'Singleline')
        $visibleStage = if ($summary.Success) {
            ConvertTo-VisibleText -Html $summary.Groups[1].Value
        }
        else {
            $n = [regex]::Match($block, '<td class="n"[^>]*>(.*?)</td>', 'Singleline')
            $s = [regex]::Match($block, '<td class="stage"[^>]*>(.*?)</td>', 'Singleline')
            (ConvertTo-VisibleText -Html ($n.Groups[1].Value + ' ' + $s.Groups[1].Value))
        }

        $stages[$id] = @{
            Exit         = $exitAttr.Groups[1].Value.Trim()
            Edges        = $edges
            VisibleExit  = $visibleExit
            VisibleEdges = $visibleEdges
            VisibleStage = $visibleStage
            Duplicates   = $duplicates
            Occurrences  = 1
            Line         = $line
            ExitLine     = $exitLine
            EdgeLines    = $edgeLines
        }
    }

    return $stages
}
