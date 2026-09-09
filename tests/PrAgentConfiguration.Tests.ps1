#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$expectedImage = 'uses: docker://pragent/pr-agent@sha256:548b760b81ab4b3f729182428695ccc1194bbf87528c2b1e2b2b07e5223af7b6'

$expectedConfig = @{
    'config.restricted_mode' = 'true'
    'config.custom_model_max_tokens' = '262144'
    'config.max_model_tokens' = '64000'
    'pr_reviewer.require_security_review' = 'true'
    'pr_reviewer.require_tests_review' = 'true'
    'pr_reviewer.require_estimate_effort_to_review' = 'false'
    'pr_reviewer.persistent_comment' = 'true'
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

# The only keys checked by name rather than by value. Both hold a multi-line
# string, so the value on the key line is just the opening delimiter and says
# nothing. $requiredInstructions below checks what those two strings must say.
# Every other approved key lives in $expectedConfig with its exact value, so a
# changed value fails. A key in neither place is a typo or a setting nobody
# approved. Docker is not available on every machine that runs this suite, so
# these lists are how the repository rejects drift without the pinned image.
$allowedExtraKeys = [System.Collections.Generic.HashSet[string]]::new(
    [string[]] @(
        'pr_reviewer.extra_instructions'
        'pr_code_suggestions.extra_instructions'
    ),
    [StringComparer]::Ordinal)

# Sentences the instruction blocks must keep. The evidence rules exist because
# an earlier review claimed a defect in unchanged code it could not see.
$requiredInstructions = @(
    'Report only defects introduced or exposed by this pull request.'
    'For every finding, state the concrete failure path and the supplied evidence that proves it.'
    'Treat unchanged code outside the supplied context as unknown.'
    'Return no finding when its evidence is incomplete.'
    'Report at most 5 findings, ordered by severity.'
    'Each suggestion must apply to changed lines only.'
    'Do not suggest new files, new tests, or refactors that span files.'
)

# Reads the subset of TOML this repository writes. TOML allows a bare key, a key
# in double quotes, and a key in single quotes, and all three set the same
# setting. Read every form, so quoting cannot hide an unsupported setting. A
# line this reader cannot understand becomes a failure rather than a silent skip.
function ConvertTo-PrAgentSetting {
    param([string] $ConfigText)

    $sections = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $settings = @{}
    $problems = [System.Collections.Generic.List[string]]::new()
    $currentSection = $null
    $openDelimiter = $null

    foreach ($line in $ConfigText -split '\r?\n') {
        # Text inside a multi-line string is instruction prose, not settings.
        if ($null -ne $openDelimiter) {
            if ($line.IndexOf($openDelimiter, [StringComparison]::Ordinal) -ge 0) {
                $openDelimiter = $null
            }

            continue
        }

        if ($line -match '^\s*(#.*)?$') {
            continue
        }

        if ($line -match '^\s*\[(?<section>[^\]]+)\]\s*(?:#.*)?$') {
            $currentSection = $Matches.section

            # TOML forbids declaring a table twice, and the pinned image reads
            # this file with Python tomllib, which raises on the second one.
            # PR-Agent then runs no command at all, so reject it here.
            if (-not $sections.Add($currentSection)) {
                $problems.Add("Duplicate PR-Agent section: [$currentSection]")
            }

            continue
        }

        if ($line -match '^\s*(?<key>"[^"]*"|''[^'']*''|[A-Za-z0-9_-]+)\s*=\s*(?<value>.*)$') {
            $key = $Matches.key
            $value = $Matches.value.Trim()

            if ($key.Length -ge 2 -and ($key[0] -eq '"' -or $key[0] -eq "'")) {
                $key = $key.Substring(1, $key.Length - 2)
            }

            if ($null -eq $currentSection) {
                $problems.Add("PR-Agent setting outside any section: $key")
                continue
            }

            $fullKey = "$currentSection.$key"

            # Same reason as a duplicate section: tomllib refuses to overwrite a
            # value, so a repeated key stops every PR-Agent command.
            if ($settings.ContainsKey($fullKey)) {
                $problems.Add("Duplicate PR-Agent setting: $fullKey")
            }

            $settings[$fullKey] = $value

            foreach ($delimiter in @("'''", '"""')) {
                if (-not $value.StartsWith($delimiter, [StringComparison]::Ordinal)) {
                    continue
                }

                # The opening delimiter is the start of the value, so look for a
                # closing one after it. No closing one means the string runs on.
                if ($value.IndexOf($delimiter, $delimiter.Length, [StringComparison]::Ordinal) -lt 0) {
                    $openDelimiter = $delimiter
                }

                break
            }

            continue
        }

        $problems.Add("Cannot read PR-Agent configuration line: $($line.Trim())")
    }

    if ($null -ne $openDelimiter) {
        $problems.Add("PR-Agent configuration ends inside an unterminated $openDelimiter string.")
    }

    return [pscustomobject] @{
        Sections = $sections
        Settings = $settings
        Problems = $problems
    }
}

function Get-PrAgentPolicyFailure {
    param(
        [string] $ConfigText,
        [string] $WorkflowText
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $parsed = ConvertTo-PrAgentSetting -ConfigText $ConfigText

    foreach ($problem in $parsed.Problems) {
        $failures.Add($problem)
    }

    foreach ($section in @('config', 'openrouter', 'pr_reviewer', 'pr_code_suggestions')) {
        if (-not $parsed.Sections.Contains($section)) {
            $failures.Add("Missing PR-Agent section: [$section]")
        }
    }

    foreach ($key in $parsed.Settings.Keys) {
        if (-not $expectedConfig.ContainsKey($key) -and -not $allowedExtraKeys.Contains($key)) {
            $failures.Add("Unsupported PR-Agent setting: $key")
        }
    }

    foreach ($setting in $expectedConfig.GetEnumerator()) {
        if (-not $parsed.Settings.ContainsKey($setting.Key) -or $parsed.Settings[$setting.Key] -ne $setting.Value) {
            $failures.Add("Expected $($setting.Key) = $($setting.Value)")
        }
    }

    foreach ($instruction in $requiredInstructions) {
        if ($ConfigText.IndexOf($instruction, [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("The reviewer instructions must contain: $instruction")
        }
    }

    if ($WorkflowText.IndexOf($expectedImage, [StringComparison]::Ordinal) -lt 0) {
        $failures.Add('The workflow must pin PR-Agent 0.45.0 by its verified digest.')
    }

    if ($WorkflowText.IndexOf('timeout-minutes: 20', [StringComparison]::Ordinal) -lt 0) {
        $failures.Add('The PR-Agent step must keep its 20-minute cap.')
    }

    if ($WorkflowText.IndexOf('Report an unfinished review', [StringComparison]::Ordinal) -lt 0) {
        $failures.Add('The workflow must retain its unfinished-review reporter.')
    }

    return $failures
}

$config = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.pr_agent.toml'))
$workflow = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.github/workflows/pr-agent.yml'))

$quotedKey = '"publish_error_details" = true' + "`n" + 'num_max_findings = 5'
$singleQuotedKey = "'publish_error_details' = true" + "`n" + 'num_max_findings = 5'
$bareKey = 'publish_error_details = true' + "`n" + 'num_max_findings = 5'
$dottedKey = 'pr_reviewer.publish_error_details = true' + "`n" + 'num_max_findings = 5'
$instructionWithEquals = 'Do not invent issues.' + "`n" + 'Prefer count = 0 over a null check.'

# Each case mutates the committed files, so a case proves the check reacts to
# one real drift. Expect is the text the failure list must contain. A case with
# no Expect must produce no failure at all.
$cases = @(
    @{
        Name = 'A quoted unsupported setting is rejected'
        Config = $config.Replace('num_max_findings = 5', $quotedKey)
        Expect = 'Unsupported PR-Agent setting: pr_reviewer.publish_error_details'
    }
    @{
        Name = 'A single-quoted unsupported setting is rejected'
        Config = $config.Replace('num_max_findings = 5', $singleQuotedKey)
        Expect = 'Unsupported PR-Agent setting: pr_reviewer.publish_error_details'
    }
    @{
        Name = 'A bare unsupported setting is rejected'
        Config = $config.Replace('num_max_findings = 5', $bareKey)
        Expect = 'Unsupported PR-Agent setting: pr_reviewer.publish_error_details'
    }
    @{
        Name = 'A dotted key is rejected as unreadable syntax'
        Config = $config.Replace('num_max_findings = 5', $dottedKey)
        Expect = 'Cannot read PR-Agent configuration line: pr_reviewer.publish_error_details = true'
    }
    @{
        Name = 'A section typo is rejected'
        Config = $config.Replace('[pr_reviewer]', '[pr_reviewers]')
        Expect = 'Missing PR-Agent section: [pr_reviewer]'
    }
    @{
        Name = 'A changed model is rejected'
        Config = $config.Replace('model = "openrouter/pareto-code"', 'model = "openrouter/deepseek/deepseek-v4-flash-0731"')
        Expect = 'Expected config.model = "openrouter/pareto-code"'
    }
    @{
        Name = 'A lowered suggestion threshold is rejected'
        Config = $config.Replace('dual_publishing_score_threshold = 8', 'dual_publishing_score_threshold = 5')
        Expect = 'Expected pr_code_suggestions.dual_publishing_score_threshold = 8'
    }
    @{
        Name = 'An older image digest is rejected'
        Workflow = $workflow.Replace('sha256:548b760b81ab4b3f729182428695ccc1194bbf87528c2b1e2b2b07e5223af7b6', 'sha256:ec267eb168375c150d75efc024e2b10e0e2768ad0c000f15fd2378fe63abfe98')
        Expect = 'The workflow must pin PR-Agent 0.45.0 by its verified digest.'
    }
    @{
        Name = 'A raised step timeout is rejected'
        Workflow = $workflow.Replace('timeout-minutes: 20', 'timeout-minutes: 30')
        Expect = 'The PR-Agent step must keep its 20-minute cap.'
    }
    @{
        Name = 'A disabled restricted mode is rejected'
        Config = $config.Replace('restricted_mode = true', 'restricted_mode = false')
        Expect = 'Expected config.restricted_mode = true'
    }
    @{
        Name = 'A disabled security review is rejected'
        Config = $config.Replace('require_security_review = true', 'require_security_review = false')
        Expect = 'Expected pr_reviewer.require_security_review = true'
    }
    @{
        Name = 'A raised input token cap is rejected'
        Config = $config.Replace('max_model_tokens = 64000', 'max_model_tokens = 128000')
        Expect = 'Expected config.max_model_tokens = 64000'
    }
    @{
        Name = 'Dropped evidence instructions are rejected'
        Config = $config.Replace('Treat unchanged code outside the supplied context as unknown.', 'Use your judgement.')
        Expect = 'The reviewer instructions must contain: Treat unchanged code outside the supplied context as unknown.'
    }
    @{
        Name = 'A duplicate section is rejected'
        Config = $config + "`n[config]`n"
        Expect = 'Duplicate PR-Agent section: [config]'
    }
    @{
        Name = 'A duplicate setting is rejected'
        Config = $config.Replace('model = "openrouter/pareto-code"', "model = `"openrouter/pareto-code`"`nmodel = `"openrouter/pareto-code`"")
        Expect = 'Duplicate PR-Agent setting: config.model'
    }
    @{
        Name = 'Instruction text holding an equals sign is not read as a setting'
        Config = $config.Replace('Do not invent issues.', $instructionWithEquals)
        Expect = $null
    }
)

$failures = [System.Collections.Generic.List[string]]::new()
$caseCount = 0

foreach ($case in $cases) {
    $caseCount++
    $caseConfig = if ($case.ContainsKey('Config')) { $case.Config } else { $config }
    $caseWorkflow = if ($case.ContainsKey('Workflow')) { $case.Workflow } else { $workflow }
    $result = @(Get-PrAgentPolicyFailure -ConfigText $caseConfig -WorkflowText $caseWorkflow)

    if ($null -eq $case.Expect) {
        if ($result.Count -gt 0) {
            $failures.Add("Case '$($case.Name)' expected no failure, got: $($result -join ' | ')")
        }

        continue
    }

    if ($result -notcontains $case.Expect) {
        $failures.Add("Case '$($case.Name)' expected the failure '$($case.Expect)', got: $($result -join ' | ')")
    }
}

foreach ($failure in Get-PrAgentPolicyFailure -ConfigText $config -WorkflowText $workflow) {
    $failures.Add($failure)
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host "PASS: PR-Agent configuration matches the approved review policy. $caseCount drift case(s) checked." -ForegroundColor Green
