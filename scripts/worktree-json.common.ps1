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

# --- JSONC text scanner -------------------------------------------------------
# Everything below edits JSON as text. ConvertFrom-Json/ConvertTo-Json cannot be used for
# writing: the round trip deletes comments, adds a BOM, and re-flows one-line arrays. The
# scanner records the character span of every value so a writer can splice new text into
# exactly that span and touch nothing else.

# The whitespace prefix of the line that holds $Index.
function Get-JsoncLineIndent {
    param([Parameter(Mandatory)][string] $Text, [int] $Index)

    $lineStart = $Index
    while ($lineStart -gt 0 -and $Text[$lineStart - 1] -ne "`n") { $lineStart-- }

    $i = $lineStart
    while ($i -lt $Index -and ($Text[$i] -eq ' ' -or $Text[$i] -eq "`t")) { $i++ }

    return $Text.Substring($lineStart, $i - $lineStart)
}

# The first index of the whitespace run that ends just before $Index. Insertion into an
# object with no members splices over this run, so an interior comment is never touched.
function Get-JsoncWhitespaceRunStart {
    param([Parameter(Mandatory)][string] $Text, [int] $Index)

    $i = $Index
    while ($i -gt 0 -and ($Text[$i - 1] -eq ' ' -or $Text[$i - 1] -eq "`t" -or $Text[$i - 1] -eq "`r" -or $Text[$i - 1] -eq "`n")) { $i-- }

    return $i
}

# The file's dominant line ending. CRLF wins when most newlines are preceded by a return.
function Get-JsoncEol {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Json)

    $crlf = ([regex]::Matches($Json, "`r`n")).Count
    $lf = ([regex]::Matches($Json, "`n")).Count
    if ($crlf * 2 -gt $lf) { return "`r`n" }
    return "`n"
}

