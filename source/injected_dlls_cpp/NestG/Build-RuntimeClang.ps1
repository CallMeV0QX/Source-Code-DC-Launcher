param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$CompilerDirectory,
    [Parameter(Mandatory = $true)][string]$CMakeExecutable,
    [Parameter(Mandatory = $true)][string]$NinjaExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-F0-9]{64}$')][string]$RuntimeUpdaterSha256,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+-nestg\.\d+$')][string]$NativeVersion
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$compiler = (Resolve-Path -LiteralPath $CompilerDirectory).Path
$cmake = (Resolve-Path -LiteralPath $CMakeExecutable).Path
$ninja = (Resolve-Path -LiteralPath $NinjaExecutable).Path
$build = [IO.Path]::GetFullPath($BuildDirectory)
if (Test-Path -LiteralPath $build) { throw 'Use a new full runtime build directory.' }
foreach ($path in @($source, $compiler, $cmake, $ninja, $build)) {
    for ($ancestor = $path; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Reparse build paths are not accepted.'
        }
    }
}
if (!(Test-Path -LiteralPath (Join-Path $source 'src/NestG/RuntimeUpdateBootstrap.h'))) { throw 'Apply the complete reviewed patch chain first.' }
if (!(Test-Path -LiteralPath (Join-Path $source '.git'))) {
    & git -C $source init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize the isolated source checkout.' }
}
if ((& git -C $source rev-parse --show-toplevel).Trim().Replace('/','\') -ne $source) { throw 'Native source must own its Git root.' }
$portabilityPatch = Join-Path $PSScriptRoot 'clang-runtime-portability.patch'
$rentalSource = [IO.File]::ReadAllText((Join-Path $source 'src/NestG/RentalRuntime.cpp'))
if ($rentalSource.Contains('std::atomic_load(&state.active)')) {
    & git -C $source apply --reverse --check --whitespace=nowarn $portabilityPatch
    if ($LASTEXITCODE -ne 0) { throw 'Existing Clang portability patch differs from the reviewed recipe.' }
} else {
    & git -C $source apply --check --whitespace=nowarn $portabilityPatch
    if ($LASTEXITCODE -ne 0) { throw 'Clang portability patch validation failed.' }
    & git -C $source apply --whitespace=nowarn $portabilityPatch
    if ($LASTEXITCODE -ne 0) { throw 'Clang portability patch application failed.' }
}
foreach ($dependency in @('lua','detours','protobuf','spdlog','tomlplusplus')) {
    if (!(Test-Path -LiteralPath (Join-Path $source ".deps/$dependency-src"))) { throw "Cached corresponding dependency is missing: $dependency" }
}
$cc = (Join-Path $compiler 'clang.exe').Replace('\','/')
$cxx = (Join-Path $compiler 'clang++.exe').Replace('\','/')
$assembler = (Join-Path $compiler 'llvm-ml.exe').Replace('\','/')
$compat = (Join-Path $PSScriptRoot 'UpdateBootstrapMingw.h').Replace('\','/')
# Build the complete main runtime, its generators, and all static dependencies.
# The stable proxy DLLs are separate artifacts and must not be replaced by this command.
& $cmake -S (Join-Path $source 'src') -B $build -G 'Ninja Multi-Config' `
    "-DCMAKE_MAKE_PROGRAM=$ninja" "-DCMAKE_C_COMPILER=$cc" "-DCMAKE_CXX_COMPILER=$cxx" `
    "-DCMAKE_ASM_MASM_COMPILER=$assembler" "-DNESTG_RUNTIME_UPDATER_SHA256=$RuntimeUpdaterSha256" `
    "-DOPENSTEAMTOOL_VERSION=$NativeVersion" '-DOST_ENABLE_UPDATER=OFF' '-DOST_ETICKET_URL=' '-DOST_TOKEER_URL=' `
    "-DCMAKE_CXX_FLAGS=-fms-extensions -DNOMINMAX -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -include `"$compat`"" `
    '-DCMAKE_C_FLAGS=-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00' `
    '-DCMAKE_CXX_FLAGS_RELEASE=-O2 -DNDEBUG' '-DCMAKE_C_FLAGS_RELEASE=-O2 -DNDEBUG' `
    '-DCMAKE_EXE_LINKER_FLAGS=-static' '-DCMAKE_SHARED_LINKER_FLAGS=-static' `
    '-DCMAKE_TRY_COMPILE_CONFIGURATION=Release'
if ($LASTEXITCODE -ne 0) { throw 'Full runtime CMake configuration failed.' }
& $cmake --build $build --config Release --target OpenSteamTool --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Full runtime compilation failed.' }
$report = [ordered]@{
    nativeVersion = $NativeVersion; upstreamUpdaterEnabled = $false; realSteamTested = $false
    sourceDirectory = $source; target = 'OpenSteamTool'; configuration = 'Release'
    compiler = (& $cxx --version | Select-Object -First 1)
    compilerSha256 = (Get-FileHash -LiteralPath $cxx).Hash
    cmakeSha256 = (Get-FileHash -LiteralPath $cmake).Hash
    ninjaSha256 = (Get-FileHash -LiteralPath $ninja).Hash
    runtimeUpdaterSha256 = $RuntimeUpdaterSha256
    portabilityPatchSha256 = (Get-FileHash -LiteralPath $portabilityPatch).Hash
}
[IO.File]::WriteAllText((Join-Path $build 'runtime-build.json'), ($report | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "Complete runtime rebuilt as $NativeVersion. Validate PE/imports/exports and package its corresponding source before distribution."
