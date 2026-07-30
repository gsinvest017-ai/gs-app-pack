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

# Abort with a message and a non-zero exit code.
#
# Not Write-Error: under `powershell -Command "& build.ps1"` a terminating error
# record still leaves $LASTEXITCODE at 0, so a caller — a CI step, pack.ps1 run
# from a wrapper — reads the failure as success. For a script whose job is to
# refuse bad builds, exiting 0 on refusal defeats the point.
function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Run a native command and return its combined output as text, without letting
# stderr become a PowerShell error record. pip writes warnings to stderr on a
# perfectly successful call ("Ignoring invalid distribution ~"), which under
# ErrorActionPreference=Stop would abort the script with a NativeCommandError
# instead of reporting what the check actually found.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $Exe @Arguments 2>&1 | Out-String
        return @{ Text = $output; Code = $LASTEXITCODE }
    } finally {
        $ErrorActionPreference = $previous
    }
}

. (Resolve-Path $Config)   # loads $AppExe, $PyiAddData, $PyiExtraArgs, etc.

# Kill running instance (file-lock prevention)
Get-Process -Name $AppExe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

if ($Clean) {
    Remove-Item -Recurse -Force dist, build -ErrorAction SilentlyContinue
}

# ── Which Python builds the app ───────────────────────────────────────────────
# The project's own virtualenv, in preference to whatever is on PATH.
#
# This is not a convenience. PyInstaller bundles the packages of the interpreter
# it runs under, so building with a different interpreter than the project uses
# produces an executable missing the project's dependencies — and PyInstaller
# reports success either way. An earlier build of a licensed app silently shipped
# without its licence module for exactly this reason: `pyinstaller` on PATH
# belonged to the system Python, which had that module installed editable.
#
# Override with $PythonExe in pack.config.ps1 when the venv lives elsewhere.
function Resolve-BuildPython {
    param([string]$Configured)

    if ($Configured) {
        if (-not (Test-Path $Configured)) {
            Fail "`$PythonExe points at '$Configured', which does not exist."
        }
        return (Resolve-Path $Configured).Path
    }
    foreach ($candidate in @(".venv\Scripts\python.exe", "venv\Scripts\python.exe",
                             ".venv/bin/python", "venv/bin/python")) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    $onPath = Get-Command python -ErrorAction SilentlyContinue
    if (-not $onPath) {
        Fail "No project virtualenv found and 'python' is not on PATH."
    }
    Write-Host "WARNING: no project virtualenv found; building with the Python on" -ForegroundColor Yellow
    Write-Host "         PATH ($($onPath.Source)). The executable will contain that" -ForegroundColor Yellow
    Write-Host "         interpreter's packages, which may not be the project's." -ForegroundColor Yellow
    return $onPath.Source
}

$Python = Resolve-BuildPython -Configured $PythonExe
Write-Host "Build interpreter: $Python"

$probe = Invoke-Native $Python @("-c", "import PyInstaller")
if ($probe.Code -ne 0) {
    Fail ("PyInstaller is not installed in the build interpreter:`n  $Python`n`n" +
          "Install it there:`n    & '$Python' -m pip install pyinstaller")
}

