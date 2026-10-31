#!/usr/bin/env python3
"""Offline release-boundary fixtures: no signing, network, builds, or user data."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("release_preparation", Path(__file__).with_name("prepare-mac-island-release.py"))
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


def config():
    return {
        "bundle_identifier": "dev.synthetic-product.macisland",
        "team_id": "ABCDE12345",
        "signing_identity": "Developer ID Application: Fixture Publisher (ABCDE12345)",
        "notary_keychain_profile": "fixture-profile",
        "version": "0.30.0", "build_number": 73,
        "previous_version": "0.29.1", "previous_build_number": 72,
        "website_url": "", "support_url": "https://synthetic-product.dev/support",
        "privacy_url": "https://synthetic-product.dev/privacy",
    }


class DistributionBoundaryTests(unittest.TestCase):
    def test_configuration_requires_production_identity_and_no_secrets(self):
        RELEASE.validate_config(config())
        for key, value in (("bundle_identifier", "com.example.macisland"),
                           ("bundle_identifier", "org.example.macisland"),
                           ("bundle_identifier", "com.wudanwu.PingIsland"),
                           ("signing_identity", "-"), ("team_id", ""),
                           ("notary_keychain_profile", ""), ("support_url", "")):
            with self.subTest(key=key):
                candidate = config()
                candidate[key] = value
                with self.assertRaises(RELEASE.ReleaseError):
                    RELEASE.validate_config(candidate)
        candidate = config()
        candidate["password"] = "synthetic-secret-must-never-be-accepted"
        with self.assertRaises(RELEASE.ReleaseError):
            RELEASE.validate_config(candidate)

    def test_existing_local_identity_is_not_forced_to_change(self):
        candidate = config()
        candidate["bundle_identifier"] = "local.synthetic.macisland"
        RELEASE.validate_config(candidate)

    def test_missing_placeholder_local_and_credential_urls_are_rejected(self):
        for url in ("http://synthetic-product.dev/privacy", "https://example.com/privacy",
                    "https://support.local/privacy", "https://127.0.0.1/privacy",
                    "https://name:password@synthetic-product.dev/privacy",
                    "https://synthetic-product.dev:8443/privacy", "https://synthetic-product.dev/#fragment"):
            with self.subTest(url=url), self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_public_url(url, "privacy_url")

    def test_monotonic_build_and_version_floor(self):
        for key, value in (("build_number", 72), ("build_number", True),
                           ("build_number", "73"), ("version", "0.29.0"), ("version", "0.30-beta")):
            with self.subTest(key=key, value=value), self.assertRaises(RELEASE.ReleaseError):
                candidate = config()
                candidate[key] = value
                RELEASE.validate_config(candidate)

    def test_previous_receipt_must_match_product_and_floor(self):
        with tempfile.TemporaryDirectory() as temporary:
            receipt = Path(temporary) / "manifest.json"
            value = {"schema_version": 1, "status": "verified_candidate",
                     "bundle_identifier": config()["bundle_identifier"], "version": "0.29.1", "build_number": 72}
            receipt.write_text(json.dumps(value))
            RELEASE.validate_previous_manifest(config(), receipt)
            value["build_number"] = 74
            receipt.write_text(json.dumps(value))
            with self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_previous_manifest(config(), receipt)

    def test_only_accepted_notarization_can_proceed(self):
        self.assertEqual(RELEASE.accepted_notarization({"id": "fixture-submission", "status": "Accepted"}),
                         "fixture-submission")
        for result in ({"id": "fixture", "status": "In Progress"},
                       {"id": "fixture", "status": "Invalid"}, {"status": "Accepted"}):
            with self.subTest(result=result), self.assertRaises(RELEASE.ReleaseError):
                RELEASE.accepted_notarization(result)

    def test_signature_requires_runtime_timestamp_team_and_no_debug_entitlement(self):
        description = "Authority=Developer ID Application: Fixture Publisher (ABCDE12345)\nTeamIdentifier=ABCDE12345\nCodeDirectory flags=0x10000(runtime)\nTimestamp=Oct 15, 2026\n"
        RELEASE.validate_signature_description(description, {}, "ABCDE12345")
        for text, entitlements in (
            (description.replace("Timestamp=", "Signed Time="), {}),
            (description.replace("runtime", "adhoc"), {}),
            (description.replace("TeamIdentifier=ABCDE12345", "TeamIdentifier=FGHIJ67890"), {}),
            (description, {"com.apple.security.get-task-allow": True}),
        ):
            with self.subTest(description=text, entitlements=entitlements), self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_signature_description(text, entitlements, "ABCDE12345")

    def test_app_inventory_rejects_escaping_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Mac Island.app"
            executables = app / "Contents/MacOS"
            executables.mkdir(parents=True)
            for name in ("Mac Island", "PingIslandBridge"):
                (executables / name).write_bytes(bytes.fromhex("cffaedfe") + b"fixture")
            binaries, bundles = RELEASE.signing_targets(app)
            self.assertEqual(len(binaries), 2)
            self.assertEqual(bundles[-1], app)
            (app / "escape").symlink_to(Path(temporary))
            with self.assertRaises(RELEASE.ReleaseError):
                RELEASE.signing_targets(app)

    def test_default_cli_does_not_build_sign_upload_or_create_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            settings = path / "config.json"
            settings.write_text(json.dumps(config()))
            output = path / "candidate"
            args = ["prepare", "--config", str(settings), "--output", str(output), "--first-public-release"]
            with patch.object(RELEASE.sys, "argv", args), \
                    patch.object(RELEASE, "preflight", return_value=("fixture-commit", "fixture-tree")), \
                    patch.object(RELEASE, "execute") as execute, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(RELEASE.main(), 0)
                execute.assert_not_called()
                self.assertFalse(output.exists())

    def test_existing_output_is_preserved_and_execution_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            settings = path / "config.json"
            settings.write_text(json.dumps(config()))
            output = path / "candidate"
            output.mkdir()
            sentinel = output / "existing-file"
            sentinel.write_text("must survive")
            args = ["prepare", "--config", str(settings), "--output", str(output), "--first-public-release", "--execute"]
            with patch.object(RELEASE.sys, "argv", args), \
                    patch.object(RELEASE, "preflight", return_value=("fixture-commit", "fixture-tree")), \
                    patch.object(RELEASE, "execute") as execute, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(RELEASE.main(), 1)
                execute.assert_not_called()
                self.assertEqual(sentinel.read_text(), "must survive")

    def test_output_rejects_other_repository_and_worktree_ancestors(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            repository = path / "other-project"
            repository.mkdir()
            marker = repository / ".git"
            marker.mkdir()
            with self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_output_path(repository / "candidate")
            marker.rmdir()
            marker.write_text("gitdir: synthetic-worktree-metadata")
            with self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_output_path(repository / "candidate")
            link = path / "linked-project"
            link.symlink_to(repository, target_is_directory=True)
            with self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_output_path(link / "candidate")
            dangling = path / "dangling-output"
            dangling.symlink_to(path / "missing")
            with self.assertRaises(RELEASE.ReleaseError):
                RELEASE.validate_output_path(dangling)
            self.assertEqual(RELEASE.validate_output_path(path / "separate-candidate"), (path / "separate-candidate").resolve())

    def test_packaged_payload_change_is_rejected_before_signature_tools(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            app = path / "Mac Island.app"
            contents = app / "Contents"
            contents.mkdir(parents=True)
            info = {"CFBundleIdentifier": config()["bundle_identifier"], "CFBundleVersion": "73"}
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            inventory = RELEASE.bundle_inventory(app)
            (contents / "Info.plist").write_bytes(plistlib.dumps({**info, "CFBundleVersion": "72"}))
            with patch.object(RELEASE, "command") as command, self.assertRaises(RELEASE.ReleaseError):
                RELEASE.verify_packaged_app(app, inventory, info, config(), path, "fixture")
            command.assert_not_called()

    def test_packaged_app_checks_are_read_only_and_include_stapled_ticket(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            app = path / "Mac Island.app"
            contents = app / "Contents"
            contents.mkdir(parents=True)
            info = {"CFBundleIdentifier": config()["bundle_identifier"], "CFBundleVersion": "73"}
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            inventory = RELEASE.bundle_inventory(app)
            with patch.object(RELEASE, "command") as command, \
                    patch.object(RELEASE, "verify_app_signature") as signature:
                RELEASE.verify_packaged_app(app, inventory, info, config(), path, "fixture")
                signature.assert_called_once_with(app, config())
                calls = [call.args[0] for call in command.call_args_list]
                self.assertTrue(any("stapler" in args and "validate" in args for args in calls))
                self.assertTrue(any("--assess" in args for args in calls))
                self.assertFalse(any("--sign" in args for args in calls))
            self.assertEqual(RELEASE.bundle_inventory(app), inventory)

    def test_dmg_detaches_with_bounded_timeout_after_failed_payload_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            mountpoint = path / "mount"
            mountpoint.mkdir()
            def fail_validation(_app):
                raise RELEASE.ReleaseError("fixture payload mismatch")
            with patch.object(RELEASE, "command", return_value=("", "")) as command:
                with self.assertRaisesRegex(RELEASE.ReleaseError, "payload mismatch"):
                    RELEASE.verify_mounted_dmg(path / "candidate.dmg", mountpoint, fail_validation, path)
                attach, detach = command.call_args_list
                self.assertIn("-readonly", attach.args[0])
                self.assertIn("-nobrowse", attach.args[0])
                self.assertEqual(detach.args[0], ["/usr/bin/hdiutil", "detach", mountpoint])
                self.assertEqual(detach.kwargs["timeout"], 30)

    def test_dmg_attach_failure_still_cleans_partial_mount(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            def command_result(args, **_kwargs):
                if "attach" in args:
                    raise RELEASE.ReleaseError("fixture attach failure")
                return "", ""
            with patch.object(RELEASE, "command", side_effect=command_result) as command, \
                    patch.object(Path, "is_mount", return_value=True):
                with self.assertRaisesRegex(RELEASE.ReleaseError, "attach failure"):
                    RELEASE.verify_mounted_dmg(path / "candidate.dmg", path / "mount", lambda _app: None, path)
                self.assertIn("detach", command.call_args_list[-1].args[0])


if __name__ == "__main__":
    unittest.main()
