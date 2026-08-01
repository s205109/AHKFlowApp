#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts\worktree-json.common.ps1')

function Assert-ExactText {
    param([string] $Expected, [string] $Actual, [string] $Message)
    if (-not [string]::Equals($Expected, $Actual, [System.StringComparison]::Ordinal)) {
        throw "$Message`n--- expected ---`n$Expected`n--- actual ---`n$Actual`n---"
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock] $Action, [string] $Pattern, [string] $Message)
    try {
        & $Action
    } catch {
        if ("$_" -notmatch $Pattern) { throw "$Message (message '$_' does not match '$Pattern')" }
        return
    }
    throw "$Message (no exception was thrown)"
}

function New-TempJsonPath {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('wtjson-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return (Join-Path $dir 'sample.json')
}

# --- Scanner: spans, comments, trailing commas ---

$sample = @(
    '{',
    '  // leading comment',
    '  "port": 5600,',
    '  "name": "api"',
    '}'
) -join "`n"

$tree = Read-JsoncTree $sample
Assert-True ($tree.Kind -eq 'Object') 'Root must be an object node.'
Assert-True (-not $tree.IsEmpty) 'Root object must not be reported as empty.'
Assert-ExactText '  ' $tree.Indent 'Root members are indented two spaces.'
Assert-True ($tree.Order.Count -eq 2) 'Root must have two members.'

$portMember = $tree.Members['port']
Assert-ExactText '5600' $sample.Substring($portMember.Value.Start, $portMember.Value.End - $portMember.Value.Start) 'The port span must cover exactly 5600.'
Assert-True ($portMember.CommaIndex -gt 0) 'The port member must record its comma.'

$nameMember = $tree.Members['name']
Assert-ExactText '"api"' $sample.Substring($nameMember.Value.Start, $nameMember.Value.End - $nameMember.Value.Start) 'The name span must cover the quoted value.'
Assert-True ($nameMember.CommaIndex -eq -1) 'The last member has no comma.'

# A trailing comma before the closing brace is legal JSONC and must parse.
$trailing = Read-JsoncTree (@('{', '  "a": 1,', '}') -join "`n")
Assert-True ($trailing.Order.Count -eq 1) 'A trailing comma must not create a phantom member.'

# --- Scanner: LineEnd keeps trailing comments attached ---

$commented = @('{', '  "a": 1 // explains a', '}') -join "`n"
$commentedTree = Read-JsoncTree $commented
$aMember = $commentedTree.Members['a']
Assert-ExactText '1' $commented.Substring($aMember.Value.Start, $aMember.Value.End - $aMember.Value.Start) 'The value span stops at the number.'
Assert-ExactText '  "a": 1 // explains a' $commented.Substring(0, $aMember.LineEnd).Split("`n")[-1] 'LineEnd must sit after the trailing comment.'

$blockCommented = @('{', '  "a": 1 /* note', '     more note */', '}') -join "`n"
$blockTree = Read-JsoncTree $blockCommented
Assert-ExactText '*/' $blockCommented.Substring($blockTree.Members['a'].LineEnd - 2, 2) 'LineEnd must sit after a multi-line block comment.'

# --- Scanner: arrays and empty objects ---

$arrayDoc = @('{', '  "items": [1, 2, 3],', '  "empty": {}', '}') -join "`n"
$arrayTree = Read-JsoncTree $arrayDoc
Assert-True ($arrayTree.Members['items'].Value.Kind -eq 'Array') 'items must be an array node.'
Assert-True ($arrayTree.Members['items'].Value.Items.Count -eq 3) 'items must have three entries.'
Assert-ExactText '2' $arrayDoc.Substring($arrayTree.Members['items'].Value.Items[1].Start, 1) 'The second array item span must cover 2.'
Assert-True ($arrayTree.Members['empty'].Value.IsEmpty) 'An empty object must report IsEmpty.'

# --- Scanner: malformed input throws with an offset ---

Assert-Throws { Read-JsoncTree '{ "a": 1 ' } 'offset' 'An unterminated object must throw with an offset.'
Assert-Throws { Read-JsoncTree '{ "a" 1 }' } 'offset' 'A missing colon must throw with an offset.'
Assert-Throws { Read-JsoncTree '{ "a": nonsense }' } "Invalid JSON value 'nonsense'.*offset" 'A bare word must not be accepted as a value.'
Assert-Throws { Read-JsoncTree '{ "a": 01 }' } "Invalid JSON value '01'.*offset" 'A leading zero must not be accepted as a number.'
Assert-Throws { Read-JsoncTree '{ "a": True }' } "Invalid JSON value 'True'.*offset" 'JSON literals are lower case only.'
Assert-Throws { Read-JsoncTree '{ "a": "x\qy" }' } 'Invalid escape.*offset' 'An unknown string escape must throw.'
Assert-Throws { Read-JsoncTree '{ "a": "x\u12zz" }' } 'Invalid \\u escape.*offset' 'A malformed \u escape must throw.'

foreach ($valid in @('0', '-0', '5600', '-12', '1.5', '-1.5e10', '2E+3', 'true', 'false', 'null')) {
    $parsed = Read-JsoncTree ('{ "a": ' + $valid + ' }')
    Assert-True ($parsed.Members.ContainsKey('a')) "The value $valid must parse."
}

# A literal tab inside a string is illegal by the JSON grammar but ConvertFrom-Json accepts
# it, so the scanner must not be stricter than the parser this repo already ships.
$tabbed = Read-JsoncTree ('{ "a": "x' + [char] 9 + 'y" }')
Assert-True ($tabbed.Members.ContainsKey('a')) 'A literal control character inside a string must still parse.'

# --- Line ending detection ---

Assert-ExactText "`r`n" (Get-JsoncEol "{`r`n  `"a`": 1`r`n}") 'A CRLF document must report CRLF.'
Assert-ExactText "`n" (Get-JsoncEol "{`n  `"a`": 1`n}") 'An LF document must report LF.'
Assert-ExactText "`n" (Get-JsoncEol '{"a":1}') 'A document with no line break defaults to LF.'

# --- Line indent ---

$indentDoc = "{`n    `"a`": 1`n}"
Assert-ExactText '    ' (Get-JsoncLineIndent $indentDoc $indentDoc.IndexOf('"a"')) 'Get-JsoncLineIndent returns the whitespace prefix.'

# --- String literal decoding ---

Assert-ExactText "a`tb" (ConvertFrom-JsoncStringLiteral '"a\tb"') 'A \t escape must decode to a tab.'
Assert-ExactText 'a"b\c' (ConvertFrom-JsoncStringLiteral '"a\"b\\c"') 'Quote and backslash escapes must decode.'
Assert-ExactText 'AB' (ConvertFrom-JsoncStringLiteral ('"' + [char]92 + 'u0041' + [char]92 + 'u0042"')) 'A \u escape must decode.'

# --- Read-JsoncFile / Write-JsoncFile ---

$noBomPath = New-TempJsonPath
[System.IO.File]::WriteAllText($noBomPath, "{`n  `"a`": 1`n}", (New-Object System.Text.UTF8Encoding($false)))
$noBom = Read-JsoncFile $noBomPath
Assert-True (-not $noBom.HasBom) 'A file without a BOM must report HasBom false.'
Assert-ExactText '{' $noBom.Text.Substring(0, 1) 'Text must start at the first real character.'
Assert-ExactText "`n" $noBom.Eol 'The LF file must report LF.'

$bomPath = New-TempJsonPath
[System.IO.File]::WriteAllText($bomPath, "{`r`n  `"a`": 1`r`n}", (New-Object System.Text.UTF8Encoding($true)))
$withBom = Read-JsoncFile $bomPath
Assert-True $withBom.HasBom 'A file with a BOM must report HasBom true.'
Assert-ExactText '{' $withBom.Text.Substring(0, 1) 'The BOM must be dropped before decoding.'
Assert-ExactText "`r`n" $withBom.Eol 'The CRLF file must report CRLF.'

Write-JsoncFile -Path $bomPath -Text $withBom.Text -HasBom $withBom.HasBom
$bytes = [System.IO.File]::ReadAllBytes($bomPath)
Assert-True ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'Writing back a BOM file must keep the BOM.'

Write-JsoncFile -Path $noBomPath -Text $noBom.Text -HasBom $noBom.HasBom
$bytes = [System.IO.File]::ReadAllBytes($noBomPath)
Assert-True (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'Writing back a BOM-free file must not add a BOM.'

Remove-Item -LiteralPath (Split-Path -Parent $noBomPath) -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Split-Path -Parent $bomPath) -Recurse -Force -ErrorAction SilentlyContinue

# --- Literal writers ---

Assert-ExactText '"api"' (ConvertTo-JsonLiteral 'api') 'A string becomes a quoted literal.'
Assert-ExactText '"a\"b\\c\td"' (ConvertTo-JsonLiteral ('a"b\c' + [char] 9 + 'd')) 'Quote, backslash, and tab must be escaped.'
Assert-ExactText (('"' + [char]92 + 'u0001"')) (ConvertTo-JsonLiteral ([string] [char] 1)) "A control character becomes a backslash-u escape."
Assert-ExactText ('"caf' + [char] 233 + '"') (ConvertTo-JsonLiteral ('caf' + [char] 233)) 'Non-ASCII is written literally.'
Assert-ExactText 'true' (ConvertTo-JsonLiteral $true) 'A true boolean becomes true.'
Assert-ExactText 'false' (ConvertTo-JsonLiteral $false) 'A false boolean becomes false.'
Assert-ExactText '5602' (ConvertTo-JsonLiteral 5602) 'An integer becomes invariant digits.'
Assert-ExactText '["a","b"]' (ConvertTo-JsonLiteral @('a', 'b')) 'A string array stays on one line.'
Assert-ExactText '[]' (ConvertTo-JsonLiteral @()) 'An empty array becomes [].'
Assert-Throws { ConvertTo-JsonLiteral ([pscustomobject]@{ a = 1 }) } 'cannot write' 'An unsupported type must throw.'

Assert-ExactText '"BaseAddress": "http://localhost:5602"' `
    (New-JsoncChainLiteral -Names @('BaseAddress') -Value 'http://localhost:5602' -Indent '  ' -Eol "`n") `
    'A single name produces one property.'

$chain = New-JsoncChainLiteral -Names @('Cors', 'AllowedOrigins') -Value @('http://localhost:5605') -Indent '  ' -Eol "`n"
Assert-ExactText (@(
    '"Cors": {',
    '    "AllowedOrigins": ["http://localhost:5605"]',
    '  }'
) -join "`n") $chain 'A two-name chain nests one object level and closes at the parent indent.'

$deepChain = New-JsoncChainLiteral -Names @('a', 'b', 'c') -Value 1 -Indent '' -Eol "`r`n"
Assert-ExactText (@(
    '"a": {',
    '  "b": {',
    '    "c": 1',
    '  }',
    '}'
) -join "`r`n") $deepChain 'A three-name chain adds two spaces per level and honours CRLF.'

# --- Set-JsoncValues ---

# 1. Replacing a scalar keeps the comment above it and the comment below it.
$doc = @(
    '{',
    '  // explains port',
    '  "port": 5600,',
    '  // explains name',
    '  "name": "api"',
    '}'
) -join "`n"
Assert-ExactText (@(
    '{',
    '  // explains port',
    '  "port": 5604,',
    '  // explains name',
    '  "name": "api"',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('port'); Value = 5604 })) 'Comments around a replaced value must survive.'

# 2. A one-line array elsewhere in the file is untouched by an unrelated edit.
$doc = @(
    '{',
    '  "Using": [ "Serilog.Sinks.Console", "Serilog.Sinks.File" ],',
    '  "AllowedHosts": "*"',
    '}'
) -join "`n"
Assert-ExactText (@(
    '{',
    '  "Using": [ "Serilog.Sinks.Console", "Serilog.Sinks.File" ],',
    '  "AllowedHosts": "localhost"',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('AllowedHosts'); Value = 'localhost' })) 'A one-line array must not be re-flowed.'

# 3. A missing property is inserted last, at the parent's member indent.
$doc = @('{', '  "environmentVariables": {', '    "A": "1"', '  }', '}') -join "`n"
Assert-ExactText (@(
    '{',
    '  "environmentVariables": {',
    '    "A": "1",',
    '    "B": "2"',
    '  }',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('environmentVariables', 'B'); Value = '2' })) 'An inserted property lands last at the parent indent.'

