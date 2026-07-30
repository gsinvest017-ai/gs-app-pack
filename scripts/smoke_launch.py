# -*- coding: utf-8 -*-
"""Start a packaged app and check that it actually serves HTTP.

The licence gate that guards these builds proved a module was bundled. It could
not prove the application *runs* — and v0.1.6 of one project shipped, installed
and passed every existing check while dying on launch:

    ERROR: Error loading ASGI app. Could not import module "web.app"

The ASGI app was named in a string (``uvicorn.run("web.app:app")``), invisible to
PyInstaller's static module graph, so the package was never bundled. A second
launch then found ``pywebview`` missing too. Neither is visible from the outside:
the data files for that package *were* bundled, so ``_internal\\web\\`` existed and
looked correct while containing no Python at all.

The only check that catches this class of problem is starting the thing.

Usage:
    python smoke_launch.py <exe> [--port N] [--timeout S] [--path /] [--env K=V]

Exit codes: 0 served a response, 1 did not.
"""

import argparse
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("--port", type=int, default=0, help="0 picks a free one")
    ap.add_argument("--timeout", type=float, default=90.0)
    ap.add_argument("--path", default="/", help="path to request")
    ap.add_argument("--port-arg", default="--port",
                    help="flag the app takes for its port")
    ap.add_argument("--env", action="append", default=[],
                    help="KEY=VALUE for the child process (repeatable)")
    args = ap.parse_args()

    exe = os.path.abspath(args.exe)
    if not os.path.exists(exe):
        print(f"FAIL  no such file: {exe}")
        return 1

    port = args.port or free_port()
    env = dict(os.environ)
    for pair in args.env:
        key, _, value = pair.partition("=")
        env[key] = value

    # Run from the executable's own directory: a onedir build resolves
    # _internal relative to itself, and a stray cwd hides bundling problems that
    # would bite a real user who launches from the Start menu.
    proc = subprocess.Popen(
        [exe, args.port_arg, str(port)], cwd=os.path.dirname(exe), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace")

    url = f"http://127.0.0.1:{port}{args.path}"
    deadline = time.time() + args.timeout
    served = False
    while time.time() < deadline:
        # A dead process will never serve anything; stop waiting for it. The app
        # may legitimately exit non-zero *after* serving (no display for a
        # desktop window, say), so this is not itself a failure.
        if proc.poll() is not None:
            break
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                print(f"PASS  {url} -> HTTP {response.status}")
                served = True
                break
        except urllib.error.HTTPError as exc:
            # Any HTTP status means something is listening and routing.
            print(f"PASS  {url} -> HTTP {exc.code}")
            served = True
            break
        except Exception:                                     # noqa: BLE001
            time.sleep(1.0)

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()

    output = ""
    if proc.stdout:
        try:
            output = proc.stdout.read() or ""
        except Exception:                                     # noqa: BLE001
            pass

    if served:
        return 0

    print(f"FAIL  nothing served at {url} within {args.timeout:.0f}s")
    print(f"      exit code: {proc.returncode}")
    if output.strip():
        print("      last output:")
        for line in output.strip().splitlines()[-15:]:
            print(f"        {line}")
    print("\n      A frozen app that builds but will not start is usually a "
          "module\n      named in a string — an ASGI target, a plugin, an entry "
          "point — which\n      PyInstaller cannot see. Add "
          "--collect-submodules=<package>.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
