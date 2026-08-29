#Requires -Version 5.1
# Decides whether the pre-push hook can check the private plans repository.
#
# This lives in its own file so a test can ask the question with a fixture path. The alternative -
# hiding the real docs/superpowers for the length of a test - is refused: every worktree links to
# that folder (`docs/development/workflow.md:753`, "Two paths stay refused").
#
# It declares 5.1 because .githooks/pre-push falls back to Windows PowerShell when pwsh is absent
# (`.githooks/pre-push:10-11`, "command -v powershell"), and pre-push-quick-checks.ps1 dot-sources
# this file.

function Get-PlansCitationScanPlan {
    param(
        [Parameter(Mandatory)][string] $PlansRoot,
        [string] $PwshPath
    )

    # A worktree links the plans repository in, so .git may be a file rather than a folder.
    if (-not (Test-Path -LiteralPath (Join-Path $PlansRoot '.git'))) {
        return [pscustomobject]@{
            Action = 'SkipNoRepository'
            Reason = 'Skipped: docs/superpowers is not a git repository in this checkout.'
        }
    }

    if (-not $PwshPath) {
        return [pscustomobject]@{
            Action = 'SkipNoPwsh'
            Reason = 'Skipped: pwsh 7 was not found on PATH, and the citation check needs it.'
        }
    }

    return [pscustomobject]@{ Action = 'Run'; Reason = '' }
}
