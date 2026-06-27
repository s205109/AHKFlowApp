#Requires -Version 5.1

$script:AhkFlowTestSqlImage = 'mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04'
$script:AhkFlowTestSqlPassword = 'AHKFlow!Test_2026'

function Start-AhkFlowTestSqlContainer {
    [CmdletBinding()]
    param()

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'docker command not found. Install/start Docker Desktop before running SQL-backed tests.'
    }

    $containerName = "ahkflow-testsql-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $arguments = @(
        'run',
        '--detach',
        '--name',
        $containerName,
        '--env',
        'ACCEPT_EULA=Y',
        '--env',
        "MSSQL_SA_PASSWORD=$script:AhkFlowTestSqlPassword",
        '--env',
        'MSSQL_PID=Developer',
        '--publish',
        '127.0.0.1::1433',
        $script:AhkFlowTestSqlImage
    )

    $dockerOutput = & docker @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "docker run failed for shared SQL test container: $($dockerOutput -join [Environment]::NewLine)"
    }

    try {
        $hostPort = Get-AhkFlowTestSqlHostPort -ContainerName $containerName
        Wait-AhkFlowTestSqlReady -ContainerName $containerName -Password $script:AhkFlowTestSqlPassword
        $stopwatch.Stop()

        [pscustomobject]@{
            ContainerName = $containerName
            ConnectionString = "Server=127.0.0.1,$hostPort;Database=master;User Id=sa;Password=$script:AhkFlowTestSqlPassword;TrustServerCertificate=True;MultipleActiveResultSets=true"
            ElapsedMilliseconds = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            StartedAtUtc = [DateTimeOffset]::UtcNow
        }
    }
    catch {
        Stop-AhkFlowTestSqlContainer -ContainerName $containerName
        throw
    }
}

function Get-AhkFlowTestSqlHostPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    $inspectOutput = & docker inspect $ContainerName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "docker inspect failed for shared SQL test container '$ContainerName': $($inspectOutput -join [Environment]::NewLine)"
    }

    $inspect = @($inspectOutput | ConvertFrom-Json)
    $portBindings = $inspect[0].NetworkSettings.Ports.'1433/tcp'
    if (-not $portBindings -or -not $portBindings[0].HostPort) {
        throw "Shared SQL test container '$ContainerName' did not publish port 1433."
    }

    return $portBindings[0].HostPort
}

function Wait-AhkFlowTestSqlReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastOutput = ''
    $sqlcmdPaths = @('/opt/mssql-tools18/bin/sqlcmd', '/opt/mssql-tools/bin/sqlcmd')

    while ((Get-Date) -lt $deadline) {
        foreach ($sqlcmdPath in $sqlcmdPaths) {
            $sqlcmdOutput = & docker exec $ContainerName $sqlcmdPath -S localhost -U sa -P $Password -Q 'SELECT 1' -C -b 2>&1
            if ($LASTEXITCODE -eq 0) {
                return
            }

            if ($sqlcmdOutput) {
                $lastOutput = $sqlcmdOutput -join [Environment]::NewLine
            }
        }

        Start-Sleep -Seconds 1
    }

    $logs = & docker logs --tail 80 $ContainerName 2>&1
    throw "Shared SQL test container '$ContainerName' did not become ready within $TimeoutSeconds seconds. Last sqlcmd output: $lastOutput$([Environment]::NewLine)Docker logs:$([Environment]::NewLine)$($logs -join [Environment]::NewLine)"
}

function Stop-AhkFlowTestSqlContainer {
    [CmdletBinding()]
    param(
        [string]$ContainerName
    )

    if ([string]::IsNullOrWhiteSpace($ContainerName)) {
        return
    }

    $dockerOutput = & docker rm --force $ContainerName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to remove shared SQL test container '$ContainerName': $($dockerOutput -join [Environment]::NewLine)"
    }
}
