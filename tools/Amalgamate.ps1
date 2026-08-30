# Amalgamate.ps1 - builds the single-file bundles in dist\ out of the modular
# units, SQLite style. One manifest per bundle in tools\bundles\, listing the
# units in dependency order.
#
# Usage:  pwsh -NoProfile -File tools\Amalgamate.ps1 [-Bundle <name>]
#
# Sections are spliced textually, uses clauses merged. It does not parse
# Pascal, only masks comments, strings and directives before looking for
# keywords. Units must have no finalization, no clashing identifiers and no
# 'in' file references. From mksqlite3c.tcl: begin and end markers, each file
# in once, an AMALGAMATION define, a check of the result before writing.

param(
    [string]$Bundle = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root 'src'
$distDir = Join-Path $root 'dist'
$bundleDir = Join-Path $PSScriptRoot 'bundles'
$enc = [System.Text.Encoding]::GetEncoding(1251)

# Blanks comments, strings and directives, keeping offsets, so a match on the
# result indexes the original. Directives get 'x': spaces would let a \s* eat them.
function Get-MaskedText([string]$text) {
    $c = $text.ToCharArray()
    $n = $c.Length
    $i = 0
    while ($i -lt $n) {
        $blankTo = -1
        $fill = ' '
        if ($c[$i] -eq '/' -and $i + 1 -lt $n -and $c[$i + 1] -eq '/') {
            $blankTo = $text.IndexOf("`n", $i)
            if ($blankTo -lt 0) { $blankTo = $n }
        }
        elseif ($c[$i] -eq '{') {
            $blankTo = $text.IndexOf('}', $i)
            $blankTo = if ($blankTo -lt 0) { $n } else { $blankTo + 1 }
            if ($i + 1 -lt $n -and $c[$i + 1] -eq '$') { $fill = 'x' }
        }
        elseif ($c[$i] -eq '(' -and $i + 1 -lt $n -and $c[$i + 1] -eq '*') {
            $blankTo = $text.IndexOf('*)', $i + 2)
            $blankTo = if ($blankTo -lt 0) { $n } else { $blankTo + 2 }
        }
        elseif ($c[$i] -eq "'") {
            $blankTo = $text.IndexOf("'", $i + 1)
            $blankTo = if ($blankTo -lt 0) { $n } else { $blankTo + 1 }
        }
        if ($blankTo -lt 0) { $i++; continue }
        while ($i -lt $blankTo) {
            if ($c[$i] -ne "`n") { $c[$i] = $fill }
            $i++
        }
    }
    -join $c
}

function Parse-Unit([string]$path) {
    $text = [System.IO.File]::ReadAllText($path, $enc)
    $text = $text -replace "`r`n", "`n"
    $mask = Get-MaskedText $text

    if ($mask -notmatch '(?m)^unit\s+(\w+)\s*;') { throw "no unit header in $path" }
    $unitName = $Matches[1]
    $unitEnd = $mask.IndexOf(';', $mask.IndexOf('unit ')) + 1

    $mInt = [regex]::Match($mask, '(?m)^interface\s*$')
    $mImpl = [regex]::Match($mask, '(?m)^implementation\s*$')
    if (-not $mInt.Success -or -not $mImpl.Success) { throw "missing interface/implementation in $path" }
    if ([regex]::IsMatch($mask, '(?m)^finalization\s*$')) { throw "finalization section not supported: $path" }
    $mInit = [regex]::Match($mask, '(?m)^initialization\s*$')
    $mEnd = [regex]::Match($mask, '(?m)^end\.')
    if (-not $mEnd.Success) { throw "no final end. in $path" }

    $preBlock = $text.Substring($unitEnd, $mInt.Index - $unitEnd)
    $intStart = $mInt.Index + $mInt.Length
    $implStart = $mImpl.Index + $mImpl.Length
    $intBody = $text.Substring($intStart, $mImpl.Index - $intStart)
    $implEnd = if ($mInit.Success) { $mInit.Index } else { $mEnd.Index }
    $implBody = $text.Substring($implStart, $implEnd - $implStart)
    $initBody = ''
    if ($mInit.Success) {
        $initBody = $text.Substring($mInit.Index + $mInit.Length, $mEnd.Index - ($mInit.Index + $mInit.Length))
    }

    # strips a section's uses clause, found in the mask so comments cannot lie
    $stripUses = {
        param([string]$body, [int]$offset)
        $m = [regex]::Match($mask.Substring($offset, $body.Length), '(?ms)^\s*uses\b(.*?);')
        $names = @()
        if ($m.Success) {
            if ($text.Substring($offset + $m.Index, $m.Length) -match "'") {
                throw "uses with 'in' reference not supported: $path"
            }
            # names come from the mask, so a comment between them is already gone
            $names = ($m.Value -replace '(?s)^\s*uses\b', '' -replace ';\s*$', '') -split ',' |
                ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($nm in $names) {
                if ($nm -notmatch '^\w+$') { throw "unexpected name '$nm' in the uses clause of $path" }
            }
            $body = $body.Remove($m.Index, $m.Length)
        }
        ,@($body, $names)
    }

    $r = & $stripUses $intBody $intStart
    $intBody = $r[0]; $intUses = $r[1]
    $r = & $stripUses $implBody $implStart
    $implBody = $r[0]; $implUses = $r[1]

    # pre-block switches, re-applied where the unit's code goes
    $preSwitches = [regex]::Matches($preBlock, '\{\$[A-Za-z]+[+-]\}') | ForEach-Object { $_.Value }

    @{
        Name = $unitName
        Pre = $preBlock.Trim("`n")
        IntBody = $intBody.Trim("`n")
        ImplBody = $implBody.Trim("`n")
        InitBody = $initBody.Trim("`n")
        Uses = @($intUses) + @($implUses)
        PreSwitches = @($preSwitches)
        # a unit that turns range or overflow checking off gets bracketed below
        NeedsGuard = ($text -match '\{\$[QR][+-]\}')
    }
}

function Build-Bundle([string]$manifestPath) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($manifestPath)
    $paths = Get-Content $manifestPath | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ }
    $seen = @{}
    foreach ($p in $paths) {
        $key = $p.ToLowerInvariant() -replace '/', '\'
        if ($seen.ContainsKey($key)) { throw "$p is listed twice in $name.manifest" }
        $seen[$key] = $true
    }
    $units = $paths | ForEach-Object { Parse-Unit (Join-Path $srcDir $_) }
    $embedded = $units | ForEach-Object { $_.Name }

    # merge external uses, first appearance wins the position
    $uses = @()
    foreach ($u in $units) {
        foreach ($n in $u.Uses) {
            if (($embedded -notcontains $n) -and ($uses -notcontains $n)) { $uses += $n }
        }
    }

    $commit = (& git -C $root rev-parse --short HEAD).Trim()
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $bar = '=' * 66
    $anyGuard = @($units | Where-Object { $_.NeedsGuard }).Count -gt 0
    $restore = '{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}' +
               '{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}'

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("unit $name;")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("// $name.pas - GENERATED FILE, DO NOT EDIT.")
    [void]$sb.AppendLine('// Single-file bundle amalgamated from the DelphiBoostPack modular units:')
    foreach ($p in $paths) { [void]$sb.AppendLine("//   src\$($p -replace '/', '\')") }
    [void]$sb.AppendLine("// Source commit $commit, generated $stamp by tools\Amalgamate.ps1.")
    [void]$sb.AppendLine('// Fix bugs in the modular units, then regenerate with:')
    [void]$sb.AppendLine('//   pwsh -NoProfile -File tools\Amalgamate.ps1')
    [void]$sb.AppendLine('// One bundle per project: two that share a helper declare it twice.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('{$DEFINE BPAMALGAMATION}')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('interface')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('uses')
    [void]$sb.AppendLine("  $($uses -join ', ');")
    if ($anyGuard) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('// Range and overflow checking as the consumer set it: a unit that turns')
        [void]$sb.AppendLine('// either off is bracketed, so its setting ends where the unit does.')
        [void]$sb.AppendLine('{$IFOPT R+}{$DEFINE BPAMALG_R}{$ELSE}{$UNDEF BPAMALG_R}{$ENDIF}')
        [void]$sb.AppendLine('{$IFOPT Q+}{$DEFINE BPAMALG_Q}{$ELSE}{$UNDEF BPAMALG_Q}{$ENDIF}')
    }

    # one line per marker, the way mksqlite3c.tcl brackets an embedded file
    $marker = {
        param([string]$word, $u, [string]$part)
        $text = " $word $($u.Name).pas $part "
        $pad = $bar.Length - $text.Length
        if ($pad -lt 4) { $pad = 4 }
        $left = [Math]::Floor($pad / 2)
        "// $('-' * $left)$text$('-' * ($pad - $left))"
    }

    $emit = {
        param($u, [string]$part, [string]$body, [string[]]$prefix)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((& $marker 'begin' $u $part))
        [void]$sb.AppendLine('')
        foreach ($line in $prefix) { [void]$sb.AppendLine($line) }
        [void]$sb.AppendLine($body)
        if ($u.NeedsGuard) { [void]$sb.AppendLine($restore) }
        [void]$sb.AppendLine((& $marker 'end' $u $part))
    }

    foreach ($u in $units) {
        $pre = if ($u.Pre) { @($u.Pre, '') } else { @() }
        & $emit $u 'interface' $u.IntBody $pre
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('implementation')
    foreach ($u in $units) {
        # the unit's own switches, so its code compiles as it did alone
        $pre = if ($u.PreSwitches) { @(($u.PreSwitches -join ''), '') } else { @() }
        & $emit $u 'implementation' $u.ImplBody $pre
    }
    $inits = $units | Where-Object { $_.InitBody }
    if ($inits) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('initialization')
        foreach ($u in $inits) {
            [void]$sb.AppendLine("  // from $($u.Name).pas")
            [void]$sb.AppendLine($u.InitBody)
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('end.')

    # bodies came in as LF and AppendLine emits CRLF, so flatten before joining
    $out = $sb.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")

    # nothing is written until the splice proves to be one well formed unit
    $outMask = Get-MaskedText ($out -replace "`r`n", "`n")
    foreach ($pat in @('^unit\s+\w+\s*;', '^interface\s*$', '^implementation\s*$', '^end\.')) {
        $count = ([regex]::Matches($outMask, "(?m)$pat")).Count
        if ($count -ne 1) { throw "$name.pas: expected 1 match of '$pat', got $count" }
    }

    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory $distDir | Out-Null }
    $outPath = Join-Path $distDir "$name.pas"
    [System.IO.File]::WriteAllText($outPath, $out, $enc)
    Write-Host "generated $outPath ($($units.Count) units, $((($out -split "`r`n").Count)) lines)"
}

$manifests = Get-ChildItem $bundleDir -Filter '*.manifest'
if ($Bundle) { $manifests = $manifests | Where-Object { $_.BaseName -eq $Bundle } }
if (-not $manifests) { throw "no manifest found for '$Bundle' in $bundleDir" }
foreach ($m in $manifests) { Build-Bundle $m.FullName }