# Decode a JSON string literal (quotes included) into its characters.
function ConvertFrom-JsoncStringLiteral {
    param([Parameter(Mandatory)][string] $Literal)

    $sb = New-Object System.Text.StringBuilder
    $i = 1
    $end = $Literal.Length - 1

    while ($i -lt $end) {
        $c = $Literal[$i]
        if ($c -ne '\') { [void] $sb.Append($c); $i++; continue }

        $i++
        if ($i -ge $end) { throw "Unterminated escape in string literal $Literal." }
        $escape = $Literal[$i]

        switch -CaseSensitive ($escape) {
            '"' { [void] $sb.Append('"'); $i++ }
            '\' { [void] $sb.Append('\'); $i++ }
            '/' { [void] $sb.Append('/'); $i++ }
            'b' { [void] $sb.Append([char] 8); $i++ }
            'f' { [void] $sb.Append([char] 12); $i++ }
            'n' { [void] $sb.Append([char] 10); $i++ }
            'r' { [void] $sb.Append([char] 13); $i++ }
            't' { [void] $sb.Append([char] 9); $i++ }
            'u' {
                [void] $sb.Append([char] [Convert]::ToInt32($Literal.Substring($i + 1, 4), 16))
                $i += 5
            }
            default { throw "Unsupported escape '\$escape' in string literal $Literal." }
        }
    }

    return $sb.ToString()
}

# Index of the next character that is not whitespace and not a comment.
function Get-JsoncNextNonTrivia {
    param([hashtable] $State, [int] $Index)

    $text = $State.Text
    $i = $Index

    while ($i -lt $State.Length) {
        $c = $text[$i]
        if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`r" -or $c -eq "`n") { $i++; continue }

        if ($c -eq '/' -and $i + 1 -lt $State.Length) {
            $next = $text[$i + 1]
            if ($next -eq '/') {
                $i += 2
                while ($i -lt $State.Length -and $text[$i] -ne "`n") { $i++ }
                continue
            }
            if ($next -eq '*') {
                $j = $i + 2
                while ($j + 1 -lt $State.Length -and -not ($text[$j] -eq '*' -and $text[$j + 1] -eq '/')) { $j++ }
                if ($j + 1 -ge $State.Length) { throw "Unterminated block comment at offset $i." }
                $i = $j + 2
                continue
            }
        }

        break
    }

    return $i
}

# Named Move-, not Skip-: Skip is not an approved PowerShell verb.
function Move-JsoncPastTrivia {
    param([hashtable] $State)

    $State.Pos = Get-JsoncNextNonTrivia $State $State.Pos
}

# Index one past the closing quote of the string literal that starts at $Start. Escape
# sequences are validated here, where the walk already happens.
function Get-JsoncStringEnd {
    param([hashtable] $State, [int] $Start)

    $text = $State.Text
    $i = $Start + 1

    while ($i -lt $State.Length) {
        $c = $text[$i]

        if ($c -eq '"') { return $i + 1 }

        if ($c -eq '\') {
            if ($i + 1 -ge $State.Length) { throw "Unterminated escape at offset $i." }
            $escape = $text[$i + 1]

            if ('"\/bfnrt'.IndexOf($escape) -ge 0) { $i += 2; continue }

            if ($escape -eq 'u') {
                if ($i + 5 -ge $State.Length) { throw "Truncated \u escape at offset $i." }
                $hex = $text.Substring($i + 2, 4)
                if ($hex -notmatch '^[0-9a-fA-F]{4}$') { throw "Invalid \u escape at offset $i." }
                $i += 6
                continue
            }

            throw "Invalid escape '\$escape' at offset $i."
        }

        $i++
    }

    throw "Unterminated string starting at offset $Start."
}

function Read-JsoncScalar {
    param([hashtable] $State)

    $text = $State.Text
    $start = $State.Pos

    if ($text[$start] -eq '"') {
        $State.Pos = Get-JsoncStringEnd $State $start
        return @{ Kind = 'Scalar'; Start = $start; End = $State.Pos }
    }

    while ($State.Pos -lt $State.Length) {
        $c = $text[$State.Pos]
        if ($c -eq ',' -or $c -eq '}' -or $c -eq ']' -or $c -eq ' ' -or $c -eq "`t" -or $c -eq "`r" -or $c -eq "`n") { break }
        if ($c -eq '/' -and $State.Pos + 1 -lt $State.Length -and ($text[$State.Pos + 1] -eq '/' -or $text[$State.Pos + 1] -eq '*')) { break }
        $State.Pos++
    }

    if ($State.Pos -eq $start) { throw "Expected a JSON value at offset $start." }

    # A run of non-delimiter characters is not automatically a value: only the three
    # literals and JSON number syntax are legal here.
    $token = $text.Substring($start, $State.Pos - $start)
    if ($token -cne 'true' -and $token -cne 'false' -and $token -cne 'null' -and
        $token -notmatch '^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$') {
        throw "Invalid JSON value '$token' at offset $start."
    }

    return @{ Kind = 'Scalar'; Start = $start; End = $State.Pos }
}

# What follows a member's value on the value's own line: the separating comma, and any
# comment that starts on that line. LineEnd is one past the last such token. Splicing a new
# member at LineEnd keeps a trailing comment attached to the member it describes.
function Read-JsoncMemberTrailing {
    param([hashtable] $State, [int] $ValueEnd)

    $text = $State.Text
    $i = $ValueEnd
    $commaIndex = -1
    $lineEnd = $ValueEnd

    while ($i -lt $State.Length) {
        $c = $text[$i]

        if ($c -eq ' ' -or $c -eq "`t") { $i++; continue }
        if ($c -eq "`r" -or $c -eq "`n") { break }

        if ($c -eq ',' -and $commaIndex -eq -1) {
            $commaIndex = $i
            $i++
            $lineEnd = $i
            continue
        }

        if ($c -eq '/' -and $i + 1 -lt $State.Length -and $text[$i + 1] -eq '/') {
            $i += 2
            while ($i -lt $State.Length -and $text[$i] -ne "`n" -and $text[$i] -ne "`r") { $i++ }
            $lineEnd = $i
            break
        }

        if ($c -eq '/' -and $i + 1 -lt $State.Length -and $text[$i + 1] -eq '*') {
            $j = $i + 2
            while ($j + 1 -lt $State.Length -and -not ($text[$j] -eq '*' -and $text[$j + 1] -eq '/')) { $j++ }
            if ($j + 1 -ge $State.Length) { throw "Unterminated block comment at offset $i." }
            $i = $j + 2
            $lineEnd = $i
            continue
        }

        break
    }

    # A comma written on the next line is still this member's separator.
    if ($commaIndex -eq -1) {
        $next = Get-JsoncNextNonTrivia $State $lineEnd
        if ($next -lt $State.Length -and $text[$next] -eq ',') {
            $commaIndex = $next
            $lineEnd = $next + 1
        }
    }

    return @{ CommaIndex = $commaIndex; LineEnd = $lineEnd }
}

function Read-JsoncObject {
    param([hashtable] $State)

    $text = $State.Text
    $start = $State.Pos
    $State.Pos++   # past '{'

    $members = @{}
    $order = New-Object System.Collections.ArrayList

    while ($true) {
        Move-JsoncPastTrivia $State
        if ($State.Pos -ge $State.Length) { throw "Unterminated object starting at offset $start." }
        if ($text[$State.Pos] -eq '}') { break }

        if ($text[$State.Pos] -ne '"') {
            throw "Expected a property name in the object starting at offset $start, found '$($text[$State.Pos])' at offset $($State.Pos)."
        }

        $nameStart = $State.Pos
        $nameEnd = Get-JsoncStringEnd $State $nameStart
        $name = ConvertFrom-JsoncStringLiteral $text.Substring($nameStart, $nameEnd - $nameStart)
        $State.Pos = $nameEnd

        Move-JsoncPastTrivia $State
        if ($State.Pos -ge $State.Length -or $text[$State.Pos] -ne ':') {
            throw "Expected ':' after property '$name' at offset $($State.Pos)."
        }
        $State.Pos++

        $value = Read-JsoncValue $State
        $trailing = Read-JsoncMemberTrailing $State $value.End

        $member = @{
            Name = $name
            NameStart = $nameStart
            Value = $value
            CommaIndex = $trailing.CommaIndex
            LineEnd = $trailing.LineEnd
        }
        $members[$name] = $member
        [void] $order.Add($member)

        if ($trailing.CommaIndex -ge 0) {
            $State.Pos = $trailing.CommaIndex + 1
            continue
        }

        $State.Pos = $trailing.LineEnd
        Move-JsoncPastTrivia $State
        if ($State.Pos -ge $State.Length) { throw "Unterminated object starting at offset $start." }
        if ($text[$State.Pos] -ne '}') {
            throw "Expected ',' or '}' in the object starting at offset $start, found '$($text[$State.Pos])' at offset $($State.Pos)."
        }
        break
    }

    Move-JsoncPastTrivia $State
    if ($State.Pos -ge $State.Length -or $text[$State.Pos] -ne '}') {
        throw "Unterminated object starting at offset $start."
    }

    $closeIndex = $State.Pos
    $State.Pos++

    $indent = if ($order.Count -gt 0) { Get-JsoncLineIndent $text $order[0].NameStart } else { '' }

    return @{
        Kind = 'Object'
        Start = $start
        End = $State.Pos
        Members = $members
        Order = $order.ToArray()
        CloseIndex = $closeIndex
        IsEmpty = ($order.Count -eq 0)
        Indent = $indent
    }
}

function Read-JsoncArray {
    param([hashtable] $State)

    $text = $State.Text
    $start = $State.Pos
    $State.Pos++   # past '['
    $items = New-Object System.Collections.ArrayList

    while ($true) {
        Move-JsoncPastTrivia $State
        if ($State.Pos -ge $State.Length) { throw "Unterminated array starting at offset $start." }
        if ($text[$State.Pos] -eq ']') { $State.Pos++; break }

        [void] $items.Add((Read-JsoncValue $State))

        Move-JsoncPastTrivia $State
        if ($State.Pos -ge $State.Length) { throw "Unterminated array starting at offset $start." }

        $c = $text[$State.Pos]
        if ($c -eq ',') { $State.Pos++; continue }
        if ($c -eq ']') { $State.Pos++; break }
        throw "Expected ',' or ']' in the array starting at offset $start, found '$c' at offset $($State.Pos)."
    }

    return @{ Kind = 'Array'; Start = $start; End = $State.Pos; Items = $items.ToArray() }
}

function Read-JsoncValue {
    param([hashtable] $State)

    Move-JsoncPastTrivia $State
    if ($State.Pos -ge $State.Length) { throw "Unexpected end of JSON at offset $($State.Pos)." }

    $c = $State.Text[$State.Pos]
    if ($c -eq '{') { return Read-JsoncObject $State }
    if ($c -eq '[') { return Read-JsoncArray $State }
    return Read-JsoncScalar $State
}

# Walk JSON-with-comments once and return a node tree of character spans.
function Read-JsoncTree {
    param([Parameter(Mandatory)][string] $Json)

    $state = @{ Text = $Json; Pos = 0; Length = $Json.Length }
    $root = Read-JsoncValue $state
    Move-JsoncPastTrivia $state
    if ($state.Pos -lt $state.Length) {
        throw "Unexpected character '$($Json[$state.Pos])' after the top-level value at offset $($state.Pos)."
    }

    return $root
}

# --- File encoding ------------------------------------------------------------
# Encoding is observed, never assumed. A BOM is dropped before decoding so every span the
# scanner records is relative to the first real character; Write-JsoncFile puts it back
# through the encoding, so the two can never double up.

function Read-JsoncFile {
    param([Parameter(Mandatory)][string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes, $offset, $bytes.Length - $offset)

    return @{ Text = $text; HasBom = $hasBom; Eol = (Get-JsoncEol $text) }
}

function Write-JsoncFile {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [bool] $HasBom
    )

    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($HasBom)))
}