# 4. A missing property in an empty object.
$doc = @('{', '  "Cors": {}', '}') -join "`n"
Assert-ExactText (@(
    '{',
    '  "Cors": {',
    '    "AllowedOrigins": ["http://localhost:5605"]',
    '  }',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('Cors', 'AllowedOrigins'); Value = @('http://localhost:5605') })) 'An empty object must be opened up correctly.'

# 5. A missing intermediate section is created.
$doc = @('{', '  "AllowedHosts": "*"', '}') -join "`n"
Assert-ExactText (@(
    '{',
    '  "AllowedHosts": "*",',
    '  "Cors": {',
    '    "AllowedOrigins": ["http://localhost:5605"]',
    '  }',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('Cors', 'AllowedOrigins'); Value = @('http://localhost:5605') })) 'A missing section must be created with its nested property.'

# 6. An array-index path.
$doc = @(
    '{',
    '  "configurations": [',
    '    { "name": "a", "url": "http://localhost:5600" },',
    '    { "name": "b" },',
    '    { "name": "c", "url": "http://localhost:5600/swagger" }',
    '  ]',
    '}'
) -join "`n"
Assert-ExactText (@(
    '{',
    '  "configurations": [',
    '    { "name": "a", "url": "http://localhost:5600" },',
    '    { "name": "b" },',
    '    { "name": "c", "url": "http://localhost:5604/swagger" }',
    '  ]',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('configurations', 2, 'url'); Value = 'http://localhost:5604/swagger' })) 'An array index must select the right element.'

