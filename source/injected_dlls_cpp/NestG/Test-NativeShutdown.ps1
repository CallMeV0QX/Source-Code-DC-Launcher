param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [switch]$ExpectHistoricalFailure
)
$ErrorActionPreference = 'Stop'
# SourceDirectory is an extracted corresponding-source archive, never Steam.
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$root = [IO.Path]::GetFullPath($WorkDirectory)
$stubs = Join-Path $root 'stubs'
[IO.Directory]::CreateDirectory($stubs) | Out-Null
Copy-Item -LiteralPath "$PSScriptRoot/tests/WatcherFixture.h" -Destination $stubs
foreach ($name in @('Hook/Hooks_Package.h', 'Hook/Hooks_NetPacket.h', 'Utils/Config/Config.h',
        'Utils/Config/LuaConfig.h', 'Utils/CloudRedirect/CloudRedirectHost.h', 'Utils/Logging/Log.h')) {
    $path = Join-Path $stubs $name
    [IO.Directory]::CreateDirectory((Split-Path $path)) | Out-Null
    [IO.File]::WriteAllText($path, '#include "WatcherFixture.h"')
}
Push-Location $root
try {
    & cl /nologo /std:c++20 /EHsc /O2 /MT /LD "/I$stubs" "/I$source/src" "/I$source/src/OSTPlatform" `
        "$PSScriptRoot/tests/WatcherFixture.cpp" "$source/src/Utils/Config/ConfigFileWatcher.cpp" `
        "$source/src/Utils/Config/LuaFileWatcher.cpp" "$source/src/OSTPlatform/Windows/DirectoryWatch.cpp" `
        "$source/src/OSTPlatform/Encoding.cpp" /link /OUT:watchers.dll
    if ($LASTEXITCODE -ne 0) { throw 'Watcher fixture compilation failed.' }
    & cl /nologo /std:c++20 /EHsc /O2 /MT "$PSScriptRoot/tests/WatcherExitProbe.cpp" /Fe:WatcherExitProbe.exe
    if ($LASTEXITCODE -ne 0) { throw 'Watcher host compilation failed.' }
    $reports = @()
    $cases = if ($ExpectHistoricalFailure) { @('idle', 'missing') } else { @('idle', 'missing', 'immediate', 'reload', 'restart', 'concurrent') }
    foreach ($case in $cases) {
        foreach ($iteration in 1..3) {
            $directory = Join-Path $root "$case-$iteration"
            $info = [Diagnostics.ProcessStartInfo]::new()
            $info.FileName = Join-Path $root 'WatcherExitProbe.exe'
            $arguments = @((Join-Path $root 'watchers.dll'), $directory, $case)
            foreach ($argument in $arguments) { if ($argument.Contains('"')) { throw 'Invalid argument' } }
            $info.Arguments = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
            $info.UseShellExecute = $false; $info.CreateNoWindow = $true
            $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
            $process = [Diagnostics.Process]::Start($info)
            try {
                if (!$process.WaitForExit(20000)) { $process.Kill(); $process.WaitForExit(); throw "Watcher test timed out: $case" }
                $code = $process.ExitCode
                $reports += [PSCustomObject]@{ case = $case; iteration = $iteration; exitCode = $code }
                $expected = if ($ExpectHistoricalFailure) { -1073740791 } else { 0 } # 0xc0000409
                if ($code -ne $expected) { throw "Watcher test $case exited $code; expected $expected" }
            } finally { $process.Dispose() }
        }
    }
    $reports | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'shutdown-results.json') -Encoding UTF8
    Write-Output "Validated $($reports.Count) watcher exit cases (historical failure expected: $ExpectHistoricalFailure)."
} finally { Pop-Location }
