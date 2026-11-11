param(
    [Parameter(Mandatory = $true)][string]$NativeOutputDirectory,
    [Parameter(Mandatory = $true)][string]$CorrespondingSourceArchive,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-F0-9]{64}$')][string]$RuntimeUpdaterSha256,
    [string]$RepositoryRoot,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion = '1.0.13',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$PreviousVersion = '1.0.12',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$MinimumDesktopVersion = '2.2.50'
)
$ErrorActionPreference = 'Stop'
if (!$RepositoryRoot) { $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')) }
$releaseVersion = $ReleaseVersion
if ([version]$releaseVersion -le [version]$PreviousVersion) { throw 'A transition release must increase the immutable version.' }
$bundleRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'))
$previous = Join-Path $bundleRoot $PreviousVersion
$destination = Join-Path $bundleRoot $releaseVersion
$pins = Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles'
if (Test-Path -LiteralPath $destination) { throw "Immutable runtime bridge $releaseVersion already exists." }
$manifestPath = Join-Path $previous 'bundle.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.version -ne $PreviousVersion -or $manifest.bundleId -ne 'bettersteamtools-cloud' -or $manifest.files.Count -ne 20) { throw 'Expected an immutable predecessor with 20 files.' }
$latestHash = (Get-FileHash -LiteralPath (Join-Path $bundleRoot 'latest.json')).Hash
$previousHash = (Get-FileHash -LiteralPath $manifestPath).Hash
$source = (Resolve-Path -LiteralPath $CorrespondingSourceArchive).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($source)
try {
    foreach ($relative in @('src/NestG/RuntimeUpdateBootstrap.h','src/NestG/ProxyBootstrap.h','NestG/runtime-update.patch','NestG/Build-UpdateBootstrap.ps1','NestG/UpdateBootstrapMingw.h','.deps/detours-src/src/detours.cpp','.deps/lua-src/src/lua.h','.deps/protobuf-src/LICENSE','.deps/spdlog-src/CMakeLists.txt','.deps/tomlplusplus-src/CMakeLists.txt')) {
        if (!$archive.GetEntry($relative)) { throw "Corresponding source is incomplete: $relative" }
    }
    foreach ($name in @('Build-Runtime.ps1','Build-UpdateBootstrap.ps1','UpdateBootstrapMingw.h','nestg.patch','startup.patch','opensteamtool.patch','shutdown.patch','rental.patch','runtime-update.patch')) {
        $entry = $archive.GetEntry("NestG/$name")
        if (!$entry) { throw "Corresponding source lacks recipe: $name" }
        $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
        try { $archived = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally { $sha.Dispose(); $stream.Dispose() }
        if ($archived -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash) { throw "Corresponding source recipe differs: $name" }
    }
} finally { $archive.Dispose() }
$stage = Join-Path $bundleRoot ('.staging-bootstrap-' + [guid]::NewGuid().ToString('N'))
foreach ($file in $manifest.files) {
    $original = [IO.Path]::GetFullPath((Join-Path $previous $file.relativePath))
    if (!$original.StartsWith($previous+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-Item -LiteralPath $original).Length -ne $file.size -or (Get-FileHash -LiteralPath $original).Hash -ne $file.sha256) { throw 'Immutable predecessor integrity failed.' }
    $input = $original
    if ($file.relativePath -in @('dwmapi.dll','xinput1_4.dll')) {
        $input = Join-Path $NativeOutputDirectory $file.relativePath
        $bytes = [IO.File]::ReadAllBytes($input)
        if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d) { throw 'Bootstrap is not PE.' }
        $pe = [BitConverter]::ToInt32($bytes,0x3c)
        if ($pe -lt 0 -or $pe -gt $bytes.Length-6 -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw 'Bootstrap must be PE x64.' }
        $ascii = [Text.Encoding]::ASCII.GetString($bytes)
        if (!$ascii.Contains($RuntimeUpdaterSha256) -or !$ascii.Contains('updater.gate.blocked') -or !$ascii.Contains('updater.helper.started')) { throw 'Bootstrap lacks helper pin or gate contract.' }
        if ($file.relativePath -eq 'dwmapi.dll' -and $ascii.Contains('DWMAPI.')) { throw 'Recursive DWM forwarder.' }
    }
    if ($file.relativePath -eq 'sources/BetterSteamTools-NestG-source.zip') { $input = $source }
    $target = [IO.Path]::GetFullPath((Join-Path $stage $file.relativePath))
    if (!$target.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe package target.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $input -Destination $target
}
$encoding = [Text.UTF8Encoding]::new($false)
$noticePath = Join-Path $stage 'THIRD_PARTY_NOTICES.md'
$notice = [IO.File]::ReadAllText($noticePath) + "`nRuntime bridge $releaseVersion pins the stable updater dispatcher in both OS proxies. The dispatcher can start an independently signed installed launcher background host; no launcher executable hash is embedded in the proxies. OpenSteamTool.dll and all Steam metadata remain byte-identical to $PreviousVersion. The upstream native updater remains disabled. Helper SHA-256: $RuntimeUpdaterSha256. Proxies use statically linked LLVM libc++/compiler-rt under Apache-2.0 WITH LLVM-exception; corresponding notices are included in the corresponding source archive's NestG toolchain notices. Native fixtures do not certify real Steam/save round-trip.`n"
[IO.File]::WriteAllText($noticePath,$notice,$encoding)
$manifest.version = $releaseVersion
$manifest.minimumDesktopVersion = $MinimumDesktopVersion
foreach ($file in $manifest.files) {
    $path = Join-Path $stage $file.relativePath
    $file.size = (Get-Item -LiteralPath $path).Length
    $file.sha256 = (Get-FileHash -LiteralPath $path).Hash
}
$pairs = @([ordered]@{steamClientSha256='253E0A11A4415B38C78A42F7BDD6ECC426455F06C1BA6453A48090DF3142DBBC';steamUiSha256='CD9226DB4E6C28942DF70C22C0475D91FDD62CBA5F100BAAE2D65AF57CABB610'})
[IO.File]::WriteAllText((Join-Path $stage 'runtime-steam-builds.json'),(ConvertTo-Json -InputObject $pairs -Depth 4)+"`n",$encoding)
$json = ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n","`n")+"`n"
[IO.File]::WriteAllText((Join-Path $stage 'bundle.json'),$json,$encoding)
if ((Get-FileHash -LiteralPath (Join-Path $bundleRoot 'latest.json')).Hash -ne $latestHash -or (Get-FileHash -LiteralPath $manifestPath).Hash -ne $previousHash) { throw 'Predecessor boundary changed.' }
$historical = Join-Path $pins "bettersteamtools-cloud-$PreviousVersion.json"
if ((Test-Path -LiteralPath $historical) -and (Get-FileHash -LiteralPath $historical).Hash -ne $previousHash) { throw 'Historical pin differs.' }
Move-Item -LiteralPath $stage -Destination $destination
if (!(Test-Path -LiteralPath $historical)) { Copy-Item -LiteralPath $manifestPath -Destination $historical }
[IO.File]::WriteAllText((Join-Path $pins 'bettersteamtools-cloud.json'),$json,$encoding)
Write-Output "Created immutable runtime bridge $releaseVersion; preserved all predecessors and latest. Signed launcher host metadata, source, helper and proxy verification precede production rollout."
