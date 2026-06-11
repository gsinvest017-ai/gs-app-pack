# gs-app-pack: Generate installer.iss from template + config, then compile.
# Called by pack.ps1; can also be run standalone from the project root.

[CmdletBinding()]
param(
    [string]$Config = "pack.config.ps1"
)

$PackRoot    = Split-Path -Parent $PSScriptRoot
$ProjectRoot = (Get-Location).Path
$ErrorActionPreference = "Stop"

. (Resolve-Path $Config)

# ── Generate installer.iss ────────────────────────────────────────────────
$template = Get-Content "$PackRoot\templates\installer.iss.template" -Raw

# gh CLI block (conditionally included)
$ghBlock = ""
if ($InstallerRequiresGh) {
    $ghBlock = @'
function IsGhInstalled(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('cmd.exe', '/c where gh >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := (ResultCode = 0);
end;

function IsGhAuthenticated(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('cmd.exe', '/c gh auth status >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := (ResultCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  NeedsRestart := False;
  if IsGhInstalled() then Exit;
  WizardForm.PreparingLabel.Caption := 'Installing GitHub CLI (gh) via winget, please wait...';
  WizardForm.PreparingLabel.Update;
  Exec('winget.exe',
    'install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ResultCode = 0 then
    WizardForm.PreparingLabel.Caption := 'GitHub CLI installed.'
  else begin
    WizardForm.PreparingLabel.Caption := 'Note: auto-install of gh failed.';
    MsgBox('Could not install GitHub CLI.' + #13#10 +
           'Install from https://cli.github.com/ then run: gh auth login',
           mbInformation, MB_OK);
  end;
  WizardForm.PreparingLabel.Update;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  if IsGhAuthenticated() then Exit;
  if MsgBox(
    'GitHub Authentication -- 3 Steps' + #13#10 + #13#10 +
    '1. Click OK and your browser will open the GitHub login page' + #13#10 +
    '2. Sign in to GitHub (if not already) and click Authorize' + #13#10 +
    '3. Return here once authorization is complete' + #13#10 + #13#10 +
    'Open browser to authorize now?',
    mbConfirmation, MB_YESNO) = IDYES then
    ShellExec('open', 'powershell.exe',
      '-NoExit -Command "gh auth login --web"',
      '', SW_SHOW, ewNoWait, ResultCode);
end;
'@
}

$iss = $template `
    -replace '__APP_NAME__',      $AppName `
    -replace '__APP_VERSION__',   $AppVersion `
    -replace '__APP_ID__',        $AppId `
    -replace '__APP_EXE__',       $AppExe `
    -replace '__APP_PUBLISHER__', $AppPublisher `
    -replace '__APP_URL__',       $AppUrl `
    -replace '__GH_BLOCK__',      $ghBlock

$iss | Set-Content -Path "installer.iss" -Encoding UTF8NoBOM
Write-Host "Generated installer.iss"

# ── Compile with ISCC ─────────────────────────────────────────────────────
$iscc = $null
foreach ($c in @(
    (Get-Command iscc -ErrorAction SilentlyContinue)?.Source,
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)) {
    if ($c -and (Test-Path $c)) { $iscc = $c; break }
}

if (-not $iscc) {
    Write-Error "ISCC.exe not found. Install Inno Setup: winget install JRSoftware.InnoSetup"
}

Write-Host "Compiling with: $iscc"
& $iscc installer.iss
if ($LASTEXITCODE -ne 0) { Write-Error "ISCC failed (exit $LASTEXITCODE)" }
Write-Host "Installer ready: dist\$AppExe-setup.exe"
