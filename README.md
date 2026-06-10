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

# 4. Install prerequisites (once)
pip install pyinstaller pywebview
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

| Project | pack.config.ps1 |
|---------|----------------|
| gs-gh-summary | AppExe=gs-gh-summary, ServerMode=function |
| autogo | AppExe=autogo, ServerMode=uvicorn |