# 7. Escaping in a written value.
$doc = @('{', '  "v": "x"', '}') -join "`n"
Assert-ExactText (@('{', '  "v": "a\"b\\c\td"', '}') -join "`n") `
    (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('v'); Value = ('a"b\c' + [char] 9 + 'd') })) 'A written value must be escaped.'

# 8. A trailing comma in the input survives.
$doc = @('{', '  "a": 1,', '  "b": 2,', '}') -join "`n"
Assert-ExactText (@('{', '  "a": 3,', '  "b": 2,', '}') -join "`n") `
    (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('a'); Value = 3 })) 'A trailing comma must survive an edit.'

# 9. Line endings are preserved in both directions.
$crlf = @('{', '  "a": 1', '}') -join "`r`n"
Assert-ExactText (@('{', '  "a": 1,', '  "b": 2', '}') -join "`r`n") `
    (Set-JsoncValues -Json $crlf -Edits @(@{ Path = @('b'); Value = 2 })) 'A CRLF file must keep CRLF.'
$lf = @('{', '  "a": 1', '}') -join "`n"
Assert-ExactText (@('{', '  "a": 1,', '  "b": 2', '}') -join "`n") `
    (Set-JsoncValues -Json $lf -Edits @(@{ Path = @('b'); Value = 2 })) 'An LF file must keep LF.'

# 10. Applying the same edits twice is byte-identical.
$doc = @('{', '  "environmentVariables": {', '    "A": "1"', '  }', '}') -join "`n"
$edits = @(
    @{ Path = @('environmentVariables', 'A'); Value = '9' },
    @{ Path = @('environmentVariables', 'B'); Value = '2' }
)
$once = Set-JsoncValues -Json $doc -Edits $edits
$twice = Set-JsoncValues -Json $once -Edits $edits
Assert-ExactText $once $twice 'Re-applying the same edits must change nothing.'

