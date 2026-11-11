param(
    [Parameter(Mandatory = $true)][string]$SteamDirectory,
    [string]$RepositoryRoot,
    [string]$MetadataDirectory,
    [string]$ReportPath
)
# Reproduce the reviewed metadata-only 1.0.11 release. Steam is read-only:
# no DLL loading, process control, installation, account access or save access.
$ErrorActionPreference = 'Stop'
if (!$RepositoryRoot) { $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')) }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$SteamDirectory = (Resolve-Path -LiteralPath $SteamDirectory).Path
$utf8 = [Text.UTF8Encoding]::new($false)
$bundleRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'))
$previous = Join-Path $bundleRoot '1.0.10'
$destination = Join-Path $bundleRoot '1.0.11'
$pinRoot = Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles'
$historicalPin = Join-Path $pinRoot 'bettersteamtools-cloud-1.0.10.json'
$currentPin = Join-Path $pinRoot 'bettersteamtools-cloud.json'

function Assert-OutsideSteam([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath.Equals($SteamDirectory, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($SteamDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package output must not be inside the inspected Steam installation.'
    }
}
function Assert-NoReparsePoint([string]$Path) {
    for ($item = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path)); $null -ne $item; $item = $item.Parent) {
        if ($item.Exists -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Package paths must not traverse a directory reparse point.'
        }
    }
}
foreach ($path in @($bundleRoot, $pinRoot, (Join-Path $RepositoryRoot '.codex-temp'))) {
    Assert-OutsideSteam $path
    Assert-NoReparsePoint $path
}
if ($ReportPath) {
    $ReportPath = [IO.Path]::GetFullPath($ReportPath)
    Assert-OutsideSteam $ReportPath
    Assert-NoReparsePoint (Split-Path $ReportPath)
    foreach ($immutableRoot in @($bundleRoot, $pinRoot)) {
        if ($ReportPath.Equals($immutableRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $ReportPath.StartsWith($immutableRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Reports must be outside immutable bundle artifacts and desktop pins.'
        }
    }
    if (Test-Path -LiteralPath $ReportPath) { throw 'Use a new report path; existing evidence is not overwritten.' }
}
if (Test-Path -LiteralPath $destination) { throw 'Release 1.0.11 already exists; releases are immutable.' }

function Assert-File([string]$Path, [long]$Size, [string]$Sha256) {
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $info.Length -ne $Size -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Reviewed size/SHA-256 mismatch: $Path"
    }
    Assert-NoReparsePoint $info.DirectoryName
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
    $matches = [regex]::Matches($Body, '(?m)^' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<value>[^"]+)"|(?<value>[0-9]+))\s*$')
    if ($matches.Count -ne 1) { throw "Missing or duplicate metadata field: $Name" }
    return $matches[0].Groups['value'].Value
}
function Get-Fnv([string]$Name) {
    [uint64]$hash = 2166136261
    foreach ($value in [Text.Encoding]::UTF8.GetBytes($Name)) {
        $hash = [uint64](([decimal]($hash -bxor [uint64]$value) * 16777619) % 4294967296)
    }
    return ('0x{0:X8}' -f $hash)
}

$previousManifestPath = Join-Path $previous 'bundle.json'
$previousManifestHash = 'D452602E79A4CD1F220EEF21702F418E565FD85DA68D88C38AED03B2286B357A'
Assert-File $previousManifestPath 7110 $previousManifestHash
$manifest = [IO.File]::ReadAllText($previousManifestPath) | ConvertFrom-Json
if ($manifest.version -ne '1.0.10' -or $manifest.bundleId -ne 'bettersteamtools-cloud' -or $manifest.files.Count -ne 17) {
    throw 'Invalid predecessor identity/file count.'
}
$predecessorFiles = @($manifest.files)
function Assert-Predecessor {
    Assert-File $previousManifestPath 7110 $previousManifestHash
    foreach ($file in $predecessorFiles) {
        $path = [IO.Path]::GetFullPath((Join-Path $previous $file.relativePath))
        if (!$path.StartsWith($previous + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Previous release path escapes its directory.'
        }
        Assert-File $path $file.size $file.sha256
    }
}
Assert-Predecessor
if (Test-Path -LiteralPath $historicalPin) { Assert-File $historicalPin 7110 $previousManifestHash }
Assert-File $currentPin 7110 $previousManifestHash
$latestPath = Join-Path $bundleRoot 'latest.json'
$latestHash = '6A33E5F4B8FE43D76BFA8AD1C14FBBAE5A9ABAD68194DC331B17C8B0D1415185'
Assert-File $latestPath 20 $latestHash
if (([IO.File]::ReadAllText($latestPath) | ConvertFrom-Json).version -ne '1.0.1') {
    throw 'Historical latest pointer must remain 1.0.1.'
}

$modulePins = @{
    'steamclient64.dll' = '253e0a11a4415b38c78a42f7bdd6ecc426455f06c1ba6453a48090df3142dbbc'
    'steamui.dll' = 'cd9226db4e6c28942df70c22c0475d91fdd62cba5f100baae2d65af57cabb610'
}
function Assert-SteamModules {
    foreach ($module in $modulePins.GetEnumerator()) {
        if ((Get-FileHash -LiteralPath (Join-Path $SteamDirectory $module.Key)).Hash -ne $module.Value) {
            throw "Steam module differs from the reviewed build: $($module.Key)"
        }
    }
}
Assert-SteamModules
$work = Join-Path $RepositoryRoot ('.codex-temp/steam-metadata-111-package-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work '1.0.11'
$upstreamRoot = Join-Path $work 'upstream'
[IO.Directory]::CreateDirectory($stage) | Out-Null
$additions = @(
    @{ channel = 'pattern'; component = 'steamclient'; module = $modulePins['steamclient64.dll']; commit = 'fe29b4ec7b19aacd317c0756938d9529add24b90'; size = 3170; sha256 = 'FC22481F939E97B8AA7928C5B260F547B26DF47997CA51971367D6AC17EFD606'; releasedSize = 3521; releasedSha256 = 'AD8AC746FB938FC7B899697348E14FEA03F53C66858900801A7C5A9B4B73C4A4' },
    @{ channel = 'pattern'; component = 'steamui'; module = $modulePins['steamui.dll']; commit = 'fe29b4ec7b19aacd317c0756938d9529add24b90'; size = 1307; sha256 = 'A5F0A8FAE28B7F2626CE2C052217A87C9D909F822B0B73C91AEC74DBAAD3EA8F'; releasedSize = 1307; releasedSha256 = 'A5F0A8FAE28B7F2626CE2C052217A87C9D909F822B0B73C91AEC74DBAAD3EA8F' },
    @{ channel = 'ipc'; component = 'steamclient'; module = $modulePins['steamclient64.dll']; commit = 'fc803cc9e9e5ab1575685d3279c5092a2538e0cd'; size = 934; sha256 = '3EB894879B1FBB8F2B7DB5963BA12E52FD5FD63EA19EC2FC5379F63CB3337193'; releasedSize = 934; releasedSha256 = '3EB894879B1FBB8F2B7DB5963BA12E52FD5FD63EA19EC2FC5379F63CB3337193' }
)
$provenance = @()
foreach ($addition in $additions) {
    $relative = "opensteamtool/$($addition.channel)/$($addition.component)/$($addition.module).toml"
    if ($relative -in $predecessorFiles.installPath) { throw 'New metadata would overwrite a predecessor payload.' }
    $upstream = Join-Path $upstreamRoot $relative
    [IO.Directory]::CreateDirectory((Split-Path $upstream)) | Out-Null
    $uri = "https://raw.githubusercontent.com/madoiscool/steam-monitor/$($addition.commit)/$($addition.component)/$($addition.module).toml"
    if ($MetadataDirectory) { Copy-Item -LiteralPath (Join-Path $MetadataDirectory $relative) -Destination $upstream }
    else { Invoke-WebRequest -Uri $uri -OutFile $upstream -UseBasicParsing -TimeoutSec 60 }
    Assert-File $upstream $addition.size $addition.sha256
    $target = Join-Path $stage $relative
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath $upstream -Destination $target
    $provenance += [PSCustomObject]@{
        relativePath = $relative; upstreamCommit = $addition.commit; upstreamUrl = $uri
        upstreamSize = $addition.size; upstreamSha256 = $addition.sha256
        releasedSize = $addition.releasedSize; releasedSha256 = $addition.releasedSha256
    }
}

# Preserve upstream names and derive only the two names required by the exact
# immutable 1.0.10 native source, using this NEW Steam build's RVA/signature.
$clientRelative = "opensteamtool/pattern/steamclient/$($modulePins['steamclient64.dll']).toml"
$clientPath = Join-Path $stage $clientRelative
$originalClient = [IO.File]::ReadAllText($clientPath)
$tables = Read-Tables $originalClient
$aliases = @(
    @{ original = '0xED5ED0C8'; key = '0x45A87956'; name = 'FindOrCreateKey'; originalName = 'KeyValues_FindOrCreateKey' },
    @{ original = '0x2434A8BA'; key = '0x40679C34'; name = 'ReadAsBinary'; originalName = 'KeyValues_ReadAsBinary' }
)
$derived = $originalClient.Replace("`r`n", "`n").TrimEnd([char[]]"`r`n")
$derived += "`n`n# NestG aliases for the immutable 1.0.10 native KeyValues consumer names.`n# RVAs/signatures are copied from this Steam build's upstream entries.`n"
foreach ($alias in $aliases) {
    if ($tables.Contains($alias.key) -or !$tables.Contains($alias.original) -or (Get-Fnv $alias.name) -ne $alias.key -or
        (Read-Field $tables[$alias.original] 'name') -ne $alias.originalName) {
        throw 'KeyValues alias conflicts with its reviewed source/key.'
    }
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

# Inspect source in memory: both macro consumers and the five direct lookups
# introduced by the current native build must be covered, without compiling it.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$native = @{}
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $previous 'sources/BetterSteamTools-NestG-source.zip'))
try {
    if ($zip.Entries.Count -ne 3330) { throw 'Corresponding source archive entry count changed.' }
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -notmatch '^src/.*\.(cpp|h|steamd)$') { continue }
        if ($native.ContainsKey($entry.FullName)) { throw 'Duplicate source archive entry.' }
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
    $native['src/Utils/HookSupport/VehCommon.h'] -notmatch 'PatternLoader::FindPattern\(module, #name\)' -or
    $native['src/Utils/SteamMetadata/PatternLoader.cpp'] -notmatch 'uint32_t key = Fnv1aHash\(funcName\)') {
    throw 'Native pattern lookup contract has changed.'
}
$consumers = @()
$ipcHandlers = @()
$macroCount = 0
$directCount = 0
foreach ($entry in $native.GetEnumerator()) {
    if ($entry.Key -notlike '*.cpp') { continue }
    $source = [regex]::Replace($entry.Value, '(?s)/\*.*?\*/|(?m)//[^\r\n]*', '')
    foreach ($match in [regex]::Matches($source, '\b(?:INSTALL_HOOK|RESOLVE|ARM_CAPTURE|ARM_INT3)_(?<component>C|U)\(\s*(?<function>\w+)')) {
        $consumers += [PSCustomObject]@{ component = $match.Groups['component'].Value; name = $match.Groups['function'].Value; source = $entry.Key; kind = 'macro' }
        $macroCount++
    }
    $direct = [regex]::Matches($source, '\bPatternLoader::FindPattern\s*\(\s*(?<module>client_hModule|ui_hModule)\s*,\s*"(?<function>\w+)"\s*\)')
    if ($direct.Count -ne [regex]::Matches($source, '\bPatternLoader::FindPattern\s*\(').Count) {
        throw 'Unreviewed dynamic or indirect native pattern lookup.'
    }
    foreach ($match in $direct) {
        $component = if ($match.Groups['module'].Value -eq 'client_hModule') { 'C' } else { 'U' }
        $consumers += [PSCustomObject]@{ component = $component; name = $match.Groups['function'].Value; source = $entry.Key; kind = 'direct' }
        $directCount++
    }
    foreach ($match in [regex]::Matches($source, 'ADD_IPC_(?:POST|PRE)_HANDLER\(\s*(?<interface>\w+)\s*,\s*(?<method>\w+)')) {
        $ipcHandlers += $match.Groups['interface'].Value + '.' + $match.Groups['method'].Value
    }
}
foreach ($consumer in $consumers) {
    if (!$patternMaps[$consumer.component].Contains((Get-Fnv $consumer.name))) { throw "Missing native pattern: $($consumer.name)" }
}
if ($macroCount -ne 23 -or $directCount -ne 5 -or $consumers.Count -ne 28 -or
    @($consumers | Where-Object component -eq 'C').Count -ne 22 -or
    @($consumers | Where-Object component -eq 'U').Count -ne 6 -or
    @($consumers | ForEach-Object { $_.component + ':' + $_.name } | Select-Object -Unique).Count -ne 28 -or
    $ipcHandlers.Count -ne 6 -or @($ipcHandlers | Select-Object -Unique).Count -ne 6) {
    throw 'Native consumer/handler coverage differs from the reviewed 1.0.10 source.'
}
$ipcRelative = "opensteamtool/ipc/steamclient/$($modulePins['steamclient64.dll']).toml"
$newIpc = Read-Tables ([IO.File]::ReadAllText((Join-Path $stage $ipcRelative)))
$oldIpc = Read-Tables ([IO.File]::ReadAllText((Join-Path $previous 'opensteamtool/ipc/steamclient/e9045710ec7ee47d7b7488d1c5dda2d933dec7e251e965967a5c48f4df68eb4e.toml')))
if (@($newIpc.Keys | Where-Object { $_.Contains('.') }).Count -ne $ipcHandlers.Count) { throw 'IPC method set differs from native handlers.' }
foreach ($handler in $ipcHandlers) {
    if (!$newIpc.Contains($handler) -or !$oldIpc.Contains($handler)) { throw "Missing IPC native handler: $handler" }
    foreach ($field in @('funcHash', 'fencepost', 'argc')) {
        if ((Read-Field $newIpc[$handler] $field) -ne (Read-Field $oldIpc[$handler] $field)) { throw "IPC native field changed: $handler / $field" }
    }
}
foreach ($interface in @(@{ name = 'IClientUser'; id = '1' }, @{ name = 'IClientUtils'; id = '4' })) {
    if ((Read-Field $newIpc[$interface.name] 'interface_id') -ne $interface.id -or
        $native['src/Steam/IPCMessages.steamd'] -notmatch ('(?m)^\s*' + $interface.name + '\s*=\s*' + $interface.id + ';')) {
        throw 'IPC interface differs from the native enum.'
    }
}
$staticReport = Join-Path $work 'steam-static-verification.json'
$static = (& (Join-Path $PSScriptRoot 'Test-SteamMetadata.ps1') -SteamDirectory $SteamDirectory -MetadataDirectory $stage -ReportPath $staticReport | Out-String) | ConvertFrom-Json
if (!$static.staticChecksPassed -or $static.modules[0].patternsMatched -ne 28 -or
    $static.modules[0].ipcVtableEntriesMatched -ne 6 -or $static.modules[1].patternsMatched -ne 10) {
    throw 'Static Steam verification did not cover all 38 reviewed patterns and six IPC entries.'
}
Assert-SteamModules

foreach ($file in $predecessorFiles) {
    $target = Join-Path $stage $file.relativePath
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $previous $file.relativePath) -Destination $target
    Assert-File $target $file.size $file.sha256
}
$manifest.version = '1.0.11'
$json = ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n", "`n") + "`n"
[IO.File]::WriteAllText((Join-Path $stage 'bundle.json'), $json, $utf8)
if ($manifest.files.Count -ne 20 -or @($manifest.files | Where-Object installPath -ne 'cloud_redirect.dll').Count -ne 19) {
    throw 'Unexpected full/core release file boundaries.'
}
foreach ($file in $manifest.files) { Assert-File (Join-Path $stage $file.relativePath) $file.size $file.sha256 }
Assert-Predecessor
Assert-File $latestPath 20 $latestHash
Assert-File $currentPin 7110 $previousManifestHash
if (Test-Path -LiteralPath $historicalPin) { Assert-File $historicalPin 7110 $previousManifestHash }
Assert-SteamModules
if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($destination)) -ne $bundleRoot -or
    [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($stage)) -ne [IO.Path]::GetFullPath($work)) {
    throw 'Release move escapes its intended directory.'
}
Assert-NoReparsePoint $bundleRoot
Assert-NoReparsePoint $pinRoot
if (Test-Path -LiteralPath $destination) { throw 'Immutable destination was created during validation.' }
# Publish the server artifact first; a pin-publication failure must never remove
# or rewrite this immutable release. The old current pin stays valid until replaced.
Move-Item -LiteralPath $stage -Destination $destination
if (!(Test-Path -LiteralPath $historicalPin)) { [IO.File]::Copy($previousManifestPath, $historicalPin, $false) }
$pinStage = Join-Path $pinRoot ('.metadata111-' + [guid]::NewGuid().ToString('N') + '.tmp')
[IO.File]::WriteAllText($pinStage, $json, $utf8)
# A nonempty diagnostic backup path also works on Windows PowerShell 5.1,
# whose binder converts a null string argument into an invalid empty path.
[IO.File]::Replace($pinStage, $currentPin, (Join-Path $work 'predecessor-client-pin.json'))
$report = [PSCustomObject]@{
    createdAtUtc = [DateTime]::UtcNow.ToString('o'); version = '1.0.11'; fullFiles = 20; coreFiles = 19
    predecessorVersion = '1.0.10'; predecessorManifestSha256 = $previousManifestHash
    predecessorPayloadsByteIdentical = 17; nativeBinariesRebuilt = $false; correspondingSourceRepacked = $false
    nativePatternConsumersMatched = $consumers.Count; nativeMacroConsumers = $macroCount; nativeDirectConsumers = $directCount
    nativeConsumers = @($consumers | Sort-Object component, name); nativeIpcHandlersMatched = $ipcHandlers.Count
    aliases = $aliases; metadata = $provenance; staticVerification = $static
    manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $destination 'bundle.json')).Hash
    sourceArchiveSha256 = (Get-FileHash -LiteralPath (Join-Path $destination 'sources/BetterSteamTools-NestG-source.zip')).Hash
    latestPointer = '1.0.1'; latestPointerSha256 = $latestHash; workDirectory = $work
    nativeE2E = 'Not run. Static verification does not prove hook ABI, game activation or Steam/save round-trip.'
}
$reportJson = ($report | ConvertTo-Json -Depth 9) + "`n"
[IO.File]::WriteAllText((Join-Path $work 'release-verification.json'), $reportJson, $utf8)
if ($ReportPath) {
    [IO.Directory]::CreateDirectory((Split-Path $ReportPath)) | Out-Null
    [IO.File]::WriteAllText($ReportPath, $reportJson, $utf8)
}
Write-Output $reportJson
