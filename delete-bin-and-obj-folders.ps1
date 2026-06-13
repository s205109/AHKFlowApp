$ErrorActionPreference = 'Stop'

$artifactDirectoryNames = @('bin', 'obj')
$directoriesToVisit = [System.Collections.Generic.Stack[string]]::new()
$directoriesToVisit.Push((Get-Location).ProviderPath)

while ($directoriesToVisit.Count -gt 0) {
    $currentDirectory = $directoriesToVisit.Pop()
    $childDirectories = Get-ChildItem -LiteralPath $currentDirectory -Directory -Force -ErrorAction SilentlyContinue

    foreach ($childDirectory in $childDirectories) {
        if (($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            continue
        }

        if ($artifactDirectoryNames -contains $childDirectory.Name) {
            Remove-Item -LiteralPath $childDirectory.FullName -Force -Recurse
            continue
        }

        $directoriesToVisit.Push($childDirectory.FullName)
    }
}
