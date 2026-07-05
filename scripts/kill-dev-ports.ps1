#Requires -Version 5.1

# Frees ports used by AHKFlowApp dev servers so dotnet run doesn't fail with "address already in use".
# Ports: 5600 (API, all scenarios), 5601 (Blazor UI)

. "$PSScriptRoot\Common.ps1"

$ports = 5600, 5601
$killed = 0

Write-Step "Freeing AHKFlowApp dev ports ($($ports -join ', '))"

foreach ($port in $ports) {
    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue

    foreach ($conn in $connections) {
        $processId = $conn.OwningProcess
        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue

        if ($proc) {
            Write-Warn "Killing $($proc.Name) (PID $processId) on port $port"
            Stop-Process -Id $processId -Force
            $killed++
        }
    }
}

if ($killed -eq 0) {
    Write-Success "No dev processes were listening; ports already free."
} else {
    Write-Success "Freed $killed process(es); dev ports are clear."
}