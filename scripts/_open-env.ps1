function Open-Env([string]$EnvFile) {
    if (-not (Test-Path $EnvFile)) {
        Write-Error "Env file not found: $EnvFile`nRun deploy.ps1 first to generate it."
        exit 1
    }

    $config = @{}
    Get-Content $EnvFile | Where-Object { $_ -match "^\s*[^#]\w+=.+" } | ForEach-Object {
        $k, $v = $_ -split "=", 2
        $config[$k.Trim()] = $v.Trim()
    }

    $required = "APP_SERVICE_HOSTNAME", "SWA_HOSTNAME"
    $missing  = $required | Where-Object { -not $config[$_] }
    if ($missing) {
        Write-Error "Missing or empty keys in ${EnvFile}: $($missing -join ", ")"
        exit 1
    }

    $api = "https://$($config["APP_SERVICE_HOSTNAME"])/api/v1/health"
    $ui  = "https://$($config["SWA_HOSTNAME"])"

    Write-Host "Opening API : $api"
    Write-Host "Opening UI  : $ui"

    Start-Process $api
    Start-Process $ui
}
