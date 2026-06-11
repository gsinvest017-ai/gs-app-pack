# gs-app-pack: Create GitHub release and upload installer.
# Called by pack.ps1; can also be run standalone.
#
# Usage:
#   C:\...\gs-app-pack\scripts\release.ps1 -Tag v0.0.1 [-Config pack.config.ps1] [-Notes "..."]

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [string]$Config = "pack.config.ps1",
    [string]$Notes  = ""
)

$ErrorActionPreference = "Stop"
. (Resolve-Path $Config)

$setupExe   = "dist\$AppExe-setup.exe"
$setupMsi   = "dist\$AppExe-setup.msi"
$assetLabel = "$AppExe-setup-$AppVersion.exe"

if (-not (Test-Path $setupExe)) {
    Write-Error "Installer not found: $setupExe  (run pack.ps1 first)"
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "'gh' CLI not found on PATH."
}

# Create and push git tag if it doesn't exist.
$existing = git tag -l $Tag 2>$null
if (-not $existing) {
    git tag -a $Tag -m "$AppName $Tag"
    git push origin $Tag
    Write-Host "Pushed tag $Tag"
}

# Build release notes if not provided.
if (-not $Notes) {
    $Notes = @"
## $AppName $Tag

### Install
Download and run ``$assetLabel``.

The installer will:
- Copy app files to ``%LOCALAPPDATA%\$AppName\``
- Create desktop shortcut and Start Menu entry
- No administrator rights required
"@
    if ($InstallerRequiresGh) {
        $Notes += "`n- Auto-install GitHub CLI (gh) if missing`n- Guide through ``gh auth login``"
    }
}

# Build asset list — always include the .exe; add .msi if it was built.
$assets = @("$setupExe#$assetLabel")
if (Test-Path $setupMsi) {
    $assets += "$setupMsi#$AppExe-setup-$AppVersion.msi"
    Write-Host "Including MSI: $setupMsi"
}

gh release create $Tag @assets `
    --title "$AppName $Tag" `
    --notes $Notes

Write-Host ""
Write-Host "Release published: https://github.com/$AppUrl/releases/tag/$Tag" -ForegroundColor Green
