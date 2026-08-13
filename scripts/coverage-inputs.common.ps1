#Requires -Version 5.1
<#
.SYNOPSIS
  Name the test projects a coverage run must produce data for, and find the ones that did not.
.DESCRIPTION
  coverlet instruments every module in a test project's output folder at test-session start.
  When another process holds one of those modules open, instrumentation fails, coverlet writes
  no coverage file for that project, and dotnet test still exits 0. Backlog 082 measured this.

  The merged report then silently loses every assembly only that project covered, and the
  threshold gate calls it a coverage regression. This check catches the missing input first.

  The expected project list is derived, never hard-coded. dotnet sln list gives the projects
  the run covers. The coverlet.collector reference decides which of those can produce a
  coverage file.
#>

# dotnet sln list prints a 'Project(s)' header and a '----------' separator before the paths,
# and the paths are relative to the solution folder. The .csproj filter drops both header lines.
function Get-AhkFlowCoverageProject {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $solutionProjects = & dotnet sln $RepoRoot list
    if ($LASTEXITCODE -ne 0) { throw "dotnet sln list failed in $RepoRoot" }

    $projects = New-Object System.Collections.Generic.List[object]
    foreach ($line in $solutionProjects) {
        $relative = "$line".Trim()
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        if (-not $relative.EndsWith('.csproj', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $full = Join-Path $RepoRoot $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        $content = Get-Content -LiteralPath $full -Raw
        if ($content -notmatch 'coverlet\.collector') { continue }

        $projects.Add([pscustomobject]@{
                Name = [System.IO.Path]::GetFileNameWithoutExtension($full)
                Path = (Resolve-Path -LiteralPath $full).Path
            })
    }

    return @($projects | Sort-Object -Property Name)
}

function Get-AhkFlowMissingCoverageInput {
    param(
        [Parameter(Mandatory = $true)][string]$ResultsRoot,
        [Parameter(Mandatory = $true)][string[]]$ExpectedProjectName
    )

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($name in $ExpectedProjectName) {
        $folder = Join-Path $ResultsRoot $name
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            $missing.Add($name)
            continue
        }

        $produced = @(Get-ChildItem -LiteralPath $folder -Recurse -Filter 'coverage.cobertura.xml' -File -ErrorAction SilentlyContinue)
        if ($produced.Count -eq 0) { $missing.Add($name) }
    }

    return @($missing)
}
