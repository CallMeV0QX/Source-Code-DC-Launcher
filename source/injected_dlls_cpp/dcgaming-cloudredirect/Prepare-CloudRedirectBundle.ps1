param(
    [Parameter(Mandatory=$true)][string]$BuildDirectory,
    [Parameter(Mandatory=$true)][string]$NativeTestResultsPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$Version,
    [string]$BaselineDirectory,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$MinimumDesktopVersion = '1.2.6'
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (!$BaselineDirectory) { $BaselineDirectory = Join-Path $workspace 'DC-Server/RuntimeBundles/BetterSteamToolsCloud/1.0.15' }
$baseline = [IO.Path]::GetFullPath($BaselineDirectory)
$build = [IO.Path]::GetFullPath($BuildDirectory)
$output = [IO.Path]::GetFullPath($OutputDirectory)
function Assert-RegularPath([string]$Path) {
    for ($current = [IO.Path]::GetFullPath($Path); $current; $current = [IO.Path]::GetDirectoryName($current)) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked paths are not supported for release preparation.'
        }
    }
}
foreach ($path in @($baseline, $build, $output, $NativeTestResultsPath)) { Assert-RegularPath $path }
if (Test-Path -LiteralPath $output) { throw 'Use a new bundle directory; existing versions are immutable.' }
$receipt = Get-Content -LiteralPath (Join-Path $build 'cloudredirect-build.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($receipt.schemaVersion -ne 1 -or $receipt.upstreamCommit -notmatch '^[a-f0-9]{40}$' -or
    $receipt.cloudRedirectVersion -notmatch '^\d+\.\d+\.\d+$' -or !$receipt.tests.pendingOpsJournalPassed) {
    throw 'A complete reviewed CloudRedirect build receipt and passing native journal tests are required.'
}
function Get-VerifiedBuildFile($Entry) {
    if (!$Entry -or $Entry.relativePath -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$' -or $Entry.relativePath.Contains('..')) { throw 'Invalid build artifact path.' }
    $path = Join-Path $build $Entry.relativePath
    Assert-RegularPath $path
    if ((Get-Item -LiteralPath $path).Length -ne $Entry.size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Entry.sha256) {
        throw 'Build artifact differs from its receipt.'
    }
    return $path
}
$dll = Get-VerifiedBuildFile $receipt.dll
$cloudSource = Get-VerifiedBuildFile $receipt.sourceArchive
$native = Get-Content -LiteralPath $NativeTestResultsPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($native.dllSha256 -ne $receipt.dll.sha256 -or $native.phases -ne 3 -or $native.assertions -lt 1) {
    throw 'Passing writer/recovery/reader tests for this exact DLL are required.'
}
$baseManifest = Get-Content -LiteralPath (Join-Path $baseline 'bundle.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ([version]$Version -le [version]$baseManifest.version) { throw 'The runtime version must increase.' }
$preparation = $output + '.preparation-' + [Guid]::NewGuid().ToString('N')
$payload = Join-Path $preparation 'payload'
[IO.Directory]::CreateDirectory((Join-Path $payload 'cloud_redirect')) | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $payload 'cloud_redirect.dll')
$notices = [IO.File]::ReadAllText((Join-Path $baseline 'THIRD_PARTY_NOTICES.md'))
$notices = $notices.Replace(('CloudRedirect ' + $baseManifest.cloudRedirectVersion), ('CloudRedirect ' + $receipt.cloudRedirectVersion))
$notices = $notices.Replace('https://github.com/Selectively11/CloudRedirect', 'https://github.com/crghofficial/cloudredirect')
$notices = $notices.Replace('sources/BetterSteamTools-NestG-source.zip', 'sources/BetterSteamTools-DCGaming-source.zip')
$notices += "`n`nDC runtime $Version replaces only the CloudRedirect native component with upstream $($receipt.cloudRedirectVersion), commit $($receipt.upstreamCommit). The DC main runtime, bootstrap proxies, helper pin and reviewed Steam metadata remain unchanged. The corresponding source archive includes dcgaming-cloudredirect/CloudRedirect-source.zip, the build recipe, portability additions, build receipt and isolated native API test evidence. The DLL has passed isolated journal and third-party API save tests; this does not certify real Steam/game/save operation.`n"
$notices += "The CloudRedirect DLL is built with LLVM-MinGW and statically linked LLVM libc++/compiler-rt. LLVM (Apache-2.0 WITH LLVM-exception), libc++, MinGW runtime and winpthreads notices are retained in the corresponding source archive under NestG/toolchain-notices/.`n"
foreach ($patch in $receipt.appliedPatches) {
    $notices += "Reviewed upstream compatibility patch: $($patch.commit), $($patch.reviewUrl), SHA-256 $($patch.sha256). This is a DC build of upstream source with the recorded patch; the upstream 2.6.6 source has no public release at preparation time.`n"
}
[IO.File]::WriteAllText((Join-Path $payload 'cloud_redirect/THIRD_PARTY_NOTICES.md'), $notices, [Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$source = Join-Path $preparation 'BetterSteamTools-DCGaming-source.zip'
Copy-Item -LiteralPath (Join-Path $baseline 'sources/BetterSteamTools-DCGaming-source.zip') -Destination $source
$archive = [IO.Compression.ZipFile]::Open($source, [IO.Compression.ZipArchiveMode]::Update)
try {
    $additions = @{
        'dcgaming-cloudredirect/CloudRedirect-source.zip' = $cloudSource
        'dcgaming-cloudredirect/cloudredirect-build.json' = (Join-Path $build 'cloudredirect-build.json')
        'dcgaming-cloudredirect/native-api-results.json' = [IO.Path]::GetFullPath($NativeTestResultsPath)
        'dcgaming-cloudredirect/Prepare-CloudRedirectBundle.ps1' = $PSCommandPath
        'dcgaming-cloudredirect/Test-CloudRedirect.ps1' = (Join-Path $PSScriptRoot 'Test-CloudRedirect.ps1')
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tests/CloudRedirectProbe') -File) {
        if ($file.Extension -in @('.cs', '.csproj')) { $additions['dcgaming-cloudredirect/CloudRedirectProbe/' + $file.Name] = $file.FullName }
    }
    foreach ($entry in $additions.Keys) {
        if ($archive.GetEntry($entry)) { throw 'The source archive already contains this CloudRedirect build evidence.' }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $additions[$entry], $entry) | Out-Null
    }
} finally { $archive.Dispose() }
& dotnet run --project (Join-Path $workspace 'DC-Runtime.ReleaseTool') --artifacts-path (Join-Path $preparation 'release-tool') -- pack $baseline $output $Version $payload $source (Join-Path $baseline 'runtime-steam-builds.json') $receipt.cloudRedirectVersion
if ($LASTEXITCODE -ne 0) { throw 'Runtime bundle preparation failed.' }
$manifest = Get-Content -LiteralPath (Join-Path $output 'bundle.json') -Raw -Encoding utf8 | ConvertFrom-Json
$manifest.minimumDesktopVersion = $MinimumDesktopVersion
[IO.File]::WriteAllText((Join-Path $output 'bundle.json'), ($manifest | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
foreach ($file in $baseManifest.files) {
    if ($file.installPath -in @('cloud_redirect.dll', 'cloud_redirect/THIRD_PARTY_NOTICES.md', 'cloud_redirect/sources/BetterSteamTools-DCGaming-source.zip')) { continue }
    $next = @($manifest.files | Where-Object installPath -eq $file.installPath)
    if ($next.Count -ne 1 -or $next[0].sha256 -ne $file.sha256 -or $next[0].size -ne $file.size) { throw 'An unrelated runtime component changed.' }
}
if ($manifest.cloudRedirectVersion -ne $receipt.cloudRedirectVersion) { throw 'CloudRedirect version metadata was not updated.' }
Write-Output ("Prepared unsigned DC runtime {0} with CloudRedirect {1} ({2}); native API tests verified, bootstrap preserved." -f $Version, $receipt.cloudRedirectVersion, $receipt.upstreamCommit)
