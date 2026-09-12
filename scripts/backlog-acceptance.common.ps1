#Requires -Version 7.0
# Backlog 151. Counts the Acceptance boxes in a backlog item.
#
# An Acceptance box is one '- [ ]' or '- [x]' line inside the item's '## Acceptance criteria'
# section. CONTEXT.md pins the term. Four rules, each forced by a real item rather than by taste:
#
#   - Scope to the section. Backlog 072 carries checkboxes under '## Friction baselines' and one
#     of them is unticked. Counting every box in the file would never call backlog 072 finished.
#   - A '###' subheading does not end the section. Backlog 121 and backlog 122 group their
#     criteria under '###' subheadings, and those boxes are real Acceptance boxes.
#   - Column zero only. No item in the backlog indents a checkbox inside its acceptance section,
#     and an indented line is a detail under a criterion, not a criterion.
#   - Skip fenced code. Backlog 132's acceptance section holds a code fence. No fence carries a
#     checkbox today, but a command example easily could.
#
# This file holds no git and reads no files, so a test can drive it straight against text.

Set-StrictMode -Version Latest

function Get-AcceptanceBoxCount {
    param([string[]] $Lines)

    $total = 0
    $ticked = 0
    if ($null -eq $Lines) {
        return [pscustomobject]@{ Total = $total; Ticked = $ticked }
    }

    $inSection = $false
    $inFence = $false

    foreach ($line in $Lines) {
        if ($null -eq $line) { continue }

        # A fence toggles wherever it appears. Tracked outside the section too, so a fence opened
        # earlier in the item cannot leave the counter thinking it is still inside one.
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }

        # Only '##' opens or closes the section. '###' is a group inside it.
        if ($line -match '^## ') {
            $inSection = $line -match '^##\s+Acceptance criteria\s*$'
            continue
        }

        if (-not $inSection) { continue }

        if ($line -match '^- \[(?<mark>[ xX])\] ') {
            $total++
            if ($Matches.mark -ne ' ') { $ticked++ }
        }
    }

    return [pscustomobject]@{ Total = $total; Ticked = $ticked }
}
