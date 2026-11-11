param(
    [Parameter(Mandatory = $true)][string]$NativeOutputDirectory,
    [Parameter(Mandatory = $true)][string]$CorrespondingSourceArchive,
    [string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)
$ErrorActionPreference = 'Stop'
$legacy = Join-Path $RepositoryRoot 'app_server/RuntimeBundles/OpenSteamToolCloud/1.0.0'
$bundleRoot = Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'
$bundle = Join-Path $bundleRoot '1.0.0'
if (Test-Path "$bundle/bundle.json") { throw 'Bundle already exists; use a new version for a new release.' }
$manifest = Get-Content "$legacy/bundle.json" -Raw | ConvertFrom-Json
# Verify every inherited artifact before copying it into the new bundle.
foreach ($file in $manifest.files) {
    $source = Join-Path $legacy $file.relativePath
    if ((Get-Item -LiteralPath $source).Length -ne $file.size -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $file.sha256) {
        throw "Legacy bundle is not intact: $($file.relativePath)"
    }
}
if (!(Test-Path -LiteralPath $CorrespondingSourceArchive -PathType Leaf)) { throw 'Missing corresponding source archive' }
foreach ($file in $manifest.files) {
    $source = Join-Path $legacy $file.relativePath
    if ($file.relativePath -in @('OpenSteamTool.dll', 'dwmapi.dll', 'xinput1_4.dll')) {
        $source = Join-Path $NativeOutputDirectory $file.relativePath
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) { throw 'Invalid PE header' }
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        if ($pe -lt 0 -or $pe -gt $bytes.Length - 6 -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x4550 -or
            [BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664) { throw 'Runtime must be PE x64' }
    }
    $target = Join-Path $bundle $file.relativePath
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}
$utf8 = [Text.UTF8Encoding]::new($false)
$notice = @'
# Third-party notices

BetterSteamTools 1.0.4 (NestG build 1.0.4-nestg.1)
https://github.com/madoiscool/BetterSteamTools
Source commit: 4747385bdc7c92fb422e63419a5093566b3bf626
Derived from OpenSteamTool; licensed under GPL-3.0.
License: licenses/OpenSteamTool-LICENSE.txt.
Corresponding source, dependency sources, NestG patch and build recipe:
sources/BetterSteamTools-NestG-source.zip (installed under cloud_redirect/sources).

CloudRedirect 2.6.5
https://github.com/Selectively11/CloudRedirect
MIT license: licenses/CloudRedirect-LICENSE.txt.

Dependency notices and licenses are included in the corresponding source archive.
'@
[IO.File]::WriteAllText("$bundle/THIRD_PARTY_NOTICES.md", $notice + "`n", $utf8)
[IO.Directory]::CreateDirectory("$bundle/sources") | Out-Null
Copy-Item -LiteralPath $CorrespondingSourceArchive -Destination "$bundle/sources/BetterSteamTools-NestG-source.zip"
$manifest.files += [PSCustomObject]@{ relativePath = 'sources/BetterSteamTools-NestG-source.zip'; installPath = 'cloud_redirect/sources/BetterSteamTools-NestG-source.zip'; size = 0; sha256 = '' }
foreach ($file in $manifest.files) {
    $path = Join-Path $bundle $file.relativePath
    $file.size = (Get-Item -LiteralPath $path).Length
    $file.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
$manifest.bundleId = 'bettersteamtools-cloud'
$manifest.runtimeMode = 'BetterSteamToolsCloudRedirect'
$manifest.openSteamToolCommit = '4747385bdc7c92fb422e63419a5093566b3bf626'
$json = ($manifest | ConvertTo-Json -Depth 8) + "`n"
[IO.File]::WriteAllText("$bundle/bundle.json", $json, $utf8)
[IO.File]::WriteAllText("$bundleRoot/latest.json", '{"version":"1.0.0"}' + "`n", $utf8)
[IO.File]::WriteAllText((Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles/bettersteamtools-cloud.json'), $json, $utf8)
Write-Output 'Created separate BetterSteamTools server bundle and embedded desktop pin. Build and test both projects before release.'
