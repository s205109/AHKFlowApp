#Requires -Version 7.0
<#
.SYNOPSIS
Checks that the handover rules say the same thing in all three places.

.DESCRIPTION
docs/development/workflow.md holds the handover rules. Two other files repeat them:

- .agents/handover-commands/SKILL.md quotes each rule word for word. A quote is a blockquote
  right below a marker line of the form <!-- rule: workflow.md#ANCHOR -->. The quote must
  still be in workflow.md, and the anchor must exist there.
- AGENTS.md carries one line per rule under "## Commands and next steps". Every line must
  link to an anchor that exists in workflow.md.

Both files must cover every rule anchor. A quote that drifts, or a rule nobody links to,
fails this suite.

Run it by hand with:  pwsh ./tests/HandoverRules.Tests.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:Failures = New-Object System.Collections.Generic.List[string]

# The rule anchors in workflow.md. None may start with 'stage-': the stage parser in
# scripts/process-workflow.common.ps1 reads every such anchor as a stage.
$script:RuleAnchor = @('handed-over-commands', 'next-step-line', 'pull-request-title-and-sessions')

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# One space for every run of whitespace, so a quote matches however either file wraps it.
function ConvertTo-FlatText {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    return (($Text -replace '\s+', ' ').Trim())
}

# Every quote in the skill: its anchor, the line of its marker, and its text made flat.
function Get-RuleQuote {
    param([Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]] $Lines)
    $quotes = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^<!-- rule: workflow\.md#([a-z0-9-]+) -->\s*$') { continue }
        $anchor = $Matches[1]
        $body = New-Object System.Collections.Generic.List[string]
        for ($j = $i + 1; $j -lt $Lines.Count -and $Lines[$j] -match '^>\s?(.*)$'; $j++) {
            $body.Add($Matches[1])
        }
        $quotes.Add([pscustomobject]@{ Anchor = $anchor; Line = $i + 1; Text = (ConvertTo-FlatText ($body -join ' ')) })
    }
    return , $quotes.ToArray()
}

# Every <a id="..."></a> anchor's own text: from that anchor to the next anchor of any kind, or
# the end of the file. A quote must match its own anchor's section, not merely appear somewhere
# else in the document under a different anchor.
function Get-AnchorSection {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    $anchorMatches = [regex]::Matches($Text, '<a id="([^"]+)"></a>')
    $sections = [ordered]@{}
    for ($i = 0; $i -lt $anchorMatches.Count; $i++) {
        $name = $anchorMatches[$i].Groups[1].Value
        # Start at the anchor's own line. An anchor embedded mid-line, such as inside a bullet's
        # "- <a id=...></a>text", would otherwise drop the "- " that precedes it.
        $start = $Text.LastIndexOf("`n", [Math]::Max(0, $anchorMatches[$i].Index - 1)) + 1
        $end = if ($i + 1 -lt $anchorMatches.Count) { $anchorMatches[$i + 1].Index } else { $Text.Length }
        $raw = $Text.Substring($start, $end - $start) -replace '<a id="[^"]*"></a>', ''
        $sections[$name] = ConvertTo-FlatText $raw
    }
    return $sections
}

# Top-level bullets under one '## ' heading, up to the next '#' or '##' heading.
function Get-SectionBullet {
    param([Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]] $Lines, [Parameter(Mandatory)][string] $Heading)
    $bullets = New-Object System.Collections.Generic.List[object]
    $start = [Array]::IndexOf($Lines, "## $Heading")
    if ($start -lt 0) { return , $bullets.ToArray() }
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^#{1,2}\s') { break }
        if ($Lines[$i] -match '^- ') { $bullets.Add([pscustomobject]@{ Line = $i + 1; Text = $Lines[$i] }) }
    }
    return , $bullets.ToArray()
}

$workflowText = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'docs/development/workflow.md'))
$workflowSection = Get-AnchorSection -Text $workflowText
$workflowAnchor = @($workflowSection.Keys)

$skillPath = Join-Path $repoRoot '.agents/handover-commands/SKILL.md'
# A missing skill is a failure the cases report, not a crash before them.
$skillLines = [string[]]@()
if (Test-Path -LiteralPath $skillPath) { $skillLines = [System.IO.File]::ReadAllLines($skillPath) }
$quotes = Get-RuleQuote -Lines $skillLines

