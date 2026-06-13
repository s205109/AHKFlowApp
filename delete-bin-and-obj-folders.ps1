$ErrorActionPreference = 'Stop'

$artifactDirectoryNames = @('bin', 'obj')
$directoriesToVisit = [System.Collections.Generic.Stack[string]]::new()
$directoriesToVisit.Push((Get-Location).ProviderPath)
$scannedDirectoryCount = 0
$deletedDirectoryCount = 0

Write-Host 'Scanning for bin/obj folders...'

while ($directoriesToVisit.Count -gt 0) {
    $currentDirectory = $directoriesToVisit.Pop()
    $scannedDirectoryCount++

    if ($scannedDirectoryCount % 100 -eq 0) {
        Write-Host ("Scanned {0} directories; deleted {1} artifact folders..." -f $scannedDirectoryCount, $deletedDirectoryCount)
    }

    $childDirectories = Get-ChildItem -LiteralPath $currentDirectory -Directory -Force -ErrorAction SilentlyContinue

    foreach ($childDirectory in $childDirectories) {
        if (($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            continue
        }

        if ($artifactDirectoryNames -contains $childDirectory.Name) {
            Remove-Item -LiteralPath $childDirectory.FullName -Force -Recurse
            $deletedDirectoryCount++
            Write-Host ("Deleted {0}: {1}" -f $deletedDirectoryCount, $childDirectory.FullName)
            continue
        }

        $directoriesToVisit.Push($childDirectory.FullName)
    }
}

Write-Host ("Finished. Scanned {0} directories; deleted {1} artifact folders." -f $scannedDirectoryCount, $deletedDirectoryCount)
