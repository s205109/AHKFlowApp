#Requires -Version 7.0

# Backlog 133. A SQL-backed test that reaches a migration before the newest one must go through
# AHKFlowApp.TestUtilities.Fixtures.RunIndependentDatabase, which drops the database first. Against
# a database already at the newest migration, EF Core reads a target migration as a request to
# migrate down, and the HotkeyTypedActions migration refuses to revert. The reused test server
# makes that the normal state of a second run.
#
# Two routes reach a target migration, and both are matched:
#   1. IMigrator, resolved from the context's internal service provider.
#   2. The target overloads on DatabaseFacade: Migrate(String) and MigrateAsync(String).
#
# Every Migrate and MigrateAsync call in tests/ is parameterless today, and none passes a
# cancellation token, so the second rule is simply: any argument at all is a failure. That catches
# a target held in a variable or a const, not only a string literal, and it catches an argument
# written on the line after the open bracket.
#
# What it does not catch: a using alias that renames IMigrator, and reflection. Neither appears in
# this repository, and matching either would cost more than it is worth.
#
# Run it by hand with:  pwsh ./tests/RunIndependentSqlTests.Tests.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$failures = @()

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:failures += $Message }
}

# The one file allowed to name IMigrator, because it is the route every test goes through. It is
# matched by its whole path, not by its file name. A second file called RunIndependentDatabase.cs
# anywhere under tests/ would otherwise exempt itself from the rule.
$script:HelperPathSegments = @('AHKFlowApp.TestUtilities', 'Fixtures', 'RunIndependentDatabase.cs')
$script:HelperRelativePath = 'tests/' + ($script:HelperPathSegments -join '/')

# Every place in $Line that reaches a target migration, as 'line <n>: <trimmed text>'.
# Lines, not a path, so a fixture case needs no file on disk.
#
# The lines are joined and matched as one string, not one at a time. A call whose argument sits on
# the next line is ordinary C#:
#
#     await context.Database.MigrateAsync(
#         "Phase3HotkeyRebuild");
#
# A per-line match never sees that. Line one ends right after the open bracket, and line two holds
# no Migrate call at all. \s already matches a newline, so the same pattern reaches it once the
# file is one string. The line number is counted back from where the match starts, so the message
# still names a line somebody can open.
#
# AllowEmptyString and AllowEmptyCollection are both required. Mandatory on a [string[]] parameter
# rejects an array that holds an empty string, and Get-Content turns every blank line in a source
# file into one. Without them this function throws on 355 of the 391 test files in the tree.
function Get-TargetMigrationHit {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line
    )

    $text = $Line -join "`n"

    # 1. IMigrator by name, whatever it is used for.
    # 2. A dot, Migrate or MigrateAsync, an open bracket, then anything that is neither a close
    #    bracket nor whitespace. A parameterless call has nothing between the brackets, on one line
    #    or spread over several, so it never matches.
    $patterns = @('IMigrator', '\.Migrate(?:Async)?\s*\(\s*[^)\s]')

    $hits = @()
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($text, $pattern)) {
            $number = ($text.Substring(0, $match.Index) -split "`n").Count
            $hits += [pscustomobject]@{ Number = $number; Text = $Line[$number - 1].Trim() }
        }
    }

    # Sorted by line, so two patterns matching one file still read in file order. Unique, so a line
    # that carries both routes is reported once.
    return @($hits | Sort-Object -Property Number, Text -Unique |
        ForEach-Object { "line $($_.Number): $($_.Text)" })
}

# Every test source file, minus build output and minus the helper itself.
#
# A plain array, so 'foreach ($file in Get-TestSourceFile ...)' walks the files one at a time.
# 'return , @(...)' would hand the caller every file as a single item and the loop would run once.
# Callers that need .Count wrap the call in @() instead, which reads an empty result as zero.
function Get-TestSourceFile {
    param([Parameter(Mandatory)][string] $Root)

    $testsRoot = Join-Path $Root 'tests'
    if (-not (Test-Path -LiteralPath $testsRoot)) { return @() }

    $helperFullPath = $testsRoot
    foreach ($segment in $script:HelperPathSegments) {
        $helperFullPath = Join-Path $helperFullPath $segment
    }

    return @(Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter '*.cs' |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
        Where-Object { $_.FullName -ne $helperFullPath })
}

# --- fixture cases: the matcher itself -----------------------------------------------------

# Every call is wrapped in @(). The functions return plain arrays, so an empty result reaches the
# caller as nothing at all, and $null.Count throws under Set-StrictMode rather than reading as zero.

# 1. IMigrator by name is a hit, whatever it is used for.
$hits = @(Get-TargetMigrationHit -Line @(
    'IMigrator migrator = ((IInfrastructure<IServiceProvider>)setup).Instance.GetRequiredService<IMigrator>();'
))
Assert-True ($hits.Count -eq 1) "IMigrator should be a hit, got: $($hits -join ' | ')"

# 2. A target migration as a string literal on the DatabaseFacade overload is a hit. This is the
#    route the design found second, and the route no IMigrator match would ever see.
$hits = @(Get-TargetMigrationHit -Line @('await context.Database.MigrateAsync("RawHotstringKind");'))
Assert-True ($hits.Count -eq 1) "A literal target should be a hit, got: $($hits -join ' | ')"

