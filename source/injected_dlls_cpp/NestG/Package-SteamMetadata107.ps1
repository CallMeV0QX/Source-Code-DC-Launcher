param(
    [Parameter(Mandatory = $true)][string]$SteamDirectory,
    [string]$RepositoryRoot,
    [string]$MetadataDirectory,
    [string]$ReportPath
)
# Reproduce the reviewed metadata-only release. Steam is inspected read-only.
# No Steam process is started, closed or loaded; no existing release is modified.
$ErrorActionPreference = 'Stop'
if (!$RepositoryRoot) { $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')) }
$utf8 = [Text.UTF8Encoding]::new($false)
$bundleRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'))
$previous = Join-Path $bundleRoot '1.0.6'
$destination = Join-Path $bundleRoot '1.0.7'
$pinRoot = Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles'
$historicalPin = Join-Path $pinRoot 'bettersteamtools-cloud-1.0.6.json'
$currentPin = Join-Path $pinRoot 'bettersteamtools-cloud.json'
if (Test-Path -LiteralPath $destination) { throw 'Release 1.0.7 already exists; releases are immutable.' }

function Assert-File([string]$Path, [long]$Size, [string]$Sha256) {
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($info.PSIsContainer -or $info.Length -ne $Size -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Reviewed size/SHA-256 mismatch: $Path"
    }
}
function Read-Tables([string]$Text) {
    $tables = [ordered]@{}
    foreach ($match in [regex]::Matches($Text, '(?ms)^\[(?<key>[^\]\r\n]+)\]\r?\n(?<body>.*?)(?=^\[|\z)')) {
        $key = $match.Groups['key'].Value
        if ($tables.Contains($key)) { throw "Duplicate metadata table: $key" }
        $tables.Add($key, $match.Groups['body'].Value)
    }
    if ($tables.Count -eq 0) { throw 'No metadata tables' }
    return $tables
}
function Read-Field([string]$Body, [string]$Name) {
    $match = [regex]::Match($Body, '(?m)^' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<value>[^"]+)"|(?<value>[0-9]+))\s*$')
    if (!$match.Success) { throw "Missing metadata field: $Name" }
    return $match.Groups['value'].Value
}
function Get-Fnv([string]$Name) {
    [uint64]$hash = 2166136261
    foreach ($value in [Text.Encoding]::UTF8.GetBytes($Name)) {
        $hash = [uint64](([decimal]($hash -bxor [uint64]$value) * 16777619) % 4294967296)
    }
    return ('0x{0:X8}' -f $hash)
}

$previousManifestPath = Join-Path $previous 'bundle.json'
$previousManifestHash = 'D1E4BF524E3E51DDA9B27A04F21C9B1A2E231E7E23CFABBF58A6A2FE529703D2'
if ((Get-FileHash -LiteralPath $previousManifestPath).Hash -ne $previousManifestHash) { throw 'The reviewed 1.0.6 manifest has changed.' }
$manifest = [IO.File]::ReadAllText($previousManifestPath) | ConvertFrom-Json
if ($manifest.version -ne '1.0.6' -or $manifest.bundleId -ne 'bettersteamtools-cloud' -or $manifest.files.Count -ne 14) {
    throw 'Invalid predecessor identity/file count.'
}
foreach ($file in $manifest.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $previous $file.relativePath))
    if (!$path.StartsWith($previous + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Previous release path escapes its directory.' }
    Assert-File $path $file.size $file.sha256
}
if ((Test-Path -LiteralPath $historicalPin) -and (Get-FileHash -LiteralPath $historicalPin).Hash -ne $previousManifestHash) {
    throw 'Historical 1.0.6 pin differs from its immutable manifest.'
}
$existingPin = [IO.File]::ReadAllText($currentPin) | ConvertFrom-Json
if (($existingPin | ConvertTo-Json -Depth 8 -Compress) -ne ($manifest | ConvertTo-Json -Depth 8 -Compress)) {
    throw 'The current desktop pin is not the predecessor release.'
}
$latestPath = Join-Path $bundleRoot 'latest.json'
$latestHash = (Get-FileHash -LiteralPath $latestPath).Hash
if (([IO.File]::ReadAllText($latestPath) | ConvertFrom-Json).version -ne '1.0.1') { throw 'Historical latest pointer must remain 1.0.1.' }

$modulePins = @{
    'steamclient64.dll' = 'e9045710ec7ee47d7b7488d1c5dda2d933dec7e251e965967a5c48f4df68eb4e'
    'steamui.dll' = '1b9457943205dc3af0bd53463ba331cbd2a381388699705c02271aac7a2b1252'
}
foreach ($module in $modulePins.GetEnumerator()) {
    if ((Get-FileHash -LiteralPath (Join-Path $SteamDirectory $module.Key)).Hash -ne $module.Value) { throw "Steam module differs from the reviewed build: $($module.Key)" }
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('NestG-Metadata107-Package-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work '1.0.7'
$upstreamRoot = Join-Path $work 'upstream'
[IO.Directory]::CreateDirectory($stage) | Out-Null
$additions = @(
    @{ channel = 'pattern'; component = 'steamclient'; module = $modulePins['steamclient64.dll']; commit = '1adb2b487819a29323129f6bb345b2536746d6bd'; size = 3170; sha256 = 'D91928573C26F319A3746EA89848A30F3D202CBE7244502047EC3ED225D58945'; releasedSize = 3520; releasedSha256 = '5EC9FDB214D050C7FCB4C76B7C48A87830DCD1C93C4C5B1E31A3A149329F71A8' },
    @{ channel = 'pattern'; component = 'steamui'; module = $modulePins['steamui.dll']; commit = '1adb2b487819a29323129f6bb345b2536746d6bd'; size = 1307; sha256 = 'DC5600964A31903EBFA67CCECEB3A88224A944F87C3E1E08C854FE011E5D4DA5'; releasedSize = 1307; releasedSha256 = 'DC5600964A31903EBFA67CCECEB3A88224A944F87C3E1E08C854FE011E5D4DA5' },
    @{ channel = 'ipc'; component = 'steamclient'; module = $modulePins['steamclient64.dll']; commit = '2c222692d85523dd3e2bb1c9ff60a2c77637bde4'; size = 934; sha256 = 'F0E29ED84BFDB7036310E9AD062900356E73F4EAEE0B18240896B58CF7453973'; releasedSize = 934; releasedSha256 = 'F0E29ED84BFDB7036310E9AD062900356E73F4EAEE0B18240896B58CF7453973' }
)
$provenance = @()
foreach ($addition in $additions) {
    $relative = "opensteamtool/$($addition.channel)/$($addition.component)/$($addition.module).toml"
    $upstream = Join-Path $upstreamRoot $relative
    [IO.Directory]::CreateDirectory((Split-Path $upstream)) | Out-Null
    $uri = "https://raw.githubusercontent.com/madoiscool/steam-monitor/$($addition.commit)/$($addition.component)/$($addition.module).toml"
    if ($MetadataDirectory) { Copy-Item -LiteralPath (Join-Path $MetadataDirectory $relative) -Destination $upstream }
    else { Invoke-WebRequest -Uri $uri -OutFile $upstream -UseBasicParsing -TimeoutSec 60 }
    Assert-File $upstream $addition.size $addition.sha256
    $target = Join-Path $stage $relative
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath $upstream -Destination $target
    $provenance += [PSCustomObject]@{ relativePath = $relative; upstreamCommit = $addition.commit; upstreamUrl = $uri; upstreamSha256 = $addition.sha256; releasedSha256 = $addition.releasedSha256 }
}

# The reviewed native source hashes the unqualified KeyValues consumer names.
# Upstream uses class-qualified names. Keep those entries and add legal aliases
# with the same NEW-build RVA/signature; no address is copied from an old build.
$clientRelative = "opensteamtool/pattern/steamclient/$($modulePins['steamclient64.dll']).toml"
$clientPath = Join-Path $stage $clientRelative
$originalClient = [IO.File]::ReadAllText($clientPath)
$tables = Read-Tables $originalClient
$aliases = @(
    @{ original = '0xED5ED0C8'; key = '0x45A87956'; name = 'FindOrCreateKey'; originalName = 'KeyValues_FindOrCreateKey' },
    @{ original = '0x2434A8BA'; key = '0x40679C34'; name = 'ReadAsBinary'; originalName = 'KeyValues_ReadAsBinary' }
)
$derived = $originalClient.Replace("`r`n", "`n").TrimEnd([char[]]"`r`n")
$derived += "`n`n# NestG aliases for the immutable 1.0.6 native KeyValues consumer names.`n# RVAs/signatures are copied from this Steam build's upstream entries.`n"
foreach ($alias in $aliases) {
    if ($tables.Contains($alias.key) -or (Get-Fnv $alias.name) -ne $alias.key -or
        (Read-Field $tables[$alias.original] 'name') -ne $alias.originalName) { throw 'KeyValues alias conflicts with its reviewed source/key.' }
    $rva = Read-Field $tables[$alias.original] 'rva'
    $signature = Read-Field $tables[$alias.original] 'sig'
    $derived += '[' + $alias.key + "]`nname = `"" + $alias.name + "`"`nrva = `"" + $rva + "`"`nsig = `"" + $signature + "`"`n`n"
}
[IO.File]::WriteAllText($clientPath, $derived.TrimEnd([char[]]"`r`n") + "`n", $utf8)
foreach ($addition in $additions) {
    $relative = "opensteamtool/$($addition.channel)/$($addition.component)/$($addition.module).toml"
    Assert-File (Join-Path $stage $relative) $addition.releasedSize $addition.releasedSha256
    $manifest.files += [PSCustomObject]@{ relativePath = $relative; installPath = $relative; size = $addition.releasedSize; sha256 = $addition.releasedSha256 }
}

# Inspect the exact corresponding native source archive without compiling or
# loading it. Every active signature consumer and IPC handler must be present.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$native = @{}
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $previous 'sources/BetterSteamTools-NestG-source.zip'))
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -notmatch '^src/.*\.(cpp|h|steamd)$') { continue }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $native[$entry.FullName] = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
} finally { $zip.Dispose() }
$patternMaps = @{
    C = (Read-Tables ([IO.File]::ReadAllText($clientPath)))
    U = (Read-Tables ([IO.File]::ReadAllText((Join-Path $stage "opensteamtool/pattern/steamui/$($modulePins['steamui.dll']).toml"))))
}
foreach ($map in $patternMaps.Values) {
    foreach ($entry in $map.GetEnumerator()) {
        if ((Get-Fnv (Read-Field $entry.Value 'name')) -ne $entry.Key) { throw 'Pattern table key disagrees with the native FNV name.' }
    }
}
if ($native['src/Hook/HookMacros.h'] -notmatch 'PatternLoader::FindPattern\(module, #name\)' -or
    $native['src/Utils/SteamMetadata/PatternLoader.cpp'] -notmatch 'uint32_t key = Fnv1aHash\(funcName\)') { throw 'Native pattern lookup contract has changed.' }
$consumerCount = 0
$ipcHandlers = @()
foreach ($entry in $native.GetEnumerator()) {
    if ($entry.Key -notlike '*.cpp') { continue }
    $source = [regex]::Replace($entry.Value, '(?s)/\*.*?\*/|(?m)//[^\r\n]*', '')
    foreach ($match in [regex]::Matches($source, '\b(?:INSTALL_HOOK|RESOLVE|ARM_CAPTURE|ARM_INT3)_(?<component>C|U)\(\s*(?<function>\w+)')) {
        $key = Get-Fnv $match.Groups['function'].Value
        if (!$patternMaps[$match.Groups['component'].Value].Contains($key)) { throw "Missing native pattern: $($match.Groups['function'].Value)" }
        $consumerCount++
    }
    foreach ($match in [regex]::Matches($source, 'ADD_IPC_(?:POST|PRE)_HANDLER\(\s*(?<interface>\w+)\s*,\s*(?<method>\w+)')) {
        $ipcHandlers += $match.Groups['interface'].Value + '.' + $match.Groups['method'].Value
    }
}
if ($consumerCount -ne 28 -or $ipcHandlers.Count -ne 6) { throw 'Native consumer/handler count differs from the reviewed source.' }
$ipcRelative = "opensteamtool/ipc/steamclient/$($modulePins['steamclient64.dll']).toml"
$newIpc = Read-Tables ([IO.File]::ReadAllText((Join-Path $stage $ipcRelative)))
$oldIpc = Read-Tables ([IO.File]::ReadAllText((Join-Path $previous 'opensteamtool/ipc/steamclient/caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee.toml')))
foreach ($handler in $ipcHandlers) {
    foreach ($field in @('funcHash', 'fencepost', 'argc')) {
        if ((Read-Field $newIpc[$handler] $field) -ne (Read-Field $oldIpc[$handler] $field)) { throw "IPC native field changed: $handler / $field" }
    }
}
foreach ($interface in @(@{ name = 'IClientUser'; id = '1' }, @{ name = 'IClientUtils'; id = '4' })) {
    if ((Read-Field $newIpc[$interface.name] 'interface_id') -ne $interface.id -or
        $native['src/Steam/IPCMessages.steamd'] -notmatch ('(?m)^\s*' + $interface.name + '\s*=\s*' + $interface.id + ';')) { throw 'IPC interface differs from the native enum.' }
}
$staticReport = Join-Path $work 'steam-static-verification.json'
$static = (& (Join-Path $PSScriptRoot 'Test-SteamMetadata.ps1') -SteamDirectory $SteamDirectory -MetadataDirectory $stage -ReportPath $staticReport | Out-String) | ConvertFrom-Json
if (!$static.staticChecksPassed -or $static.modules[0].patternsMatched -ne 28 -or
    $static.modules[0].ipcVtableEntriesMatched -ne 6 -or $static.modules[1].patternsMatched -ne 10) { throw 'Static Steam verification did not cover the reviewed metadata.' }
foreach ($module in $modulePins.GetEnumerator()) {
    if ((Get-FileHash -LiteralPath (Join-Path $SteamDirectory $module.Key)).Hash -ne $module.Value) { throw 'Steam changed during static verification.' }
}

foreach ($file in $manifest.files | Select-Object -First 14) {
    $target = Join-Path $stage $file.relativePath
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $previous $file.relativePath) -Destination $target
    Assert-File $target $file.size $file.sha256
}
$manifest.version = '1.0.7'
$json = ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n", "`n") + "`n"
[IO.File]::WriteAllText((Join-Path $stage 'bundle.json'), $json, $utf8)
if ($manifest.files.Count -ne 17 -or (Get-FileHash -LiteralPath $latestPath).Hash -ne $latestHash -or
    (Get-FileHash -LiteralPath $previousManifestPath).Hash -ne $previousManifestHash) { throw 'Release predecessor/latest integrity changed.' }
