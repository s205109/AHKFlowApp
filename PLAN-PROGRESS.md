# Plan progress - backlog 070. Draft PR: https://github.com/s205109/AHKFlowApp/pull/297
Plan: docs/superpowers/plans/2026-08-13-personal-defaults-sync-marker-plan.md
Task 1 | a28c9a8 | checks: suite red without the common script, green with it; green under pwsh 7 and Windows PowerShell 5.1 | deferrals: none
Task 2 | 3be3ec3 | checks: real file stamped (body-sha256=25e3ce18...); appending a line to the body fails the suite with "still records the old body hash", restore turns it green; update script idempotent on a second run | deferrals: the paste into the web box is the user's step, still open
Task 3 | 7059cd0 | checks: three cited paths exist, AGENTS.md subsection sits under Agent skills | deferrals: none
Task 4 (simplify) | 8a7b0a8 | checks: New-Fixture registers its own fixture, suite green on both hosts, no leftover temp files | deferrals: none

Recovery task R1 - fix the line-endings case for a CRLF checkout.
Failing command: CI job powershell-suites, run 31706878126 job 94469546693.
Output: "Line endings: the LF body hashes to c3133e27... and the CRLF body to 868abfe5... They must agree."
Cause: tests/PersonalDefaultsSyncMarker.Tests.ps1:152 builds the CRLF variant with -replace "`n","`r`n".
CI checks out .ps1 with CRLF, so the here-string is already CRLF and the replace makes "`r`r`n".
Fix: normalize the sample to LF first, then build the CRLF variant from it.
