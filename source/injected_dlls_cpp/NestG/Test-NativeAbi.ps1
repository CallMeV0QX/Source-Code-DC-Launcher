param(
    [Parameter(Mandatory = $true)][string]$SourceArchive,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
# Compile the UNMODIFIED thunks from the immutable shipped source archive, using
# controlled target signatures rather than calling undocumented Windows APIs.
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$root = [IO.Path]::GetFullPath($WorkDirectory)
$SourceArchive = (Resolve-Path -LiteralPath $SourceArchive).Path
New-Item -ItemType Directory -Path $root | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($SourceArchive)
try {
    $entry = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -match '(^|/)src/dwmapi/thunks.asm$' })
    if ($entry.Count -ne 1) { throw 'Expected exactly one original DWM assembly source.' }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry[0], (Join-Path $root 'thunks.asm'))
    foreach ($relative in @('src/dwmapi/dwmapi.cpp', 'src/dwmapi/dwmapi.def', 'src/dwmapi/exports.inc', 'src/NestG/ProxyBootstrap.h', 'src/NestG/StartupDiagnostics.h')) {
        $matches = @($zip.Entries | Where-Object { $name = $_.FullName.Replace('\', '/'); $name.EndsWith('/' + $relative) -or $name -eq $relative })
        if ($matches.Count -ne 1) { throw "Expected one original source: $relative" }
        $target = Join-Path $root $relative
        [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($matches[0], $target)
    }
} finally { $zip.Dispose() }
0..102 | ForEach-Object { 'extern "C" void NestGDwm' + $_ + '();' } | Set-Content (Join-Path $root 'AbiDeclarations.inc') -Encoding ASCII
0..102 | ForEach-Object { 'reinterpret_cast<void*>(&NestGDwm' + $_ + '),' } | Set-Content (Join-Path $root 'AbiAddresses.inc') -Encoding ASCII
Push-Location $root
try {
    & ml64 /nologo /c /Fothunks.obj thunks.asm
    if ($LASTEXITCODE -ne 0) { throw 'Production thunk assembly failed.' }
    & ml64 /nologo /c /Foresolver.obj "$PSScriptRoot/tests/AbiResolver.asm"
    if ($LASTEXITCODE -ne 0) { throw 'Fixture resolver assembly failed.' }
    & cl /nologo /EHsc /O2 /MT "/I$root" "$PSScriptRoot/tests/DwmAbiProbe.cpp" thunks.obj resolver.obj /Fe:DwmAbiProbe.exe
    if ($LASTEXITCODE -ne 0) { throw 'ABI probe compilation failed.' }
    $output = & (Join-Path $root 'DwmAbiProbe.exe')
    $code = $LASTEXITCODE
    [pscustomobject]@{ exitCode = $code; thunks = 103; cases = 412; output = "$output";
        sourceArchiveSha256 = (Get-FileHash -LiteralPath $SourceArchive).Hash;
        thunkSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $root 'thunks.asm')).Hash } |
        ConvertTo-Json | Set-Content (Join-Path $root 'native-abi-results.json') -Encoding UTF8
    if ($code -ne 0) { throw "ABI probe failed: $code" }
    Write-Output $output
    & cl /nologo /EHsc /O2 /MT /LD "/FI$PSScriptRoot/tests/MissingExportFixture.h" src/dwmapi/dwmapi.cpp thunks.obj /link /DEF:src/dwmapi/dwmapi.def /OUT:missing-dwmapi.dll
    if ($LASTEXITCODE -ne 0) { throw 'Controlled missing-export proxy build failed.' }
    & cl /nologo /EHsc /O2 /MT "$PSScriptRoot/tests/MissingExportProbe.cpp" /Fe:MissingExportProbe.exe
    if ($LASTEXITCODE -ne 0) { throw 'Missing-export probe build failed.' }
    $missingOutput = & (Join-Path $root 'MissingExportProbe.exe') (Join-Path $root 'missing-dwmapi.dll')
    $missingCode = $LASTEXITCODE
    [pscustomobject]@{ exitCode = $missingCode; cases = 103; output = "$missingOutput";
        scope = 'Original archived resolver/thunks, test-only GetProcAddress failure seam; not the shipped binary' } |
        ConvertTo-Json | Set-Content (Join-Path $root 'missing-export-results.json') -Encoding UTF8
    if ($missingCode -ne 0) { throw "Missing-export probe failed: $missingCode" }
    Write-Output $missingOutput
} finally { Pop-Location }
