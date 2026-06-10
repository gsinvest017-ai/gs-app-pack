# gs-app-pack -- Universal Windows desktop app packager.
# Run from your project root; this script lives in the gs-app-pack repo.
#
# Prerequisites (project side):
#   - app.py         (pywebview launcher; see templates/app_launcher.py)
#   - pack.config.ps1 (copy pack.example.ps1, fill in values)
#   - pip install pyinstaller pywebview
#   - winget install JRSoftware.InnoSetup   (for installer step)
#
# Usage:
#   C:\path\to\gs-app-pack\pack.ps1                      # full pipeline
#   C:\path\to\gs-app-pack\pack.ps1 -Only build          # PyInstaller only
#   C:\path\to\gs-app-pack\pack.ps1 -Only installer      # Inno Setup only
#   C:\path\to\gs-app-pack\pack.ps1 -Only release -Tag v1.0.0
#   C:\path\to\gs-app-pack\pack.ps1 -Clean               # clean build first
#   C:\path\to\gs-app-pack\pack.ps1 -SkipBuild           # skip PyInstaller

[CmdletBinding()]
param(
    [string]$Config    = "pack.config.ps1",
    [string]$Only      = "",            # "build" | "installer" | "release"
    [string]$Tag       = "",            # required when -Only release
    [string]$Notes     = "",            # optional release notes
    [switch]$Clean,
    [switch]$SkipBuild,
    [switch]$OneFile
)

$PackRoot    = $PSScriptRoot
$ProjectRoot = (Get-Location).Path
$ErrorActionPreference = "Stop"

if (-not (Test-Path $Config)) {
    Write-Error @"
pack.config.ps1 not found in: $ProjectRoot

1. Copy pack.example.ps1 from gs-app-pack:
   Copy-Item "$PackRoot\pack.example.ps1" pack.config.ps1
2. Edit pack.config.ps1 with your app settings.
"@
}

# ── Step 1: Build (PyInstaller) ───────────────────────────────────────────
if ($Only -eq "" -or $Only -eq "build") {
    if (-not $SkipBuild) {
        Write-Host "=== [1/3] PyInstaller build ===" -ForegroundColor Cyan
        $buildParams = @{ Config = $Config }
        if ($Clean)   { $buildParams["Clean"]   = $true }
        if ($OneFile) { $buildParams["OneFile"] = $true }
        & "$PackRoot\scripts\build.ps1" @buildParams
    } else {
        Write-Host "=== [1/3] Skipping build (SkipBuild) ===" -ForegroundColor DarkGray
    }
}

# ── Step 2: Installer (Inno Setup) ───────────────────────────────────────
if ($Only -eq "" -or $Only -eq "installer") {
    Write-Host "=== [2/3] Generating installer ===" -ForegroundColor Cyan
    & "$PackRoot\scripts\gen_installer.ps1" -Config $Config
}

# ── Step 3: GitHub Release ───────────────────────────────────────────────
if ($Only -eq "release") {
    if (-not $Tag) { Write-Error "-Tag is required when -Only release" }
    Write-Host "=== [3/3] Creating GitHub release $Tag ===" -ForegroundColor Cyan
    & "$PackRoot\scripts\release.ps1" -Tag $Tag -Config $Config -Notes $Notes
} elseif ($Tag) {
    Write-Host "=== [3/3] Creating GitHub release $Tag ===" -ForegroundColor Cyan
    & "$PackRoot\scripts\release.ps1" -Tag $Tag -Config $Config -Notes $Notes
} else {
    Write-Host "=== [3/3] Release skipped (pass -Tag vX.X.X to publish) ===" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
