# gs-app-pack: Generate MSI installer using WiX Toolset v4.
#
# Prerequisites:
#   dotnet tool install --global wix
#
# Usage (standalone from project root):
#   C:\...\gs-app-pack\scripts\gen_msi.ps1 [-Config pack.config.ps1]
#
# Called automatically by pack.ps1 when -Msi is passed or -Only msi.

[CmdletBinding()]
param(
    [string]$Config = "pack.config.ps1"
)

$PackRoot    = Split-Path -Parent $PSScriptRoot
$ProjectRoot = (Get-Location).Path
$ErrorActionPreference = "Stop"

. (Resolve-Path $Config)

$SourceDir = Join-Path $ProjectRoot "dist" $AppExe
if (-not (Test-Path $SourceDir)) {
    Write-Error @"
PyInstaller output not found: $SourceDir
Run the build step first:
    C:\...\gs-app-pack\pack.ps1 -Only build
"@
}

# ── Locate WiX v4 ─────────────────────────────────────────────────────────
$wix = (Get-Command wix -ErrorAction SilentlyContinue)?.Source
if (-not $wix) {
    Write-Error @"
WiX v4 not found on PATH.

Install once:
    dotnet tool install --global wix

Then verify:
    wix --version
"@
}
Write-Host "WiX: $wix  ($(& $wix --version 2>&1 | Select-Object -First 1))" -ForegroundColor DarkGray

# ── Locate icon (optional) ────────────────────────────────────────────────
$iconFile    = $null
$iconAttr    = ""
$iconElement = "    <!-- icon: none found; run the app once to generate static\gs-icon.ico -->"
foreach ($candidate in @(
    (Join-Path $SourceDir "static\gs-icon.ico"),
    (Join-Path $ProjectRoot "static\gs-icon.ico")
)) {
    if (Test-Path $candidate) {
        $iconFile    = $candidate
        $iconAttr    = ' Icon="AppIcon"'
        $iconElement = "    <Icon Id=`"AppIcon`" SourceFile=`"$iconFile`" />"
        Write-Host "Icon: $iconFile" -ForegroundColor DarkGray
        break
    }
}

# ── Generate product.wxs ──────────────────────────────────────────────────
$template = [System.IO.File]::ReadAllText("$PackRoot\templates\product.wxs.template")

$wxs = $template `
    -replace '__APP_NAME__',         $AppName `
    -replace '__APP_VERSION__',      $AppVersion `
    -replace '__APP_PUBLISHER__',    $AppPublisher `
    -replace '__APP_UPGRADE_CODE__', $AppId `
    -replace '__APP_EXE__',          $AppExe `
    -replace '__SOURCE_DIR__',       $SourceDir `
    -replace '__ICON_ATTR__',        $iconAttr `
    -replace '__ICON_ELEMENT__',     $iconElement

$wxsPath = Join-Path $ProjectRoot "product.wxs"
[System.IO.File]::WriteAllText($wxsPath, $wxs, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated product.wxs"

# ── Compile ───────────────────────────────────────────────────────────────
$outDir = Join-Path $ProjectRoot "dist"
$outMsi = Join-Path $outDir "$AppExe-setup.msi"
New-Item -ItemType Directory -Force $outDir | Out-Null

Write-Host "=== Compiling MSI ===" -ForegroundColor Cyan
& $wix build $wxsPath -arch x64 -out $outMsi

if ($LASTEXITCODE -ne 0) {
    Write-Error "WiX build failed (exit $LASTEXITCODE)"
}

$sizeMB = [Math]::Round((Get-Item $outMsi).Length / 1MB, 1)
Write-Host ""
Write-Host "MSI ready: $outMsi  ($sizeMB MB)" -ForegroundColor Green
