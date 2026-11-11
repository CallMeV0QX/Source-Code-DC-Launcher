param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
# This fixture compiles the state tracker only. It neither loads a DLL into
# Steam nor accesses a Steam installation, credentials, network or save data.
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$root = [IO.Path]::GetFullPath($WorkDirectory)
[IO.Directory]::CreateDirectory($root) | Out-Null
Push-Location $root
try {
    & cl /nologo /std:c++20 /EHsc /O2 /MT "/I$source/src" `
        "$PSScriptRoot/tests/RentalIdentityProbe.cpp" "$source/src/NestG/RentalIdentity.cpp" `
        /Fe:RentalIdentityProbe.exe
    if ($LASTEXITCODE -ne 0) { throw 'Rental identity fixture compilation failed.' }
    & (Join-Path $root 'RentalIdentityProbe.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Rental identity fixture failed.' }
} finally { Pop-Location }
