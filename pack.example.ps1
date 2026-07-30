# pack.config.ps1 -- project-specific config for gs-app-pack
# Copy this file to your project root as "pack.config.ps1" and fill in values.
# Usage: C:\path\to\gs-app-pack\pack.ps1   (run from your project root)

# ── App metadata ────────────────────────────────────────────────────────────
$AppName      = "My App"
$AppVersion   = "0.0.1"
$AppId        = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"   # generate a GUID: [guid]::NewGuid()
$AppExe       = "my-app"               # output exe name (no .exe)
$AppPublisher = "My Company"
$AppUrl       = "https://github.com/myorg/my-app"

# ── Server startup ────────────────────────────────────────────────────────
# Mode "function" : calls $ServerModule.$ServerFunc(host, port, cfg)
#   requires $ConfigModule.$ConfigFunc(path?) to return a config object
# Mode "uvicorn"  : calls uvicorn.run("$ServerModule:$ServerApp", host, port)
# Mode "subprocess": spawns $ServerCmd as a background subprocess
$ServerMode   = "function"             # "function" | "uvicorn" | "subprocess"
$ServerModule = "server"              # module name
$ServerFunc   = "serve"               # for "function" mode
$ServerApp    = "app"                 # for "uvicorn" mode (module:app)
$ServerCmd    = ""                    # for "subprocess" mode (full command string)
$ServerHost   = "127.0.0.1"
$ServerPort   = 8790

# Config loader (only for "function" mode; leave blank to skip)
$ConfigModule = "myapp.config"
$ConfigFunc   = "load"

# ── pywebview window ──────────────────────────────────────────────────────
$WinTitle     = "My App"
$WinWidth     = 1400
$WinHeight    = 900
$WinBgColor   = "#07060a"             # prevents white flash before page loads

# DWM title bar colors (Windows 11 only; COLORREF = 0x00BBGGRR)
$DwmCaption   = 0x000A0607            # caption background  (#07060a)
$DwmBorder    = 0x0037AFD4            # border color        (#d4af37 gold)
$DwmText      = 0x0095D1E8            # caption text        (#e8d195 champagne)

# ── Icon ──────────────────────────────────────────────────────────────────
$IconBg       = "#07060a"             # background color
$IconRing     = "#d4af37"             # ring/accent color
$IconSize     = 32

# ── PyInstaller ──────────────────────────────────────────────────────────
# Windows path separator is semicolon: "src;dest"
$PyiAddData   = @(
    "templates;templates",
    "static;static",
    "myapp;myapp",
    "data;data"
    # "config.yaml;."
)
$PyiExtraArgs = @()                   # any extra pyinstaller flags

# ── Build environment ─────────────────────────────────────────────────────────
# Which interpreter builds the app. Left blank, the project's .venv is used, then
# venv, then whatever python is on PATH (with a warning). Set this only when the
# virtualenv lives somewhere unusual.
#
# It matters because PyInstaller bundles the packages of the interpreter it runs
# under: build with the wrong one and the executable is missing the project's
# dependencies, while PyInstaller still reports success.
$PythonExe    = ""

# Packages that must be installed NON-editable in the build interpreter.
# PyInstaller's module graph is static and cannot follow a `.pth`-based editable
# install whose directory is not named after the package (a `src/` layout, say);
# the package is then omitted silently. Anything the app crashes without is
# self-evident, so list the ones whose absence is *quiet* — a licence check that
# fails open, telemetry, a plugin loader.
$RequireNonEditable = @()             # e.g. @("keyguard")

# A command run against the executable straight after the build. Non-zero exit
# fails the build. `{dist}` is replaced with the path to the built .exe.
#
# Worth having because bundling problems are invisible from the outside: pure
# Python modules are compiled into the exe's PYZ archive, so inspecting the dist
# directory proves nothing. Only running it does.
$PostBuildCheck = ""                  # e.g. "python C:\...\verify_x.py {dist}"

# ── Installer (Inno Setup) ────────────────────────────────────────────────
$InstallerRequiresGh = $false         # auto-install GitHub CLI if missing