if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($destination)) -ne $bundleRoot -or
    [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($stage)) -ne [IO.Path]::GetFullPath($work)) { throw 'Release move escapes its intended directory.' }
Move-Item -LiteralPath $stage -Destination $destination
Copy-Item -LiteralPath $previousManifestPath -Destination $historicalPin
[IO.File]::WriteAllText($currentPin, $json, $utf8)
$report = [PSCustomObject]@{
    createdAtUtc = [DateTime]::UtcNow.ToString('o'); version = '1.0.7'; fullFiles = 17; coreFiles = 16
    predecessorPayloadsByteIdentical = 14; nativeBinariesRebuilt = $false
    nativePatternConsumersMatched = $consumerCount; nativeIpcHandlersMatched = $ipcHandlers.Count
    aliases = $aliases; metadata = $provenance; staticVerification = $static
    latestPointer = '1.0.1'; workDirectory = $work
    nativeE2E = 'Not run. Static verification does not prove hook ABI, game activation or Steam/save round-trip.'
}
$reportJson = ($report | ConvertTo-Json -Depth 9) + "`n"
[IO.File]::WriteAllText((Join-Path $work 'release-verification.json'), $reportJson, $utf8)
if ($ReportPath) {
    $fullReport = [IO.Path]::GetFullPath($ReportPath)
    [IO.Directory]::CreateDirectory((Split-Path $fullReport)) | Out-Null
    [IO.File]::WriteAllText($fullReport, $reportJson, $utf8)
}
Write-Output $reportJson
