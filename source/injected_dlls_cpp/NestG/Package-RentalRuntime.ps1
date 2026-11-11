param(
    [Parameter(Mandatory = $true)][string]$NativeOutputDirectory,
    [Parameter(Mandatory = $true)][string]$CorrespondingSourceArchive,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion = '1.0.10',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$PreviousVersion = '1.0.9',
    [ValidatePattern('^\d+\.\d+\.\d+-nestg\.\d+$')][string]$NativeVersion = '1.0.4-nestg.9',
    [string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)
$ErrorActionPreference = 'Stop'
$bundleRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'))
$previous = Join-Path $bundleRoot $PreviousVersion
$destination = Join-Path $bundleRoot $ReleaseVersion
$pins = Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles'
if ([version]$ReleaseVersion -le [version]$PreviousVersion) { throw 'Release must be newer than its immutable predecessor.' }
if (Test-Path -LiteralPath $destination) { throw "Immutable release $ReleaseVersion already exists." }
$manifest = Get-Content -LiteralPath (Join-Path $previous 'bundle.json') -Raw | ConvertFrom-Json
if ($manifest.version -ne $PreviousVersion -or $manifest.bundleId -ne 'bettersteamtools-cloud' -or $manifest.files.Count -ne 17) { throw 'Invalid predecessor.' }
$latestHash = (Get-FileHash -LiteralPath (Join-Path $bundleRoot 'latest.json')).Hash
$predecessorHash = (Get-FileHash -LiteralPath (Join-Path $previous 'bundle.json')).Hash
$historicalPin = Join-Path $pins "bettersteamtools-cloud-$PreviousVersion.json"
if ((Test-Path -LiteralPath $historicalPin) -and
    (Get-FileHash -LiteralPath $historicalPin).Hash -ne (Get-FileHash -LiteralPath (Join-Path $previous 'bundle.json')).Hash) { throw 'Historical pin differs.' }
# Refuse a stale or incomplete corresponding-source ZIP before publishing any files.
# This archive must carry the same five-patch build recipe as the release being built.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceArchive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $CorrespondingSourceArchive).Path)
try {
    foreach ($required in @('src/NestG/RentalRuntime.cpp','src/NestG/RentalIdentity.cpp','src/NestG/RentalStatusPipe.cpp',
                            '.deps/detours-src/src/detours.cpp','.deps/lua-src/src/lua.h','.deps/protobuf-src/LICENSE',
                            '.deps/spdlog-src/CMakeLists.txt','.deps/tomlplusplus-src/CMakeLists.txt','NestG/Build-Runtime.ps1')) {
        if (!$sourceArchive.GetEntry($required)) { throw "Corresponding source is incomplete: $required" }
    }
    $reader = [IO.StreamReader]::new($sourceArchive.GetEntry('NestG/Build-Runtime.ps1').Open())
    try { $recipe = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if (!$recipe.Contains("-DOPENSTEAMTOOL_VERSION=$NativeVersion")) { throw 'Corresponding source has a different native build version.' }
    if ([version]$ReleaseVersion -ge [version]'1.0.10') {
        foreach ($name in @('Build-Runtime.ps1','nestg.patch','startup.patch','opensteamtool.patch','shutdown.patch','rental.patch')) {
            $entry = $sourceArchive.GetEntry("NestG/$name")
            if (!$entry) { throw "Corresponding source lacks recipe file: $name" }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $archivedHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ($archivedHash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash) { throw "Corresponding source recipe differs: $name" }
        }
    }
} finally { $sourceArchive.Dispose() }
$stagedFiles = [Collections.Generic.List[object]]::new()
foreach ($file in $manifest.files) {
    $source = [IO.Path]::GetFullPath((Join-Path $previous $file.relativePath))
    if (!$source.StartsWith($previous + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        (Get-Item -LiteralPath $source).Length -ne $file.size -or (Get-FileHash -LiteralPath $source).Hash -ne $file.sha256) { throw 'Predecessor payload integrity failed.' }
    if ($file.relativePath -in @('OpenSteamTool.dll','dwmapi.dll','xinput1_4.dll')) {
        $source = Join-Path $NativeOutputDirectory $file.relativePath
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d) { throw 'Native payload is not PE.' }
        $pe = [BitConverter]::ToInt32($bytes,0x3c)
        if ($pe -lt 0 -or $pe -gt $bytes.Length-6 -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw 'Native payload must be x64.' }
        $ascii = [Text.Encoding]::ASCII.GetString($bytes)
        if (!$ascii.Contains('NestGInitialize')) { throw 'Missing explicit proxy initialization contract.' }
        if ($file.relativePath -eq 'OpenSteamTool.dll' -and
            (!$ascii.Contains('NestGRentalRuntimeProtocolVersion') -or !$ascii.Contains('NestGRentalRuntimeCapabilities'))) { throw 'Missing rental capabilities.' }
        if ($file.relativePath -eq 'OpenSteamTool.dll' -and !$ascii.Contains($NativeVersion)) { throw 'Native DLL version differs from its source recipe.' }
        if ($file.relativePath -eq 'OpenSteamTool.dll' -and [version]$ReleaseVersion -ge [version]'1.0.9' -and
            !$ascii.Contains('NestGRentalStatusProtocolVersion')) { throw 'Missing rental login-confirmation capability.' }
        if ($file.relativePath -eq 'dwmapi.dll' -and $ascii.Contains('DWMAPI.')) { throw 'Recursive export forwarder.' }
        if ($file.relativePath -ne 'OpenSteamTool.dll' -and !([Text.Encoding]::Unicode.GetString($bytes)).Contains('OpenSteamTool.dll')) { throw 'Wrong proxy runtime target.' }
    }
    if ($file.relativePath -eq 'sources/BetterSteamTools-NestG-source.zip') { $source = (Resolve-Path -LiteralPath $CorrespondingSourceArchive).Path }
    $stagedFiles.Add([PSCustomObject]@{descriptor=$file;source=$source})
}
$stage = Join-Path $bundleRoot ('.staging-rental-' + [guid]::NewGuid().ToString('N'))
foreach ($item in $stagedFiles) {
    $target = [IO.Path]::GetFullPath((Join-Path $stage $item.descriptor.relativePath))
    if (!$target.StartsWith($stage+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $item.source -Destination $target
}
$encoding = [Text.UTF8Encoding]::new($false)
$noticePath = Join-Path $stage 'THIRD_PARTY_NOTICES.md'
$notice = [regex]::Replace([IO.File]::ReadAllText($noticePath),'\d+\.\d+\.\d+-nestg\.\d+',$NativeVersion)
$protocolNotice = if ([version]$ReleaseVersion -ge [version]'1.0.9') {
    'Rental runtime protocol 1 and authenticated local login-status protocol 1 are included.'
} else { 'Rental runtime protocol 1 is included.' }
$notice += "`n$protocolNotice Native fixtures do not certify live Steam account switching or save round-trip.`n"
[IO.File]::WriteAllText($noticePath,$notice,$encoding)
$manifest.version = $ReleaseVersion
foreach ($file in $manifest.files) {
    $path = Join-Path $stage $file.relativePath
    $file.size = (Get-Item -LiteralPath $path).Length
    $file.sha256 = (Get-FileHash -LiteralPath $path).Hash
}
$json = ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n","`n") + "`n"
[IO.File]::WriteAllText((Join-Path $stage 'bundle.json'),$json,$encoding)
if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($stage)) -ne $bundleRoot -or
    [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($destination)) -ne $bundleRoot -or
    (Get-FileHash -LiteralPath (Join-Path $bundleRoot 'latest.json')).Hash -ne $latestHash -or
    (Get-FileHash -LiteralPath (Join-Path $previous 'bundle.json')).Hash -ne $predecessorHash) { throw 'Release boundary/integrity failed.' }
Move-Item -LiteralPath $stage -Destination $destination
if (!(Test-Path -LiteralPath $historicalPin)) { Copy-Item -LiteralPath (Join-Path $previous 'bundle.json') -Destination $historicalPin }
[IO.File]::WriteAllText((Join-Path $pins 'bettersteamtools-cloud.json'),$json,$encoding)
Write-Output "Created immutable $ReleaseVersion (17 full / 16 core), preserved $PreviousVersion pin and latest 1.0.1. Steam E2E was not executed."
