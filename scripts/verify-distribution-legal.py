#!/usr/bin/env python3
"""Read-only checks for the licenses and offline documents shipped with Mac Island.

This does not build, install, sign, notarize, or publish an application.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
LEGAL = ROOT / "PingIsland/Resources/Legal"
RESOURCE_NAMES = (
    "MacIsland-Privacy-zh-Hans.md",
    "MacIsland-Privacy-en.md",
    "MacIsland-Help-zh-Hans.md",
    "MacIsland-Help-en.md",
    "MacIsland-ThirdPartyNotices.txt",
    "MacIsland-Legal-Manifest.json",
)
LOCAL_SECTIONS = {
    "Apache License 2.0": ROOT / "LICENSE.md",
    "Original Ping Island NOTICE": ROOT / "NOTICE",
    "Silkscreen Open Font License": ROOT / "PingIsland/Resources/Fonts/Silkscreen-OFL.txt",
}
SPARKLE_SECTION = "Sparkle 2.10.1 and included components"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def section_bytes(notices, title):
    start = f"===== BEGIN {title} =====\n".encode()
    end = f"\n===== END {title} =====".encode()
    require(notices.count(start) == 1 and notices.count(end) == 1,
            f"Missing or duplicate license section: {title}")
    return notices.split(start, 1)[1].split(end, 1)[0]


def validate_sources(sparkle_license):
    require(not any((ROOT / "PingIsland/Resources/Sounds").rglob("*.wav")),
            "The silent product must not redistribute unreviewed legacy audio")
    for name in RESOURCE_NAMES:
        resource = LEGAL / name
        require(resource.is_file() and resource.stat().st_size > 0,
                f"Missing or empty offline resource: {name}")

    manifest = json.loads((LEGAL / "MacIsland-Legal-Manifest.json").read_text())
    require(manifest.get("schemaVersion") == 1, "Unknown legal manifest schema")
    entries = manifest["sections"]
    expected_sections = set(LOCAL_SECTIONS) | {SPARKLE_SECTION}
    require(len(entries) == len(expected_sections)
            and {entry["section"] for entry in entries} == expected_sections,
            "Unexpected license inventory; review and update the verifier")
    notices = (LEGAL / "MacIsland-ThirdPartyNotices.txt").read_bytes()
    for entry in entries:
        title = entry["section"]
        content = section_bytes(notices, title)
        require(hashlib.sha256(content).hexdigest() == entry["sha256"],
                f"License text differs from recorded source: {title}")
        if title in LOCAL_SECTIONS:
            require(content == LOCAL_SECTIONS[title].read_bytes(),
                    f"Bundled license is stale: {title}")

    lock = json.loads((ROOT / "PingIsland.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
    pins = lock["pins"]
    require(len(pins) == 1 and pins[0]["identity"] == "sparkle",
            "Dependency inventory changed; audit all licenses before distribution")
    pinned = pins[0]
    recorded = manifest["sparkle"]
    require(pinned["location"] == recorded["repository"]
            and pinned["state"]["version"] == recorded["version"]
            and pinned["state"]["revision"] == recorded["revision"],
            "Sparkle pin differs from bundled notice provenance")
    if sparkle_license is not None:
        require(sparkle_license.is_file(), "Sparkle artifact license does not exist")
        require(sparkle_license.read_bytes() == section_bytes(notices, SPARKLE_SECTION),
                "Bundled Sparkle notice differs from the supplied artifact license")


def validate_app(app):
    require(app.is_dir() and app.suffix == ".app", "--app must name a built .app directory")
    resources = app / "Contents/Resources"
    require(resources.is_dir(), "Application Resources directory is missing")
    require(not any(resources.rglob("*.wav")),
            "Built app contains legacy audio; discard stale build products and rebuild")
    for name in RESOURCE_NAMES:
        matches = list(resources.rglob(name))
        require(len(matches) == 1 and matches[0].is_file(),
                f"Built app must contain exactly one {name}")
        require(matches[0].read_bytes() == (LEGAL / name).read_bytes(),
                f"Built app contains stale offline resource: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Check an existing built app's actual resources")
    parser.add_argument("--sparkle-license", type=Path,
                        help="Compare with LICENSE from the resolved Sparkle binary artifact")
    args = parser.parse_args()
    try:
        validate_sources(args.sparkle_license)
        if args.app is not None:
            validate_app(args.app)
    except (ValueError, KeyError, TypeError, OSError) as error:
        print(f"Distribution legal check failed: {error}", file=sys.stderr)
        return 1
    print("Distribution legal resources verified" + (" in built app." if args.app else "."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
