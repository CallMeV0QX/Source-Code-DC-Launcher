param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$CompilerDirectory,
    [Parameter(Mandatory = $true)][string]$CMakeExecutable,
    [Parameter(Mandatory = $true)][string]$NinjaExecutable,
    [ValidatePattern('^[a-f0-9]{40}$')][string]$Commit = '4e81e492e4678c1d907fbeaef2625846f6afaad8',
    [ValidateRange(1,16)][int]$Parallel = 4
)
$ErrorActionPreference = 'Stop'
$encoding = [Text.UTF8Encoding]::new($false)
$sourceLockPath = Join-Path $PSScriptRoot 'cloudredirect-source.json'
$sourceLock = Get-Content -LiteralPath $sourceLockPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($sourceLock.schemaVersion -ne 1 -or $sourceLock.commit -ne $Commit -or
    $sourceLock.compatibility.commit -notmatch '^[a-f0-9]{40}$') {
    throw 'The source commit must match the reviewed CloudRedirect source lock.'
}
$steamPatch = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $sourceLock.compatibility.patch)).Path
if ((Get-FileHash -LiteralPath $steamPatch -Algorithm SHA256).Hash -ne $sourceLock.compatibility.sha256) {
    throw 'The Steam compatibility patch differs from its reviewed source lock.'
}
$upstream = (Resolve-Path -LiteralPath $SourceDirectory).Path
$compiler = (Resolve-Path -LiteralPath $CompilerDirectory).Path
$cmake = (Resolve-Path -LiteralPath $CMakeExecutable).Path
$ninja = (Resolve-Path -LiteralPath $NinjaExecutable).Path
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $work) { throw 'Use a new CloudRedirect build directory; artifacts are immutable.' }
foreach ($path in @($upstream,$compiler,$cmake,$ninja,$work)) {
    for ($ancestor = $path; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Reparse build paths are not accepted.'
        }
    }
}
$actualCommit = (& git -C $upstream rev-parse "$Commit^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $Commit) { throw 'Pinned upstream commit is not available in the source repository.' }
[IO.Directory]::CreateDirectory($work) | Out-Null
$snapshot = Join-Path $work 'upstream-source.zip'
& git -C $upstream archive --format=zip "--output=$snapshot" $Commit
if ($LASTEXITCODE -ne 0) { throw 'Could not snapshot the pinned upstream source.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source = Join-Path $work 'source'
[IO.Compression.ZipFile]::ExtractToDirectory($snapshot,$source)
$recipeDirectory = Join-Path $source 'dcgaming-build'
[IO.Directory]::CreateDirectory($recipeDirectory) | Out-Null
$compat = Join-Path $recipeDirectory 'CloudRedirectMingw.h'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CloudRedirectMingw.h') -Destination $compat
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $recipeDirectory 'Build-CloudRedirect.ps1')
Copy-Item -LiteralPath $sourceLockPath -Destination (Join-Path $recipeDirectory 'cloudredirect-source.json')
Copy-Item -LiteralPath $steamPatch -Destination (Join-Path $recipeDirectory $sourceLock.compatibility.patch)
$patch = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'cloudredirect-clang-portability.patch')).Path
Copy-Item -LiteralPath $patch -Destination (Join-Path $recipeDirectory 'cloudredirect-clang-portability.patch')
# Give the extracted snapshot its own Git root; otherwise git apply inside a
# parent checkout can silently skip paths outside the current subdirectory.
& git -C $source init --quiet
if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the isolated source root.' }
& git -C $source apply --check $patch
if ($LASTEXITCODE -ne 0) { throw 'The reviewed CloudRedirect portability patch does not match the pinned source.' }
& git -C $source apply $patch
if ($LASTEXITCODE -ne 0) { throw 'CloudRedirect portability patch application failed.' }
& git -C $source apply --check $steamPatch
if ($LASTEXITCODE -ne 0) { throw 'The reviewed Steam compatibility patch does not match the pinned source.' }
& git -C $source apply $steamPatch
if ($LASTEXITCODE -ne 0) { throw 'Steam compatibility patch application failed.' }
$build = Join-Path $work 'build'
$cc = (Join-Path $compiler 'clang.exe').Replace('\','/')
$cxx = (Join-Path $compiler 'clang++.exe').Replace('\','/')
$configure = @('-S',$source,'-B',$build,'-G','Ninja',
    "-DCMAKE_MAKE_PROGRAM=$ninja", "-DCMAKE_C_COMPILER=$cc", "-DCMAKE_CXX_COMPILER=$cxx",
    '-DCMAKE_BUILD_TYPE=Release', "-DCR_GIT_SHA=$($Commit.Substring(0,7))-dcsteam-$($sourceLock.compatibility.commit.Substring(0,7))",
    "-DCMAKE_CXX_FLAGS=-fms-extensions -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -include `"$($compat.Replace('\','/'))`"",
    '-DCMAKE_C_FLAGS=-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00',
    '-DCMAKE_SHARED_LINKER_FLAGS=-static', '-DCMAKE_EXE_LINKER_FLAGS=-static')
& $cmake @configure 2>&1 | Tee-Object -FilePath (Join-Path $work 'configure.log')
if ($LASTEXITCODE -ne 0) { throw 'CloudRedirect CMake configuration failed.' }
& $cmake --build $build --target cloud_redirect pending_ops_journal_tests --parallel $Parallel 2>&1 | Tee-Object -FilePath (Join-Path $work 'build.log')
if ($LASTEXITCODE -ne 0) { throw 'Full CloudRedirect compilation failed.' }
# The upstream journal test deletes a fixed child of temp_directory_path(). Point
# all temporary and application-data roots at this fresh, verified build folder.
$isolated = Join-Path $work 'test-profile'
$savedEnvironment = @{}
foreach ($name in @('TEMP','TMP','APPDATA','LOCALAPPDATA')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
    $isolatedPath = Join-Path $isolated $name.ToLowerInvariant()
    [IO.Directory]::CreateDirectory($isolatedPath) | Out-Null
    [Environment]::SetEnvironmentVariable($name,$isolatedPath,'Process')
}
try {
    & $cmake -E env (Join-Path $build 'pending_ops_journal_tests.exe') 2>&1 | Tee-Object -FilePath (Join-Path $work 'pending-ops-tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'CloudRedirect interrupted-upload journal tests failed.' }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
}
$dll = Join-Path $work 'cloud_redirect.dll'
Copy-Item -LiteralPath (Join-Path $build 'cloud_redirect.dll') -Destination $dll
[xml]$props = Get-Content -LiteralPath (Join-Path $source 'Version.props') -Raw -Encoding utf8
$version = $props.Project.PropertyGroup.ReleaseVersion
$sourceArchive = Join-Path $work "CloudRedirect-$version-$($Commit.Substring(0,7))-source.zip"
$archive = [IO.Compression.ZipFile]::Open($sourceArchive,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force) {
        $relative = $file.FullName.Substring($source.Length + 1).Replace('\','/')
        if ($relative.StartsWith('.git/')) { continue }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
$report = [ordered]@{
    schemaVersion = 1
    upstreamRepository = 'https://github.com/crghofficial/cloudredirect.git'
    upstreamCommit = $Commit
    appliedPatches = @([ordered]@{
        commit = $sourceLock.compatibility.commit
        reviewUrl = $sourceLock.compatibility.reviewUrl
        relativePath = 'dcgaming-build/' + $sourceLock.compatibility.patch
        sha256 = $sourceLock.compatibility.sha256
    })
    cloudRedirectVersion = $version
    configuration = 'Release'; architecture = 'x64'; target = 'cloud_redirect'
    sourceSnapshotSha256 = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash
    toolchain = [ordered]@{
        compiler = (& $cxx --version | Select-Object -First 1)
        compilerSha256 = (Get-FileHash -LiteralPath $cxx -Algorithm SHA256).Hash
        cmakeSha256 = (Get-FileHash -LiteralPath $cmake -Algorithm SHA256).Hash
        ninjaSha256 = (Get-FileHash -LiteralPath $ninja -Algorithm SHA256).Hash
    }
    configureArguments = $configure
    dll = [ordered]@{ relativePath = 'cloud_redirect.dll'; sha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash; size = (Get-Item -LiteralPath $dll).Length }
    sourceArchive = [ordered]@{ relativePath = [IO.Path]::GetFileName($sourceArchive); sha256 = (Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash; size = (Get-Item -LiteralPath $sourceArchive).Length }
    portabilityFiles = @(
        [ordered]@{ relativePath = 'dcgaming-build/CloudRedirectMingw.h'; sha256 = (Get-FileHash -LiteralPath $compat -Algorithm SHA256).Hash },
        [ordered]@{ relativePath = 'dcgaming-build/cloudredirect-clang-portability.patch'; sha256 = (Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash }
    )
    tests = [ordered]@{ pendingOpsJournalPassed = $true }
    realSteamTested = $false
}
[IO.File]::WriteAllText((Join-Path $work 'cloudredirect-build.json'),($report | ConvertTo-Json -Depth 6)+"`n",$encoding)
Write-Output "CloudRedirect $version built from $Commit. The DLL and journal tests are complete; native Steam compatibility is a separate check."
