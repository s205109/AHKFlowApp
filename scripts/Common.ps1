#Requires -Version 5.1

Set-StrictMode -Version Latest

function Write-Step([string]$Message)
{
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message)
{
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message)
{
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message)
{
    Write-Host "`n  [FAIL] $Message" -ForegroundColor Red
}

function Confirm-Command([string]$Name, [string]$InstallUrl)
{
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue))
    {
        Write-Fail "$Name is not installed."
        Write-Host "    Install from: $InstallUrl" -ForegroundColor Yellow
        exit 1
    }

    Write-Success "$Name found"
}

function Assert-AzureLogin()
{
    $null = az account show 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        Write-Fail "Not logged into Azure. Run: az login"
        exit 1
    }

    Write-Success "Azure login verified"
}

function Assert-GitHubAuth()
{
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        Write-Fail "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    }

    Write-Success "GitHub CLI authenticated"
}

function Read-KeyValueFile([string]$Path)
{
    $config = @{}

    Get-Content $Path | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $parts = $_ -split '=', 2
        $config[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $config
}
