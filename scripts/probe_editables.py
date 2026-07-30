# -*- coding: utf-8 -*-
"""Report editable installs that PyInstaller cannot follow.

Not every editable install is a problem, and banning all of them would be wrong.
The distinction is what the ``.pth`` file does:

**Plain path** — ``C:\\path\\to\\project\\src`` on a line by itself. Standard
``src/`` layout, where ``src/mypkg/`` is a real directory. PyInstaller reads
``.pth`` files, adds the path, and finds the package on disk. Fine.

**Custom finder** — ``import __editable___x_finder; ...install()``. Produced when
the project maps a package name onto a differently-named directory
(``package-dir = {mypkg = "src"}``), which cannot be expressed as a path
addition. The mapping exists only inside a ``MetaPathFinder`` installed at
runtime, and PyInstaller's module graph is static, so the package is invisible to
it — omitted from the build with no warning.

That second shape is the one that shipped an unprotected release: a licence
module installed this way vanished from the executable, and the check was written
to fail open so nothing complained.

Prints JSON: ``{"finder_based": {pkg: source_dir}, "plain": [paths]}``.
"""

import ast
import json
import re
import site
import sys
import sysconfig
from pathlib import Path


def site_dirs() -> list[Path]:
    """Every directory that could hold a .pth for this interpreter."""
    seen: list[Path] = []
    candidates = list(site.getsitepackages())
    try:
        candidates.append(site.getusersitepackages())
    except Exception:                                    # noqa: BLE001
        pass
    for key in ("purelib", "platlib"):
        path = sysconfig.get_paths().get(key)
        if path:
            candidates.append(path)
    for raw in candidates:
        path = Path(raw)
        if path.is_dir() and path not in seen:
            seen.append(path)
    return seen


def finder_mapping(finder: Path) -> dict:
    """The MAPPING dict out of an __editable___*_finder.py, without importing it.

    Parsed rather than imported: importing installs the finder into this process,
    and a build tool has no business mutating its own import system to answer a
    question about someone else's.
    """
    try:
        tree = ast.parse(finder.read_text(encoding="utf-8"))
    except (OSError, SyntaxError):
        return {}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        names = [t.id for t in targets if isinstance(t, ast.Name)]
        if "MAPPING" not in names or node.value is None:
            continue
        try:
            value = ast.literal_eval(node.value)
        except ValueError:
            return {}
        if isinstance(value, dict):
            return {str(k): str(v) for k, v in value.items()}
    return {}


def main() -> int:
    finder_based: dict[str, str] = {}
    plain: list[str] = []

    for directory in site_dirs():
        for pth in sorted(directory.glob("*.pth")):
            try:
                text = pth.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if not re.search(r"^\s*import\s+__editable__", text, re.M):
                # A plain .pth may still belong to an editable install; it is
                # simply one PyInstaller can follow, so it is reported separately
                # rather than as a problem.
                if "__editable__" in pth.name:
                    plain.extend(line.strip() for line in text.splitlines()
                                 if line.strip())
                continue
            match = re.search(r"import\s+(__editable___\w+_finder)", text)
            if not match:
                continue
            finder = directory / f"{match.group(1)}.py"
            mapping = finder_mapping(finder)
            if mapping:
                finder_based.update(mapping)
            else:
                # The finder exists but its mapping could not be read. Still a
                # finder-based install, so still invisible; name it after the
                # .pth so the operator has something to act on.
                finder_based[pth.stem.replace("__editable__.", "")] = str(finder)

    json.dump({"finder_based": finder_based, "plain": plain}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
