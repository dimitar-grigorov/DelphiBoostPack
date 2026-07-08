# Amalgamate.ps1 - generates single-file "carry one .pas" bundles in dist\
# from the modular units under src\Core, SQLite amalgamation style.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1 [-Bundle <name>]
#
# Each bundle is described by tools\bundles\<name>.manifest: one src-relative
# unit path per line, in dependency order (a unit may only use units listed
# above it or external RTL units). '#' starts a comment.
#
# The generator is deliberately dumb: it splices interface and implementation
# sections textually, merges the external uses clauses into one, and appends
# merged initialization sections. It does not parse Pascal. Rules the source
# units must follow (checked where cheap):
#   - no finalization sections
#   - no unit-level identifier clashes across bundle members (per-unit names
#     like gcStrEmptyHash / gcIntEmptyHash; verified by compiling the bundle)
#   - uses clauses contain plain unit names, no 'in' file references

param(
    [string]$Bundle = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root 'src'
$distDir = Join-Path $root 'dist'
$bundleDir = Join-Path $PSScriptRoot 'bundles'
$enc = [System.Text.Encoding]::GetEncoding(1251)

function Parse-Unit([string]$path) {
    $text = [System.IO.File]::ReadAllText($path, $enc)
    $text = $text -replace "`r`n", "`n"

    if ($text -notmatch '(?m)^unit\s+(\w+)\s*;') { throw "no unit header in $path" }
    $unitName = $Matches[1]
    $unitEnd = $text.IndexOf(';', $text.IndexOf('unit ')) + 1

    $mInt = [regex]::Match($text, '(?m)^interface\s*$')
    $mImpl = [regex]::Match($text, '(?m)^implementation\s*$')
    if (-not $mInt.Success -or -not $mImpl.Success) { throw "missing interface/implementation in $path" }
    if ([regex]::IsMatch($text, '(?m)^finalization\s*$')) { throw "finalization section not supported: $path" }
    $mInit = [regex]::Match($text, '(?m)^initialization\s*$')
    $mEnd = [regex]::Match($text, '(?m)^end\.')
    if (-not $mEnd.Success) { throw "no final end. in $path" }

    $preBlock = $text.Substring($unitEnd, $mInt.Index - $unitEnd)
    $intBody = $text.Substring($mInt.Index + $mInt.Length, $mImpl.Index - ($mInt.Index + $mInt.Length))
    $implEnd = if ($mInit.Success) { $mInit.Index } else { $mEnd.Index }
    $implBody = $text.Substring($mImpl.Index + $mImpl.Length, $implEnd - ($mImpl.Index + $mImpl.Length))
    $initBody = ''
    if ($mInit.Success) {
        $initBody = $text.Substring($mInit.Index + $mInit.Length, $mEnd.Index - ($mInit.Index + $mInit.Length))
    }

    # strip the first uses clause of a section, returning the unit names
    $stripUses = {
        param([string]$body)
        $m = [regex]::Match($body, '(?ms)^\s*uses\b(.*?);')
        $names = @()
        if ($m.Success) {
            if ($m.Groups[1].Value -match "'") { throw "uses with 'in' reference not supported: $path" }
            $names = $m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $body = $body.Remove($m.Index, $m.Length)
        }
        ,@($body, $names)
    }

    $r = & $stripUses $intBody;  $intBody = $r[0];  $intUses = $r[1]
    $r = & $stripUses $implBody; $implBody = $r[0]; $implUses = $r[1]

    @{
        Name = $unitName
        Pre = $preBlock.Trim("`n")
        IntBody = $intBody.Trim("`n")
        ImplBody = $implBody.Trim("`n")
        InitBody = $initBody.Trim("`n")
        Uses = @($intUses) + @($implUses)
    }
}

function Build-Bundle([string]$manifestPath) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($manifestPath)
    $paths = Get-Content $manifestPath | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ }
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

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("unit $name;")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("// $name.pas - GENERATED FILE, DO NOT EDIT.")
    [void]$sb.AppendLine('// Single-file bundle amalgamated from the DelphiBoostPack modular units:')
    foreach ($p in $paths) { [void]$sb.AppendLine("//   src\$($p -replace '/', '\')") }
    [void]$sb.AppendLine("// Source commit $commit, generated $stamp by tools\Amalgamate.ps1.")
    [void]$sb.AppendLine('// Fix bugs in the modular units, then regenerate with:')
    [void]$sb.AppendLine('//   powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1')
    [void]$sb.AppendLine('// Notes:')
    [void]$sb.AppendLine('// - use at most one bundle per project; two bundles embedding the same')
    [void]$sb.AppendLine('//   helper unit would declare duplicate identifiers')
    [void]$sb.AppendLine('// - unit-wide compiler directives of embedded units (e.g. {$Q-} in the')
    [void]$sb.AppendLine('//   hash units) apply from their position to the end of this file')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('interface')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('uses')
    [void]$sb.AppendLine("  $($uses -join ', ');")
    foreach ($u in $units) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("// $bar")
        [void]$sb.AppendLine("// $($u.Name).pas - interface")
        [void]$sb.AppendLine("// $bar")
        [void]$sb.AppendLine('')
        if ($u.Pre) { [void]$sb.AppendLine($u.Pre); [void]$sb.AppendLine('') }
        [void]$sb.AppendLine($u.IntBody)
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('implementation')
    foreach ($u in $units) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("// $bar")
        [void]$sb.AppendLine("// $($u.Name).pas - implementation")
        [void]$sb.AppendLine("// $bar")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($u.ImplBody)
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

    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory $distDir | Out-Null }
    $outPath = Join-Path $distDir "$name.pas"
    # unit bodies were normalized to LF on input, AppendLine emits CRLF;
    # normalize everything to LF first so no line ends up as CR CR LF
    $out = $sb.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($outPath, $out, $enc)
    Write-Host "generated $outPath ($($units.Count) units, $((($out -split "`r`n").Count)) lines)"
}

$manifests = Get-ChildItem $bundleDir -Filter '*.manifest'
if ($Bundle) { $manifests = $manifests | Where-Object { $_.BaseName -eq $Bundle } }
if (-not $manifests) { throw "no manifest found for '$Bundle' in $bundleDir" }
foreach ($m in $manifests) { Build-Bundle $m.FullName }