# --- Literal writers ----------------------------------------------------------
# Written by hand rather than through ConvertTo-Json: Windows PowerShell 5.1 escapes
# < > & ' as \u00xx and PowerShell 7 does not, so only a hand-written escaper gives
# byte-identical output on both hosts.

function ConvertTo-JsonStringLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Value)

    $sb = New-Object System.Text.StringBuilder
    [void] $sb.Append('"')

    foreach ($c in $Value.ToCharArray()) {
        $code = [int] $c
        if ($c -eq '"') { [void] $sb.Append('\"') }
        elseif ($c -eq '\') { [void] $sb.Append('\\') }
        elseif ($code -eq 8) { [void] $sb.Append('\b') }
        elseif ($code -eq 9) { [void] $sb.Append('\t') }
        elseif ($code -eq 10) { [void] $sb.Append('\n') }
        elseif ($code -eq 12) { [void] $sb.Append('\f') }
        elseif ($code -eq 13) { [void] $sb.Append('\r') }
        elseif ($code -lt 32) { [void] $sb.Append('\u').Append($code.ToString('x4', [System.Globalization.CultureInfo]::InvariantCulture)) }
        else { [void] $sb.Append($c) }
    }

    [void] $sb.Append('"')
    return $sb.ToString()
}

# Leaf values only. Building a missing object is New-JsoncChainLiteral's job.
function ConvertTo-JsonLiteral {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return ConvertTo-JsonStringLiteral $Value }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long]) { return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }

    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = @()
        foreach ($item in $Value) { $parts += ConvertTo-JsonLiteral $item }
        return '[' + ($parts -join ',') + ']'
    }

    throw "ConvertTo-JsonLiteral cannot write a value of type '$($Value.GetType().FullName)'."
}

# Text for a property whose value may sit under a chain of objects that do not exist yet.
# $Indent is the indent of the line the property will be written on; each nested level adds
# two spaces, and each closing brace sits at the indent of its own opening line.
function New-JsoncChainLiteral {
    param(
        [Parameter(Mandatory)][string[]] $Names,
        $Value,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Indent,
        [Parameter(Mandatory)][string] $Eol
    )

    if ($Names.Count -eq 1) {
        return (ConvertTo-JsonStringLiteral $Names[0]) + ': ' + (ConvertTo-JsonLiteral $Value)
    }

    $inner = New-JsoncChainLiteral -Names $Names[1..($Names.Count - 1)] -Value $Value -Indent ($Indent + '  ') -Eol $Eol
    return (ConvertTo-JsonStringLiteral $Names[0]) + ': {' + $Eol + $Indent + '  ' + $inner + $Eol + $Indent + '}'
}
