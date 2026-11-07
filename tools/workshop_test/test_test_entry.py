"""Entry boundaries: never start a cloud helper offline or replace a live game."""
import importlib.util
import io
import json
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

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
        signed = Mock()
        signed.check.return_value = {"status": "SIGNED_ONLINE_ENTRY_CHECKED"}
        with patch.object(entry, "guard_addon_vpk_labs", side_effect=AssertionError("Offline guard only")), \
                patch.object(entry, "load_online", return_value=signed):
            self.assertEqual(entry.check("online")["status"], "SIGNED_ONLINE_ENTRY_CHECKED")
        signed.check.assert_called_once_with()

    def test_regular_launch_arguments_keep_their_mode_and_port(self):
        args = entry.launch_arguments("offline", Path("normal.log"))
        self.assertEqual(args[args.index("+survival_offline_logic_test") + 1], "1")
        self.assertEqual(args[args.index("+survival_archive_http_enabled") + 1], "0")
        self.assertEqual(args.count("+survival_archive_http_enabled"), 1)
        self.assertEqual(args[args.index("-vconport") + 1], "29006")
        with self.assertRaisesRegex(RuntimeError, "online_requires_canonical_launcher"):
            entry.launch_arguments("online", Path("online.log"))

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
            self.assertNotIn("svt_w24", args)

    def signed(self):
        signed = Mock()
        signed.prepare.return_value = {"summary": {"ok": True, "game_started": False,
                                                   "status": "SIGNED_ONLINE_ENTRY_CHECKED"}}
        signed.run_prepared.return_value = {"ok": True, "status": "SIGNED_ONLINE_EXITED_ORIGINAL_RESTORED"}
        return signed

    def test_live_game_is_preserved_before_any_helper_or_launch(self):
        signed = self.signed()
        with patch.object(entry, "check", return_value={"ok": True}), \
                patch.object(entry, "load_online", return_value=signed), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": [456]}), \
                patch.object(entry, "ensure_relay") as relay, patch.object(entry.subprocess, "Popen") as launch:
            for mode in ("offline", "online"):
                with self.assertRaisesRegex(RuntimeError, "dota_already_running"):
                    entry.run(mode)
            relay.assert_not_called()
            launch.assert_not_called()
            signed.run_prepared.assert_not_called()

    def test_failed_relay_never_launches_online_or_falls_back_offline(self):
        signed = self.signed()
        with patch.object(entry, "load_online", return_value=signed), \
                patch.object(entry, "process_inventory", return_value={"steam_running": True, "dota_pids": []}), \
                patch.object(entry, "ensure_relay", side_effect=RuntimeError("steam_test_relay_identity_invalid")), \
                patch.object(entry.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(RuntimeError, "steam_test_relay_identity_invalid"):
                entry.run("online")
            signed.run_prepared.assert_not_called()
            launch.assert_not_called()

    def test_online_delegates_only_after_authentication_and_relay(self):
        signed, order = self.signed(), []
        signed.prepare.side_effect = lambda: order.append("verify") or {"summary": {"ok": True}}
        signed.run_prepared.side_effect = lambda prepared: order.append("canonical") or prepared["summary"]
        with patch.object(entry, "load_online", return_value=signed), \
                patch.object(entry, "process_inventory", side_effect=lambda: order.append("process") or
                             {"steam_running": True, "dota_pids": []}), \
                patch.object(entry, "ensure_relay", side_effect=lambda: order.append("relay") or {"running": True}), \
                patch.object(entry.subprocess, "Popen", side_effect=AssertionError("No independent Dota launch")), \
                patch.object(entry, "launch_arguments", side_effect=AssertionError("No Tools/legacy argv")):
            result = entry.run("online")
        self.assertEqual(order, ["verify", "process", "relay", "canonical"])
        self.assertEqual(result["steam_transport"], {"running": True})
        signed.prepare.assert_called_once_with()

    def test_check_only_does_not_read_processes_or_start_helpers(self):
        signed = self.signed()
        with patch.object(entry, "load_online", return_value=signed), \
                patch.object(entry, "process_inventory") as inventory, \
                patch.object(entry, "ensure_relay") as relay, patch.object(entry.subprocess, "Popen") as launch:
            result = entry.run("online", check_only=True)
        self.assertFalse(result["game_started"])
        inventory.assert_not_called()
        relay.assert_not_called()
        launch.assert_not_called()
        signed.run_prepared.assert_not_called()

    def test_missing_steam_preserves_install_and_never_starts_relay(self):
        signed = self.signed()
        with patch.object(entry, "load_online", return_value=signed), \
                patch.object(entry, "process_inventory", return_value={"steam_running": False, "dota_pids": []}), \
                patch.object(entry, "ensure_relay") as relay:
            with self.assertRaisesRegex(RuntimeError, "steam_not_running"):
                entry.run("online")
        relay.assert_not_called()
        signed.run_prepared.assert_not_called()

    def test_invalid_candidate_refuses_before_any_cloud_or_process(self):
        signed = self.signed()
        signed.prepare.side_effect = RuntimeError("online_expected_newest_mismatch")
        with patch.object(entry, "load_online", return_value=signed), \
                patch.object(entry, "process_inventory") as inventory, patch.object(entry, "ensure_relay") as relay:
            with self.assertRaisesRegex(RuntimeError, "online_expected_newest_mismatch"):
                entry.run("online")
        inventory.assert_not_called()
        relay.assert_not_called()
        signed.run_prepared.assert_not_called()

    def test_existing_relay_identity_failure_does_not_replace_live_helper(self):
        relay = Mock()
        relay.RECEIPT.exists.return_value = True
        relay.RECEIPT.read_text.return_value = json.dumps({"pid": 12, "owner": "expected"})
        relay.process_identity.return_value = {"pid": 12, "owner": "different"}
        with patch.object(entry, "load_relay", return_value=relay):
            with self.assertRaisesRegex(RuntimeError, "steam_test_relay_identity_invalid"):
                entry.ensure_relay()
        relay.start.assert_not_called()
        relay.stop.assert_not_called()

    def test_wrapper_streams_keeper_and_does_not_return_early(self):
        script = Path(__file__).with_name("launch_test.ps1").read_text(encoding="utf-8")
        self.assertIn("& $python @entryArguments", script)
        self.assertNotIn("$reply=", script)
        self.assertIn("keep this window open", script.lower())


if __name__ == "__main__":
    unittest.main()
