param(
    [Parameter(Mandatory = $false)]
    [string]$Path = ".",

    [switch]$NoRecurse
)

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Path does not exist: $Path"
    exit 1
}

Get-ChildItem `
    -LiteralPath $Path `
    -Force `
    -Recurse:(!$NoRecurse) |
    Select-Object Name, LinkType, Target, Attributes