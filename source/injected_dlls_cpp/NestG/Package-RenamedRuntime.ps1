param(
    [Parameter(Mandatory = $true)][string]$NativeOutputDirectory,
    [Parameter(Mandatory = $true)][string]$CorrespondingSourceArchive,
    [string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)
$ErrorActionPreference = 'Stop'
$bundleRoot = Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'
$previous = Join-Path $bundleRoot '1.0.2'
$destination = Join-Path $bundleRoot '1.0.3'
if (Test-Path -LiteralPath $destination) { throw 'Release 1.0.3 already exists; never replace an immutable release.' }
$manifest = Get-Content -LiteralPath "$previous/bundle.json" -Raw | ConvertFrom-Json
$staged = [Collections.Generic.List[object]]::new()
foreach ($file in $manifest.files) {
    $source = Join-Path $previous $file.relativePath
    if ((Get-Item -LiteralPath $source).Length -ne $file.size -or
        (Get-FileHash -LiteralPath $source).Hash -ne $file.sha256) { throw "Previous release damaged: $($file.relativePath)" }
    if ($file.relativePath -eq 'NestGSteamTools.dll') {
        $file.relativePath = 'NestG.dll'
        $file.installPath = 'NestG.dll'
    }
    if ($file.relativePath -in @('NestG.dll', 'dwmapi.dll', 'xinput1_4.dll')) {
        $source = Join-Path $NativeOutputDirectory $file.relativePath
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) { throw 'Invalid PE header' }
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        if ($pe -lt 0 -or $pe -gt $bytes.Length - 6 -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x4550 -or
            [BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664) { throw 'Runtime must be PE x64' }
        if ($file.relativePath -ne 'NestG.dll') {
            $text = [Text.Encoding]::ASCII.GetString($bytes)
            if (!$text.Contains('NestG.dll') -or $text.Contains('NestGSteamTools.dll') -or $text.Contains('OpenSteamTool.dll')) {
                throw "Loader does not target the renamed DLL: $($file.relativePath)"
            }
        }
    }
    if ($file.relativePath -eq 'sources/BetterSteamTools-NestG-source.zip') { $source = $CorrespondingSourceArchive }
    $null = Get-Item -LiteralPath $source -ErrorAction Stop
    $staged.Add([PSCustomObject]@{ descriptor = $file; source = $source })
}
foreach ($item in $staged) {
    $target = Join-Path $destination $item.descriptor.relativePath
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath $item.source -Destination $target
}
$utf8 = [Text.UTF8Encoding]::new($false)
$noticePath = Join-Path $destination 'THIRD_PARTY_NOTICES.md'
$notice = [IO.File]::ReadAllText($noticePath).Replace('1.0.4-nestg.2', '1.0.4-nestg.3').Replace('NestGSteamTools.dll', 'NestG.dll')
[IO.File]::WriteAllText($noticePath, $notice, $utf8)
$manifest.version = '1.0.3'
foreach ($file in $manifest.files) {
    $path = Join-Path $destination $file.relativePath
    $file.size = (Get-Item -LiteralPath $path).Length
    $file.sha256 = (Get-FileHash -LiteralPath $path).Hash
}
$json = ($manifest | ConvertTo-Json -Depth 8) + "`n"
[IO.File]::WriteAllText("$destination/bundle.json", $json, $utf8)
[IO.File]::WriteAllText((Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles/bettersteamtools-cloud.json'), $json, $utf8)
# Compatibility: old desktops pin 1.0.1 and still request /latest.
# New desktops request the authenticated /bettersteamtools-cloud/1.0.3 endpoint.
Write-Output 'Created immutable 1.0.3 and its client pin. latest.json remains unchanged for old desktops.'
