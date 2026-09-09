#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contains {
    param(
        [string] $Text,
        [string] $Expected,
        [string] $Message
    )

    if ($Text.IndexOf($Expected, [StringComparison]::Ordinal) -lt 0) {
        $script:failures.Add($Message)
    }
}

$config = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.pr_agent.toml'))
$workflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.github/workflows/pr-agent.yml'))

$sections = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$settings = @{}
$currentSection = $null

foreach ($line in $config -split '\r?\n') {
    if ($line -match '^\s*\[(?<section>[^\]]+)\]\s*(?:#.*)?$') {
        $currentSection = $Matches.section
        [void] $sections.Add($currentSection)
        continue
    }

    if ($null -ne $currentSection -and $line -match '^\s*(?<key>[A-Za-z0-9_]+)\s*=\s*(?<value>.*)$') {
        $settings["$currentSection.$($Matches.key)"] = $Matches.value.Trim()
    }
}

$expectedConfig = @{
    'config.model' = '"openrouter/pareto-code"'
    'config.fallback_models' = '["openrouter/tencent/hy3"]'
    'config.retry_same_model_on_timeout' = 'false'
    'config.output_run_details' = 'true'
    'config.output_run_cost' = 'true'
    'config.persistent_inline_comments' = 'true'
    'openrouter.max_tokens' = '16000'
    'pr_reviewer.require_risk_assessment' = 'true'
    'pr_reviewer.require_merge_recommendation' = 'true'
    'pr_reviewer.require_priority_files' = 'true'
    'pr_reviewer.persistent_finding_state' = 'true'
    'pr_reviewer.num_max_findings' = '5'
    'pr_code_suggestions.commitable_code_suggestions' = 'false'
    'pr_code_suggestions.dual_publishing_score_threshold' = '8'
}

foreach ($section in @('config', 'openrouter', 'pr_reviewer', 'pr_code_suggestions')) {
    if (-not $sections.Contains($section)) {
        $failures.Add("Missing PR-Agent section: [$section]")
    }
}

foreach ($setting in $expectedConfig.GetEnumerator()) {
    if (-not $settings.ContainsKey($setting.Key) -or $settings[$setting.Key] -ne $setting.Value) {
        $failures.Add("Expected $($setting.Key) = $($setting.Value)")
    }
}

$image = 'uses: docker://pragent/pr-agent@sha256:548b760b81ab4b3f729182428695ccc1194bbf87528c2b1e2b2b07e5223af7b6'
Assert-Contains -Text $workflow -Expected $image -Message 'The workflow must pin PR-Agent 0.45.0 by its verified digest.'
Assert-Contains -Text $workflow -Expected 'timeout-minutes: 20' -Message 'The PR-Agent step must keep its 20-minute cap.'
Assert-Contains -Text $workflow -Expected 'Report an unfinished review' -Message 'The workflow must retain its unfinished-review reporter.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'PASS: PR-Agent configuration matches the approved review policy.' -ForegroundColor Green
