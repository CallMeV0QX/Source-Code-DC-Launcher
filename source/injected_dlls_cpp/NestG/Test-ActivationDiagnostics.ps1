param([Parameter(Mandatory = $true)][string]$WorkDirectory)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$root = [IO.Path]::GetFullPath($WorkDirectory)
$steam = Join-Path $root 'Steam'
$launcher = Join-Path $root 'Launcher'
foreach ($relative in @('Steam/logs', 'Steam/cloud_redirect', 'Steam/userdata/fixture', 'Launcher/Logs', 'Launcher/ActivationLogs')) {
    [IO.Directory]::CreateDirectory((Join-Path $root $relative)) | Out-Null
}
# Deliberately recognizable fake secrets, never live credentials.
$sample = @'
Authorization: Bearer fixture.bearer.secret
{"access_token":"fixture-json-access","refresh_token": "fixture-json-refresh"}
password="fixture password with spaces"
provider_token='fixture provider secret'
token=fixture-unquoted-token; safe=value
{"client_secret":"fixture-escaped-\"-secret"}
'@
[IO.File]::WriteAllText((Join-Path $launcher 'Logs/fixture.log'), $sample)
[IO.File]::WriteAllText((Join-Path $launcher 'Logs/second.log'), 'second-log-evidence')
[IO.File]::WriteAllText((Join-Path $steam 'cloud_redirect/config.json'), '{"token":"do-not-collect-config"}')
[IO.File]::WriteAllText((Join-Path $steam 'userdata/fixture/save.dat'), 'do-not-collect-save')
[IO.File]::WriteAllText((Join-Path $steam 'logs/bootstrap_log.txt'), (('bounded harmless line' + "`n") * 150000))
# A log path that is a directory must be reported unavailable, never traversed.
[IO.Directory]::CreateDirectory((Join-Path $steam 'cloud_redirect.log')) | Out-Null
$before = @(Get-ChildItem -LiteralPath $root -File -Recurse | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash })
$output = Join-Path $root 'report'
& "$PSScriptRoot/Collect-ActivationDiagnostics.ps1" -SteamDirectory $steam -LauncherDirectory $launcher -OutputDirectory $output -Since (Get-Date).AddHours(-1)
$logFiles = @(Get-ChildItem -LiteralPath $output -File -Filter 'Logs-*.log')
if ($logFiles.Count -ne 2) { throw 'Multiple input logs were overwritten or lost.' }
$text = ($logFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
if (!$text.Contains('second-log-evidence')) { throw 'Second log evidence is missing.' }
foreach ($secret in @('fixture.bearer.secret','fixture-json-access','fixture-json-refresh','fixture password with spaces','fixture provider secret','fixture-unquoted-token','fixture-escaped-')) {
    if ($text.Contains($secret)) { throw 'A fixture secret was not redacted.' }
}
if (!$text.Contains('safe=value')) { throw 'Unrelated log evidence was removed.' }
if ((Get-Item -LiteralPath (Join-Path $output 'steam-bootstrap.log')).Length -gt 2MB) { throw 'Log tail exceeds the bound.' }
$summary = Get-Content -LiteralPath (Join-Path $output 'summary.json') -Raw | ConvertFrom-Json
if (!($summary.logs | Where-Object { $_.name -eq 'cloud_redirect.log' -and $_.unavailable })) { throw 'Unavailable log was not reported.' }
if (!($summary.logs | Where-Object { $_.name -eq 'steam-bootstrap.log' -and $_.truncated })) { throw 'Truncated log was not reported.' }
$after = @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { !$_.FullName.StartsWith($output + '\', [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash })
if (Compare-Object $before $after) { throw 'Collector mutated fixture inputs.' }
if (Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Name -like '*config*' -or $_.Name -like '*save*' }) { throw 'Private config/save was collected.' }
[pscustomobject]@{ status = 'Pass'; cases = @('quoted-json-secrets','quoted-spaces','bearer','unquoted-secret','bounded-tail','unavailable-log','read-only','no-config-or-save','distinct-log-files') } |
    ConvertTo-Json | Set-Content (Join-Path $root 'diagnostics-test-results.json') -Encoding UTF8
Write-Output 'Passed diagnostics redaction, bounds and read-only checks.'
