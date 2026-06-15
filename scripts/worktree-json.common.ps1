#Requires -Version 5.1
# Shared JSON helpers for the worktree tooling. Windows PowerShell 5.1's JSON cmdlets
# are strict and ugly: ConvertFrom-Json rejects comments and trailing commas (both legal
# in VS Code launch.json/tasks.json and .NET appsettings.json), and ConvertTo-Json emits
# column-aligned output with double spaces after colons. These helpers tolerate JSON-with-
# comments on read and emit conventional two-space JSON on write.

# Strip // line and /* */ block comments. String-aware: a // inside a string value such as
# an "http://..." URL, and an escaped quote (\") inside a string, are left untouched.
function Remove-JsonComments {
    param([Parameter(Mandatory)][string] $Json)

    $sb = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $i = 0
    $n = $Json.Length

    while ($i -lt $n) {
        $c = $Json[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }

        if ($c -eq '/' -and $i + 1 -lt $n) {
            $next = $Json[$i + 1]
            if ($next -eq '/') {
                $i += 2
                while ($i -lt $n -and $Json[$i] -ne "`n") { $i++ }
                continue   # leave the newline; the next iteration emits it
            }
            if ($next -eq '*') {
                $i += 2
                while ($i + 1 -lt $n -and -not ($Json[$i] -eq '*' -and $Json[$i + 1] -eq '/')) { $i++ }
                $i += 2
                continue
            }
        }

        [void]$sb.Append($c)
        $i++
    }

    return $sb.ToString()
}

# Drop trailing commas (a comma whose next non-whitespace char is } or ]). Run after
# Remove-JsonComments so only whitespace can sit between the comma and the closer.
function Remove-JsonTrailingCommas {
    param([Parameter(Mandatory)][string] $Json)

    $sb = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $i = 0
    $n = $Json.Length

    while ($i -lt $n) {
        $c = $Json[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }

        if ($c -eq ',') {
            $j = $i + 1
            while ($j -lt $n -and ($Json[$j] -in ' ', "`t", "`r", "`n")) { $j++ }
            if ($j -lt $n -and ($Json[$j] -eq '}' -or $Json[$j] -eq ']')) {
                $i++   # skip the trailing comma
                continue
            }
        }

        [void]$sb.Append($c)
        $i++
    }

    return $sb.ToString()
}

# Parse JSON-with-comments (and trailing commas) into an object on Windows PowerShell 5.1.
function ConvertFrom-Jsonc {
    param([Parameter(Mandatory)][string] $Json)

    return (Remove-JsonTrailingCommas (Remove-JsonComments $Json)) | ConvertFrom-Json
}

# Re-indent ConvertTo-Json output to conventional two-space JSON. Only rewrites whitespace
# outside string literals, so escaping, numbers, and backslashes in values are preserved
# verbatim; escaped quotes and braces inside string values are left intact.
function Format-Json {
    param([Parameter(Mandatory)][string] $Json)

    $unit = '  '
    $sb = New-Object System.Text.StringBuilder
    $indent = 0
    $inString = $false
    $escaped = $false

    for ($i = 0; $i -lt $Json.Length; $i++) {
        $c = $Json[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            continue
        }

        switch -CaseSensitive ($c) {
            '"' { $inString = $true; [void]$sb.Append($c) }
            ' '  { }   # drop insignificant whitespace; we re-emit our own
            "`t" { }
            "`r" { }
            "`n" { }
            ':' { [void]$sb.Append(': ') }
            ',' { [void]$sb.Append(",`n").Append($unit * $indent) }
            { $_ -eq '{' -or $_ -eq '[' } {
                $close = if ($c -eq '{') { '}' } else { ']' }
                $j = $i + 1
                while ($j -lt $Json.Length -and ($Json[$j] -in ' ', "`t", "`r", "`n")) { $j++ }
                if ($j -lt $Json.Length -and $Json[$j] -eq $close) {
                    [void]$sb.Append($c).Append($close)   # empty container stays on one line
                    $i = $j
                } else {
                    $indent++
                    [void]$sb.Append($c).Append("`n").Append($unit * $indent)
                }
            }
            { $_ -eq '}' -or $_ -eq ']' } {
                $indent--
                [void]$sb.Append("`n").Append($unit * $indent).Append($c)
            }
            default { [void]$sb.Append($c) }
        }
    }

    return $sb.ToString()
}
