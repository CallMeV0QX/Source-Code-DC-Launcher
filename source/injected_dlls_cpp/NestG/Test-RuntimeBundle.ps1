param(
    [string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot/../..").Path,
    [string]$ServerRoot,
    [string]$DesktopPublishDirectory,
    [string]$SteamDirectory,
    [string]$ReportPath,
    [string]$BuiltUpdaterDirectory
)
$ErrorActionPreference = 'Stop'
if (!$ServerRoot) { $ServerRoot = Join-Path $RepositoryRoot 'app_server' }
$checks = [Collections.Generic.List[object]]::new()
function Record-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add([PSCustomObject]@{ name = $Name; passed = $Passed; detail = $Detail })
}
function Assert-PeX64([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'Missing DOS header' }
        $stream.Position = 0x3c
        $pe = $reader.ReadInt32()
        if ($pe -lt 0 -or $pe -gt $stream.Length - 6) { throw 'Invalid PE offset' }
        $stream.Position = $pe
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Not PE x64' }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

foreach ($item in @(
    @{ id = 'opensteamtool-cloud'; directory = 'OpenSteamToolCloud' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.0' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.1' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.2' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.3' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.4' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.5' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.6' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.7' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.8' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.9' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.10' },
    @{ id = 'bettersteamtools-cloud'; directory = 'BetterSteamToolsCloud'; pinSuffix = '-1.0.11' }
)) {
    try {
        $pinPath = Join-Path $RepositoryRoot "app_desktop/Services/CloudRedirect/TrustedBundles/$($item.id)$($item.pinSuffix).json"
        $clientPin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json
        if ($clientPin.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Unexpected pinned version format' }
        if ($item.pinSuffix -and $clientPin.version -ne $item.pinSuffix.Substring(1)) {
            throw 'Historical pin version differs from its filename'
        }
        $bundleRoot = [IO.Path]::GetFullPath((Join-Path $ServerRoot "RuntimeBundles/$($item.directory)/$($clientPin.version)"))
        $manifestPath = Join-Path $bundleRoot 'bundle.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        # JSON formatting and checkout line endings are not part of the pin. Compare
        # every manifest field and file entry; actual payload bytes remain SHA-256 pinned.
        if (($manifest | ConvertTo-Json -Compress -Depth 16) -cne ($clientPin | ConvertTo-Json -Compress -Depth 16)) {
            throw 'Manifest differs from embedded client pin'
        }
        if ($manifest.bundleId -ne $item.id -or $manifest.version -ne $clientPin.version -or !$manifest.enabled) {
            throw 'Unexpected manifest identity or disabled bundle'
        }
        $latest = Get-Content -LiteralPath (Join-Path (Split-Path $bundleRoot) 'latest.json') -Raw | ConvertFrom-Json
        $expectedLatest = if ($item.id -eq 'bettersteamtools-cloud') { '1.0.1' } else { $manifest.version }
        if ($latest.version -ne $expectedLatest) { throw 'latest.json breaks the older desktop compatibility pin' }
        if ($item.id -eq 'bettersteamtools-cloud' -and !$item.pinSuffix) {
            if ($manifest.version -ne '1.0.12' -or $manifest.files.Count -ne 20) {
                throw 'Current BetterSteamTools release must be 1.0.12 with exactly 20 full files'
            }
            if (@($manifest.files | Where-Object { $_.installPath -ne 'cloud_redirect.dll' }).Count -ne 19) {
                throw 'Current BetterSteamTools core view must contain exactly 19 files'
            }
            $nativeAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $bundleRoot 'OpenSteamTool.dll')))
            foreach ($capability in @('NestGRentalRuntimeProtocolVersion','NestGRentalRuntimeCapabilities','NestGRentalStatusProtocolVersion')) {
                if (!$nativeAscii.Contains($capability)) { throw 'Current native runtime lacks rental protocol exports' }
            }
            $helperRoot = Join-Path $RepositoryRoot 'app_desktop/Assets/RuntimeUpdater'
            $helperPin = Get-Content -LiteralPath (Join-Path $helperRoot 'helper-pin.json') -Raw | ConvertFrom-Json
            $helper = Join-Path $helperRoot 'NestG.RuntimeUpdater.exe'
            if ((Get-Item -LiteralPath $helper).Length -ne $helperPin.size -or (Get-FileHash -LiteralPath $helper).Hash -ne $helperPin.sha256) { throw 'Packaged standalone helper differs from embedded pin.' }
            Assert-PeX64 $helper
            foreach ($proxyName in @('dwmapi.dll','xinput1_4.dll')) {
                $proxyAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $bundleRoot $proxyName)))
                if (!$proxyAscii.Contains($helperPin.sha256) -or !$proxyAscii.Contains('updater.gate.blocked')) { throw 'Bootstrap lacks the packaged helper pin or compatibility gate.' }
            }
        }
        foreach ($file in $manifest.files) {
            $path = [IO.Path]::GetFullPath((Join-Path $bundleRoot $file.relativePath))
            if (!$path.StartsWith($bundleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'File escapes bundle directory'
            }
            $info = Get-Item -LiteralPath $path
            if ($info.Length -ne $file.size -or (Get-FileHash -LiteralPath $path).Hash -ne $file.sha256) {
                throw "Size/hash mismatch: $($file.relativePath)"
            }
            if ($info.Extension -eq '.dll') { Assert-PeX64 $path }
        }
        Record-Check "$($item.id)$($item.pinSuffix)" $true "$($manifest.files.Count) files verified against client pin, sizes, hashes and DLL x64 headers"
    } catch { Record-Check "$($item.id)$($item.pinSuffix)" $false $_.Exception.Message }
}
Record-Check 'private-bundle-storage' (!(Test-Path -LiteralPath (Join-Path $ServerRoot 'wwwroot/RuntimeBundles'))) 'Bundles must not be public static files'

