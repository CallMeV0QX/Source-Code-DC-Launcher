param(
    [Parameter(Mandatory = $true)][string]$NativeOutputDirectory,
    [Parameter(Mandatory = $true)][string]$CorrespondingSourceArchive,
    [string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)
$ErrorActionPreference = 'Stop'
$bundleRoot = Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'
$previous = Join-Path $bundleRoot '1.0.3'
$destination = Join-Path $bundleRoot '1.0.4'
$pinRoot = Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles'
if (Test-Path -LiteralPath $destination) { throw 'Release 1.0.4 already exists; never replace an immutable release.' }
$previousJson = [IO.File]::ReadAllText("$previous/bundle.json")
$manifest = $previousJson | ConvertFrom-Json
if ($manifest.version -ne '1.0.3' -or $manifest.bundleId -ne 'bettersteamtools-cloud') { throw 'Invalid previous release' }
$staged = [Collections.Generic.List[object]]::new()
foreach ($file in $manifest.files) {
    $source = [IO.Path]::GetFullPath((Join-Path $previous $file.relativePath))
    if (!$source.StartsWith($previous + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid bundle path' }
    if ((Get-Item -LiteralPath $source).Length -ne $file.size -or (Get-FileHash -LiteralPath $source).Hash -ne $file.sha256) { throw "Damaged previous release: $($file.relativePath)" }
    if ($file.relativePath -in @('NestG.dll', 'dwmapi.dll', 'xinput1_4.dll')) {
        $source = Join-Path $NativeOutputDirectory $file.relativePath
        $bytes = [IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) { throw 'Invalid PE header' }
        $pe = [BitConverter]::ToInt32($bytes, 0x3c)
        if ($pe -lt 0 -or $pe -gt $bytes.Length - 6 -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664) { throw 'Runtime must be PE x64' }
        $ascii = [Text.Encoding]::ASCII.GetString($bytes)
        if ($file.relativePath -eq 'dwmapi.dll' -and $ascii.Contains('DWMAPI.')) { throw 'Recursive DWM export forwarders are forbidden' }
        if (!$ascii.Contains('NestGInitialize')) { throw 'Missing explicit runtime initialization contract' }
    }
    if ($file.relativePath -eq 'sources/BetterSteamTools-NestG-source.zip') { $source = $CorrespondingSourceArchive }
    $null = Get-Item -LiteralPath $source -ErrorAction Stop
    $staged.Add([PSCustomObject]@{ descriptor = $file; source = $source })
}
$historicalPin = Join-Path $pinRoot 'bettersteamtools-cloud-1.0.3.json'
if ((Test-Path -LiteralPath $historicalPin) -and (Get-FileHash -LiteralPath $historicalPin).Hash -ne (Get-FileHash -LiteralPath "$previous/bundle.json").Hash) { throw 'Historical client pin differs from 1.0.3' }
$stage = Join-Path $bundleRoot ('.staging-' + [guid]::NewGuid().ToString('N'))
foreach ($item in $staged) {
    $target = Join-Path $stage $item.descriptor.relativePath
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    Copy-Item -LiteralPath $item.source -Destination $target
}
$utf8 = [Text.UTF8Encoding]::new($false)
$noticePath = Join-Path $stage 'THIRD_PARTY_NOTICES.md'
$notice = [IO.File]::ReadAllText($noticePath).Replace('1.0.4-nestg.3', '1.0.4-nestg.4')
[IO.File]::WriteAllText($noticePath, $notice, $utf8)
$manifest.version = '1.0.4'
foreach ($file in $manifest.files) {
    $path = Join-Path $stage $file.relativePath
    $file.size = (Get-Item -LiteralPath $path).Length
    $file.sha256 = (Get-FileHash -LiteralPath $path).Hash
}
$json = ($manifest | ConvertTo-Json -Depth 8) + "`n"
[IO.File]::WriteAllText("$stage/bundle.json", $json, $utf8)
Move-Item -LiteralPath $stage -Destination $destination
Copy-Item -LiteralPath "$previous/bundle.json" -Destination $historicalPin
[IO.File]::WriteAllText((Join-Path $pinRoot 'bettersteamtools-cloud.json'), $json, $utf8)
Write-Output 'Created immutable 1.0.4 and current/historical client pins. latest.json remains 1.0.1.'
