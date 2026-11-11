param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [string]$ProbeArtifactRoot,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion = '1.0.10',
    [ValidateRange(100,5000)][int]$Iterations = 1000,
    [ValidateRange(1,100)][int]$VaultCycles = 30,
    [ValidateRange(1,30)][int]$ProcessRepeats = 10
)
$ErrorActionPreference = 'Stop'
# Use an x64 MSVC/SDK environment. All child processes below are disposable
# fixtures. Nothing discovers, starts, stops or writes to an installed Steam.
$repository = (Resolve-Path "$PSScriptRoot/../..").Path
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
if ([string]::IsNullOrWhiteSpace($ProbeArtifactRoot)) {
    $ProbeArtifactRoot = Join-Path $repository '.codex-temp/rental-runtime-native'
}
$previous = (Resolve-Path -LiteralPath $ProbeArtifactRoot).Path
$root = [IO.Path]::GetFullPath($WorkDirectory)
$allowed = [IO.Path]::GetFullPath((Join-Path $repository '.codex-temp/rental-stability-native'))
if (!$root.StartsWith($allowed + '\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $root)) {
    throw 'Use a new child directory under .codex-temp/rental-stability-native.'
}
[IO.Directory]::CreateDirectory($root) | Out-Null
$results = [Collections.Generic.List[object]]::new()
$started = [DateTime]::UtcNow
$failure = $null

function Frozen-Snapshot {
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repository "app_server/RuntimeBundles/BetterSteamToolsCloud/$ReleaseVersion") -File -Recurse) { $paths.Add($file.FullName) }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repository 'app_desktop/Services/CloudRedirect/TrustedBundles') -File -Filter '*.json') { $paths.Add($file.FullName) }
    $paths.Add((Join-Path $repository 'tools/BetterSteamTools/rental.patch'))
    $paths.Add((Join-Path $repository 'app_server/RuntimeBundles/BetterSteamToolsCloud/1.0.7/bundle.json'))
    $paths.Add((Join-Path $repository 'app_server/RuntimeBundles/BetterSteamToolsCloud/latest.json'))
    return @($paths | Sort-Object | ForEach-Object { [pscustomobject]@{ path=$_.Substring($repository.Length+1); sha256=(Get-FileHash -LiteralPath $_).Hash } })
}
function Run-Probe([string]$Name,[string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=120) {
    $directory = Join-Path $root $Name
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    foreach ($argument in $Arguments) { if ($argument.Contains('"')) { throw 'Fixture argument contains quote.' } }
    $info.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.WorkingDirectory=$directory
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $process=[Diagnostics.Process]::Start($info)
    $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
    $peakPrivate=0L; $peakWorking=0L; $peakHandles=0; $peakThreads=0; $cpuMs=0.0; $timedOut=$false
    try {
        while (!$process.WaitForExit(50)) {
            try {
                $process.Refresh()
                $peakPrivate=[Math]::Max($peakPrivate,$process.PrivateMemorySize64)
                $peakWorking=[Math]::Max($peakWorking,$process.WorkingSet64)
                $peakHandles=[Math]::Max($peakHandles,$process.HandleCount)
                $peakThreads=[Math]::Max($peakThreads,$process.Threads.Count)
                $cpuMs=$process.TotalProcessorTime.TotalMilliseconds
            } catch { }
            if ($clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) { $timedOut=$true; $process.Kill(); $process.WaitForExit(); break }
        }
        $clock.Stop()
        try { $cpuMs=$process.TotalProcessorTime.TotalMilliseconds } catch { }
        $stdout=$outTask.GetAwaiter().GetResult(); $stderr=$errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $directory 'stdout.log'),$stdout)
        [IO.File]::WriteAllText((Join-Path $directory 'stderr.log'),$stderr)
        $result=[pscustomobject]@{ name=$Name; exitCode=$process.ExitCode; timedOut=$timedOut; elapsedMs=$clock.ElapsedMilliseconds; cpuMs=$cpuMs; peakPrivateBytes=$peakPrivate; peakWorkingSetBytes=$peakWorking; peakHandles=$peakHandles; peakThreads=$peakThreads; executableSha256=(Get-FileHash -LiteralPath $Executable).Hash }
        $results.Add($result)
        Write-Output "$Name exit=$($result.exitCode) elapsedMs=$($result.elapsedMs)"
        if ($timedOut -or $result.exitCode -ne 0) { throw "Native stability case failed: $Name (see its stdout/stderr)." }
    } finally { $process.Dispose() }
}