if ($DesktopPublishDirectory) {
    foreach ($name in @('NestG launcher.exe', 'NestG launcher.dll', 'NestG.Updater.exe', 'Tomlyn.dll', 'appsettings.enc')) {
        Record-Check "desktop/$name" (Test-Path -LiteralPath (Join-Path $DesktopPublishDirectory $name) -PathType Leaf) 'Release dependency present'
    }
    Record-Check 'desktop/no-plaintext-config' (@(Get-ChildItem -LiteralPath $DesktopPublishDirectory -Filter 'appsettings*.json').Count -eq 0) 'No plaintext client settings'
    if ($BuiltUpdaterDirectory) {
        foreach ($name in @('NestG.Updater.exe', 'NestG.Updater.dll', 'NestG.Updater.deps.json', 'NestG.Updater.runtimeconfig.json')) {
            $builtPath = Join-Path $BuiltUpdaterDirectory $name
            $publishedPath = Join-Path $DesktopPublishDirectory $name
            $matches = (Test-Path -LiteralPath $builtPath -PathType Leaf) -and (Test-Path -LiteralPath $publishedPath -PathType Leaf)
            if ($matches) { $matches = (Get-FileHash -LiteralPath $builtPath).Hash -eq (Get-FileHash -LiteralPath $publishedPath).Hash }
            Record-Check "desktop/current-build/$name" $matches 'Published updater must match this build, not a stale bin directory'
        }
    }
}

$steamStatus = 'Blocked: disposable Steam environment has not been supplied'
$steamMetadataSupported = $null
if ($SteamDirectory) {
    # Read-only module check. This does not certify that Steam/save data is disposable,
    # launch Steam, inspect accounts, read saves, close processes or install any files.
    $pin = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles/bettersteamtools-cloud.json') -Raw | ConvertFrom-Json
    $supported = $true
    foreach ($module in @(@{ name = 'steamclient64.dll'; component = 'steamclient' }, @{ name = 'steamui.dll'; component = 'steamui' })) {
        $path = Join-Path $SteamDirectory $module.name
        $matched = $false
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $hash = (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
            $matched = "opensteamtool/pattern/$($module.component)/$hash.toml" -in $pin.files.installPath
            if ($module.component -eq 'steamclient') { $matched = $matched -and "opensteamtool/ipc/steamclient/$hash.toml" -in $pin.files.installPath }
        }
        $supported = $supported -and $matched
    }
    $steamStatus = if ($supported) { 'Module hashes supported; native Steam/save E2E still required on a disposable environment' }
        else { 'Blocked: missing or unsupported Steam module hashes' }
    $steamMetadataSupported = $supported
    Record-Check 'steam/module-hash-support' $supported 'Read-only module SHA-256 and pinned metadata check; no Steam execution or save verification'
}

$report = [PSCustomObject]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    passed = @($checks | Where-Object { !$_.passed }).Count -eq 0
    checks = @($checks.ToArray())
    steamE2E = $steamStatus
    steamMetadataSupported = $steamMetadataSupported
    steamE2EExecuted = $false
}
$json = $report | ConvertTo-Json -Depth 6
if ($ReportPath) {
    $fullReportPath = [IO.Path]::GetFullPath($ReportPath)
    [IO.Directory]::CreateDirectory((Split-Path $fullReportPath)) | Out-Null
    [IO.File]::WriteAllText($fullReportPath, $json + "`n", [Text.UTF8Encoding]::new($false))
}
Write-Output $json
if (!$report.passed) { throw 'Runtime artifact verification failed; see checks above.' }
