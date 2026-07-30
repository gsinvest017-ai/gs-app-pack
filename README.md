# gs-app-pack

Universal Windows desktop app packager for GS projects.

Wraps a Python web-server project into a native pywebview window, packages with PyInstaller, and produces an Inno Setup installer — all driven by one config file.

## What it produces

```
your-project/
├── app.py                  ← pywebview launcher (you write once)
├── pack.config.ps1         ← your settings (copy pack.example.ps1)
├── static/gs-icon.ico      ← auto-generated GS gold-ring icon
├── installer.iss           ← auto-generated (do not edit manually)
└── dist/
    ├── your-app/           ← PyInstaller onedir output
    └── your-app-setup.exe  ← distributable installer
```

## Quick start

```powershell
# 1. Copy template files into your project
Copy-Item C:\path\to\gs-app-pack\pack.example.ps1      pack.config.ps1
Copy-Item C:\path\to\gs-app-pack\templates\app_launcher.py  app.py

# 2. Edit pack.config.ps1  (app name, version, pyinstaller add-data, etc.)
# 3. Edit app.py           (fill in _start_server() for your server type)

# 4. Install prerequisites (once) — into the PROJECT'S venv, not globally
.venv\Scripts\python -m pip install pyinstaller pywebview
winget install JRSoftware.InnoSetup

# 5. Full build + installer
C:\path\to\gs-app-pack\pack.ps1

# 6. Publish a release
C:\path\to\gs-app-pack\pack.ps1 -Tag v0.1.0
```

## Commands

| Command | Description |
|---------|-------------|
| `pack.ps1` | Full pipeline: build + installer |
| `pack.ps1 -Clean` | Clean dist/ build/ first |
| `pack.ps1 -SkipBuild` | Recompile installer only |
| `pack.ps1 -Only build` | PyInstaller step only |
| `pack.ps1 -Only installer` | Inno Setup step only |
| `pack.ps1 -Tag v0.1.0` | Build + installer + GitHub release |
| `pack.ps1 -Only release -Tag v0.1.0` | Release existing installer |

## Build environment

**The build uses the project's own virtualenv**, resolved in this order:

1. `$PythonExe` from `pack.config.ps1`
2. `.venv\Scripts\python.exe`
3. `venv\Scripts\python.exe`
4. `python` on PATH — with a warning

This is not cosmetic. PyInstaller bundles the packages of *the interpreter it runs
under*, and it reports success either way. Building with `pyinstaller` from PATH
when the project's dependencies live in `.venv` produces an executable missing
them. A licensed app shipped this way once: the licence module was installed
editable in the system Python, PyInstaller could not follow that install, the
module was omitted, and the licence check — written to fail open so a packaging
slip never locks out a paying customer — let the unprotected build run silently.

Two config knobs guard against a repeat:

| Setting | What it does |
|---------|--------------|
| `$RequireNonEditable = @("pkg")` | Build fails if `pkg` is missing, or installed `-e`, in the build interpreter. List packages whose absence is *quiet* rather than a crash. |

Every build also **reports editable installs PyInstaller cannot follow**, declared
or not. Not all editable installs are a problem, and the difference is in the
`.pth` file:

| `.pth` contains | Example | PyInstaller |
|-----------------|---------|-------------|
| a bare path | `C:\proj\src` | **follows it** — standard `src/mypkg/` layout, the package is a real directory |
| `import __editable___x_finder` | `package-dir = {mypkg = "src"}` | **cannot follow** — the name→directory mapping lives in a runtime `MetaPathFinder`, and the module graph is static |

The second form is what silently dropped a licence module. `scripts/probe_editables.py`
finds them by parsing the finder's `MAPPING` (without importing it) and the build
lists each one as a warning — harmless if the app never imports them, fatal if it
does, and only the project knows which. Put those in `$RequireNonEditable` to turn
the warning into a failure.
| `$PostBuildCheck = "cmd {dist}"` | Runs against the finished executable; non-zero exit fails the build. `{dist}` becomes the exe path. Bundling problems cannot be seen from outside — pure-Python modules are compiled into the exe's PYZ archive, so inspecting `dist\` proves nothing. Only running it does. |

Example (`autogo`, which must ship with its licence gate intact):

```powershell
$RequireNonEditable = @("keyguard")
$PostBuildCheck = "python C:\Users\User\KEYGUARD\scripts\verify_packaged_licence.py {dist}"
```

## Server modes (in app.py)

**function** — stdlib HTTP server (e.g. gs-gh-summary):
```python
from myapp import config as cfg_mod
import server as srv
def _start_server(host, port):
    cfg = cfg_mod.load()
    srv.serve(host, port, cfg)
```

**uvicorn** — FastAPI/ASGI (e.g. autogo):
```python
import uvicorn
def _start_server(host, port):
    uvicorn.run("web.app:app", host=host, port=port, log_level="warning")
```

## Installer features

- Per-user install (no UAC)
- Desktop shortcut + Start Menu
- Kills running instance before install
- Optional: auto-install `gh` CLI + guide `gh auth login`

## Projects using gs-app-pack

| Project | pack.config.ps1 | Build interpreter | Guards |
|---------|----------------|-------------------|--------|
| autogo | AppExe=autogo, ServerMode=uvicorn | `.venv` | `RequireNonEditable=keyguard`, `PostBuildCheck` |
| gs-suite | AppExe=gs-suite | `.venv` | none needed — see below |
| gs-gh-summary | AppExe=gs-gh-summary, ServerMode=function | **no venv** → system Python | none needed — see below |

Audited 2026-07-30 after autogo shipped an unprotected build twice. What the two
other projects import when a package goes missing:

- **gs-gh-summary** — `webview` logs an error and exits 1, `slack_bolt` prints and
  exits 2, optional `jira_sync` prints "jira sync idle". All loud. `yaml` falls
  back to `None`, which is quieter, but PyYAML is an ordinary non-editable
  dependency and bundles normally.
- **gs-suite** — `webview` falls back to a browser with a log line; the Stripe
  provider returns `False` when `stripe` is absent, i.e. fails *closed*.

Neither has a control that grants something when its module vanishes, so neither
needs `$RequireNonEditable`. Their editable installs (`gs-common`, `gs-suite`) use
plain `.pth` files, which PyInstaller follows.

**gs-gh-summary has no virtualenv**, so it builds with whatever Python is on PATH
and inherits every package installed there. It works, and the build now says so —
but giving it a `.venv` would make its builds reproducible and silence the
editable-install warning it currently inherits from the system interpreter.