$before=Frozen-Snapshot
$before | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'frozen-before.json') -Encoding UTF8
try {
    # Source used by this harness must match the immutable corresponding archive.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=Join-Path $repository "app_server/RuntimeBundles/BetterSteamToolsCloud/$ReleaseVersion/sources/BetterSteamTools-NestG-source.zip"
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    $sourceCount=0
    try {
        foreach ($entry in $zip.Entries) {
            $relative=$entry.FullName.Replace('\','/')
            if (!$relative.StartsWith('src/') -or $relative.EndsWith('/')) { continue }
            $reader=[IO.StreamReader]::new($entry.Open(),[Text.Encoding]::UTF8,$true)
            try { $archived=$reader.ReadToEnd().Replace("`r`n","`n") } finally { $reader.Dispose() }
            $disk=[IO.File]::ReadAllText((Join-Path $source $relative)).Replace("`r`n","`n")
            if ($archived -cne $disk) { throw "Frozen source mismatch: $relative" }
            $sourceCount++
        }
    } finally { $zip.Dispose() }
    $expectedSourceCount=if ([version]$ReleaseVersion -ge [version]'1.0.9') { 157 } else { 155 }
    if ($sourceCount -ne $expectedSourceCount) { throw 'Unexpected native source count.' }

    $build=Join-Path $root 'build'
    [IO.Directory]::CreateDirectory($build) | Out-Null
    [IO.File]::WriteAllText((Join-Path $build 'ost_log_macros.h'),'#pragma once')
    $detours=Join-Path $source '.deps/detours-src/src'
    $detoursSources=@('detours.cpp','modules.cpp','disasm.cpp','image.cpp','creatwth.cpp','disolx64.cpp') | ForEach-Object { Join-Path $detours $_ }
    $statusSources=@()
    $statusSource=Join-Path $source 'src/NestG/RentalStatusPipe.cpp'
    if (Test-Path -LiteralPath $statusSource) { $statusSources=@($statusSource) }
    Push-Location $build
    try {
        & cl /nologo /std:c++20 /EHsc /Od /MP2 /MT /DNOMINMAX /DWIN32_LEAN_AND_MEAN "/I$source/src" "/I$build" "/I$detours" `
            "$PSScriptRoot/tests/RentalStabilityProbe.cpp" "$source/src/NestG/RentalIdentity.cpp" "$source/src/OSTPlatform/Encoding.cpp" @statusSources @detoursSources `
            /Fe:RentalStabilityProbe.exe /link /SUBSYSTEM:CONSOLE crypt32.lib bcrypt.lib winhttp.lib ole32.lib psapi.lib advapi32.lib
        if ($LASTEXITCODE -ne 0) { throw 'Native stability fixture compilation failed.' }
    } finally { Pop-Location }
    Run-Probe 'runtime-stress' (Join-Path $build 'RentalStabilityProbe.exe') @((Join-Path $root 'fixture'),"$Iterations","$VaultCycles") 180

    # Rebuild each rental probe against this release's verified source. Historical
    # cached executables cannot establish regression coverage for a newer DLL.
    $powershell=(Get-Command powershell.exe).Source
    foreach ($fixture in @(@{name='identity';script='Test-RentalIdentity.ps1'},
                          @{name='package';script='Test-RentalPackage.ps1'},
                          @{name='runtime';script='Test-RentalRuntime.ps1'})) {
        Run-Probe "fresh-$($fixture.name)" $powershell @('-NoProfile','-File',
            (Join-Path $PSScriptRoot $fixture.script),'-SourceDirectory',$source,
            '-WorkDirectory',(Join-Path $root "$($fixture.name)-fixture")) 180
    }
    $identity=Join-Path $root 'identity-fixture/RentalIdentityProbe.exe'
    $package=Join-Path $root 'package-fixture/RentalPackageProbe.exe'
    $runtime=Join-Path $root 'runtime-fixture/RentalRuntimeProbe.exe'
    foreach ($iteration in 1..$ProcessRepeats) {
        Run-Probe "identity-$iteration" $identity @()
        Run-Probe "package-$iteration" $package @()
        Run-Probe "adapter-failure-$iteration" $runtime @((Join-Path $root "adapter-fixture-$iteration"),'--adapter-failure') 20
        Run-Probe "worker-exit-$iteration" $runtime @((Join-Path $root "worker-fixture-$iteration"),'--worker-exit') 20
    }
    Run-Probe 'abi' (Join-Path $previous 'abi-fixture-108-final/DwmAbiProbe.exe') @()
    Run-Probe 'missing-exports' (Join-Path $previous 'abi-fixture-108-final/MissingExportProbe.exe') @((Join-Path $previous 'abi-fixture-108-final/missing-dwmapi.dll'))
    $native=Join-Path $repository "app_server/RuntimeBundles/BetterSteamToolsCloud/$ReleaseVersion"
    Run-Probe 'loader-matrix' $powershell @('-NoProfile','-File',"$PSScriptRoot/Test-NativeLoaders.ps1",'-NativeOutputDirectory',$native,'-WorkDirectory',(Join-Path $root 'loader-fixture'),'-HistoricalDwmPath',(Join-Path $repository 'app_server/RuntimeBundles/BetterSteamToolsCloud/1.0.3/dwmapi.dll')) 180
    Run-Probe 'watcher-shutdown' $powershell @('-NoProfile','-File',"$PSScriptRoot/Test-NativeShutdown.ps1",'-SourceDirectory',$source,'-WorkDirectory',(Join-Path $root 'watcher-fixture')) 180
    Run-Probe 'diagnostics' $powershell @('-NoProfile','-File',"$PSScriptRoot/Test-ActivationDiagnostics.ps1",'-WorkDirectory',(Join-Path $root 'diagnostics-fixture'))
    Run-Probe 'bundle-integrity' $powershell @('-NoProfile','-File',"$PSScriptRoot/Test-RuntimeBundle.ps1",'-ReportPath',(Join-Path $root 'bundle-results.json'))
} catch { $failure=$_.Exception.Message }
finally {
    $after=Frozen-Snapshot
    $after | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'frozen-after.json') -Encoding UTF8
    $unchanged=!(Compare-Object ($before | ForEach-Object { $_.path+':'+$_.sha256 }) ($after | ForEach-Object { $_.path+':'+$_.sha256 }))
    if (!$unchanged -and !$failure) { $failure='Frozen release artifacts changed.' }
    [pscustomobject]@{ startedAtUtc=$started.ToString('O'); finishedAtUtc=[DateTime]::UtcNow.ToString('O'); passed=(!$failure); failure=$failure; sourceFilesMatched=$sourceCount; iterations=$Iterations; vaultCycles=$VaultCycles; processRepeats=$ProcessRepeats; frozenArtifactsUnchanged=$unchanged; realSteamAccessed=$false; networkUsed=$false; cases=$results } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'native-stability-report.json') -Encoding UTF8
}
if ($failure) { throw $failure }
Write-Output "Native stability passed: $($results.Count) process cases; frozen release unchanged. Steam/save E2E was not executed."
