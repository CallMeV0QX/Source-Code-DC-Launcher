param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new fixture directory.' }
$source=(Resolve-Path -LiteralPath $SourceDirectory).Path
$work=[IO.Path]::GetFullPath($WorkDirectory)
[IO.Directory]::CreateDirectory($work) | Out-Null
$macros=[Collections.Generic.List[string]]::new()
$macros.Add('#pragma once')
foreach($prefix in @('PACKAGE','MISC')) { foreach($level in @('TRACE','DEBUG','INFO','WARN','ERROR')) { $macros.Add("#define LOG_${prefix}_${level}(...) ((void)0)") } }
[IO.File]::WriteAllLines((Join-Path $work 'ost_log_macros.h'),$macros)
Push-Location $work
try {
    & cl /nologo /std:c++20 /EHsc /Od /MT /DNOMINMAX "/I$source/src" "/I$work" `
        "$PSScriptRoot/tests/RentalPackageProbe.cpp" "$source/src/NestG/RentalIdentity.cpp" /Fe:RentalPackageProbe.exe
    if($LASTEXITCODE -ne 0) { throw 'Package fixture compilation failed.' }
    & ./RentalPackageProbe.exe
    if($LASTEXITCODE -ne 0) { throw 'Package fixture failed.' }
} finally { Pop-Location }
