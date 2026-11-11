param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$RuntimeUpdaterExecutable,
    [Parameter(Mandatory = $true)][string]$CompilerDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$helper = (Resolve-Path -LiteralPath $RuntimeUpdaterExecutable).Path
$compiler = Join-Path (Resolve-Path -LiteralPath $CompilerDirectory).Path 'clang++.exe'
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $work) { throw 'Use a new bootstrap build directory.' }
$hash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
foreach ($path in @($source,$helper,$compiler,$work)) {
    for ($current = $path; $current; $current = [IO.Path]::GetDirectoryName($current)) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse build paths are not accepted.' }
    }
}
if (!(Test-Path -LiteralPath (Join-Path $source 'src/NestG/RuntimeUpdateBootstrap.h'))) { throw 'Apply all six patches first.' }
[IO.Directory]::CreateDirectory($work) | Out-Null
# Keep the pin in a generated forced-include header so shell quoting cannot strip
# its literal string delimiters. This file is part of the build evidence.
$encoding = [Text.UTF8Encoding]::new($false)
$pinHeader = Join-Path $work 'RuntimeUpdaterPin.h'
[IO.File]::WriteAllText($pinHeader,"#define NESTG_RUNTIME_UPDATER_SHA256 `"$hash`"`n",$encoding)
# GAS equivalent of the reviewed MASM thunks, including Windows unwind records.
$assembly = [Text.StringBuilder]::new(".intel_syntax noprefix`n.text`n.extern NestGResolveDwm`n")
foreach ($index in 0..102) {
    [void]$assembly.Append(".global NestGDwm$index`n.seh_proc NestGDwm$index`nNestGDwm${index}:`n sub rsp, 0xA8`n .seh_stackalloc 0xA8`n .seh_endprologue`n")
    foreach ($register in @(@('rcx','20'),@('rdx','28'),@('r8','30'),@('r9','38'))) { [void]$assembly.Append(" mov [rsp+0x$($register[1])], $($register[0])`n") }
    foreach ($register in @(@('xmm0','40'),@('xmm1','50'),@('xmm2','60'),@('xmm3','70'))) { [void]$assembly.Append(" movdqu [rsp+0x$($register[1])], $($register[0])`n") }
    [void]$assembly.Append(" mov ecx, $index`n call NestGResolveDwm`n")
    foreach ($register in @(@('rcx','20'),@('rdx','28'),@('r8','30'),@('r9','38'))) { [void]$assembly.Append(" mov $($register[0]), [rsp+0x$($register[1])]`n") }
    foreach ($register in @(@('xmm0','40'),@('xmm1','50'),@('xmm2','60'),@('xmm3','70'))) { [void]$assembly.Append(" movdqu $($register[0]), [rsp+0x$($register[1])]`n") }
    [void]$assembly.Append(" add rsp, 0xA8`n jmp rax`n.seh_endproc`n")
}
$assemblyPath = Join-Path $work 'thunks.s'
[IO.File]::WriteAllText($assemblyPath,$assembly.ToString(),$encoding)
$common = @('-std=c++17','-O2','-g','-shared','-static','-D_WIN32_WINNT=0x0601','-DWINVER=0x0601','-include',$pinHeader,'-include',(Join-Path $PSScriptRoot 'UpdateBootstrapMingw.h'))
& $compiler @common (Join-Path $source 'src/dwmapi/dwmapi.cpp') $assemblyPath (Join-Path $source 'src/dwmapi/dwmapi.def') '-o' (Join-Path $work 'dwmapi.dll') '-lbcrypt' '-lcrypt32' '-lshell32'
if ($LASTEXITCODE -ne 0) { throw 'DWM bootstrap compilation failed.' }
& $compiler @common (Join-Path $source 'src/xinput1_4/xinput1_4.cpp') (Join-Path $source 'src/xinput1_4/xinput1_4.def') '-o' (Join-Path $work 'xinput1_4.dll') '-lbcrypt' '-lcrypt32' '-lshell32'
if ($LASTEXITCODE -ne 0) { throw 'XInput bootstrap compilation failed.' }
$report = [ordered]@{ runtimeUpdaterSha256=$hash; compiler=((& $compiler --version | Select-Object -First 1)); compilerSha256=(Get-FileHash -LiteralPath $compiler).Hash; dwmSha256=(Get-FileHash -LiteralPath (Join-Path $work 'dwmapi.dll')).Hash; xinputSha256=(Get-FileHash -LiteralPath (Join-Path $work 'xinput1_4.dll')).Hash; upstreamUpdaterEnabled=$false; realSteamTested=$false }
[IO.File]::WriteAllText((Join-Path $work 'bootstrap-build.json'),($report | ConvertTo-Json)+"`n",$encoding)
Write-Output 'Both update bootstrap proxies built. Run isolated native fixtures and package matching corresponding source before distribution.'
