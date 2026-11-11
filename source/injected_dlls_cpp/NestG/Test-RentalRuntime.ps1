param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
# Isolated real Win32/Detours/DPAPI fixture. No real Steam process, installation,
# network, credentials, game files or save data are used.
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$root = [IO.Path]::GetFullPath($WorkDirectory)
[IO.Directory]::CreateDirectory($root) | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'ost_log_macros.h'), '#pragma once')
$detours = Join-Path $source '.deps/detours-src/src'
$detoursSources = @('detours.cpp','modules.cpp','disasm.cpp','image.cpp','creatwth.cpp','disolx64.cpp') | ForEach-Object { Join-Path $detours $_ }
$statusSource = Join-Path $source 'src/NestG/RentalStatusPipe.cpp'
$statusSources = @()
if (Test-Path -LiteralPath $statusSource) { $statusSources += $statusSource }
Push-Location $root
try {
    & cl /nologo /std:c++20 /EHsc /Od /MT /DNOMINMAX /DWIN32_LEAN_AND_MEAN "/I$source/src" "/I$root" "/I$detours" `
        "$PSScriptRoot/tests/RentalRuntimeProbe.cpp" "$source/src/NestG/RentalIdentity.cpp" `
        "$source/src/OSTPlatform/Encoding.cpp" @detoursSources @statusSources `
        /Fe:RentalRuntimeProbe.exe /link /SUBSYSTEM:CONSOLE crypt32.lib bcrypt.lib winhttp.lib ole32.lib advapi32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Rental runtime fixture compilation failed.' }
    & (Join-Path $root 'RentalRuntimeProbe.exe') (Join-Path $root 'disposable-installation')
    if ($LASTEXITCODE -ne 0) { throw 'Rental runtime fixture failed.' }
    $entryPoint = [IO.File]::ReadAllText((Join-Path $source 'src/dllmain.cpp'))
    if ($entryPoint -notmatch '(?s)if\s*\(!NestGRental::Start\([^;]+?\)\)\s*\{[^}]*return 0;\s*\}\s*NestGStartup::Write\("runtime.lua.begin"\)') {
        throw 'The unrestricted Lua VM must be gated by successful filesystem isolation.'
    }
    foreach ($mode in @('--adapter-failure','--worker-exit')) {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = Join-Path $root 'RentalRuntimeProbe.exe'
        $info.Arguments = '"' + (Join-Path $root $mode.Substring(2)) + '" ' + $mode
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $process = [Diagnostics.Process]::Start($info)
        try {
            if (!$process.WaitForExit(15000)) { $process.Kill(); $process.WaitForExit(); throw "Rental startup fixture timeout: $mode" }
            if ($process.ExitCode -ne 0) { throw "Rental startup fixture failed: $mode" }
        } finally { $process.Dispose() }
    }
} finally { Pop-Location }
