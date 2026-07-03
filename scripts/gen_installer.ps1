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
var
  CachedGhPath: String;

{ Resolve gh.exe by absolute path first: right after winget installs gh,
  THIS installer process still has the pre-install PATH, so bare "gh"
  would not be found. PATH lookup is only the last resort. }
function GhExe(): String;
var
  ResultCode: Integer;
  PfPath, UserPath: String;
begin
  if CachedGhPath <> '' then begin
    Result := CachedGhPath;
    Exit;
  end;
  PfPath   := ExpandConstant('{autopf}\GitHub CLI\gh.exe');
  UserPath := ExpandConstant('{localappdata}\Programs\GitHub CLI\gh.exe');
  if FileExists(PfPath) then
    CachedGhPath := PfPath
  else if FileExists(UserPath) then
    CachedGhPath := UserPath
  else if Exec('cmd.exe', '/c where gh >nul 2>&1', '', SW_HIDE,
               ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
    CachedGhPath := 'gh';
  Result := CachedGhPath;
end;

function IsGhInstalled(): Boolean;
begin
  Result := (GhExe() <> '');
end;

function IsGhAuthenticated(): Boolean;
var
  ResultCode: Integer;
  Gh: String;
begin
  Result := False;
  Gh := GhExe();
  if Gh = '' then Exit;
  if Exec(Gh, 'auth status', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
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
  CachedGhPath := '';  { re-resolve now that winget may have installed it }
  if (ResultCode = 0) and IsGhInstalled() then
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
  Gh: String;
begin
  if CurStep <> ssPostInstall then Exit;
  { Silent runs (auto-update) must never pop dialogs; gh is normally
    already authenticated on an upgrade anyway. }
  if WizardSilent() then Exit;
  if IsGhAuthenticated() then Exit;
  Gh := GhExe();
  if Gh = '' then Exit;  { gh missing entirely; manual message already shown }
  if MsgBox(
    'GitHub Authorization -- what will happen' + #13#10 + #13#10 +
    '1. Click Yes: a PowerShell window opens and shows a one-time code (XXXX-XXXX).' + #13#10 +
    '2. Copy that code, then press Enter in the window -- your browser opens GitHub.' + #13#10 +
    '3. Sign in, paste the code, and click Authorize. Then close the window.' + #13#10 + #13#10 +
    'Start GitHub authorization now?',
    mbConfirmation, MB_YESNO) = IDYES then
    ShellExec('open', 'powershell.exe',
      '-NoExit -Command "& ''' + Gh + ''' auth login --web --hostname github.com --git-protocol https"',
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
