#!/usr/bin/env python3
"""Export only numeric test counts. Never upload xcresult diagnostics or attachments."""

import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("results", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
summaries = []
for result in sorted(args.results.glob("*.xcresult")):
    if result.is_symlink() or not result.is_dir():
        continue
    entry = {"summaryAvailable": False}
    try:
        command = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
            capture_output=True, timeout=30, check=True,
        )
        data = json.loads(command.stdout)
        for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
            value = data.get(key)
            if type(value) is int and 0 <= value <= 1_000_000:
                entry[key] = value
        entry["summaryAvailable"] = "totalTestCount" in entry
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    summaries.append(entry)
(args.output / "test-summary.json").write_text(
    json.dumps({"schemaVersion": 1, "results": summaries}, indent=2) + "\n", encoding="utf-8"
)
print(f"Exported {len(summaries)} content-free test summaries")
