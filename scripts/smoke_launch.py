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
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request


def safe(text: str) -> str:
    """Printable on this console, whatever the app happened to emit.

    The app's bytes are decoded with errors="replace", so its output can contain
    U+FFFD — and a zh-TW console is cp950, which cannot encode that. Printing an
    offending line then raised UnicodeEncodeError *from inside the failure
    reporter*, turning a clear "this log line is forbidden" into a traceback.
    """
    encoding = getattr(sys.stdout, "encoding", None) or "ascii"
    return text.encode(encoding, errors="replace").decode(encoding, errors="replace")


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
    # Serving a page proves the server started; it does not prove the app works.
    # A missing OCR engine, a dead GPU provider, an unreadable config — each
    # leaves the HTTP check green and writes its complaint to the log. So the
    # project gets to name what must and must not appear there.
    ap.add_argument("--forbid-log", action="append", default=[], metavar="REGEX",
                    help="fail if the app's output matches this (repeatable)")
    ap.add_argument("--require-log", action="append", default=[], metavar="REGEX",
                    help="fail unless the app's output matches this (repeatable)")
    ap.add_argument("--settle", type=float, default=0.0,
                    help="seconds to keep reading output after the first "
                         "response, for checks on warm-up messages")
    args = ap.parse_args()

    exe = os.path.abspath(args.exe)
    if not os.path.exists(exe):
        print(f"FAIL  no such file: {exe}")
        return 1

    port = args.port or free_port()
    env = dict(os.environ)
    # A licence refusal shows a modal when the app has no console; an
    # unattended smoke run would sit on it until the timeout.
    env.setdefault("KEYGUARD_NO_DIALOG", "1")
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

    # Drain the pipe continuously, in a thread. Reading only at the end deadlocks
    # the child once the OS buffer fills — about 64 KB, which a warming-up app
    # produces in seconds. The child then blocks mid-startup and never reaches
    # the messages being checked for, so --forbid-log passes by starving the app
    # of the chance to complain. A gate that passes because nothing ran is worse
    # than no gate.
    lines: list[str] = []

    def drain() -> None:
        if not proc.stdout:
            return
        for line in proc.stdout:
            lines.append(line)

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

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

    # Warm-up work often finishes after the first request is answered, so give it
    # a moment before reading the log — otherwise the interesting failures are
    # still in flight when the process is killed.
    if served and args.settle > 0 and proc.poll() is None:
        time.sleep(args.settle)

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()

    reader.join(timeout=10)
    output = "".join(lines)

    if served:
        problems = []
        for pattern in args.forbid_log:
            found = [l for l in output.splitlines() if re.search(pattern, l)]
            if found:
                problems.append(f"output matched --forbid-log {pattern!r}:")
                problems += [f"    {safe(l.strip())}" for l in found[:5]]
        for pattern in args.require_log:
            if not re.search(pattern, output):
                problems.append(f"output never matched --require-log {pattern!r}")
        if problems:
            print(f"FAIL  {url} responded, but the app reported problems:")
            for line in problems:
                print(f"      {safe(line)}")
            return 1
        return 0

    print(f"FAIL  nothing served at {url} within {args.timeout:.0f}s")
    print(f"      exit code: {proc.returncode}")
    if output.strip():
        print("      last output:")
        for line in output.strip().splitlines()[-15:]:
            print(f"        {safe(line)}")
    print("\n      A frozen app that builds but will not start is usually a "
          "module\n      named in a string — an ASGI target, a plugin, an entry "
          "point — which\n      PyInstaller cannot see. Add "
          "--collect-submodules=<package>.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
