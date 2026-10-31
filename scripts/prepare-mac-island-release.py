#!/usr/bin/env python3
"""Prepare a Developer ID distribution; preflight only unless --execute is given.

Never publishes, installs, modifies client configuration, removes quarantine,
creates certificates, exports keys, or modifies another repository.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
CONFIG_FIELDS = {
    "bundle_identifier", "team_id", "signing_identity", "notary_keychain_profile",
    "version", "build_number", "previous_version", "previous_build_number",
    "website_url", "support_url", "privacy_url",
}
MACHO_MAGICS = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe",
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
)}
BUNDLE_SUFFIXES = {".app", ".framework", ".xpc", ".appex"}
ARCHITECTURES = {"arm64", "x86_64"}


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def version_tuple(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value),
            "Version must contain one to three numeric components")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def validate_public_url(value, field, optional=False):
    if optional and value == "":
        return
    require(isinstance(value, str) and value == value.strip() and not re.search(r"\s", value),
            f"{field} must be a public HTTPS URL")
    try:
        parsed = urllib.parse.urlsplit(value)
        hostname = (parsed.hostname or "").lower()
        port = parsed.port
    except ValueError as error:
        raise ReleaseError(f"Invalid {field}") from error
    require(parsed.scheme == "https" and hostname and "." in hostname
            and parsed.username is None and parsed.password is None
            and port in (None, 443) and not parsed.fragment,
            f"{field} must use HTTPS without credentials, fragments, or custom ports")
    require(not any(hostname == suffix or hostname.endswith("." + suffix)
                    for suffix in ("example.com", "example.org", "example.net", "invalid", "test", "localhost", "local")),
            f"{field} cannot use a placeholder or local host")
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        pass
    else:
        raise ReleaseError(f"{field} must use a public domain, not an IP address")


def validate_config(config):
    require(isinstance(config, dict) and set(config) == CONFIG_FIELDS,
            "Configuration fields differ from Distribution.example.json; do not add credentials")
    for key in CONFIG_FIELDS - {"build_number", "previous_build_number"}:
        require(isinstance(config[key], str), f"{key} must be a string")
    bundle_identifier = config["bundle_identifier"]
    require(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}", bundle_identifier)
            and not bundle_identifier.lower().startswith(("com.example.", "org.example."))
            and bundle_identifier.lower() != "com.wudanwu.pingisland",
            "Configure this product's stable bundle identifier, not a placeholder or upstream identity")
    require(re.fullmatch(r"[A-Z0-9]{10}", config["team_id"]), "Configure the enrolled developer Team ID")
    require(config["signing_identity"].startswith("Developer ID Application: ")
            and config["signing_identity"].endswith("(" + config["team_id"] + ")")
            and "\n" not in config["signing_identity"],
            "Use the exact Developer ID Application certificate name for the configured team")
    require(re.fullmatch(r"[A-Za-z0-9_. -]{1,100}", config["notary_keychain_profile"])
            and config["notary_keychain_profile"].strip() == config["notary_keychain_profile"],
            "Configure a notarytool Keychain profile name; never put passwords or keys here")
    current_version = version_tuple(config["version"])
    previous_version = version_tuple(config["previous_version"])
    require(current_version >= previous_version, "Version cannot move backwards")
    require(type(config["build_number"]) is int and type(config["previous_build_number"]) is int
            and 0 < config["previous_build_number"] < config["build_number"] <= 999999999,
            "Build number must be a positive integer greater than the last distributed build")
    for field in ("support_url", "privacy_url", "website_url"):
        validate_public_url(config[field], field, optional=field == "website_url")


def validate_previous_manifest(config, path):
    if path is None:
        # This is a deliberate operator declaration, not a fabricated online check.
        return
    previous = json.loads(path.read_text())
    require(previous.get("schema_version") == 1 and previous.get("status") == "verified_candidate",
            "Previous manifest is not a verified candidate receipt")
    require(previous.get("bundle_identifier") == config["bundle_identifier"],
            "Previous manifest belongs to another product")
    require(previous.get("version") == config["previous_version"]
            and previous.get("build_number") == config["previous_build_number"],
            "Configured previous release differs from the provided manifest")


def command(args, *, cwd=ROOT, timeout=120, log=None):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, capture_output=True,
                            timeout=timeout, check=False)
    if log is not None:
        log.write_bytes(result.stdout + result.stderr)
    require(result.returncode == 0,
            f"{Path(str(args[0])).name} failed; inspect the local stage log when available")
    return result.stdout.decode("utf-8", errors="replace"), result.stderr.decode("utf-8", errors="replace")


def git_state():
    status, _ = command(["/usr/bin/git", "status", "--porcelain", "--untracked-files=all"])
    require(not status.strip(), "Commit the reviewed release changes first; source checkout must be clean")
    commit, _ = command(["/usr/bin/git", "rev-parse", "HEAD"])
    tree, _ = command(["/usr/bin/git", "rev-parse", "HEAD^{tree}"])
    return commit.strip(), tree.strip()


def preflight(config, previous_manifest):
    validate_config(config)
    validate_previous_manifest(config, previous_manifest)
    require(sys.platform == "darwin", "Developer ID preparation requires macOS and Xcode")
    for tool in ("/usr/bin/xcodebuild", "/usr/bin/xcrun", "/usr/bin/codesign", "/usr/bin/security",
                 "/usr/bin/ditto", "/usr/bin/hdiutil", "/usr/sbin/spctl"):
        require(Path(tool).is_file(), f"Required macOS tool is missing: {Path(tool).name}")
    commit, tree = git_state()
    identities, _ = command(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])
    require('"' + config["signing_identity"] + '"' in identities,
            "The configured Developer ID Application certificate/private-key identity is not available")
    command([sys.executable, ROOT / "scripts/verify-distribution-legal.py"])
    policy = (ROOT / "PingIsland/Core/MacIslandProductPolicy.swift").read_text()
    for name, value in (("monitorOnly", "true"), ("analyticsEnabled", "false"), ("updatesEnabled", "false")):
        require(re.search(r"static let " + name + r"\s*=\s*" + value + r"\b", policy),
                f"Product policy {name} changed; review the direct-distribution contract")
    return commit, tree


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        validate_public_url(new_url, "redirect URL")
        return super().redirect_request(request, fp, code, message, headers, new_url)


def check_public_pages(config):
    opener = urllib.request.build_opener(HTTPSRedirects())
    for field in ("support_url", "privacy_url", "website_url"):
        if not config[field]:
            continue
        request = urllib.request.Request(config[field], headers={"User-Agent": "Mac-Island-Release-Preflight"})
        try:
            with opener.open(request, timeout=20) as response:
                validate_public_url(response.url, field)
                require(response.status == 200 and response.read(1), f"{field} is empty or unavailable")
        except (urllib.error.URLError, TimeoutError) as error:
            raise ReleaseError(f"{field} must be publicly accessible before packaging") from error


def write_metadata(app, config, commit, tree):
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    require(info.get("CFBundleIdentifier") == config["bundle_identifier"]
            and info.get("CFBundleShortVersionString") == config["version"]
            and info.get("CFBundleVersion") == str(config["build_number"]),
            "Built app identity/version differs from the requested release")
    require(info.get("LSUIElement") is True, "Built product is not the expected menu-bar application")
    for key in ("SUFeedURL", "SUPublicEDKey"):
        require(not info.get(key), "This manual-update product must not carry an active Sparkle configuration")
    info.update({"MacIslandSupportURL": config["support_url"],
                 "MacIslandPrivacyPolicyURL": config["privacy_url"],
                 "MacIslandSourceCommit": commit, "MacIslandSourceTree": tree,
                 "MacIslandDistributionChannel": "developer-id-manual"})
    if config["website_url"]:
        info["MacIslandWebsiteURL"] = config["website_url"]
    else:
        info.pop("MacIslandWebsiteURL", None)
    # This edit precedes every final nested/outer signature and seal verification.
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))


def signing_targets(app):
    binaries, bundles = [], []
    for path in app.rglob("*"):
        if path.is_symlink():
            require(path.resolve().is_relative_to(app.resolve()), "App contains a symlink escaping its bundle")
            continue
        if path.is_dir() and path.suffix in BUNDLE_SUFFIXES:
            bundles.append(path)
        elif path.is_file():
            with path.open("rb") as file:
                if file.read(4) in MACHO_MAGICS:
                    binaries.append(path)
    require(app / "Contents/MacOS/Mac Island" in binaries
            and app / "Contents/MacOS/PingIslandBridge" in binaries,
            "Expected app/Bridge executable is missing")
    # Do not use --deep when signing. Sign individual code then enclosing bundles.
    return sorted(binaries, key=lambda item: len(item.parts), reverse=True), \
        sorted(bundles, key=lambda item: len(item.parts), reverse=True) + [app]


def parse_entitlements(output):
    if not output.strip():
        return {}
    begin = output.find("<?xml")
    end = output.find("</plist>")
    require(begin >= 0 and end >= begin, "Cannot inspect code entitlements")
    value = plistlib.loads(output[begin:end + len("</plist>")].encode())
    require(isinstance(value, dict), "Code entitlements are not a dictionary")
    return value


def validate_signature_description(description, entitlements, team):
    require("Authority=Developer ID Application:" in description
            and f"TeamIdentifier={team}\n" in description,
            "Code is not signed with the configured Developer ID team")
    require(re.search(r"flags=.*\bruntime\b", description) and re.search(r"^Timestamp=.+", description, re.M),
            "Code lacks hardened runtime or a secure signing timestamp")
    require(not entitlements.get("com.apple.security.get-task-allow", False),
            "Development get-task-allow entitlement is forbidden in a release")


def sign_and_verify(app, config, logs):
    binaries, bundles = signing_targets(app)
    for index, target in enumerate(binaries + bundles):
        args = ["/usr/bin/codesign", "--force", "--sign", config["signing_identity"],
                "--options", "runtime", "--timestamp", "--preserve-metadata=identifier,entitlements"]
        if target == app:
            args = [arg for arg in args if arg != "--preserve-metadata=identifier,entitlements"]
            args += ["--entitlements", ROOT / "PingIsland/Resources/PingIsland.entitlements"]
        command(args + [target], log=logs / f"sign-{index}.log")
    return verify_app_signature(app, config)


def verify_app_signature(app, config):
    """Verify without modifying either the source app or packaged copies."""
    binaries, bundles = signing_targets(app)
    evidence = []
    for target in binaries + bundles:
        command(["/usr/bin/codesign", "--verify", "--strict", target])
        stdout, stderr = command(["/usr/bin/codesign", "--display", "--verbose=4", target])
        description = stdout + stderr
        stdout, _ = command(["/usr/bin/codesign", "--display", "--entitlements", ":-", target])
        validate_signature_description(description, parse_entitlements(stdout), config["team_id"])
        if target in binaries:
            output, _ = command(["/usr/bin/xcrun", "lipo", "-archs", target])
            require(ARCHITECTURES.issubset(set(output.split())), "An embedded binary lacks a required architecture")
        evidence.append(str(target.relative_to(app)) if target != app else ".")
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    return evidence


def accepted_notarization(result):
    require(isinstance(result, dict) and result.get("status") == "Accepted"
            and isinstance(result.get("id"), str) and result["id"],
            "Notarization was not Accepted; candidate is not distributable")
    return result["id"]


def notarize(submission, staple_target, config, logs, label):
    output, _ = command(["/usr/bin/xcrun", "notarytool", "submit", submission,
                         "--keychain-profile", config["notary_keychain_profile"],
                         "--wait", "--timeout", "30m", "--output-format", "json"],
                        timeout=1900, log=logs / f"notary-{label}.log")
    submission_id = accepted_notarization(json.loads(output))
    command(["/usr/bin/xcrun", "stapler", "staple", staple_target], log=logs / f"staple-{label}.log")
    command(["/usr/bin/xcrun", "stapler", "validate", staple_target])
    return submission_id


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_inventory(app):
    """Compare payload files, symlinks and executable modes across packaging."""
    require(app.is_dir() and not app.is_symlink(), "Packaged application is missing or a symlink")
    inventory = {}
    for path in app.rglob("*"):
        name = str(path.relative_to(app))
        if path.is_symlink():
            require(path.resolve().is_relative_to(app.resolve()), "Packaged app symlink escapes its bundle")
            inventory[name] = ("symlink", os.readlink(path))
        elif path.is_file():
            inventory[name] = ("file", path.stat().st_mode & 0o777, sha256(path))
        elif path.is_dir():
            inventory[name] = ("directory",)
        else:
            raise ReleaseError("Unexpected special file in application bundle")
    return inventory


def verify_packaged_app(app, expected_inventory, expected_info, config, logs, label):
    require(bundle_inventory(app) == expected_inventory,
            f"The {label} application payload differs from the signed, stapled source")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info == expected_info, f"The {label} application identity/version/resources differ")
    command([sys.executable, ROOT / "scripts/verify-distribution-legal.py", "--app", app],
            log=logs / f"legal-{label}.log")
    verify_app_signature(app, config)
    command(["/usr/bin/xcrun", "stapler", "validate", app], log=logs / f"ticket-{label}.log")
    command(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app],
            log=logs / f"gatekeeper-{label}.log")


def verify_mounted_dmg(dmg, mountpoint, verify, logs):
    """Mount only our candidate read-only, and detach even when validation fails."""
    attached = False
    try:
        command(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                 "-mountpoint", mountpoint, dmg], timeout=120, log=logs / "mount-verification.log")
        attached = True
        verify(mountpoint / "Mac Island.app")
    finally:
        # An attach timeout/error may still have mounted the explicitly owned path.
        if attached or mountpoint.is_mount():
            command(["/usr/bin/hdiutil", "detach", mountpoint], timeout=30,
                    log=logs / "detach-verification.log")


def verify_packages(app, zip_path, dmg, config, output, logs):
    expected_inventory = bundle_inventory(app)
    expected_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    before = {path.name: sha256(path) for path in (zip_path, dmg)}
    # Retain our new verification directory. Never recursively delete a possibly
    # mounted volume if detach fails. The .noindex suffix limits build-copy noise.
    verification = Path(tempfile.mkdtemp(prefix="package-verification-", suffix=".noindex", dir=output))
    extracted = verification / "zip"
    extracted.mkdir()
    command(["/usr/bin/ditto", "-x", "-k", zip_path, extracted], timeout=300,
            log=logs / "extract-verification.log")
    verify_packaged_app(extracted / "Mac Island.app", expected_inventory, expected_info, config, logs, "zip")
    mountpoint = verification / "dmg"
    mountpoint.mkdir()
    verify_mounted_dmg(dmg, mountpoint,
                       lambda packaged: verify_packaged_app(packaged, expected_inventory, expected_info,
                                                            config, logs, "dmg"), logs)
    require(all(sha256(path) == before[path.name] for path in (zip_path, dmg)),
            "An artifact changed during packaged-payload verification")
    return before


def validate_output_path(requested):
    require(not requested.is_symlink(), "Output cannot be an existing or dangling symlink")
    require(not any(parent.is_symlink() and not parent.exists() for parent in requested.parents),
            "Output parent cannot be a dangling symlink")
    output = requested.resolve()
    require(not output.exists(), "Output already exists; use a fresh candidate directory")
    if output.is_relative_to(ROOT):
        require(output.is_relative_to(ROOT / "build"), "Repository output must be under ignored build/")
    require(not any(parent != ROOT and ((parent / ".git").exists() or (parent / ".git").is_symlink())
                    for parent in output.parents),
            "Output is inside another Git checkout; choose a non-repository directory")
    require(not any(part in (".git", ".ssh", ".aws") for part in output.parts),
            "Output path is not suitable for a release candidate")
    return output


def execute(config, output, commit, tree):
    require(not output.exists(), "Output already exists; choose a new candidate directory")
    check_public_pages(config)
    output.mkdir(parents=True, exist_ok=False)
    logs = output / "logs"
    logs.mkdir()
    (output / "INCOMPLETE.txt").write_text("This candidate is incomplete. Do not distribute it.\n")
    derived = output / "DerivedData"
    print("Building the universal Release candidate…", flush=True)
    command(["/usr/bin/xcodebuild", "-project", ROOT / "PingIsland.xcodeproj", "-scheme", "MacIsland",
             "-configuration", "Release", "-destination", "generic/platform=macOS",
             "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
             "-derivedDataPath", derived, "-jobs", "2", "build",
             "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGN_STYLE=Manual",
             "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=" + config["signing_identity"],
             "DEVELOPMENT_TEAM=" + config["team_id"], "PRODUCT_BUNDLE_IDENTIFIER=" + config["bundle_identifier"],
             "MARKETING_VERSION=" + config["version"], "CURRENT_PROJECT_VERSION=" + str(config["build_number"]),
             "ENABLE_HARDENED_RUNTIME=YES", "OTHER_CODE_SIGN_FLAGS=--timestamp"],
            timeout=7200, log=logs / "build.log")
    app = output / "Mac Island.app"
    command(["/usr/bin/ditto", derived / "Build/Products/Release/Mac Island.app", app])
    write_metadata(app, config, commit, tree)
    command([sys.executable, ROOT / "scripts/verify-distribution-legal.py", "--app", app,
             "--sparkle-license", derived / "SourcePackages/artifacts/sparkle/Sparkle/LICENSE"])
    print("Signing and checking every embedded code component…", flush=True)
    components = sign_and_verify(app, config, logs)
    notary_zip = output / "notary-submission.zip"
    command(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, notary_zip])
    print("Submitting the app to Apple for notarization…", flush=True)
    app_submission = notarize(notary_zip, app, config, logs, "app")
    command(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app],
            log=logs / "gatekeeper-app.log")
    stem = f"MacIsland-{config['version']}-{config['build_number']}"
    zip_path = output / (stem + ".zip")
    command(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, zip_path])
    staging = output / "dmg-staging"
    staging.mkdir()
    command(["/usr/bin/ditto", app, staging / "Mac Island.app"])
    (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
    dmg = output / (stem + ".dmg")
    command(["/usr/bin/hdiutil", "create", "-volname", "Mac Island", "-srcfolder", staging,
             "-format", "UDZO", dmg], timeout=300, log=logs / "dmg.log")
    command(["/usr/bin/codesign", "--sign", config["signing_identity"], "--timestamp", dmg],
            log=logs / "sign-dmg.log")
    command(["/usr/bin/codesign", "--verify", "--strict", dmg])
    print("Notarizing and checking the disk image…", flush=True)
    dmg_submission = notarize(dmg, dmg, config, logs, "dmg")
    command(["/usr/sbin/spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
             "--verbose=2", dmg], log=logs / "gatekeeper-dmg.log")
    print("Checking the applications actually contained in the ZIP and read-only DMG…", flush=True)
    package_hashes = verify_packages(app, zip_path, dmg, config, output, logs)
    require(git_state() == (commit, tree), "Source changed during preparation; do not distribute this candidate")
    manifest = {
        "schema_version": 1, "status": "verified_candidate", "channel": "developer-id-manual",
        "prepared_at": datetime.now(timezone.utc).isoformat(),
        "bundle_identifier": config["bundle_identifier"], "version": config["version"],
        "build_number": config["build_number"], "source_commit": commit, "source_tree": tree,
        "website_url": config["website_url"], "support_url": config["support_url"], "privacy_url": config["privacy_url"],
        "previous_version": config["previous_version"], "previous_build_number": config["previous_build_number"],
        "architectures": sorted(ARCHITECTURES), "verified_code_components": components,
        "notarization": {"app": app_submission, "dmg": dmg_submission},
        "artifacts": [{"name": path.name, "bytes": path.stat().st_size, "sha256": package_hashes[path.name],
                       "packaged_app_verified": True}
                      for path in (zip_path, dmg)],
        "remaining_acceptance": ["downloaded clean-Mac install and first launch", "upgrade and permission continuity",
                                 "supported-client real use", "sleep, displays, accessibility, and energy acceptance"],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "SHA256SUMS").write_text("".join(item["sha256"] + "  " + item["name"] + "\n"
                                              for item in manifest["artifacts"]))
    (output / "INCOMPLETE.txt").unlink()
    print("Verified candidate prepared. It has not been installed or published; real-device acceptance remains.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path, help="Local configuration; never include passwords or keys")
    parser.add_argument("--previous-manifest", type=Path, help="Receipt for the last distributed version; required after the first public release")
    parser.add_argument("--first-public-release", action="store_true", help="Declare that no prior public release exists; previous version/build still set the local upgrade floor")
    parser.add_argument("--output", type=Path, help="New directory; no existing output is ever removed")
    parser.add_argument("--execute", action="store_true", help="Explicitly build, sign, submit to Apple, and package; never publishes")
    args = parser.parse_args()
    try:
        require(bool(args.previous_manifest) != args.first_public_release,
                "Provide the previous release manifest, or explicitly declare the first public release")
        config = json.loads(args.config.read_text())
        commit, tree = preflight(config, args.previous_manifest)
        output = validate_output_path(args.output or ROOT / "build/distribution" / (config["version"] + "-" + str(config["build_number"])))
        if not args.execute:
            print("Preflight passed. No build, signature, notarization, installation, or publication was performed.")
            print("Public page availability and notarization credentials are checked only during explicit execution.")
            return 0
        execute(config, output, commit, tree)
    except (ReleaseError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Release preparation stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
