<#
.SYNOPSIS
Un-deduplicate the archive: write device files with their commands inlined.

.DESCRIPTION
The PowerShell twin of rehydrate.py, byte-for-byte identical output. The archive
stores each distinct command set once under codesets/ and gives every device a small
stub pointing at one; this walks that indirection and writes self-contained files.

JSON is emitted by hand rather than with ConvertTo-Json so the bytes match the Python
version exactly: keys sorted ordinally, two-space indent, LF endings, UTF-8 with no
BOM, non-ASCII characters left as themselves.

Windows' built-in PowerShell 5.1 parses JSON slowly. That is fine for one
manufacturer; use rehydrate.py or PowerShell 7 for anything larger.

.EXAMPLE
./rehydrate.ps1 -Manufacturer Sony -Out /tmp/sony
.EXAMPLE
./rehydrate.ps1 -ModelFile my-devices.txt -Out /tmp/mine
.EXAMPLE
./rehydrate.ps1 -All -Out /tmp/everything     # ~5.8 GB across 276,236 files
#>
[CmdletBinding()]
param(
    [string]   $Archive = ".",
    [Parameter(Mandatory = $true)][string] $Out,
    [string[]] $Manufacturer = @(),
    [string]   $ModelFile,
    [switch]   $All
)
$ErrorActionPreference = "Stop"

function Read-ArchiveJson([string] $Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-JsonString([string] $s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 0x20) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) }
                else                   { [void]$sb.Append($ch) }
            }
        }
    }
    '"' + $sb.ToString() + '"'
}

function Write-JsonValue($v, [int] $Indent) {
    $pad = ' ' * $Indent
    $pad2 = ' ' * ($Indent + 2)
    if ($null -eq $v)      { return 'null' }
    if ($v -is [string])   { return Get-JsonString $v }
    if ($v -is [bool])     { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [psobject] -and $v.PSObject.Properties.Name -and -not ($v -is [array])) {
        $names = [string[]]@($v.PSObject.Properties.Name)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)   # Python's sort_keys
        $parts = foreach ($n in $names) {
            $pad2 + (Get-JsonString $n) + ': ' + (Write-JsonValue $v.$n ($Indent + 2))
        }
        return "{`n" + ($parts -join ",`n") + "`n" + $pad + "}"
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $items = @($v)
        if ($items.Count -eq 0) { return '[]' }
        $parts = foreach ($i in $items) { $pad2 + (Write-JsonValue $i ($Indent + 2)) }
        return "[`n" + ($parts -join ",`n") + "`n" + $pad + "]"
    }
    return $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

# -Manufacturer means every model; -ModelFile narrows to named models.
$wanted = @{}
foreach ($m in $Manufacturer) { $wanted[$m] = $null }
if ($ModelFile) {
    foreach ($line in Get-Content -LiteralPath $ModelFile -Encoding UTF8) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $sep = if ($line.Contains("`t")) { "`t" } else { '/' }
        $i = $line.IndexOf($sep)
        $man = $line.Substring(0, $i).Trim()
        $mod = $line.Substring($i + 1).Trim()
        if (-not $wanted.ContainsKey($man)) { $wanted[$man] = New-Object 'System.Collections.Generic.HashSet[string]' }
        if ($null -ne $wanted[$man]) { [void]$wanted[$man].Add($mod) }
    }
}
if ($wanted.Count -eq 0 -and -not $All) {
    throw "nothing selected: pass -Manufacturer, -ModelFile, or -All (-All writes ~5.8 GB across 276,236 files)"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$cache = @{}
$n = 0
foreach ($man in (Read-ArchiveJson (Join-Path $Archive 'index.json'))) {
    if (-not $All -and -not $wanted.ContainsKey($man.n)) { continue }
    $models = if ($All) { $null } else { $wanted[$man.n] }
    $dir = Join-Path $Archive (Join-Path 'devices' $man.s)
    foreach ($entry in (Read-ArchiveJson (Join-Path $dir 'index.json'))) {
        if ($null -ne $models -and -not $models.Contains($entry.m)) { continue }
        $dev = Read-ArchiveJson (Join-Path $dir $entry.f)
        $path = $dev.codeset                       # relative to the archive root
        if ($path -and -not $cache.ContainsKey($path)) {
            $cache[$path] = (Read-ArchiveJson (Join-Path $Archive $path)).commands
        }
        $cmds = @(if ($path) { $cache[$path] } else { @() })
        $dev.PSObject.Properties.Remove('codeset')
        # Add-Member's binder turns an empty array into $null, and a one-element one
        # into a bare object; adding the note property directly keeps it an array.
        $dev.PSObject.Properties.Add(
            [System.Management.Automation.PSNoteProperty]::new('commands', $cmds))
        $od = Join-Path $Out $man.s
        if (-not (Test-Path -LiteralPath $od)) { [void](New-Item -ItemType Directory -Path $od -Force) }
        [System.IO.File]::WriteAllText((Join-Path $od $entry.f),
                                       (Write-JsonValue $dev 0) + "`n", $utf8)
        $n++
        if ($n % 5000 -eq 0) { Write-Host "  $n devices" }
    }
}
Write-Host "wrote $n device files to $Out"
