#Requires -Version 5.1
<#
.SYNOPSIS
TEMPORARY. Proves the powershell-suites CI job goes red when a suite fails.

.DESCRIPTION
Backlog 066 asks for a one-time proof that the job now fails, and that the suites after the failing
one still run. This file exists for exactly one CI run and is removed in the next commit.

It sorts between CiPowerShellSuiteRunner and PreCommitAntiPatternHook, so a dozen suites follow it.
Their rows in the job summary are the proof that the run did not stop here.
#>
[CmdletBinding()]
param()

Write-Host 'Deliberate CI proof failure.'
exit 1
