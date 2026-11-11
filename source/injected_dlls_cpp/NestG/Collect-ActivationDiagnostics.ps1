param(
    [Parameter(Mandatory = $true)][string]$SteamDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$LauncherDirectory = (Join-Path $env:LOCALAPPDATA 'NestGLauncher'),
    [datetime]$Since = (Get-Date).AddHours(-8)
)
$ErrorActionPreference = 'Stop'
# Read-only collection: no Steam launch/shutdown, DLL loading, registry changes,
# account files, provider configuration, save data or recovery journal decryption.
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a new output directory; existing evidence is never overwritten.' }
$steamRoot = (Resolve-Path -LiteralPath $SteamDirectory).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if ($outputRoot.StartsWith($steamRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Diagnostics output must be outside the Steam installation.'
}
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$report = [ordered]@{ collectedUtc = [DateTime]::UtcNow.ToString('o'); sinceUtc = $Since.ToUniversalTime().ToString('o'); osVersion = [Environment]::OSVersion.VersionString; modules = @(); logs = @(); crashEvents = @() }
foreach ($name in @('steam.exe', 'steamclient64.dll', 'steamui.dll', 'dwmapi.dll', 'xinput1_4.dll', 'NestG.dll', 'OpenSteamTool.dll', 'NestGSteamTools.dll', 'cloud_redirect.dll')) {
    $path = Join-Path $steamRoot $name
    try {
        $file = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Not a regular file' }
        $report.modules += @{ name = $name; size = $file.Length; version = $file.VersionInfo.FileVersion; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    } catch { $report.modules += @{ name = $name; unavailable = $true; error = $_.Exception.GetType().Name } }
}

function Copy-LogTail([string]$Path, [string]$Name) {
    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Not a regular log' }
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $length = [int][Math]::Min($stream.Length, 2MB)
            $truncated = $stream.Length -gt $length
            $null = $stream.Seek(-$length, [IO.SeekOrigin]::End)
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
        if ($truncated) { $text = $text.Substring([Math]::Max(0, $text.IndexOf("`n") + 1)) }
        # Defense in depth for old application logs; never collect raw config files.
        $text = [regex]::Replace($text, '(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+', '$1[REDACTED]')
        # Older logs can contain JSON or quoted values with spaces. Match the
        # optional key quotes and the whole quoted value, including escaped chars.
        $secretPattern = @'
(?i)((?:["']?(?:access_token|refresh_token|client_secret|password|authorization|sync_token|provider_token|token|api_key|jwt|sepay_key|smtp_password|secret)["']?)\s*[=:]\s*)(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|[^\s,;]+)
'@
        $text = [regex]::Replace($text, $secretPattern.Trim(), '$1[REDACTED]')
        [IO.File]::WriteAllText((Join-Path $outputRoot $Name), $text, $utf8)
        $report.logs += @{ name = $Name; modifiedUtc = $file.LastWriteTimeUtc.ToString('o'); truncated = $truncated }
    } catch { $report.logs += @{ name = $Name; unavailable = $true; error = $_.Exception.GetType().Name } }
}
Copy-LogTail (Join-Path $steamRoot 'logs/bootstrap_log.txt') 'steam-bootstrap.log'
Copy-LogTail (Join-Path $steamRoot 'cloud_redirect.log') 'cloud_redirect.log'
Copy-LogTail (Join-Path $steamRoot 'opensteamtool/nestg_startup.log') 'nestg_startup.log'
foreach ($folder in @('ActivationLogs', 'Logs')) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $LauncherDirectory $folder) -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -GE $Since | Sort-Object LastWriteTime -Descending | Select-Object -First 10)
    $index = 0
    foreach ($file in $files) {
        # Post-increment emits no value in PowerShell: interpolation would make
        # every destination Logs-.log and silently replace earlier evidence.
        Copy-LogTail $file.FullName "$folder-$index.log"
        $index++
    }
}
try {
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000,1001; StartTime = $Since } -MaxEvents 200 -ErrorAction Stop
    foreach ($event in $events) {
        $xml = [xml]$event.ToXml()
        $fields = @{}
        foreach ($data in $xml.Event.EventData.Data) {
            if ($data.Name -in @('AppName','AppVersion','ModuleName','ModuleVersion','ExceptionCode','FaultingOffset','ProcessId')) {
                $fields[[string]$data.Name] = [string]$data.'#text'
            }
        }
        if ($fields.AppName -eq 'steam.exe') {
            $report.crashEvents += @{ utc = $event.TimeCreated.ToUniversalTime().ToString('o'); id = $event.Id; fields = $fields }
        }
    }
} catch { $report.crashEventStatus = 'No matching accessible events; absence is not proof that Steam did not crash.' }
[IO.File]::WriteAllText((Join-Path $outputRoot 'summary.json'), ($report | ConvertTo-Json -Depth 8), $utf8)
Write-Output "Collected bounded diagnostics: $outputRoot"