# 11. An out-of-range array index throws, naming the path and the offset.
$doc = @('{', '  "configurations": [ { "url": "a" } ]', '}') -join "`n"
Assert-Throws { Set-JsoncValues -Json $doc -Edits @(@{ Path = @('configurations', 5, 'url'); Value = 'b' }) } `
    'configurations\.5\.url.*offset' 'An out-of-range index must name the path and the offset.'

# 12. Inserting after a member that carries a trailing // comment.
$doc = @('{', '  "a": 1 // explains a', '}') -join "`n"
Assert-ExactText (@('{', '  "a": 1, // explains a', '  "b": 2', '}') -join "`n") `
    (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('b'); Value = 2 })) 'The comma must land before a trailing line comment.'

# 13. Inserting after a member that carries a trailing block comment.
$doc = @('{', '  "a": 1 /* note */', '}') -join "`n"
Assert-ExactText (@('{', '  "a": 1, /* note */', '  "b": 2', '}') -join "`n") `
    (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('b'); Value = 2 })) 'The comma must land before a trailing block comment.'

# 14. Inserting after a member whose block comment closes lines later.
$doc = @('{', '  "a": 1 /* note', '     more note */', '}') -join "`n"
Assert-ExactText (@('{', '  "a": 1, /* note', '     more note */', '  "b": 2', '}') -join "`n") `
    (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('b'); Value = 2 })) 'A multi-line trailing comment must stay whole.'

# 15. Inserting after a member that already has a trailing comma writes no second comma.
$doc = @('{', '  "a": 1,', '}') -join "`n"
Assert-ExactText (@('{', '  "a": 1,', '  "b": 2', '}') -join "`n") `
    (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('b'); Value = 2 })) 'An existing trailing comma is reused as the separator.'

# 16. Overlapping edits are rejected before anything is written.
$doc = @('{', '  "a": { "b": 1 }', '}') -join "`n"
Assert-Throws { Set-JsoncValues -Json $doc -Edits @(
        @{ Path = @('a'); Value = 'x' },
        @{ Path = @('a', 'b'); Value = 2 }
    ) } 'Conflicting JSON edits' 'Two edits whose spans overlap must throw.'

