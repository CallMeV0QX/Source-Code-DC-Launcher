param(
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [Parameter(Mandatory=$true)][string]$WorkDirectory
)
$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work=[IO.Path]::GetFullPath($WorkDirectory)
if (!$work.StartsWith((Join-Path $repository '.codex-temp')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $work)) { throw 'Use a new disposable directory under repository/.codex-temp.' }
for ($path=$work; $path; $path=[IO.Path]::GetDirectoryName($path)) {
    if ((Test-Path -LiteralPath $path) -and (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Reparse fixture paths are refused.' }
}
$source=(Resolve-Path -LiteralPath $SourceDirectory).Path
[IO.Directory]::CreateDirectory($work) | Out-Null
[IO.File]::WriteAllText((Join-Path $work 'ost_log_macros.h'),'#pragma once')
Push-Location $work
try {
    & cl /nologo /std:c++20 /EHsc /Od /MT /DNOMINMAX /DWIN32_LEAN_AND_MEAN "/I$source/src" "/I$work" `
        "$PSScriptRoot/tests/RentalStatusProbe.cpp" "$source/src/NestG/RentalIdentity.cpp" "$source/src/OSTPlatform/Encoding.cpp" `
        /Fe:RentalStatusProbe.exe /link /SUBSYSTEM:CONSOLE crypt32.lib bcrypt.lib winhttp.lib ole32.lib advapi32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Status probe compilation failed.' }
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $work 'RentalStatusProbe.exe'
    $info.Arguments='"'+(Join-Path $work 'disposable-installation')+'"'
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $process=[Diagnostics.Process]::Start($info)
    try {
        $output=$process.StandardOutput.ReadToEndAsync(); $errorOutput=$process.StandardError.ReadToEndAsync()
        $timeout=!$process.WaitForExit(90000)
        if ($timeout) { $process.Kill(); $process.WaitForExit() }
        $stdout=$output.GetAwaiter().GetResult(); $stderr=$errorOutput.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $work 'stdout.log'),$stdout)
        [IO.File]::WriteAllText((Join-Path $work 'stderr.log'),$stderr)
        [pscustomobject]@{passed=(!$timeout -and $process.ExitCode -eq 0);exitCode=$process.ExitCode;timedOut=$timeout;elapsedMs=$watch.ElapsedMilliseconds;realSteam=$false;syntheticIdentity=$true} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'status-report.json') -Encoding UTF8
        Write-Output $stdout
        if ($timeout -or $process.ExitCode -ne 0) { throw 'Native status probe failed; inspect its retained logs.' }
    } finally { $process.Dispose() }
} finally { Pop-Location }
