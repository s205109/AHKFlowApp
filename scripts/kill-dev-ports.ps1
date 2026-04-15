#Requires -Version 5.1

# Frees ports used by AHKFlowApp dev servers so dotnet run doesn't fail with "address already in use".
# Ports: 5600 (API, all scenarios), 5601 (Blazor UI)

$ports = 5600, 5601

foreach ($port in $ports) {
    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    
    foreach ($conn in $connections) {
        $processId = $conn.OwningProcess
        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
        
        if ($proc) {
            Write-Host "Killing $($proc.Name) (PID $processId) on port $port"
            Stop-Process -Id $processId -Force
        }
    }
}

Write-Host "Done."