# 17. Two missing sections under the same parent produce one comma each and stay valid JSON.
$doc = @('{', '  "AllowedHosts": "*"', '}') -join "`n"
$actual = Set-JsoncValues -Json $doc -Edits @(
    @{ Path = @('Cors', 'AllowedOrigins'); Value = @('http://localhost:5605') },
    @{ Path = @('ConnectionStrings', 'DefaultConnection'); Value = 'Server=localhost' }
)
Assert-ExactText (@(
    '{',
    '  "AllowedHosts": "*",',
    '  "Cors": {',
    '    "AllowedOrigins": ["http://localhost:5605"]',
    '  },',
    '  "ConnectionStrings": {',
    '    "DefaultConnection": "Server=localhost"',
    '  }',
    '}'
) -join "`n") $actual 'Two missing sections under one parent must be written as two members.'
Assert-True ([bool] ($actual | ConvertFrom-Json)) 'Two missing sections must still produce parseable JSON.'

# 18. Two missing keys in the same non-empty object, alongside a replacement in it.
$doc = @(
    '{',
    '  "environmentVariables": {',
    '    "ASPNETCORE_ENVIRONMENT": "Development",',
    '    "AHKFLOW_START_DOCKER_SQL": "true"',
    '  }',
    '}'
) -join "`n"
$actual = Set-JsoncValues -Json $doc -Edits @(
    @{ Path = @('environmentVariables', 'ASPNETCORE_ENVIRONMENT'); Value = 'Staging' },
    @{ Path = @('environmentVariables', 'COMPOSE_PROJECT_NAME'); Value = 'ahkflowapp-wt' },
    @{ Path = @('environmentVariables', 'AHKFLOW_SQL_PORT'); Value = '14330' }
)
Assert-ExactText (@(
    '{',
    '  "environmentVariables": {',
    '    "ASPNETCORE_ENVIRONMENT": "Staging",',
    '    "AHKFLOW_START_DOCKER_SQL": "true",',
    '    "COMPOSE_PROJECT_NAME": "ahkflowapp-wt",',
    '    "AHKFLOW_SQL_PORT": "14330"',
    '  }',
    '}'
) -join "`n") $actual 'Two inserted keys must be separated by one comma each.'
Assert-True ([bool] ($actual | ConvertFrom-Json)) 'Two inserted keys must still produce parseable JSON.'

# 19. Two missing keys in an empty object.
$doc = @('{', '  "environmentVariables": {}', '}') -join "`n"
Assert-ExactText (@(
    '{',
    '  "environmentVariables": {',
    '    "A": "1",',
    '    "B": "2"',
    '  }',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(
    @{ Path = @('environmentVariables', 'A'); Value = '1' },
    @{ Path = @('environmentVariables', 'B'); Value = '2' }
)) 'Two inserted keys in an empty object must be separated by a comma.'

# 20. An object holding only comments keeps them when a member is inserted.
$doc = @(
    '{',
    '  "Cors": {',
    '    // keep this explanation',
    '  }',
    '}'
) -join "`n"
Assert-ExactText (@(
    '{',
    '  "Cors": {',
    '    // keep this explanation',
    '    "AllowedOrigins": ["http://localhost:5605"]',
    '  }',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('Cors', 'AllowedOrigins'); Value = @('http://localhost:5605') })) 'A comment-only object must keep its comment.'

# 21. A comment-only object written on one line keeps its comment too.
$doc = @('{', '  "Cors": { /* why */ }', '}') -join "`n"
Assert-ExactText (@(
    '{',
    '  "Cors": { /* why */',
    '    "AllowedOrigins": []',
    '  }',
    '}'
) -join "`n") (Set-JsoncValues -Json $doc -Edits @(@{ Path = @('Cors', 'AllowedOrigins'); Value = @() })) 'A one-line comment-only object must keep its comment.'

# 22. Grouped insertions are idempotent too.
$doc = @('{', '  "AllowedHosts": "*"', '}') -join "`n"
$groupEdits = @(
    @{ Path = @('Cors', 'AllowedOrigins'); Value = @('http://localhost:5605') },
    @{ Path = @('ConnectionStrings', 'DefaultConnection'); Value = 'Server=localhost' }
)
$once = Set-JsoncValues -Json $doc -Edits $groupEdits
$twice = Set-JsoncValues -Json $once -Edits $groupEdits
Assert-ExactText $once $twice 'Re-applying grouped insertions must change nothing.'

Write-Host 'Worktree JSON edit tests passed.'
