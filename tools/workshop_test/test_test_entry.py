"""Entry boundaries: never start a cloud helper offline or replace a live game."""
import importlib.util
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("developer_test_entry", Path(__file__).with_name("test_entry.py"))
entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entry)


class TestEntryBoundaryTest(unittest.TestCase):
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
            with patch.object(entry, "ONLINE_POLICY_RECORD", receipt):
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


if __name__ == "__main__":
    unittest.main()
