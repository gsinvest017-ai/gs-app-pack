# gs-app-pack: PyInstaller build step.
# Called by pack.ps1; can also be run standalone from the project root.
#
# Usage:
#   C:\...\gs-app-pack\scripts\build.ps1 [-Config pack.config.ps1] [-Clean] [-OneFile]

[CmdletBinding()]
param(
    [string]$Config  = "pack.config.ps1",
    [switch]$Clean,
    [switch]$OneFile
)

$PackScripts = $PSScriptRoot
$ProjectRoot = (Get-Location).Path
$ErrorActionPreference = "Stop"

. (Resolve-Path $Config)   # loads $AppExe, $PyiAddData, $PyiExtraArgs, etc.

# Kill running instance (file-lock prevention)
Get-Process -Name $AppExe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

if ($Clean) {
    Remove-Item -Recurse -Force dist, build -ErrorAction SilentlyContinue
}

foreach ($cmd in @("pyinstaller", "python")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "'$cmd' not found on PATH."
    }
}

# Generate icon
Write-Host "Generating icon ($IconBg / $IconRing) ..."
python "$PackScripts\make_icon.py" --out "static\gs-icon.ico" --bg $IconBg --ring $IconRing --size $IconSize
if ($LASTEXITCODE -ne 0) { Write-Error "make_icon.py failed" }

# Build --add-data flags
$addDataArgs = @()
foreach ($d in $PyiAddData) { $addDataArgs += "--add-data", $d }
if (Test-Path "config.yaml") { $addDataArgs += "--add-data", "config.yaml;." }

$mode = if ($OneFile) { "--onefile" } else { "--onedir" }

$pyiArgs = @(
    "app.py", $mode, "--windowed",
    "--name", $AppExe,
    "--icon", "static\gs-icon.ico",
    "--noconfirm"
) + $addDataArgs + $PyiExtraArgs

Write-Host ""
Write-Host "pyinstaller $($pyiArgs -join ' ')"
Write-Host ""
& pyinstaller @pyiArgs

if ($LASTEXITCODE -ne 0) { Write-Error "pyinstaller failed (exit $LASTEXITCODE)" }

$dist = if ($OneFile) { "dist\$AppExe.exe" } else { "dist\$AppExe\" }
Write-Host "Build done -> $dist"