# 3. THE GAP THE DESIGN LEFT OPEN. A target held in a const or a variable is still an argument, so
#    it is still a hit. A matcher that looked for a quoted string would miss this one.
$hits = @(Get-TargetMigrationHit -Line @('await context.Database.MigrateAsync(TargetMigration);'))
Assert-True ($hits.Count -eq 1) "A variable target should be a hit, got: $($hits -join ' | ')"

# 4. The synchronous overload counts too.
$hits = @(Get-TargetMigrationHit -Line @('context.Database.Migrate("Phase3HotkeyRebuild");'))
Assert-True ($hits.Count -eq 1) "The synchronous overload should be a hit, got: $($hits -join ' | ')"

# 5. A target on the line after the open bracket is a hit. This needs no alias and no reflection,
#    so it is the cheapest bypass there is, and a matcher that read one line at a time missed it.
$hits = @(Get-TargetMigrationHit -Line @(
    'await context.Database.MigrateAsync('
    '    "Phase3HotkeyRebuild");'
))
Assert-True ($hits.Count -eq 1 -and $hits[0].StartsWith('line 1:')) `
    "A target on the next line should be a hit on line 1, got: $($hits -join ' | ')"

# 6. Migrating to the newest migration stays allowed. It is what the correct tests already do, and
#    it is a no-op on a database that is already there.
$hits = @(Get-TargetMigrationHit -Line @(
    'await context.Database.MigrateAsync();'
    'await write.Database.MigrateAsync();'
))
Assert-True ($hits.Count -eq 0) "A parameterless call must be allowed, got: $($hits -join ' | ')"

# 7. And it stays allowed when it is wrapped over two lines. Case 5 must not have bought its reach
#    by failing every wrapped call.
$hits = @(Get-TargetMigrationHit -Line @(
    'await context.Database.MigrateAsync('
    ');'
))
Assert-True ($hits.Count -eq 0) "A wrapped parameterless call must be allowed, got: $($hits -join ' | ')"

# 8. The helper's own name is not a hit. Tests are supposed to call it.
$hits = @(Get-TargetMigrationHit -Line @(
    'await RunIndependentDatabase.DropThenMigrateToAsync(setup, "AddHotstringDelivery");'
    'await RunIndependentDatabase.DropAsync(context);'
))
Assert-True ($hits.Count -eq 0) "The helper must not be a hit, got: $($hits -join ' | ')"

# 9. The line number reported is the line the bypass is on, so the message can be acted on.
$hits = @(Get-TargetMigrationHit -Line @(
    'await context.Database.MigrateAsync();'
    'IMigrator migrator = context.GetService<IMigrator>();'
))
Assert-True ($hits.Count -eq 1 -and $hits[0].StartsWith('line 2:')) `
    "The hit should name line 2, got: $($hits -join ' | ')"

# 10. A blank line does not stop the scan. Mandatory on a [string[]] parameter rejects an array
#     holding an empty string, and Get-Content produces one for every blank line in a source file.
#     Without AllowEmptyString the real-tree scan below throws on almost every file it opens.
$hits = @(Get-TargetMigrationHit -Line @('using Xunit;', '', 'public class A { }'))
Assert-True ($hits.Count -eq 0) "A file with a blank line must scan cleanly, got: $($hits -join ' | ')"

# --- the real tree ---------------------------------------------------------------------------

# 11. Every test source file is opened, one at a time. A file enumerator that returned every file
#     as one item would run this loop once and report nothing, so the count is asserted first.
$sourceFile = @(Get-TestSourceFile -Root $repoRoot)
Assert-True ($sourceFile.Count -gt 100) `
    "The scan should find the whole test tree, got $($sourceFile.Count) file(s)."

$scanned = 0
$offender = @()
foreach ($file in Get-TestSourceFile -Root $repoRoot) {
    $scanned++
    $hits = @(Get-TargetMigrationHit -Line @(Get-Content -LiteralPath $file.FullName))
    if ($hits.Count -gt 0) {
        $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
        $offender += "$relative -> $($hits -join ' | ')"
    }
}
Assert-True ($scanned -eq $sourceFile.Count) `
    "The loop should walk every file: found $($sourceFile.Count), walked $scanned."

# 12. No test file bypasses the helper. This is the rule; everything above proves the matcher can
#     tell the difference, and that the scan actually reaches every file.
Assert-True ($offender.Count -eq 0) `
    ("A test must reach a target migration through RunIndependentDatabase, not directly: " +
     ($offender -join ' ;; '))

# 13. The helper file itself exists, at the exact path the exemption points at. A rename that left
#     this suite behind would exempt nothing and fail case 12 instead, which is confusing.
$helperPath = Join-Path $repoRoot $script:HelperRelativePath
Assert-True (Test-Path -LiteralPath $helperPath) `
    "The helper must live at $script:HelperRelativePath."

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host ''
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    Write-Host ''
    throw "Run-independent SQL test rules failed with $($failures.Count) problem(s). See the detail above."
}

Write-Host "Run-independent SQL test rules passed. 13 cases, $scanned files scanned."
