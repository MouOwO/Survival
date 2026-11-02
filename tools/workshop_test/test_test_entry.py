"""Entry boundaries: never start a cloud helper offline or replace a live game."""
import importlib.util
import hashlib
import io
import json
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("developer_test_entry", Path(__file__).with_name("test_entry.py"))
entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entry)


class TestEntryBoundaryTest(unittest.TestCase):
    def test_absent_labs_use_only_bounded_metadata_without_scanning(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(entry, "ROOT", Path(directory)), \
                patch.object(entry.os, "scandir", side_effect=AssertionError("No absent-root traversal")), \
                patch.object(Path, "lstat", autospec=True, side_effect=FileNotFoundError) as metadata:
            entry.guard_addon_vpk_labs()
        self.assertLessEqual(metadata.call_count, 9)

    def test_receipts_only_lab_passes_without_reading_files(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(entry, "ROOT", Path(directory)):
            lab = entry.ROOT / entry.ADDON_VPK_LAB_ROOTS[0]
            (lab / "run01").mkdir(parents=True)
            (lab / "run01/receipt.json").write_text("not a VPK", encoding="utf8")
            with patch.object(Path, "read_bytes", side_effect=AssertionError("No file-content read")), \
                    patch.object(Path, "read_text", side_effect=AssertionError("No file-content read")):
                entry.guard_addon_vpk_labs()

    def test_each_known_lab_rejects_bare_data_volume_before_any_launch(self):
        for relative in entry.ADDON_VPK_LAB_ROOTS:
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as directory, \
                    patch.object(entry, "ROOT", Path(directory)), \
                    patch.object(entry, "process_inventory", side_effect=AssertionError("No native query")), \
                    patch.object(entry.subprocess, "Popen", side_effect=AssertionError("No client launch")), \
                    patch.object(entry, "ensure_relay", side_effect=AssertionError("No cloud")):
                lab = entry.ROOT / relative / "run01/570/3824360109"
                lab.mkdir(parents=True)
                (lab / "3824360109_000.vpk").write_bytes(b"synthetic data volume, not a directory index")
                for check_only in (True, False):
                    with self.subTest(check_only=check_only), self.assertRaisesRegex(RuntimeError, "addon_lab_vpk_detected"):
                        entry.run("offline", check_only=check_only)
                self.assertTrue((lab / "3824360109_000.vpk").exists(), "Guard must never remove or move a VPK")

    def test_actual_map_package_and_unrelated_backup_are_never_scanned(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(entry, "ROOT", Path(directory)):
            for relative in ("maps/template_map.vpk", "real_backup/original/3824360109_000.vpk"):
                path = entry.ROOT / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"must not inspect or modify this real-path fixture")
            with patch.object(entry.os, "scandir", side_effect=AssertionError("Do not traverse real map/backup")):
                entry.guard_addon_vpk_labs()

    def test_reparse_lab_parent_refuses_without_following_into_real_packages(self):
        fake = SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=0x400)
        with patch.object(Path, "lstat", return_value=fake), \
                patch.object(entry.os, "scandir", side_effect=AssertionError("Never follow junction")):
            with self.assertRaisesRegex(RuntimeError, "addon_lab_path_unsafe"):
                entry.guard_addon_vpk_labs()

    def test_guard_errors_have_stable_code_and_chinese_explanation(self):
        with patch.object(entry.sys, "argv", ["test_entry.py", "offline", "--check"]), \
                patch.object(entry, "run", side_effect=RuntimeError("addon_lab_vpk_detected")), \
                redirect_stdout(io.StringIO()) as output, redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(entry.main(), 1)
        result = json.loads(output.getvalue())
        self.assertEqual(result["error"], "addon_lab_vpk_detected")
        self.assertIn("插件目录之外", result["message"])
        self.assertIn("本工具不会自动移动或删除文件", errors.getvalue())

    def test_online_check_does_not_traverse_offline_lab_namespace(self):
        with patch.object(entry, "guard_addon_vpk_labs", side_effect=AssertionError("Offline guard only")), \
                patch.object(Path, "is_file", return_value=True), \
                patch.object(Path, "read_bytes", return_value=b"enabled = true"), \
                patch.object(entry, "check_online_policy"):
            self.assertEqual(entry.check("online")["status"], "ENTRY_CHECKED")

    def test_regular_launch_arguments_keep_their_mode_and_port(self):
        args = entry.launch_arguments("offline", Path("normal.log"))
        self.assertEqual(args[args.index("+survival_offline_logic_test") + 1], "1")
        self.assertEqual(args[args.index("+survival_archive_http_enabled") + 1], "0")
        self.assertEqual(args.count("+survival_archive_http_enabled"), 1)
        self.assertEqual(args[args.index("-vconport") + 1], "29006")
        online = entry.launch_arguments("online", Path("online.log"))
        self.assertEqual(online[online.index("-vconport") + 1], "29005")
        self.assertNotIn("+survival_offline_logic_test", online)
        self.assertNotIn("+survival_archive_http_enabled", online)

    def test_offline_launcher_preserves_live_game_and_never_contacts_cloud(self):
        with patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": [456]}), \
                patch.object(entry, "ensure_relay", side_effect=AssertionError("offline cloud access")), \
                patch.object(entry.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(RuntimeError, "dota_already_running"):
                entry.run("offline")
            launch.assert_not_called()

    def test_offline_launch_never_touches_cloud_transport(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(entry, "RUNTIME", Path(directory)), \
                patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": []}), \
                patch.object(entry, "ensure_relay", side_effect=AssertionError("offline cloud access")), \
                patch.object(entry.subprocess, "Popen", return_value=SimpleNamespace(pid=1234)) as launch:
            result = entry.run("offline")
            self.assertTrue(result["game_started"])
            args = launch.call_args.args[0]
            self.assertEqual(args[args.index("-addon") + 1], entry.ROOT.name)
            self.assertEqual(args[args.index("+survival_offline_logic_test") + 1], "1")
            self.assertEqual(args[args.index("+survival_archive_http_enabled") + 1], "0")
            self.assertEqual(args.count("+survival_archive_http_enabled"), 1)
            self.assertEqual(args[args.index("+sv_cheats") + 1], "1")
            self.assertNotIn(entry.ONLINE_ADDON, args)

    def test_live_game_is_preserved_before_any_helper_or_launch(self):
        with patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": [456]}), \
                patch.object(entry, "ensure_relay") as relay, patch.object(entry.subprocess, "Popen") as launch:
            for mode in ("offline", "online"):
                with self.assertRaisesRegex(RuntimeError, "dota_already_running"):
                    entry.run(mode)
            relay.assert_not_called()
            launch.assert_not_called()

    def test_failed_relay_never_launches_online_or_falls_back_offline(self):
        with patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": []}), \
                patch.object(entry, "ensure_relay", side_effect=RuntimeError("steam_test_relay_identity_invalid")), \
                patch.object(entry.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(RuntimeError, "steam_test_relay_identity_invalid"):
                entry.run("online")
            launch.assert_not_called()

    def test_online_uses_only_verified_online_addon_without_offline_flag(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(entry, "RUNTIME", Path(directory)), \
                patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": []}), \
                patch.object(entry, "ensure_relay", return_value={"running": True, "started": False}), \
                patch.object(entry.subprocess, "Popen", return_value=SimpleNamespace(pid=1234)) as launch:
            entry.run("online")
            args = launch.call_args.args[0]
            self.assertEqual(args[args.index("-addon") + 1], entry.ONLINE_ADDON)
            self.assertNotIn("+survival_offline_logic_test", args)
            self.assertNotIn("+survival_archive_http_enabled", args)
            self.assertEqual(args[args.index("+sv_cheats") + 1], "0")
            self.assertEqual(args.count("+sv_cheats"), 1)

    def test_check_only_does_not_read_processes_or_start_helpers(self):
        with patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "process_inventory") as inventory, \
                patch.object(entry, "ensure_relay") as relay, patch.object(entry.subprocess, "Popen") as launch:
            entry.run("online", check_only=True)
            inventory.assert_not_called()
            relay.assert_not_called()
            launch.assert_not_called()

    def test_stale_or_modified_online_policy_is_rejected_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            addon = Path(directory)
            policy = addon / "scripts/vscripts/core/release_policy.lua"
            profile = addon / "scripts/vscripts/config/release_profile.lua"
            policy.parent.mkdir(parents=True)
            profile.parent.mkdir(parents=True)
            policy.write_bytes(b"protected online gate")
            profile.write_bytes(b'return { channel = "production" }')
            manifest = addon / "_online_policy_install.json"
            manifest.write_text(json.dumps({"content_sha256": "new_release"}), encoding="utf-8")
            receipt = addon / "policy_record.json"
            record = {"online_cheats_allowed": False, "candidate": {
                "content_sha256": "new_release",
                "runtime_policy_sha256": hashlib.sha256(policy.read_bytes()).hexdigest(),
                "release_profile_sha256": hashlib.sha256(profile.read_bytes()).hexdigest()}}
            receipt.write_text(json.dumps(record), encoding="utf-8")
            with patch.object(entry, "ONLINE_POLICY_RECORD", receipt), \
                    patch.object(entry, "PAYMENT_HELPER_RECORD", addon / "no_helper.json"):
                entry.check_online_policy(addon)
                manifest.write_text(json.dumps({"content_sha256": "old_release"}), encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "online_release_policy_outdated"):
                    entry.check_online_policy(addon)
                manifest.write_text(json.dumps({"content_sha256": "new_release"}), encoding="utf-8")
                policy.write_bytes(b"old or modified gate")
                with self.assertRaisesRegex(RuntimeError, "online_cheat_policy_bytes_changed"):
                    entry.check_online_policy(addon)
                policy.write_bytes(b"protected online gate")
                profile.write_bytes(b'return { channel = "development" }')
                with self.assertRaisesRegex(RuntimeError, "online_release_profile_changed"):
                    entry.check_online_policy(addon)
                record["online_cheats_allowed"] = True
                receipt.write_text(json.dumps(record), encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "online_cheat_policy_not_verified"):
                    entry.check_online_policy(addon)

    def test_verified_payment_helper_pins_cannot_enable_cheats_or_stale_installs(self):
        with tempfile.TemporaryDirectory() as directory:
            addon = Path(directory)
            hashes = {}
            for name in entry.PAYMENT_HELPER_PINS:
                path = addon / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(("reviewed:" + name).encode())
                hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
            installation = {"content_sha256": "helper_release", "release_sequence": 2026102701,
                            "signature_valid": True, "online_cheats_allowed": False,
                            "full_after_verification": True}
            marker = addon / "_online_policy_install.json"
            marker.write_text(json.dumps(installation), encoding="utf-8")
            record = {"kind": "VERIFIED_WS4_PAYMENT_HELPER", "enabled": True,
                      "online_cheats_allowed": False, "cloud_login_required": True,
                      "candidate": {"content_sha256": "helper_release", "release_sequence": 2026102701,
                                    "runtime_hashes": hashes}}
            receipt = addon / "helper.json"
            receipt.write_text(json.dumps(record), encoding="utf-8")
            with patch.object(entry, "PAYMENT_HELPER_RECORD", receipt), \
                    patch.object(entry, "ONLINE_POLICY_RECORD", addon / "missing_legacy.json"):
                entry.check_online_policy(addon)
                marker.write_text(json.dumps({**installation, "signature_valid": False}), encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "online_payment_helper_outdated"):
                    entry.check_online_policy(addon)
                marker.write_text(json.dumps(installation), encoding="utf-8")
                record["online_cheats_allowed"] = True
                receipt.write_text(json.dumps(record), encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "payment_helper_record_invalid"):
                    entry.check_online_policy(addon)
                record["online_cheats_allowed"] = False
                receipt.write_text(json.dumps(record), encoding="utf-8")
                (addon / "scripts/vscripts/systems/payment_service.lua").write_bytes(b"stale service")
                with self.assertRaisesRegex(RuntimeError, "online_payment_helper_bytes_changed"):
                    entry.check_online_policy(addon)


if __name__ == "__main__":
    unittest.main()
