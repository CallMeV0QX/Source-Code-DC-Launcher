param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-F0-9]{64}$')][string]$RuntimeUpdaterSha256,
    [ValidatePattern('^\d+\.\d+\.\d+-nestg\.\d+$')][string]$NativeVersion = '1.0.4-nestg.9'
)
$ErrorActionPreference = 'Stop'
# Run in an x64 Native Tools / Developer PowerShell with MSVC, Windows SDK,
# CMake 3.31+ and Ninja on PATH. No global tool installation is performed here.
$commit = '4747385bdc7c92fb422e63419a5093566b3bf626'
if (Test-Path -LiteralPath $SourceDirectory) {
    throw 'Use a new empty source directory so no existing checkout is changed.'
}
git clone https://github.com/madoiscool/BetterSteamTools.git $SourceDirectory
if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }
git -C $SourceDirectory checkout --detach $commit
if ($LASTEXITCODE -ne 0) { throw 'Checkout failed' }
git -C $SourceDirectory apply --check --whitespace=nowarn "$PSScriptRoot/nestg.patch"
if ($LASTEXITCODE -ne 0) { throw 'Patch validation failed' }
git -C $SourceDirectory apply --whitespace=nowarn "$PSScriptRoot/nestg.patch"
if ($LASTEXITCODE -ne 0) { throw 'Patch failed' }
git -C $SourceDirectory apply --check --whitespace=nowarn "$PSScriptRoot/startup.patch"
if ($LASTEXITCODE -ne 0) { throw 'Startup patch validation failed' }
git -C $SourceDirectory apply --whitespace=nowarn "$PSScriptRoot/startup.patch"
if ($LASTEXITCODE -ne 0) { throw 'Startup patch failed' }
git -C $SourceDirectory apply --check --whitespace=nowarn "$PSScriptRoot/opensteamtool.patch"
if ($LASTEXITCODE -ne 0) { throw 'OpenSteamTool patch validation failed' }
git -C $SourceDirectory apply --whitespace=nowarn "$PSScriptRoot/opensteamtool.patch"
if ($LASTEXITCODE -ne 0) { throw 'OpenSteamTool patch failed' }
git -C $SourceDirectory apply --check --whitespace=nowarn "$PSScriptRoot/shutdown.patch"
if ($LASTEXITCODE -ne 0) { throw 'Shutdown patch validation failed' }
git -C $SourceDirectory apply --whitespace=nowarn "$PSScriptRoot/shutdown.patch"
if ($LASTEXITCODE -ne 0) { throw 'Shutdown patch failed' }
git -C $SourceDirectory apply --check --whitespace=nowarn "$PSScriptRoot/rental.patch"
if ($LASTEXITCODE -ne 0) { throw 'Rental runtime patch validation failed' }
git -C $SourceDirectory apply --whitespace=nowarn "$PSScriptRoot/rental.patch"
if ($LASTEXITCODE -ne 0) { throw 'Rental runtime patch failed' }
git -C $SourceDirectory apply --check --whitespace=nowarn "$PSScriptRoot/runtime-update.patch"
if ($LASTEXITCODE -ne 0) { throw 'Runtime update bootstrap patch validation failed' }
git -C $SourceDirectory apply --whitespace=nowarn "$PSScriptRoot/runtime-update.patch"
if ($LASTEXITCODE -ne 0) { throw 'Runtime update bootstrap patch failed' }
cmake -S "$SourceDirectory/src" -B $BuildDirectory -G 'Ninja Multi-Config' `
    "-DNESTG_RUNTIME_UPDATER_SHA256=$RuntimeUpdaterSha256" `
    '-DOST_ENABLE_UPDATER=OFF' "-DOPENSTEAMTOOL_VERSION=$NativeVersion" `
    '-DOST_ETICKET_URL=' '-DOST_TOKEER_URL=' '-DCMAKE_TRY_COMPILE_CONFIGURATION=Release' `
    '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded' `
    '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /Zi' '-DCMAKE_SHARED_LINKER_FLAGS_RELEASE=/DEBUG:FULL /OPT:REF /OPT:ICF'
if ($LASTEXITCODE -ne 0) { throw 'Configure failed' }
cmake --build $BuildDirectory --config Release --target OpenSteamTool dwmapi xinput1_4 --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
Write-Output "DLL output: $BuildDirectory/Release. Review binaries and regenerate bundle and client pins together."
