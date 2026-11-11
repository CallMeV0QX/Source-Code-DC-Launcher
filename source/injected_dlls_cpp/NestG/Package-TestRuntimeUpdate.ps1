param(
    [Parameter(Mandatory = $true)][string]$NativeRuntime,
    [Parameter(Mandatory = $true)][string]$CorrespondingSourceArchive,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$BaseVersion = '1.0.13',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion = '1.0.14',
    [ValidatePattern('^\d+\.\d+\.\d+-nestg\.\d+$')][string]$NativeVersion = '1.0.4-nestg.10'
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path "$PSScriptRoot/../..").Path
$base = Join-Path $repository "app_server/RuntimeBundles/BetterSteamToolsCloud/$BaseVersion"
$output = [IO.Path]::GetFullPath($OutputDirectory)
$allowed = [IO.Path]::GetFullPath((Join-Path $repository '.codex-temp')) + '\'
if (!$output.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $output) -or [version]$ReleaseVersion -le [version]$BaseVersion) {
    throw 'Use a new test bundle directory beneath .codex-temp and a newer release version.'
}
$manifestPath = Join-Path $base 'bundle.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.version -ne $BaseVersion -or $manifest.bundleId -ne 'bettersteamtools-cloud' -or $manifest.files.Count -ne 20) {
    throw 'Expected the immutable 20-file base runtime.'
}
$boundary = @($manifestPath, (Join-Path $repository 'app_desktop/Services/CloudRedirect/TrustedBundles/bettersteamtools-cloud.json'),
    (Join-Path (Split-Path $base) 'latest.json')) | ForEach-Object {
        [pscustomobject]@{ Path = $_; Hash = (Get-FileHash -LiteralPath $_).Hash }
    }
$native = (Resolve-Path -LiteralPath $NativeRuntime).Path
$source = (Resolve-Path -LiteralPath $CorrespondingSourceArchive).Path
$nativeBytes = [IO.File]::ReadAllBytes($native)
if ($nativeBytes.Length -lt 256 -or [BitConverter]::ToUInt16($nativeBytes,0) -ne 0x5a4d) { throw 'Main runtime is not PE.' }
$pe = [BitConverter]::ToInt32($nativeBytes,0x3c)
if ($pe -lt 64 -or $pe -gt $nativeBytes.Length-26 -or [BitConverter]::ToUInt32($nativeBytes,$pe) -ne 0x4550 -or
    [BitConverter]::ToUInt16($nativeBytes,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($nativeBytes,$pe+24) -ne 0x20b) { throw 'Main runtime must be PE x64.' }
$ascii = [Text.Encoding]::ASCII.GetString($nativeBytes)
foreach ($required in @($NativeVersion,'NestGInitialize','NestGRentalRuntimeProtocolVersion','NestGRentalRuntimeCapabilities','NestGRentalStatusProtocolVersion')) {
    if (!$ascii.Contains($required)) { throw "Main runtime lacks required compiled version/capability: $required" }
}
$oldMain = $manifest.files | Where-Object installPath -eq 'OpenSteamTool.dll'
$nativeHash = (Get-FileHash -LiteralPath $native).Hash
if (!$oldMain -or $nativeHash -eq $oldMain.sha256) { throw 'The new main runtime must genuinely differ from its immutable predecessor.' }
$oldNativeHash = $oldMain.sha256
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($source)
try {
    foreach ($entry in @('src/dllmain.cpp','src/NestG/RentalRuntime.cpp','src/cmake/OpenSteamToolBuildInfo.h.in',
        'NestG/Build-Runtime.ps1','NestG/Build-RuntimeClang.ps1','NestG/Package-TestRuntimeUpdate.ps1',
        'NestG/toolchain-notices/LLVM-LICENSE.txt','NestG/toolchain-notices/LIBCXX-LICENSE.txt')) {
        if (!$zip.GetEntry($entry)) { throw "Corresponding source lacks $entry" }
    }
} finally { $zip.Dispose() }
$stage = $output + '.staging-' + [guid]::NewGuid().ToString('N')
foreach ($file in $manifest.files) {
    $original = [IO.Path]::GetFullPath((Join-Path $base $file.relativePath))
    if (!$original.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Get-Item -LiteralPath $original).Length -ne $file.size -or
        (Get-FileHash -LiteralPath $original).Hash -ne $file.sha256) { throw 'Immutable base integrity failed.' }
    $input = $original
    if ($file.installPath -eq 'OpenSteamTool.dll') { $input = $native }
    if ($file.relativePath -eq 'sources/BetterSteamTools-NestG-source.zip') { $input = $source }
    $target = [IO.Path]::GetFullPath((Join-Path $stage $file.relativePath))
    if (!$target.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test bundle path.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $input -Destination $target
}
$encoding = [Text.UTF8Encoding]::new($false)
$noticePath = Join-Path $stage 'THIRD_PARTY_NOTICES.md'
$notice = [IO.File]::ReadAllText($noticePath) + "`nTest runtime update $ReleaseVersion rebuilds the complete OpenSteamTool.dll as $NativeVersion from the corresponding native source using the included Build-RuntimeClang.ps1 recipe and statically linked LLVM libc++/compiler-rt. No native code is replaced with a stub. The upstream updater and redemption entry points remain disabled. Both stable bootstrap proxies, helper pin, cloud_redirect.dll and reviewed Steam metadata are byte-identical to $BaseVersion. This unsigned bundle is for isolated old-to-new runtime-update testing; signing/publication is a separate authenticated step. No real Steam/save round-trip has been certified.`n"
[IO.File]::WriteAllText($noticePath, $notice, $encoding)
$manifest.version = $ReleaseVersion
foreach ($file in $manifest.files) {
    $path = Join-Path $stage $file.relativePath
    $file.size = (Get-Item -LiteralPath $path).Length
    $file.sha256 = (Get-FileHash -LiteralPath $path).Hash
}
Copy-Item -LiteralPath (Join-Path $base 'runtime-steam-builds.json') -Destination (Join-Path $stage 'runtime-steam-builds.json')
[IO.File]::WriteAllText((Join-Path $stage 'bundle.json'), ($manifest | ConvertTo-Json -Depth 8).Replace("`r`n","`n") + "`n", $encoding)
foreach ($original in $boundary) {
    if ((Get-FileHash -LiteralPath $original.Path).Hash -ne $original.Hash) { throw 'Immutable base, embedded pin or legacy latest changed.' }
}
Move-Item -LiteralPath $stage -Destination $output
[pscustomobject]@{ unsigned = $true; version = $ReleaseVersion; nativeVersion = $NativeVersion;
    nativeSha256 = $nativeHash; previousNativeSha256 = $oldNativeHash; files = $manifest.files.Count;
    embeddedPinChanged = $false; legacyLatestChanged = $false; bundleDirectory = $output } | ConvertTo-Json
