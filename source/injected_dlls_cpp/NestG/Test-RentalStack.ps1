param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$HistoricalSourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
# Run in an x64 MSVC/SDK environment. All files and child processes are disposable;
# this harness never discovers, starts, stops or writes an installed Steam.
$repository = (Resolve-Path "$PSScriptRoot/../..").Path
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$historical = (Resolve-Path -LiteralPath $HistoricalSourceDirectory).Path
$root = [IO.Path]::GetFullPath($WorkDirectory)
$allowed = [IO.Path]::GetFullPath((Join-Path $repository '.codex-temp'))
if (!$root.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $root)) {
    throw 'Use a new fixture directory beneath the repository .codex-temp directory.'
}
if ($source -eq $historical) { throw 'Candidate and immutable historical source must be separate.' }
[IO.Directory]::CreateDirectory($root) | Out-Null
$results = [Collections.Generic.List[object]]::new()
$started = [DateTime]::UtcNow
$failure = $null
$historicalFile = Join-Path $historical 'src/NestG/RentalRuntime.cpp'
$historicalHash = (Get-FileHash -LiteralPath $historicalFile).Hash
$candidateFile = Join-Path $source 'src/NestG/RentalRuntime.cpp'
$candidateHash = (Get-FileHash -LiteralPath $candidateFile).Hash
if ($candidateHash -eq $historicalHash) { throw 'The candidate must contain the stack-buffer fix.' }

function Build-Probe([string]$Name, [string]$NativeSource) {
    $build = Join-Path $root "$Name-build"
    [IO.Directory]::CreateDirectory($build) | Out-Null
    [IO.File]::WriteAllText((Join-Path $build 'ost_log_macros.h'), '#pragma once')
    $detours = Join-Path $NativeSource '.deps/detours-src/src'
    $detoursSources = @('detours.cpp','modules.cpp','disasm.cpp','image.cpp','creatwth.cpp','disolx64.cpp') | ForEach-Object { Join-Path $detours $_ }
    Push-Location $build
    try {
        & cl /nologo /std:c++20 /EHsc /O2 /MT /Zi /DNOMINMAX /DWIN32_LEAN_AND_MEAN "/I$NativeSource/src" "/I$build" "/I$detours" `
            "$PSScriptRoot/tests/RentalStackProbe.cpp" "$NativeSource/src/NestG/RentalIdentity.cpp" `
            "$NativeSource/src/OSTPlatform/Encoding.cpp" "$NativeSource/src/NestG/RentalStatusPipe.cpp" @detoursSources `
            /Fe:RentalStackProbe.exe /link /DEBUG /SUBSYSTEM:CONSOLE crypt32.lib bcrypt.lib winhttp.lib ole32.lib advapi32.lib 2>&1 |
            Out-File -LiteralPath (Join-Path $build 'build.log') -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Release stack fixture compilation failed: $Name (see build.log)." }
    } finally { Pop-Location }
    return Join-Path $build 'RentalStackProbe.exe'
}
function Run-Probe([string]$Name, [string]$Executable, [string]$Context, [int]$StackKiB, [string]$Operation, [bool]$ExpectOverflow) {
    $directory = Join-Path $root $Name
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $arguments = @((Join-Path $directory 'fixture'), $Context, "$StackKiB", $Operation)
    foreach ($argument in $arguments) { if ($argument.Contains('"')) { throw 'Fixture argument contains quote.' } }
    $info.Arguments = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $info.WorkingDirectory = $directory
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = !$process.WaitForExit(20000)
        if ($timedOut) { $process.Kill(); $process.WaitForExit() }
        $timer.Stop()
        $output = $stdout.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $directory 'stdout.log'), $output)
        [IO.File]::WriteAllText((Join-Path $directory 'stderr.log'), $stderr.GetAwaiter().GetResult())
        $exitCode = $process.ExitCode
        $exitHex = '0x' + [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$exitCode), 0).ToString('X8')
        $passed = !$timedOut -and $(if ($ExpectOverflow) { $exitHex -eq '0xC00000FD' } else { $exitCode -eq 0 })
        $results.Add([pscustomobject]@{ name=$Name; context=$Context; stackReserveKiB=$StackKiB; operation=$Operation; expectedHistoricalOverflow=$ExpectOverflow; exitCode=$exitCode; exitHex=$exitHex; timedOut=$timedOut; elapsedMs=$timer.ElapsedMilliseconds; passed=$passed })
        Write-Output "$Name $exitHex passed=$passed"
        if (!$passed) { throw "Stack regression failed: $Name (see stdout.log and stderr.log)." }
        if ($output -notmatch "worker reserve=$($StackKiB * 1024) ") { throw "Missing actual stack-reservation evidence: $Name" }
    } finally { $process.Dispose() }
}
try {
    $historicalExe = Build-Probe 'historical-109' $historical
    $candidateExe = Build-Probe 'candidate' $source
    foreach ($context in @('thread','fiber')) {
        foreach ($stack in @(64,128,256)) {
            foreach ($operation in @('absolute','relative')) {
                Run-Probe "historical-$context-$stack-$operation" $historicalExe $context $stack $operation ($stack -eq 64)
            }
            foreach ($operation in @('absolute','relative','reserved','scoped','allocation-failure')) {
                Run-Probe "candidate-$context-$stack-$operation" $candidateExe $context $stack $operation $false
            }
        }
    }
} catch { $failure = $_.Exception.Message }
finally {
    $historicalUnchanged = (Get-FileHash -LiteralPath $historicalFile).Hash -eq $historicalHash
    $candidateUnchanged = (Get-FileHash -LiteralPath $candidateFile).Hash -eq $candidateHash
    if ((!$historicalUnchanged -or !$candidateUnchanged) -and !$failure) { $failure = 'Native source changed during regression.' }
    [pscustomobject]@{ passed=(!$failure); failure=$failure; startedAtUtc=$started.ToString('O'); finishedAtUtc=[DateTime]::UtcNow.ToString('O'); configuration='MSVC x64 /O2 /MT /EHsc'; historicalRuntimeSha256=$historicalHash; candidateRuntimeSha256=$candidateHash; historicalSourceUnchanged=$historicalUnchanged; candidateSourceUnchanged=$candidateUnchanged; realSteamAccessed=$false; networkUsed=$false; cases=$results } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'stack-regression-report.json') -Encoding utf8
}
if ($failure) { throw $failure }
Write-Output "Stack regression passed: $($results.Count) isolated process cases, including historical 0xC00000FD reproduction."
