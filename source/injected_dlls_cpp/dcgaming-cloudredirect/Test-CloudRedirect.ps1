param(
    [Parameter(Mandatory=$true)][string]$DllPath,
    [Parameter(Mandatory=$true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
$dll = (Resolve-Path -LiteralPath $DllPath).Path
$work = [IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $work) { throw 'Use a new test directory.' }
# The fixture performs no recursive cleanup. Preserve all evidence for review.
[IO.Directory]::CreateDirectory($work) | Out-Null
$isolatedDll = Join-Path $work 'cloud_redirect.dll'
Copy-Item -LiteralPath $dll -Destination $isolatedDll
$expectedHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
$project = Join-Path $PSScriptRoot 'tests/CloudRedirectProbe/CloudRedirectProbe.csproj'
$probeOutput = Join-Path $work 'probe'
& dotnet build $project -c Release --artifacts-path (Join-Path $work 'build') -o $probeOutput --nologo
if ($LASTEXITCODE -ne 0) { throw 'Native API fixture build failed.' }
$probe = Join-Path $probeOutput 'CloudRedirectProbe.exe'
$provider = Join-Path $work 'provider'
foreach ($phase in @('writer', 'recover', 'reader')) {
    if ($phase -ne 'recover') {
        $clientRoot = Join-Path $work $phase
        $target = Join-Path $clientRoot 'junction-target'
        $documents = Join-Path $clientRoot 'KnownFolders/fdd39ad0238f46afadb46c85480369c7'
        $junction = Join-Path $documents '.cloudredirect'
        # Both ends stay inside this disposable fixture. Native cleanup must
        # unlink the junction without deleting the legacy-named target files.
        foreach ($candidate in @($target, $junction)) {
            if (![IO.Path]::GetFullPath($candidate).StartsWith($work.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Junction fixture escaped the test root.'
            }
        }
        [IO.Directory]::CreateDirectory($target) | Out-Null
        [IO.Directory]::CreateDirectory($documents) | Out-Null
        [IO.File]::WriteAllText((Join-Path $target 'Playtime.bin'), 'junction target must survive')
        [IO.File]::WriteAllText((Join-Path $target 'UserGameStats.bin'), 'junction target must survive')
        New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
    }
    # Child process owns all redirected environment variables and native hooks.
    $stdout = Join-Path $work ($phase + '.stdout.log')
    $stderr = Join-Path $work ($phase + '.stderr.log')
    $arguments = @('"' + $isolatedDll + '"', '"' + $work + '"', $phase, '"' + $provider + '"')
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $probe
    $startInfo.Arguments = [string]::Join(' ', $arguments)
    $startInfo.WorkingDirectory = $work
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (!$process.Start()) { throw 'Could not start isolated API fixture.' }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(60000)) {
            # Only this fixture process is ours; never stop Steam or another launcher.
            $process.Kill()
            throw "CloudRedirect API fixture timed out in phase $phase; inspect $work"
        }
        [IO.File]::WriteAllText($stdout, $outputTask.Result, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderr, $errorTask.Result, [Text.UTF8Encoding]::new($false))
        if ($process.ExitCode -ne 0) {
            Get-Content -LiteralPath $stderr -Encoding utf8
            throw "CloudRedirect API fixture failed in phase $phase"
        }
        Get-Content -LiteralPath $stdout -Encoding utf8
    } finally { $process.Dispose() }
}
if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne $expectedHash -or
    (Get-FileHash -LiteralPath $isolatedDll -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'The fixture must not modify the tested DLL.'
}
$results = @('writer', 'recover', 'reader') | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $work ('probe-' + $_ + '.json')) -Raw -Encoding utf8 | ConvertFrom-Json
}
$summary = [ordered]@{ dllSha256=$expectedHash; phases=3; assertions=($results | Measure-Object -Property passed -Sum).Sum; results=$results }
[IO.File]::WriteAllText((Join-Path $work 'results.json'), ($summary | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output ("Passed {0} native DLL assertions across writer, interrupted-upload recovery and fresh-reader processes." -f $summary.assertions)
