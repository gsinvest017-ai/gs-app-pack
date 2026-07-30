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

# Pushing the tag can trigger a CI workflow that builds its own artefacts and
# creates the release before this upload — a large installer takes minutes to
# transfer, so the race is not close. `gh release create` then fails with
# "Release.tag_name already exists" and, unchecked, the script would go on to
# announce success while the published assets came from somewhere else entirely.
# That shipped once: a release marked Latest carrying a 2.4 MB installer with no
# licence gate, in place of the 585 MB one that had just passed every check.
gh release create $Tag @assets `
    --title "$AppName $Tag" `
    --notes $Notes

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "gh release create FAILED (exit $LASTEXITCODE)." -ForegroundColor Red
    Write-Host ""
    Write-Host "If it says the tag already exists, something else published this" -ForegroundColor Red
    Write-Host "release first -- usually a workflow triggered by the tag push." -ForegroundColor Red
    Write-Host "Check what is actually attached before trusting it:" -ForegroundColor Red
    Write-Host "    gh release view $Tag --json assets" -ForegroundColor Red
    Write-Host ""
    Write-Host "To replace those assets with the ones just built:" -ForegroundColor Red
    foreach ($a in $assets) {
        $parts = $a -split "#"
        Write-Host "    gh release upload $Tag '$($parts[0])#$($parts[1])' --clobber" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
# $AppUrl is already absolute (pack.example.ps1 shows it as https://github.com/owner/repo),
# so prefixing it again produced https://github.com/https://github.com/... — an
# unclickable link printed as the final word on a successful release.
Write-Host "Release published: $($AppUrl.TrimEnd('/'))/releases/tag/$Tag" -ForegroundColor Green
