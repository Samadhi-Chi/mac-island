#!/usr/bin/env python3
"""Lightweight source validation; does not read user configuration or install tools."""

import ast
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(args):
    subprocess.run(args, cwd=ROOT, check=True)


paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
).decode().split("\0")
counts = {"json": 0, "python": 0, "shell": 0, "plist": 0}
for name in paths:
    path = ROOT / name
    if not name or not path.is_file():
        continue
    if path.suffix == ".json":
        json.loads(path.read_text(encoding="utf-8"))
        counts["json"] += 1
    elif path.suffix == ".py":
        ast.parse(path.read_text(encoding="utf-8"), filename=name)
        counts["python"] += 1
    elif path.suffix == ".sh":
        run(["bash", "-n", name])
        counts["shell"] += 1
    elif path.suffix in {".plist", ".strings", ".entitlements"}:
        run(["plutil", "-lint", name])
        counts["plist"] += 1

run(["git", "diff", "--check"])
formatted = [line.strip() for line in (ROOT / "Config/SwiftFormatFiles.txt").read_text().splitlines()
             if line.strip() and not line.startswith("#")]
swift_paths = {name for name in paths if name.endswith(".swift") and (ROOT / name).is_file()}
if set(formatted) != swift_paths or len(formatted) != len(set(formatted)):
    raise SystemExit("Swift format list must include every repository Swift file exactly once")
run(["xcrun", "swift-format", "lint", "--strict", "--configuration", ".swift-format", *formatted])
run([sys.executable, "scripts/check-site.py"])
print(f"Source checks passed: {counts}; Swift format scope: {len(formatted)} files")
