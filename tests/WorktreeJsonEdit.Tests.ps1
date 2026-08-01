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

Write-Host 'Worktree JSON edit tests passed.'
