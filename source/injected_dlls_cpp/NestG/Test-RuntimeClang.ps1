param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$CompilerDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [ValidateRange(100,5000)][int]$Iterations = 1000,
    [ValidateRange(1,100)][int]$VaultCycles = 30
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path "$PSScriptRoot/../..").Path
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$compiler = Join-Path (Resolve-Path -LiteralPath $CompilerDirectory).Path 'clang++.exe'
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (!$work.StartsWith((Join-Path $repository '.codex-temp')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $work)) {
    throw 'Use a new isolated fixture directory under .codex-temp.'
}
foreach ($path in @($work,$source,$compiler)) {
    for ($ancestor=$path; $ancestor; $ancestor=[IO.Path]::GetDirectoryName($ancestor)) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse fixture paths are refused.' }
    }
}
[IO.Directory]::CreateDirectory($work) | Out-Null
[IO.File]::WriteAllText((Join-Path $work 'ost_log_macros.h'), '#pragma once')
$detours = Join-Path $source '.deps/detours-src/src'
$detoursSources = @('detours.cpp','modules.cpp','disasm.cpp','image.cpp','creatwth.cpp','disolx64.cpp') | ForEach-Object { Join-Path $detours $_ }
$common = @('-std=c++20','-O2','-g','-static','-fms-extensions','-DNOMINMAX','-DWIN32_LEAN_AND_MEAN',
    '-D_WIN32_WINNT=0x0A00','-DWINVER=0x0A00','-Wno-deprecated-declarations','-Wno-macro-redefined',
    '-include',(Join-Path $PSScriptRoot 'UpdateBootstrapMingw.h'),'-I',(Join-Path $source 'src'),'-I',$work,'-I',$detours)
$libraries = @('-lcrypt32','-lbcrypt','-lwinhttp','-lole32','-ladvapi32','-lshell32','-lpsapi')
$results = [Collections.Generic.List[object]]::new()
function Build-Probe([string]$Name, [bool]$StatusIncluded, [bool]$IdentityOnly) {
    $executable = Join-Path $work "$Name.exe"
    $inputs = @((Join-Path $PSScriptRoot "tests/$Name.cpp"), (Join-Path $source 'src/NestG/RentalIdentity.cpp'))
    $options = @($common)
    if (!$IdentityOnly) {
        $options += '-municode'
        $inputs += Join-Path $source 'src/OSTPlatform/Encoding.cpp'
        if (!$StatusIncluded) { $inputs += Join-Path $source 'src/NestG/RentalStatusPipe.cpp' }
        $inputs += $detoursSources
    }
    & $compiler @options @inputs '-o' $executable @libraries 2>&1 | Out-File -LiteralPath (Join-Path $work "$Name-build.log") -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "Clang fixture compilation failed: $Name" }
    return $executable
}
function Run-Probe([string]$Name, [string]$Executable, [string[]]$Arguments) {
    foreach ($argument in $Arguments) { if ($argument.Contains('"')) { throw 'Fixture argument contains quote.' } }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $info.WorkingDirectory = $work
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = !$process.WaitForExit(120000)
        if ($timedOut) { $process.Kill(); $process.WaitForExit() }
        $output = $stdout.GetAwaiter().GetResult(); $errorOutput = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $work "$Name-stdout.log"), $output)
        [IO.File]::WriteAllText((Join-Path $work "$Name-stderr.log"), $errorOutput)
        $results.Add([pscustomobject]@{name=$Name;passed=(!$timedOut -and $process.ExitCode -eq 0);exitCode=$process.ExitCode;
            timedOut=$timedOut;elapsedMs=$clock.ElapsedMilliseconds;executableSha256=(Get-FileHash -LiteralPath $Executable).Hash})
        Write-Output $output
        if ($timedOut -or $process.ExitCode -ne 0) { throw "Clang native fixture failed: $Name (see retained logs)." }
    } finally { $process.Dispose() }
}
$failure = $null
try {
    $identity = Build-Probe 'RentalIdentityProbe' $false $true
    Run-Probe 'identity' $identity @()
    $runtime = Build-Probe 'RentalRuntimeProbe' $false $false
    Run-Probe 'runtime' $runtime @((Join-Path $work 'runtime-installation'))
    Run-Probe 'adapter-failure' $runtime @((Join-Path $work 'adapter-failure-installation'),'--adapter-failure')
    Run-Probe 'worker-exit' $runtime @((Join-Path $work 'worker-exit-installation'),'--worker-exit')
    $status = Build-Probe 'RentalStatusProbe' $true $false
    Run-Probe 'status' $status @((Join-Path $work 'status-installation'))
    $stability = Build-Probe 'RentalStabilityProbe' $false $false
    Run-Probe 'stability' $stability @((Join-Path $work 'stability-installation'),"$Iterations","$VaultCycles")
} catch { $failure = $_.Exception.Message }
finally {
    [pscustomobject]@{passed=(!$failure);failure=$failure;compiler=(& $compiler --version | Select-Object -First 1);
        compilerSha256=(Get-FileHash -LiteralPath $compiler).Hash;realSteamAccessed=$false;networkUsed=$false;
        syntheticIdentity=$true;iterations=$Iterations;vaultCycles=$VaultCycles;cases=$results} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $work 'native-fixtures.json') -Encoding utf8
}
if ($failure) { throw $failure }
Write-Output "All $($results.Count) Clang native fixture processes passed; no installed Steam or network used."
