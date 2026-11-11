param(
    [Parameter(Mandatory = $true)][string]$SteamDirectory,
    [Parameter(Mandatory = $true)][string]$MetadataDirectory,
    [string]$ReportPath
)
# Static inspection only: no DLL loading, process control, Steam writes or save access.
$ErrorActionPreference = 'Stop'
function Read-Pe([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5a4d) { throw 'Invalid DOS header' }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($pe -lt 0 -or $pe + 264 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x4550 -or
        [BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664 -or [BitConverter]::ToUInt16($bytes, $pe + 24) -ne 0x20b) {
        throw 'Expected PE32+ x64 image'
    }
    $count = [BitConverter]::ToUInt16($bytes, $pe + 6)
    $sectionOffset = $pe + 24 + [BitConverter]::ToUInt16($bytes, $pe + 20)
    $sections = @()
    for ($index = 0; $index -lt $count; $index++) {
        $offset = $sectionOffset + 40 * $index
        if ($offset + 40 -gt $bytes.Length) { throw 'Truncated section table' }
        $sections += [PSCustomObject]@{
            rva = [BitConverter]::ToUInt32($bytes, $offset + 12)
            rawSize = [BitConverter]::ToUInt32($bytes, $offset + 16)
            raw = [BitConverter]::ToUInt32($bytes, $offset + 20)
            executable = ([BitConverter]::ToUInt32($bytes, $offset + 36) -band 0x20000000) -ne 0
        }
    }
    return [PSCustomObject]@{ bytes = $bytes; sections = $sections; imageBase = [BitConverter]::ToUInt64($bytes, $pe + 48) }
}
function Resolve-Rva($Image, [long]$Rva, [int]$Length, [bool]$Executable = $false) {
    foreach ($section in $Image.sections) {
        if ($Rva -ge $section.rva -and $Rva + $Length -le [long]$section.rva + $section.rawSize) {
            $offset = [long]$section.raw + $Rva - $section.rva
            if ($offset + $Length -gt $Image.bytes.Length -or ($Executable -and !$section.executable)) {
                throw 'RVA is not backed by the expected section'
            }
            return [int]$offset
        }
    }
    throw ('Unmapped RVA: 0x{0:X}' -f $Rva)
}
function Read-Tables([string]$Path) {
    $tables = [ordered]@{}
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($Path), '(?ms)^\[(?<key>[^\]\r\n]+)\]\r?\n(?<body>.*?)(?=^\[|\z)')) {
        if ($tables.Contains($match.Groups['key'].Value)) { throw 'Duplicate metadata table' }
        $tables.Add($match.Groups['key'].Value, $match.Groups['body'].Value)
    }
    if ($tables.Count -eq 0) { throw 'No metadata tables' }
    return $tables
}
function Read-Field([string]$Body, [string]$Name) {
    $match = [regex]::Match($Body, '(?m)^' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<v>[^"]+)"|(?<v>[0-9]+))\s*$')
    if (!$match.Success) { throw "Missing metadata field: $Name" }
    return $match.Groups['v'].Value
}
function Read-Hex([string]$Value) { return [Convert]::ToInt64($Value.Replace('0x', ''), 16) }

$checks = @()
foreach ($module in @(@{ name='steamclient64.dll'; component='steamclient' }, @{ name='steamui.dll'; component='steamui' })) {
    $modulePath = Join-Path $SteamDirectory $module.name
    $hash = (Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $image = Read-Pe $modulePath
    $patterns = Read-Tables (Join-Path $MetadataDirectory "opensteamtool/pattern/$($module.component)/$hash.toml")
    foreach ($entry in $patterns.GetEnumerator()) {
        $name = Read-Field $entry.Value 'name'
        $rva = Read-Hex (Read-Field $entry.Value 'rva')
        $signature = (Read-Field $entry.Value 'sig') -split '\s+'
        $offset = Resolve-Rva $image $rva $signature.Count $true
        for ($index = 0; $index -lt $signature.Count; $index++) {
            if ($signature[$index] -in @('?', '??')) { continue }
            if ($image.bytes[$offset + $index] -ne [Convert]::ToByte($signature[$index], 16)) {
                throw "Pattern does not match module bytes: $($module.name) / $name"
            }
        }
    }
    $ipcMethods = 0
    if ($module.component -eq 'steamclient') {
        $ipc = Read-Tables (Join-Path $MetadataDirectory "opensteamtool/ipc/steamclient/$hash.toml")
        foreach ($entry in $ipc.GetEnumerator()) {
            if (!$entry.Key.Contains('.')) { continue }
            $interface = $entry.Key.Split('.')[0]
            $vtableRva = Read-Hex (Read-Field $ipc[$interface] 'vtable_rva')
            $methodIndex = [int](Read-Field $entry.Value 'method_index')
            $wrapperRva = Read-Hex (Read-Field $entry.Value 'wrapper_rva')
            $slot = Resolve-Rva $image ($vtableRva + 8 * $methodIndex) 8
            if ([BitConverter]::ToUInt64($image.bytes, $slot) -ne $image.imageBase + $wrapperRva) {
                throw "IPC vtable entry does not match wrapper: $($entry.Key)"
            }
            $null = Resolve-Rva $image $wrapperRva 1 $true
            $ipcMethods++
        }
        if ($ipcMethods -eq 0) { throw 'Missing IPC methods' }
    }
    $checks += [PSCustomObject]@{ module = $module.name; sha256 = $hash; patternsMatched = $patterns.Count; ipcVtableEntriesMatched = $ipcMethods }
}
$json = [PSCustomObject]@{ checkedAtUtc = [DateTime]::UtcNow.ToString('o'); staticChecksPassed = $true; modules = $checks;
    nativeE2E = 'Not run. Static signature/vtable checks do not prove game activation or save round-trip.' } | ConvertTo-Json -Depth 5
if ($ReportPath) {
    $fullReport = [IO.Path]::GetFullPath($ReportPath)
    [IO.Directory]::CreateDirectory((Split-Path $fullReport)) | Out-Null
    [IO.File]::WriteAllText($fullReport, $json + "`n", [Text.UTF8Encoding]::new($false))
}
Write-Output $json
