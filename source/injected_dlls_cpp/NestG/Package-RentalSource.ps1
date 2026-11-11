param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion = '1.0.13',
    [switch]$IncludeClangPortability
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repository = (Resolve-Path "$PSScriptRoot/../..").Path
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$work = [IO.Path]::GetFullPath($WorkDirectory)
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path $repository '.codex-temp'))
if (!$work.StartsWith($temporaryRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $work)) { throw 'Use a new child directory under .codex-temp.' }
$baseline = Join-Path $repository 'app_server/RuntimeBundles/BetterSteamToolsCloud/1.0.7/sources/BetterSteamTools-NestG-source.zip'
$baselineHash = (Get-FileHash -LiteralPath $baseline).Hash
$fixture = Join-Path $work 'patch-chain-fixture'
$output = Join-Path $work "BetterSteamTools-NestG-source-$ReleaseVersion.zip"
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $source 'src') -File -Recurse)
if ($sourceFiles.Count -ne 158) { throw 'Expected 158 corresponding native source files including the runtime update bootstrap.' }
foreach ($required in @('.deps/detours-src/src/detours.cpp','.deps/lua-src/src/lua.h','.deps/protobuf-src/LICENSE',
                        '.deps/spdlog-src/CMakeLists.txt','.deps/tomlplusplus-src/CMakeLists.txt')) {
    if (!(Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) { throw "Dependency source absent: $required" }
}
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($baseline)
try {
    foreach ($entry in $zip.Entries) {
        if (!$entry.FullName.StartsWith('src/') -or !$entry.Name) { continue }
        $target = [IO.Path]::GetFullPath((Join-Path $fixture $entry.FullName.Replace('/','\')))
        if (!$target.StartsWith($fixture + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe baseline source path.' }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target)
    }
} finally { $zip.Dispose() }
& git -C $fixture init --quiet
if ($LASTEXITCODE -ne 0) { throw 'Patch fixture initialization failed.' }
if ((& git -C $fixture rev-parse --show-toplevel).Trim().Replace('/','\') -ne $fixture) { throw 'Fixture must own its Git root.' }
# The immutable 1.0.7 archive contains the four pre-rental patches. Reverse them
# to reconstruct upstream, then prove that the complete current recipe reproduces src/.
foreach ($name in @('shutdown.patch','opensteamtool.patch','startup.patch','nestg.patch')) {
    & git -C $fixture -c core.autocrlf=true apply --reverse --check --whitespace=nowarn (Join-Path $PSScriptRoot $name)
    if ($LASTEXITCODE -ne 0) { throw "Cannot reconstruct upstream before $name." }
    & git -C $fixture -c core.autocrlf=true apply --reverse --whitespace=nowarn (Join-Path $PSScriptRoot $name)
    if ($LASTEXITCODE -ne 0) { throw 'Source reconstruction failed.' }
}
$patches = @('nestg.patch','startup.patch','opensteamtool.patch','shutdown.patch','rental.patch','runtime-update.patch')
if ($IncludeClangPortability) { $patches += 'clang-runtime-portability.patch' }
foreach ($name in $patches) {
    & git -C $fixture -c core.autocrlf=true apply --check --whitespace=nowarn (Join-Path $PSScriptRoot $name)
    if ($LASTEXITCODE -ne 0) { throw "Patch chain validation failed: $name" }
    & git -C $fixture -c core.autocrlf=true apply --whitespace=nowarn (Join-Path $PSScriptRoot $name)
    if ($LASTEXITCODE -ne 0) { throw "Patch chain application failed: $name" }
}
if (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -File -Recurse).Count -ne $sourceFiles.Count) {
    throw 'Reapplied patch chain has a different source file count.'
}
foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($source.Length).TrimStart('\')
    $actual = [IO.File]::ReadAllText($file.FullName).Replace("`r`n","`n")
    $reapplied = [IO.File]::ReadAllText((Join-Path $fixture $relative)).Replace("`r`n","`n")
    if ($actual -cne $reapplied) { throw "Reapplied source differs: $relative" }
}
# Keep downloaded dependency sources, licenses and source metadata. Exclude all
# build products/toolchains and replace the source tree's old NestG/ recipes in
# the ZIP with the current repository recipes without modifying SourceDirectory.
$files = [Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force) {
    $relative = $file.FullName.Substring($source.Length).TrimStart('\').Replace('\','/')
    if ($relative.StartsWith('NestG/') -or
        $relative -match '(^|/)(\.git|build|bin|obj|[^/]+-build|[^/]+-subbuild)/|\.(exe|dll|pdb|obj|lib|ilk|exp|nupkg|vsix)$') { continue }
    $files.Add([pscustomobject]@{path=$file.FullName;relativePath=$relative})
}
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File -Recurse) {
    $relative = $file.FullName.Substring($PSScriptRoot.Length).TrimStart('\').Replace('\','/')
    $files.Add([pscustomobject]@{path=$file.FullName;relativePath="NestG/$relative"})
}
$fingerprints = @($files | Where-Object { $_.relativePath.StartsWith('src/') -or $_.relativePath.StartsWith('NestG/') } |
    ForEach-Object { [pscustomobject]@{path=$_.path;sha256=(Get-FileHash -LiteralPath $_.path).Hash} })
$stream = [IO.File]::Create($output)
$writer = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {
    foreach ($file in $files) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($writer,$file.path,$file.relativePath,[IO.Compression.CompressionLevel]::Fastest) | Out-Null
    }
} finally { $writer.Dispose(); $stream.Dispose() }
foreach ($file in $fingerprints) {
    if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) { throw 'Native source or build recipe changed while packaging.' }
}
if ((Get-FileHash -LiteralPath $baseline).Hash -ne $baselineHash) { throw 'Immutable baseline source changed.' }
$report = [pscustomobject]@{
    verified=$true; releaseVersion=$ReleaseVersion; nativeSourceFiles=$sourceFiles.Count
    reconstructedFromHistorical107=$true; patchChain=$patches; normalizedSourceFilesMatched=$sourceFiles.Count
    archiveFiles=$files.Count; archive=$output; archiveBytes=(Get-Item -LiteralPath $output).Length
    archiveSha256=(Get-FileHash -LiteralPath $output).Hash
    patchSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'rental.patch')).Hash
    historical107Unchanged=$true; sourceDirectoryModified=$false
}
$json = $report | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $work 'source-verification.json'),$json+"`n",[Text.UTF8Encoding]::new($false))
Write-Output $json