# ── Packages that must not be installed editable ──────────────────────────────
# PyInstaller's module graph is static: it cannot follow a `.pth`-based editable
# install whose directory is not named after the package (a `src/` layout, say).
# The package is then omitted with no warning. For anything the app merely uses
# that is an obvious crash; for a licence check written to fail open it is a
# silently unprotected release, which is the case this check exists for.
#
# Declare in pack.config.ps1:  $RequireNonEditable = @("keyguard")
#
# Ahead of that, every editable install of the invisible kind is reported whether
# it was declared or not. Not all editable installs are a problem: a plain `.pth`
# holding a path is one PyInstaller reads and follows, so a standard `src/mypkg/`
# layout bundles correctly. What it cannot follow is a `.pth` that installs a
# MetaPathFinder at runtime, which is what setuptools emits when a package name is
# mapped onto a differently-named directory. Those are listed below because each
# one is silently unbundlable, and only the project knows which of them it needs.
$probe = Invoke-Native $Python @("$PackScripts\probe_editables.py")
$invisible = @{}
if ($probe.Code -eq 0) {
    try {
        $parsed = $probe.Text | ConvertFrom-Json
        foreach ($p in $parsed.finder_based.PSObject.Properties) {
            $invisible[$p.Name] = $p.Value
        }
    } catch {
        Write-Host "NOTE  could not probe editable installs; skipping that check" `
                   -ForegroundColor DarkGray
    }
}
if ($invisible.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNING: these packages are installed editable in a form" -ForegroundColor Yellow
    Write-Host "         PyInstaller CANNOT follow, and will be omitted from the" -ForegroundColor Yellow
    Write-Host "         build with no error:" -ForegroundColor Yellow
    foreach ($name in ($invisible.Keys | Sort-Object)) {
        Write-Host ("           $name  <- " + $invisible[$name]) -ForegroundColor Yellow
    }
    Write-Host "         Harmless if this app does not import them. If it does," -ForegroundColor Yellow
    Write-Host "         reinstall normally (no -e) and add the name to" -ForegroundColor Yellow
    Write-Host "         `$RequireNonEditable so this fails instead of warning." -ForegroundColor Yellow
    Write-Host ""
}

foreach ($pkg in $RequireNonEditable) {
    $show = Invoke-Native $Python @("-m", "pip", "show", $pkg)
    if ($show.Code -ne 0 -or $show.Text -notmatch "(?m)^Name:") {
        Fail ("Required package '$pkg' is not installed in the build " +
              "interpreter:`n  $Python`n`nInstall it there:`n" +
              "    & '$Python' -m pip install <path-to-$pkg>")
    }
    # @(...) so a single match stays a one-element array: indexing a bare string
    # returns its first character, which printed the location as "E".
    $editable = @($show.Text -split "`r?`n" |
                  Where-Object { $_ -match "^Editable project location:" })
    if ($editable.Count -gt 0) {
        # ASCII only in these messages. A build run from a zh-TW console prints
        # through cp950, where an em-dash arrives as "??" and turns the one
        # explanation someone needs into noise.
        Fail ("'$pkg' is installed EDITABLE in the build interpreter, so " +
              "PyInstaller will`nomit it, and the build will look completely " +
              "fine while missing it.`n`n  $Python`n  $($editable[0].Trim())`n`n" +
              "PyInstaller's module graph is static and cannot follow a .pth " +
              "editable`ninstall whose directory is not named after the package. " +
              "--hidden-import,`n--collect-submodules and --paths do NOT help.`n`n" +
              "Reinstall it normally before building:`n" +
              "    & '$Python' -m pip uninstall -y $pkg`n" +
              "    & '$Python' -m pip install <path-to-$pkg>")
    }
    Write-Host "OK    $pkg is installed non-editable"
}

# Generate icon
Write-Host "Generating icon ($IconBg / $IconRing) ..."
& $Python "$PackScripts\make_icon.py" --out "static\gs-icon.ico" --bg $IconBg --ring $IconRing --size $IconSize
if ($LASTEXITCODE -ne 0) { Write-Error "make_icon.py failed" }

# Build --add-data flags — ONLY what the project's $PyiAddData lists.
# Never auto-include config.yaml: a dev machine's config may carry private
# values (LAN IPs, tokens' owner names); projects that want it bundled must
# opt in explicitly via $PyiAddData.
$addDataArgs = @()
foreach ($d in $PyiAddData) { $addDataArgs += "--add-data", $d }

# ── Server module started by name ─────────────────────────────────────────────
# `uvicorn.run("web.app:app", ...)` names its ASGI app in a string, and a string
# is invisible to PyInstaller's static module graph. The build then succeeds, the
# installer builds, the app installs, and it dies on first launch with
# "Error loading ASGI app. Could not import module". Worse, $PyiAddData usually
# bundles that package's templates, so `_internal\web\` exists and looks right
# while containing no Python at all.
#
# Collecting the top-level package is the fix. Added automatically here rather
# than left to each project, because nothing about the failure points at it.
if ($ServerMode -eq "uvicorn" -and $ServerModule) {
    $root = ($ServerModule -split "\.")[0]
    $already = @($PyiExtraArgs) -match "collect-submodules=$root(\s|$)"
    if (-not $already) {
        Write-Host "Adding --collect-submodules=$root (uvicorn starts it by name)"
        $PyiExtraArgs = @($PyiExtraArgs) + "--collect-submodules=$root"
    }
}

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
# `python -m PyInstaller`, not the `pyinstaller` shim: the module form cannot
# resolve to a different interpreter than the one chosen above.
& $Python -m PyInstaller @pyiArgs

if ($LASTEXITCODE -ne 0) { Fail "pyinstaller failed (exit $LASTEXITCODE)" }

$dist = if ($OneFile) { "dist\$AppExe.exe" } else { "dist\$AppExe\" }
Write-Host "Build done -> $dist"

# ── Post-build gate ───────────────────────────────────────────────────────────
# A check the project runs against the artefact it just produced. Bundling
# problems are invisible in the dist directory — pure-Python modules are compiled
# into the executable's PYZ archive, so "is the folder there?" answers nothing.
# Only running the thing does.
#
# Declare in pack.config.ps1:
#   $PostBuildCheck = "python C:\...\verify_packaged_licence.py {dist}"
# {dist} is replaced with the path to the built executable.
if ($PostBuildCheck) {
    $exe = if ($OneFile) { "dist\$AppExe.exe" } else { "dist\$AppExe\$AppExe.exe" }
    $cmd = $PostBuildCheck.Replace("{dist}", (Resolve-Path $exe).Path)
    Write-Host ""
    Write-Host "=== Post-build check ===" -ForegroundColor Cyan
    Write-Host $cmd

    # Via a temp script, not `powershell -Command $cmd`: passing a command as a
    # string re-parses it in the child, so a `|` inside a quoted regex became a
    # pipeline and the check failed on its own arguments. A file has no such
    # layer, and it also lets $PostBuildCheck be several lines.
    $probeScript = Join-Path ([System.IO.Path]::GetTempPath()) `
                             ("gs-app-pack-postbuild-$PID.ps1")
    try {
        [System.IO.File]::WriteAllText($probeScript, $cmd,
                                       (New-Object System.Text.UTF8Encoding($false)))
        & powershell -NoProfile -ExecutionPolicy Bypass -File $probeScript
    } finally {
        Remove-Item $probeScript -ErrorAction SilentlyContinue
    }
    if ($LASTEXITCODE -ne 0) {
        Fail ("Post-build check FAILED (exit $LASTEXITCODE).`n`nThe build exists " +
              "at $exe but did not pass its own gate.`nDO NOT SHIP IT.")
    }
    Write-Host "Post-build check passed." -ForegroundColor Green
}
