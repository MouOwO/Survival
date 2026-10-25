"""Synthetic launcher/receipt guards plus parse-only PowerShell validation."""
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launch_workshop as launcher


def observed(log, pid=1234):
    return dict(pid=pid, name="dota2.exe", executable=str(launcher.EXE),
                created_utc="2026-10-25T06:00:00.1234567Z", command_line="synthetic ordinary command")


@contextmanager
def receipt_fixture():
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary).resolve() / "online_workshop"
        folder = output / "workshop_20261025T060000123456Z_1234abcd"
        folder.mkdir(parents=True)
        path, log = folder / "launch_receipt.json", folder / "game.log"
        data = dict(ok=True, kind=launcher.KIND, app_id=570, workshop_id="3824360109",
                    entry_map="ws4_entry", expected_auto_reopen_map="template_map",
                    content_sha256=launcher.native.CONTENT_SHA, release_sequence=launcher.native.SEQUENCE,
                    tools=False, insecure=False, author_addon=False, cheats_allowed=False,
                    vcon_port=29007, pid=1234, log_file=str(log), arguments=launcher.launch_arguments(log),
                    created_utc=observed(log)["created_utc"],
                    command_line_sha256=hashlib.sha256(observed(log)["command_line"].encode()).hexdigest())
        def save(): path.write_text(json.dumps(data), encoding="utf-8")
        save()
        relay = SimpleNamespace(split_command_line=lambda line: [str(launcher.EXE), *launcher.launch_arguments(log)])
        with patch.object(launcher, "OUTPUT", output), \
                patch.object(launcher, "process_details", return_value=observed(log)) as process, \
                patch.object(launcher, "port_owners", return_value=[1234]) as port, \
                patch.object(launcher.entry, "load_relay", return_value=relay):
            yield path, data, save, process, port