$agentsLines = [System.IO.File]::ReadAllLines((Join-Path $repoRoot 'AGENTS.md'))
$bullets = Get-SectionBullet -Lines $agentsLines -Heading 'Commands and next steps'

Invoke-TestCase 'Every rule anchor exists in workflow.md, and none reads as a stage' {
    foreach ($anchor in $script:RuleAnchor) {
        Assert-True ($workflowAnchor -ccontains $anchor) "workflow.md has no <a id=`"$anchor`"></a>."
        Assert-True (-not $anchor.StartsWith('stage-')) "'$anchor' would be read as a stage."
    }
}

Invoke-TestCase 'A quote is checked against its own anchor''s section, not the whole document' {
    $fakeText = @"
<a id="anchor-a"></a>
- Section A text holds unique-marker-alpha, and nothing else.

<a id="anchor-b"></a>
- Section B text holds unique-marker-beta, and nothing else.
"@
    $sections = Get-AnchorSection -Text $fakeText
    Assert-True ($sections['anchor-a'].Contains('unique-marker-alpha', [System.StringComparison]::Ordinal)) `
        'Sanity check: section a must hold its own text.'
    Assert-True (-not $sections['anchor-b'].Contains('unique-marker-alpha', [System.StringComparison]::Ordinal)) `
        'A quote borrowed from another anchor''s section must not silently match a different one.'
}

Invoke-TestCase 'Every quote in the skill is still in workflow.md, word for word' {
    Assert-True ($quotes.Count -gt 0) "The skill holds no quote. Expected marker lines like <!-- rule: workflow.md#next-step-line -->."
    foreach ($quote in $quotes) {
        Assert-True ($quote.Text.Length -gt 0) "SKILL.md:$($quote.Line) has a marker with no blockquote below it."
        Assert-True ($workflowAnchor -ccontains $quote.Anchor) "SKILL.md:$($quote.Line) names #$($quote.Anchor), which workflow.md does not have."
        Assert-True ($workflowSection[$quote.Anchor].Contains($quote.Text, [System.StringComparison]::Ordinal)) `
            "SKILL.md:$($quote.Line) no longer matches its own section (#$($quote.Anchor)) in workflow.md. Quote: $($quote.Text.Substring(0, [Math]::Min(120, $quote.Text.Length)))"
    }
}

Invoke-TestCase 'The skill quotes every rule' {
    foreach ($anchor in $script:RuleAnchor) {
        Assert-True (@($quotes | Where-Object { $_.Anchor -ceq $anchor }).Count -gt 0) "The skill has no quote for #$anchor."
    }
}

Invoke-TestCase 'Every AGENTS.md line under Commands and next steps links to a live anchor' {
    Assert-True ($bullets.Count -gt 0) "AGENTS.md has no rule lines under '## Commands and next steps'."
    foreach ($bullet in $bullets) {
        $links = @([regex]::Matches($bullet.Text, 'docs/development/workflow\.md#([a-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value })
        Assert-True ($links.Count -gt 0) "AGENTS.md:$($bullet.Line) links to no rule in workflow.md."
        foreach ($link in $links) {
            Assert-True ($workflowAnchor -ccontains $link) "AGENTS.md:$($bullet.Line) links to #$link, which workflow.md does not have."
        }
    }
}

Invoke-TestCase 'AGENTS.md links every rule' {
    # The link target, not the link text: '[workflow.md#x](docs/development/workflow.md#y)' links to y.
    $linked = @($bullets | ForEach-Object { [regex]::Matches($_.Text, 'docs/development/workflow\.md#([a-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value } })
    foreach ($anchor in $script:RuleAnchor) {
        Assert-True ($linked -ccontains $anchor) "No AGENTS.md line links to #$anchor."
    }
}

Invoke-TestCase 'The skill description fits the 140-character cap' {
    # Measured the way scripts/agents/setup-cross-agent-skills.ps1 measures it: the raw value.
    $line = @($skillLines | Where-Object { $_ -match '^description:' }) | Select-Object -First 1
    Assert-True ($null -ne $line) 'The skill has no description line.'
    $description = ($line -replace '^description:\s*', '').Trim()
    Assert-True ($description.Length -le 140) "The description is $($description.Length) characters. The cap is 140."
}

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "FAILED: $($script:Failures.Count) test(s)" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'All handover rule tests passed.' -ForegroundColor Green
exit 0
