param([string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot/../..").Path)
# Reproduce the metadata-only 1.0.1 release. Never modifies a Steam installation.
$ErrorActionPreference = 'Stop'
$bundleRoot = Join-Path $RepositoryRoot 'app_server/RuntimeBundles/BetterSteamToolsCloud'
$previous = Join-Path $bundleRoot '1.0.0'
$target = Join-Path $bundleRoot '1.0.1'
if (Test-Path -LiteralPath $target) { throw 'Version 1.0.1 already exists; releases are immutable.' }
$manifest = Get-Content -LiteralPath "$previous/bundle.json" -Raw | ConvertFrom-Json
foreach ($file in $manifest.files) {
    $path = Join-Path $previous $file.relativePath
    if ((Get-Item -LiteralPath $path).Length -ne $file.size -or (Get-FileHash -LiteralPath $path).Hash -ne $file.sha256) {
        throw "Previous release is not intact: $($file.relativePath)"
    }
}
$additions = @(
    @{ channel='pattern'; component='steamclient'; module='caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee'; commit='977aac5dbdb6e0a47e1f1ede0b5633217232e56f'; sha256='6AC14220B35235CCBD1912F96D710316AE72009FC8436009A155798FD664A4C8' },
    @{ channel='pattern'; component='steamui'; module='cb387adefbbac64a3c1490d4275d00daf3a1e0219b4580726ef7681db7429278'; commit='977aac5dbdb6e0a47e1f1ede0b5633217232e56f'; sha256='44BA2B454535F3052B4A7530EFC2A924908853A5C72BE2DB660FFEAF5B142E58' },
    @{ channel='ipc'; component='steamclient'; module='caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee'; commit='7deb2817e89be646d1230ea47367825b4d3a1061'; sha256='012A06ED69570E3E82FACD134AF7FFC8138F9C030438371C80254D007CF4535B' }
)
foreach ($file in $manifest.files) {
    $destination = Join-Path $target $file.relativePath
    [IO.Directory]::CreateDirectory((Split-Path $destination)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $previous $file.relativePath) -Destination $destination
}
foreach ($addition in $additions) {
    $relativePath = "opensteamtool/$($addition.channel)/$($addition.component)/$($addition.module).toml"
    $destination = Join-Path $target $relativePath
    [IO.Directory]::CreateDirectory((Split-Path $destination)) | Out-Null
    $url = "https://raw.githubusercontent.com/madoiscool/steam-monitor/$($addition.commit)/$($addition.component)/$($addition.module).toml"
    Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing -TimeoutSec 30
    if ((Get-FileHash -LiteralPath $destination).Hash -ne $addition.sha256) { throw 'Downloaded metadata does not match reviewed SHA-256' }
    $manifest.files += [PSCustomObject]@{
        relativePath=$relativePath; installPath=$relativePath; size=(Get-Item -LiteralPath $destination).Length; sha256=$addition.sha256
    }
}
$manifest.version = '1.0.1'
$utf8 = [Text.UTF8Encoding]::new($false)
$json = ($manifest | ConvertTo-Json -Depth 8) + "`n"
[IO.File]::WriteAllText((Join-Path $target 'bundle.json'), $json, $utf8)
[IO.File]::WriteAllText((Join-Path $RepositoryRoot 'app_desktop/Services/CloudRedirect/TrustedBundles/bettersteamtools-cloud.json'), $json, $utf8)
[IO.File]::WriteAllText((Join-Path $bundleRoot 'latest.json'), '{"version":"1.0.1"}' + "`n", $utf8)
Write-Output 'Created metadata-only BetterSteamTools 1.0.1; previous files and native binaries are unchanged.'
