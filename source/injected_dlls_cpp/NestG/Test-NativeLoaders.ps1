param(
    [Parameter(Mandatory = $true)][string]$NativeOutputDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [string]$HistoricalDwmPath = "$PSScriptRoot/../../app_server/RuntimeBundles/BetterSteamToolsCloud/1.0.3/dwmapi.dll"
)
$ErrorActionPreference = 'Stop'
# Run with the same x64 MSVC/SDK environment as Build-Runtime.ps1.
# Every executable called steam.exe below is OUR compiled disposable test host.
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$root = [IO.Path]::GetFullPath($WorkDirectory)
New-Item -ItemType Directory -Path $root | Out-Null
Push-Location $root
try {
    & cl /nologo /EHsc /MT "$PSScriptRoot/tests/ProxyProbe.cpp" /Fe:ProxyProbe.exe /link /SUBSYSTEM:CONSOLE
    if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed' }
    $reports = [Collections.Generic.List[object]]::new()
    function Run-Probe([string]$Name, [string]$Executable, [string[]]$Arguments) {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $Executable
        # Paths are validated to exclude quote characters; quote every native argument.
        foreach ($argument in $Arguments) { if ($argument.Contains('"')) { throw 'Invalid path argument' } }
        $info.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $info.WorkingDirectory = $root
        $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($info)
        try {
            if (!$process.WaitForExit(15000)) { $process.Kill(); $process.WaitForExit(); throw "Probe timeout: $Name" }
            $result = [PSCustomObject]@{ name = $Name; exitCode = $process.ExitCode; output = $process.StandardOutput.ReadToEnd(); error = $process.StandardError.ReadToEnd() }
            $reports.Add($result)
            if ($result.exitCode -ne 0) { throw "Probe failed: $Name ($($result.exitCode)): $($result.output) $($result.error)" }
        } finally { $process.Dispose() }
    }
    Run-Probe 'historical-export-map' (Join-Path $root 'ProxyProbe.exe') @((Join-Path $NativeOutputDirectory 'dwmapi.dll'), 'exports', (Resolve-Path -LiteralPath $HistoricalDwmPath).Path)
    foreach ($case in @('without-runtime', 'unicode-Steam có dấu', 'invalid-runtime')) {
        $directory = Join-Path $root $case
        New-Item -ItemType Directory -Path $directory | Out-Null
        foreach ($name in @('dwmapi.dll', 'xinput1_4.dll')) { Copy-Item -LiteralPath (Join-Path $NativeOutputDirectory $name) -Destination $directory }
        Copy-Item -LiteralPath (Join-Path $root 'ProxyProbe.exe') -Destination (Join-Path $directory 'steam.exe')
        if ($case -like 'unicode-*') { Copy-Item -LiteralPath (Join-Path $NativeOutputDirectory 'OpenSteamTool.dll') -Destination $directory }
        if ($case -eq 'invalid-runtime') { [IO.File]::WriteAllText((Join-Path $directory 'OpenSteamTool.dll'), 'invalid PE fixture') }
        Run-Probe "$case/dwm" (Join-Path $root 'ProxyProbe.exe') @((Join-Path $directory 'dwmapi.dll'))
        Run-Probe "$case/parallel" (Join-Path $root 'ProxyProbe.exe') @((Join-Path $directory 'dwmapi.dll'), 'parallel')
        Run-Probe "$case/system-first" (Join-Path $root 'ProxyProbe.exe') @((Join-Path $directory 'dwmapi.dll'), 'system-first')
        Run-Probe "$case/xinput" (Join-Path $root 'ProxyProbe.exe') @((Join-Path $directory 'xinput1_4.dll'), 'xinput')
        Run-Probe "$case/xinput-parallel" (Join-Path $root 'ProxyProbe.exe') @((Join-Path $directory 'xinput1_4.dll'), 'xinput-parallel')
        Run-Probe "$case/steam-both" (Join-Path $directory 'steam.exe') @((Join-Path $directory 'dwmapi.dll'), 'both', (Join-Path $directory 'xinput1_4.dll'))
        $log = Get-Content -LiteralPath (Join-Path $directory 'opensteamtool/nestg_startup.log') -Raw
        if ($case -like 'unicode-*') {
            $counter = $reports[$reports.Count - 1].output
            if ($counter -notmatch 'Runtime init callbacks=1 completions=1 calls=2 lastError=126 workerThreadsDistinct=1') { throw 'Both concurrent proxy workers must execute the actual runtime InitOnce callback exactly once and report absent fixture modules.' }
            # StartupDiagnostics is deliberately best-effort: simultaneous proxy
            # writes can drop a stage when its exclusive writer is busy. Its
            # text is diagnostic evidence, not an initialization counter.
            $reports[$reports.Count - 1] | Add-Member -NotePropertyName startupRuntimeStagesObserved -NotePropertyValue ([regex]::Matches($log, 'Stage=runtime\.').Count)
        } elseif (!$log.Contains('Stage=proxy.load.failed ')) { throw 'Missing/invalid runtime must produce diagnostic evidence' }
        # Start another process in the opposite order; each PID gets one initialization.
        $logPath = Join-Path $directory 'opensteamtool/nestg_startup.log'
        [IO.File]::WriteAllText($logPath, '')
        Run-Probe "$case/steam-reverse" (Join-Path $directory 'steam.exe') @((Join-Path $directory 'xinput1_4.dll'), 'both-reverse', (Join-Path $directory 'dwmapi.dll'))
        $log = Get-Content -LiteralPath $logPath -Raw
        if ($case -like 'unicode-*' -and $reports[$reports.Count - 1].output -notmatch 'Runtime init callbacks=1 completions=1 calls=2 lastError=126 workerThreadsDistinct=1') { throw 'Reverse loader order must execute the actual runtime InitOnce callback exactly once from concurrent workers.' }
        if ($case -like 'unicode-*') {
            Run-Probe "$case/steam-both-cold" (Join-Path $directory 'steam.exe') @((Join-Path $directory 'dwmapi.dll'), 'both-cold', (Join-Path $directory 'xinput1_4.dll'))
            Run-Probe "$case/steam-reverse-cold" (Join-Path $directory 'steam.exe') @((Join-Path $directory 'xinput1_4.dll'), 'both-cold-reverse', (Join-Path $directory 'dwmapi.dll'))
        }
    }
    foreach ($fault in @('unwritable-log', 'oversized-log')) {
        $directory = Join-Path $root $fault
        New-Item -ItemType Directory -Path $directory | Out-Null
        foreach ($name in @('dwmapi.dll', 'xinput1_4.dll', 'OpenSteamTool.dll')) { Copy-Item -LiteralPath (Join-Path $NativeOutputDirectory $name) -Destination $directory }
        Copy-Item -LiteralPath (Join-Path $root 'ProxyProbe.exe') -Destination (Join-Path $directory 'steam.exe')
        if ($fault -eq 'unwritable-log') { [IO.File]::WriteAllText((Join-Path $directory 'opensteamtool'), 'blocks-log-directory') }
        else {
            New-Item -ItemType Directory -Path (Join-Path $directory 'opensteamtool') | Out-Null
            [IO.File]::WriteAllText((Join-Path $directory 'opensteamtool/nestg_startup.log'), ('x' * 600KB))
        }
        Run-Probe $fault (Join-Path $directory 'steam.exe') @((Join-Path $directory 'dwmapi.dll'), 'both', (Join-Path $directory 'xinput1_4.dll'))
        if ($fault -eq 'oversized-log' -and (Get-Item -LiteralPath (Join-Path $directory 'opensteamtool/nestg_startup.log')).Length -gt 512KB) { throw 'Native startup log was not bounded.' }
    }
    $reports | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'native-loader-results.json') -Encoding UTF8
    Write-Output "Passed $($reports.Count) native loader cases. Real Steam/save E2E remains required."
} finally { Pop-Location }
