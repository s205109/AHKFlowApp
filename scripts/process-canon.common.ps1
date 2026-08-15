#Requires -Version 7.0
<#
.SYNOPSIS
    Parses the process documents into one stage-machine shape.
.DESCRIPTION
    workflow.md is the canon. The two HTML files carry data-* markers plus visible text that
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

function Get-CanonStage {
    param([Parameter(Mandatory)][string] $Path)

    $canon = Get-NormalizedText -Path $Path
    $stages = [ordered]@{}
    $anchors = [regex]::Matches($canon, '<a id="stage-([0-9a-z-]+)"></a>')

    for ($i = 0; $i -lt $anchors.Count; $i++) {
        $id = $anchors[$i].Groups[1].Value
        $start = $anchors[$i].Index
        $end = if ($i + 1 -lt $anchors.Count) { $anchors[$i + 1].Index } else { $canon.Length }
        $block = $canon.Substring($start, $end - $start)

        $edges = [ordered]@{}
        $duplicates = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($block, '(?m)^\| (success|failure|blocked|not applicable|resume) \| [^|]+ \| ([^|]+) \|$')) {
            $word = $m.Groups[1].Value
            # A duplicate must be reported, never silently overwritten: a wrong row followed
            # by a correct one passed before the original checker grew this report. Carrying
            # the list here keeps that report alive after the parser was shared.
            if ($edges.Contains($word)) { $duplicates.Add($word); continue }
            $edges[$word] = $m.Groups[2].Value.Trim()
        }

        $exitMatches = [regex]::Matches($block, '(?m)^- \*\*Exit\*\* — (.+)$')
        $exit = if ($exitMatches.Count -ge 1) { $exitMatches[0].Groups[1].Value.Trim() } else { '' }

        $stages[$id] = @{ Exit = $exit; Edges = $edges; ExitCount = $exitMatches.Count; Duplicates = $duplicates }
    }

    return $stages
}

function Get-HtmlStage {
    param([Parameter(Mandatory)][string] $Path)

    $html = Get-NormalizedText -Path $Path
    $stages = [ordered]@{}

    $starts = [regex]::Matches($html, '<(?:section|tr) data-stage="([0-9a-z-]+)"')
    for ($i = 0; $i -lt $starts.Count; $i++) {
        $id = $starts[$i].Groups[1].Value
        $start = $starts[$i].Index
        $end = if ($i + 1 -lt $starts.Count) { $starts[$i + 1].Index } else { $html.Length }
        $block = $html.Substring($start, $end - $start)

        # Line number of the block start, so a message can name the losing line.
        $line = ($html.Substring(0, $start) -split "`n").Count

        $exitAttr = [regex]::Match($block, 'data-exit="([^"]*)"')
        $exitElement = [regex]::Match($block, '<(p|td)[^>]*data-exit="[^"]*"[^>]*>(.*?)</\1>', 'Singleline')
        $visibleExit = ConvertTo-VisibleText -Html $exitElement.Groups[2].Value
        $visibleExit = ($visibleExit -replace '^Exit:\s*', '')

        $edges = [ordered]@{}
        $visibleEdges = [ordered]@{}
        $duplicates = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($block, '<(li|td)[^>]*data-next="([^:]+):([^"]*)"[^>]*>(.*?)</\1>', 'Singleline')) {
            $word = $m.Groups[2].Value
            if ($edges.Contains($word)) { $duplicates.Add($word); continue }
            $edges[$word] = $m.Groups[3].Value.Trim()
            $visible = ConvertTo-VisibleText -Html $m.Groups[4].Value
            # workflow.html renders the target in a trailing "-> target" span; the cheatsheet
            # cell holds the bare target.
            $arrow = [regex]::Match($visible, '→\s*(.+)$')
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
            Line         = $line
        }
    }

    return $stages
}
