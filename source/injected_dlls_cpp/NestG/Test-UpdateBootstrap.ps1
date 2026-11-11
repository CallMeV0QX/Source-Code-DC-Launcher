param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$CompilerDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [string]$NativeOutputDirectory
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$compiler = Join-Path (Resolve-Path -LiteralPath $CompilerDirectory).Path 'clang++.exe'
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $work) { throw 'Use a new fixture directory.' }
[IO.Directory]::CreateDirectory((Join-Path $work 'Helper')) | Out-Null
$helper = Join-Path $work 'Helper/NestG.RuntimeUpdater.exe'
& $compiler '-std=c++17' '-O2' '-static' '-municode' (Join-Path $PSScriptRoot 'tests/RuntimeUpdaterHelperFixture.cpp') '-o' $helper
if ($LASTEXITCODE -ne 0) { throw 'Helper fixture compilation failed.' }
$pinHeader = Join-Path $work 'RuntimeUpdaterPin.h'
$pin = (Get-FileHash -LiteralPath $helper).Hash
[IO.File]::WriteAllText($pinHeader,"#define NESTG_RUNTIME_UPDATER_SHA256 `"$pin`"`n",[Text.UTF8Encoding]::new($false))
$probe = Join-Path $work 'RuntimeUpdateBootstrapProbe.exe'
& $compiler '-std=c++17' '-O2' '-static' '-municode' '-D_WIN32_WINNT=0x0601' '-DWINVER=0x0601' '-include' $pinHeader '-include' (Join-Path $PSScriptRoot 'UpdateBootstrapMingw.h') '-I' (Join-Path $source 'src/NestG') (Join-Path $PSScriptRoot 'tests/RuntimeUpdateBootstrapProbe.cpp') '-o' $probe '-lbcrypt' '-lcrypt32' '-lshell32'
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap probe compilation failed.' }
& $probe $work
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap gate/helper fixture failed.' }
if ($NativeOutputDirectory) {
    $native = (Resolve-Path -LiteralPath $NativeOutputDirectory).Path
    $proxyProbe = Join-Path $work 'ProxyProbe.exe'
    & $compiler '-std=c++17' '-O2' '-static' '-municode' '-D_WIN32_WINNT=0x0601' '-DWINVER=0x0601' (Join-Path $PSScriptRoot 'tests/ProxyProbe.cpp') '-o' $proxyProbe
    if ($LASTEXITCODE -ne 0) { throw 'Proxy dispatch probe compilation failed.' }
    $dwm = Join-Path $native 'dwmapi.dll'; $xinput = Join-Path $native 'xinput1_4.dll'
    & $proxyProbe $dwm 'exports' (Resolve-Path (Join-Path $PSScriptRoot '../../app_server/RuntimeBundles/BetterSteamToolsCloud/1.0.3/dwmapi.dll')).Path
    if ($LASTEXITCODE -ne 0) { throw 'DWM export/ordinal preservation failed.' }
    foreach ($mode in @('parallel','system-first')) {
        & $proxyProbe $dwm $mode
        if ($LASTEXITCODE -ne 0) { throw "DWM dispatch fixture failed: $mode" }
    }
    foreach ($mode in @('xinput','xinput-parallel')) {
        & $proxyProbe $xinput $mode
        if ($LASTEXITCODE -ne 0) { throw "XInput dispatch fixture failed: $mode" }
    }
    0..102 | ForEach-Object { 'extern "C" void NestGDwm' + $_ + '();' } | Set-Content (Join-Path $work 'AbiDeclarations.inc') -Encoding ASCII
    0..102 | ForEach-Object { 'reinterpret_cast<void*>(&NestGDwm' + $_ + '),' } | Set-Content (Join-Path $work 'AbiAddresses.inc') -Encoding ASCII
    $resolver = @'
.intel_syntax noprefix
.text
.extern AbiTarget
.extern AbiIndex
.global NestGResolveDwm
NestGResolveDwm:
 mov DWORD PTR AbiIndex[rip], ecx
 mov rax, QWORD PTR AbiTarget[rip]
 mov rcx, 0x11111111
 mov rdx, 0x22222222
 mov r8, 0x33333333
 mov r9, 0x44444444
 pxor xmm0, xmm0
 pxor xmm1, xmm1
 pxor xmm2, xmm2
 pxor xmm3, xmm3
 ret
'@
    $resolverPath = Join-Path $work 'AbiResolver.s'
    [IO.File]::WriteAllText($resolverPath,$resolver,[Text.UTF8Encoding]::new($false))
    $abiProbe = Join-Path $work 'DwmAbiProbe.exe'
    $thunks = Join-Path $native 'thunks.s'
    & $compiler '-std=c++17' '-O2' '-static' '-include' (Join-Path $PSScriptRoot 'tests/MingwAbiProbeCompat.h') '-I' $work (Join-Path $PSScriptRoot 'tests/DwmAbiProbe.cpp') $thunks $resolverPath '-o' $abiProbe
    if ($LASTEXITCODE -ne 0) { throw 'Generated bootstrap ABI fixture compilation failed.' }
    & $abiProbe
    if ($LASTEXITCODE -ne 0) { throw 'Generated bootstrap argument/unwind ABI fixture failed.' }
    $missing = Join-Path $work 'missing-dwmapi.dll'
    & $compiler '-std=c++17' '-O2' '-shared' '-static' '-D_WIN32_WINNT=0x0601' '-DWINVER=0x0601' '-include' $pinHeader '-include' (Join-Path $PSScriptRoot 'UpdateBootstrapMingw.h') '-include' (Join-Path $PSScriptRoot 'tests/MissingExportFixture.h') (Join-Path $source 'src/dwmapi/dwmapi.cpp') $thunks (Join-Path $source 'src/dwmapi/dwmapi.def') '-o' $missing '-lbcrypt' '-lcrypt32' '-lshell32'
    if ($LASTEXITCODE -ne 0) { throw 'Missing-export fixture compilation failed.' }
    $missingProbe = Join-Path $work 'MissingExportProbe.exe'
    & $compiler '-std=c++17' '-O2' '-static' '-municode' '-D_WIN32_WINNT=0x0601' (Join-Path $PSScriptRoot 'tests/MissingExportProbe.cpp') '-o' $missingProbe
    if ($LASTEXITCODE -ne 0) { throw 'Missing-export probe compilation failed.' }
    & $missingProbe $missing
    if ($LASTEXITCODE -ne 0) { throw 'Controlled missing-export fixture failed.' }
    Write-Output 'Passed 5 shipped-proxy dispatch cases, 412 generated-thunk ABI cases and 103 controlled missing-export cases.'
}