class OrdinaryWorkshopLauncherTest(unittest.TestCase):
    def test_exact_ordinary_entry_arguments_and_app_identity(self):
        args = launcher.launch_arguments(Path("C:/qa/game.log"))
        self.assertEqual(args, ["-steam", "-novid", "-console", "-vconport", "29007", "-condebug",
                               "-con_logfile", str(Path("C:/qa/game.log")), "+sv_cheats", "0",
                               "+dota_launch_custom_game", "3824360109", "ws4_entry"])
        self.assertEqual(launcher.APP_ID, 570)
        self.assertEqual(launcher.GAMEPLAY_MAP, "template_map")
        self.assertFalse(set(args) & {"-tools", "-addon", "-insecure", "-dev"})

    def test_extra_tools_addon_insecure_or_other_map_is_rejected(self):
        log = Path("C:/qa/game.log")
        for extra in (["-tools"], ["-addon", "survival"], ["-insecure"], ["+sv_cheats", "1"]):
            with self.subTest(extra=extra), self.assertRaisesRegex(RuntimeError, "arguments_mismatch"):
                launcher.validate_process(observed(log), 1234, log,
                    argv_parser=lambda line: [str(launcher.EXE), *launcher.launch_arguments(log), *extra])
        args = launcher.launch_arguments(log);args[-1] = "template_map"
        with self.assertRaisesRegex(RuntimeError, "arguments_mismatch"):
            launcher.validate_process(observed(log), 1234, log, argv_parser=lambda line: [str(launcher.EXE), *args])

    def test_default_is_read_only_and_never_ensures_relay_launches_or_creates_output(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(launcher, "OUTPUT", Path(temporary)/"absent"), \
                patch.object(launcher, "preflight", return_value={}), \
                patch.object(launcher, "existing_relay", return_value={"running": True, "started": False}), \
                patch.object(launcher.entry, "ensure_relay", side_effect=AssertionError("relay mutation")), \
                patch.object(launcher.subprocess, "Popen", side_effect=AssertionError("game launch")):
            result = launcher.run()
            self.assertEqual(result["status"], "READ_ONLY_ENTRY_CHECKED")
            self.assertFalse(result["game_started"])
            self.assertFalse(launcher.OUTPUT.exists())

    def test_existing_game_missing_steam_or_foreign_vcon_blocks_before_download(self):
        for inventory, ports, expected in ((dict(steam_running=False, dota_pids=[]), [], "steam_required"),
                                            (dict(steam_running=True, dota_pids=[99]), [], "close_existing"),
                                            (dict(steam_running=True, dota_pids=[]), [99], "port_in_use")):
            with self.subTest(expected=expected), patch.object(launcher.entry, "process_inventory", return_value=inventory), \
                    patch.object(launcher, "port_owners", return_value=ports), \
                    patch.object(launcher, "check_download", side_effect=AssertionError("download read")), \
                    self.assertRaisesRegex(RuntimeError, expected):
                launcher.preflight()

    def test_valid_receipt_pid_birth_and_owned_listener_is_read_only(self):
        with receipt_fixture() as (path, data, save, process, port), \
                patch.object(launcher.subprocess, "Popen", side_effect=AssertionError("launch")):
            result = launcher.validate_live_receipt(path, 1234)
            self.assertTrue(result["ok"])
            self.assertEqual(result["port"], 29007)
            self.assertFalse(result["game_control_performed"])

    def test_receipt_cannot_select_other_id_map_app_mode_or_pid(self):
        for key, value in (("workshop_id", "1"), ("app_id", 1), ("entry_map", "template_map"),
                           ("tools", True), ("insecure", True), ("author_addon", True),
                           ("cheats_allowed", True), ("pid", 999), ("vcon_port", 29005)):
            with self.subTest(key=key), receipt_fixture() as (path, data, save, process, port):
                data[key] = value;save()
                with self.assertRaisesRegex(RuntimeError, "receipt_identity"):
                    launcher.validate_live_receipt(path, 1234)
                process.assert_not_called()

    def test_missing_birth_or_command_binding_fails_before_process_query(self):
        for key in ("created_utc", "command_line_sha256"):
            with self.subTest(key=key), receipt_fixture() as (path, data, save, process, port):
                data.pop(key);save()
                with self.assertRaisesRegex(RuntimeError, "binding_missing"):
                    launcher.validate_live_receipt(path, 1234)
                process.assert_not_called()

    def test_reused_pid_changed_command_or_foreign_port_fails_closed(self):
        for what in ("birth", "command", "port"):
            with self.subTest(what=what), receipt_fixture() as (path, data, save, process, port):
                if what == "birth": process.return_value = dict(process.return_value, created_utc="other creation")
                elif what == "command": process.return_value = dict(process.return_value, command_line="other command")
                else: port.return_value = [999]
                with self.assertRaisesRegex(RuntimeError, "pid_reused|command_changed|vcon_owner_mismatch"):
                    launcher.validate_live_receipt(path, 1234)

    def test_receipt_log_or_argument_override_is_rejected(self):
        for key, value in (("log_file", "C:/other.log"), ("arguments", ["-tools"])):
            with self.subTest(key=key), receipt_fixture() as (path, data, save, process, port):
                data[key] = value;save()
                with self.assertRaisesRegex(RuntimeError, "receipt_arguments"):
                    launcher.validate_live_receipt(path, 1234)

    def test_old_latest_or_other_receipt_location_is_rejected(self):
        with receipt_fixture() as (path, data, save, process, port):
            wrong = path.with_name("current_game.json");wrong.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "receipt_path_invalid"):
                launcher.validate_live_receipt(wrong, 1234)

    def test_explicit_launch_with_mock_child_writes_unique_receipt_only(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(launcher, "OUTPUT", Path(temporary)/"ordinary"), \
                patch.object(launcher, "preflight", return_value={}) as preflight, \
                patch.object(launcher.entry, "ensure_relay", return_value={"running": True, "started": False}), \
                patch.object(launcher.subprocess, "Popen", return_value=SimpleNamespace(pid=1234)) as popen, \
                patch.object(launcher, "process_details", return_value={}), \
                patch.object(launcher, "validate_process", return_value=dict(pid=1234, created_utc="birth", command_line_sha256="0"*64)):
            result = launcher.run(launch=True)
            self.assertTrue(result["ok"] and result["game_started"])
            self.assertEqual(preflight.call_count, 2)
            self.assertEqual(popen.call_args.kwargs["env"]["SteamAppId"], "570")
            self.assertEqual(popen.call_args.args[0][-3:], ["+dota_launch_custom_game", "3824360109", "ws4_entry"])
            receipt = Path(result["receipt"])
            self.assertTrue(receipt.exists() and (receipt.parent/"launch_request.json").exists())
            self.assertFalse((launcher.OUTPUT/"launch.lock").exists())
            self.assertFalse((launcher.OUTPUT/"current_game.json").exists())

    def test_launch_lock_never_replaces_competing_lock(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(launcher, "OUTPUT", Path(temporary)/"ordinary"):
            with launcher.launch_lock():
                before=(launcher.OUTPUT/"launch.lock").read_bytes()
                with self.assertRaises(FileExistsError):
                    with launcher.launch_lock(): self.fail("second launch acquired lock")
                self.assertEqual((launcher.OUTPUT/"launch.lock").read_bytes(), before)

    def test_gui_helper_defaults_to_check_before_any_focus_or_input_and_exclusive_capture(self):
        text=Path(__file__).with_name("workshop_window.ps1").read_text("utf-8-sig")
        self.assertIn("$Action='CheckOnly'", text)
        self.assertLess(text.index("if($Action -eq 'CheckOnly')"),text.index("Add-Type @'"))
        self.assertIn("--check-receipt $ReceiptPath --pid $GameProcessId",text)
        self.assertIn("Start-Sleep -Milliseconds 150",text)
        self.assertIn("[IO.FileMode]::CreateNew",text)
        self.assertNotIn("Stop-Process",text)
        self.assertNotIn("TerminateProcess",text)

    def test_gui_helper_powershell_parse_only_no_script_execution(self):
        path=Path(__file__).with_name("workshop_window.ps1").resolve()
        literal=str(path).replace("'","''")
        code="$t=$null;$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('"+literal+"',[ref]$t,[ref]$e);if($e.Count){$e|ForEach-Object{$_.Message};exit 2};'PARSE_OK'"
        result=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-Command",code],capture_output=True,text=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn("PARSE_OK",result.stdout)


if __name__ == "__main__":
    unittest.main()
