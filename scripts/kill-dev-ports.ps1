#Requires -Version 5.1

# Frees ports used by AHKFlowApp dev servers so dotnet run doesn't fail with "address already in use".
# Ports: 5600, 7600 (API), 5601, 7601 (Blazor UI), 5602 (Docker Compose API)

$ports = 5600, 7600, 5601, 7601, 5602

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