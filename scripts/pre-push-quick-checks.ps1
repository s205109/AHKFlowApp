#Requires -Version 5.1
<#
.SYNOPSIS
  Fast fail-fast pre-push checks: incremental build + container-free unit tests.
.DESCRIPTION
  Called by .githooks/pre-push.ps1. CI runs the full coverage + format gate on every PR with a
  changed path that .github/code-paths-filter.yml does not exclude, so this script deliberately
  skips coverage collection and testcontainers to stay fast.
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\Common.ps1"

$skipHint = "CI runs the full coverage + format gate on this PR when a changed path is not excluded by .github/code-paths-filter.yml. Skip locally with: SKIP_PUSH_HOOK=1 git push  (or: git push --no-verify)"

Push-Location $repoRoot
try {
    Write-Step "Building solution ($Configuration)"
    & dotnet build --configuration $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed. $skipHint"
    }
    Write-Success 'Build succeeded.'

    Write-Step 'Running fast test slice'
    try {
        & (Join-Path $PSScriptRoot 'test-fast.ps1') -Mode Fast -Configuration $Configuration -NoBuild
        if ($LASTEXITCODE -ne 0) {
            throw "Fast test slice failed."
        }
    }
    catch {
        throw "Fast test slice failed. $skipHint"
    }
    Write-Success 'Fast test slice passed.'

    # The private plans repository holds most of this project's citations, and CI never sees it:
    # (`.gitignore:473`, "docs/superpowers") ignores it. Pre-push is the only gate that can reach it.
    #
    # Tiers 1 and 2 only. Tier 3 would force a quoted phrase on every citation in a new plan, and
    # the largest plan carries 65 of them.
    Write-Step 'Checking citations in the private plans repository'
    . "$PSScriptRoot\plans-citation-scan.common.ps1"

    $plansRoot = Join-Path $repoRoot 'docs/superpowers'
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { '' }
    $scanPlan = Get-PlansCitationScanPlan -PlansRoot $plansRoot -PwshPath $pwshPath

    # The plans repository is one shared working tree with a single branch, linked into every
    # worktree. So a whole-repository scan reads plans another branch is part-way through writing,
    # whose citations resolve against that branch's files and not against these. Measured on
    # 2026-08-21: the same plans scored 82 problems from one worktree and 104 from another, and the
    # second worktree saw zero problems in the very plan the first saw twenty in. No line number is
    # right in both trees, so no repair can make a whole-repository scan green for everybody.
    #
    # A branch owns the plans whose number matches a backlog item it adds or edits. Everything else
    # is somebody else's in-flight work. Shipped plans are frozen instead, which is
    # branch-independent - see check-archived-plan-frozen.ps1. That is backlog 112.
    # Compare against the merge base, never against the moving origin/main tip. A tip comparison
    # is two-way: it also reports every backlog file main gained since this branch left. Measured
    # on 2026-08-22, after a day of merges, that turned this branch's 2 owned numbers into 10.
    $mergeBase = & git -C $repoRoot merge-base HEAD origin/main
    if ($LASTEXITCODE -ne 0 -or -not $mergeBase) {
        throw "Could not resolve the merge base with origin/main, so which plans this branch owns is unknown. Fetch the remote and retry. $skipHint"
    }

    $backlogDiff = & git -C $repoRoot diff --name-only ([string] $mergeBase).Trim() -- backlog
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the backlog diff against the merge base, so which plans this branch owns is unknown. $skipHint"
    }

    # Fail closed on both commands above. Leaving $ownedPlan empty would print 'No plan on this
    # branch' and pass, so a broken remote ref would silently switch the whole check off.
    $ownedPlan = @()
    $numbers = @($backlogDiff |
        ForEach-Object { if ($_ -match '/(\d{3})-') { $Matches[1] } } |
        Sort-Object -Unique)
    foreach ($number in $numbers) {
        foreach ($sub in @('plans', 'specs')) {
            $folder = Join-Path $plansRoot $sub
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            foreach ($hit in (Get-ChildItem -LiteralPath $folder -Filter "*-$number.md" -File)) {
                $ownedPlan += ('{0}/{1}' -f $sub, $hit.Name)
            }
        }
    }

    if ($scanPlan.Action -ne 'Run') {
        Write-Host $scanPlan.Reason
    }
    elseif ($ownedPlan.Count -eq 0) {
        Write-Host 'No plan on this branch: nothing to check.'
    }
    else {
        Write-Host ("Checking {0}: {1}" -f $ownedPlan.Count, ($ownedPlan -join ', '))

        # The list goes through a file, not the command line. `pwsh -File` cannot carry an array:
        # with two paths the second binds to the wrong parameter and is dropped without a word,
        # and with three the child process dies on "A positional parameter cannot be found".
        $manifest = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $manifest -Value $ownedPlan -Encoding utf8
            & $pwshPath -NoProfile -File (Join-Path $PSScriptRoot 'check-citation-freshness.ps1') `
                -ScanRoot $plansRoot -ResolveRoot $repoRoot -NoAdoptionTier -OnlyPathFile $manifest
            if ($LASTEXITCODE -ne 0) {
                throw "This branch's plan citations failed. $skipHint"
            }
        }
        finally {
            Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
        }

        Write-Success 'This branch''s plan citations passed.'
    }

    # A plan that transcribes the stage machine is a second normative source, and reviews of
    # backlog 071 found it drifted three rounds running. CI cannot check it for the same reason
    # as above, so pre-push is where the real plans meet the source. tests/PlanWorkflowParity.Tests.ps1
    # covers the checker itself against fixtures, which is the half CI can run.
    Write-Step 'Checking the plans against the source'
    if ($scanPlan.Action -ne 'Run') {
        Write-Host $scanPlan.Reason
    }
    else {
        # -RequirePlans, because here the plans repository is in the checkout. Without it a
        # discovery that finds no Appendix A exits 0, and this step printed 'Plans agree with
        # the source' having compared nothing at all.
        & $pwshPath -NoProfile -File (Join-Path $PSScriptRoot 'check-plan-workflow-parity.ps1') `
            -PlansRoot (Join-Path $plansRoot 'plans') -RequirePlans
        if ($LASTEXITCODE -ne 0) {
            throw "A plan's Appendix A disagrees with workflow.md, or no plan carries one. $skipHint"
        }
        Write-Success 'Plans agree with the source.'
    }

    # Stage 9 freezes a shipped plan against the citation check. Nothing else can check that it
    # happened: CI cannot see the plans repository, and the citation check itself only reports the
    # rot, never the missing freeze. Without this step the archive fills with re-audited history
    # again, one shipped item at a time - which is how backlog 112 started, with 52 stale citations
    # across 18 shipped files. tests/ArchivedPlanFrozen.Tests.ps1 covers the rule against fixtures,
    # which is the half CI can run.
    Write-Step 'Checking that shipped plans are frozen'
    if ($scanPlan.Action -ne 'Run') {
        Write-Host $scanPlan.Reason
    }
    else {
        & $pwshPath -NoProfile -File (Join-Path $PSScriptRoot 'check-archived-plan-frozen.ps1')
        if ($LASTEXITCODE -ne 0) {
            throw "A shipped plan or spec is still open to the citation check. $skipHint"
        }
        Write-Success 'Shipped plans are frozen.'
    }
}
finally {
    Pop-Location
}

Write-Success 'Pre-push quick checks passed.'
