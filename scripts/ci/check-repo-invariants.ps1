#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the repository-invariant suites, so ci.yml can gate the expensive jobs on them and still
    finish inside two minutes.

.DESCRIPTION
    Backlog 121. A duplicate backlog number, filed on one branch and unseen on another, used to
    fail CI only after the slowest job had run for minutes. The repo-invariants job runs the cheap
    suites that check repository invariants first, and every other job waits on it.

    Backlog 127. This script used to keep its own list of the five suite names and its own parallel
    loop. That was a second copy of a list tests/powershell-suites.json already holds, and two
    lists drift. The manifest is now the one record: an entry belongs to this job when its "jobs"
    array names "invariants". So this script does one thing - it calls the runner and asks for that
    job - and adding a suite to the job is a one-line manifest edit with nothing to keep in step.

    Do not add -Suite here. -Job invariants means exactly the manifest's invariants set; a -Suite
    filter beside it would narrow that set, and a suite silently skipped is the failure this
    repository has already paid for once. tests/RepoInvariantsCiJob.Tests.ps1 reads this
    invocation and fails when it names anything else.

    The runner still gives every suite its own process, still runs them in parallel, and still runs
    all of them even after one fails, so one run lists every broken invariant.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A plain assignment to this variable is safe on every PowerShell version; only a read of it
# throws under Set-StrictMode before 7.3. run-powershell-suites.ps1 sets it the same way.
$PSNativeCommandUseErrorActionPreference = $false

$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-powershell-suites.ps1'

& $runner -Job 'invariants'

# The runner ends with an explicit exit, so its code reaches this scope in $LASTEXITCODE. Pass it
# through unchanged: a suite that failed must fail this job.
exit $LASTEXITCODE
