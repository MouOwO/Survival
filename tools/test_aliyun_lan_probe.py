from __future__ import annotations

from contextlib import ExitStack, redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import aliyun_lan_probe as lan


NONCE = "GOUFAYU_LAN_" + "a" * 32
STALE_NONCE = "GOUFAYU_LAN_" + "b" * 32


class LanProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(lan, "ROOT", self.root))

    def test_parser_requires_current_nonce_confirmation_and_exact_status_line(self):
        valid = (NONCE + ":waiting_players:2\n" + NONCE + "\n").encode()
        self.assertEqual(lan.parse_result(valid, NONCE),
                         {"ok": True, "status": "waiting_players", "players": 2})
        stale = (STALE_NONCE + ":waiting_players:4\n" + STALE_NONCE + "\n").encode()
        with self.assertRaisesRegex(lan.auth.AuthError, "tools_server_confirmation_missing"):
            lan.parse_result(stale, NONCE)
        with self.assertRaisesRegex(lan.auth.AuthError, "tools_server_confirmation_missing"):
            lan.parse_result((NONCE + ":waiting_players:4\n").encode(), NONCE)
        invalid_payloads = [
            "waiting_players:4", STALE_NONCE + ":waiting_players:4",
            "echo " + NONCE + ":waiting_players:4", NONCE + ":waiting_players:4 trailing",
            NONCE + ":waiting_players:25", NONCE + ":waiting_players:-1",
            NONCE + ":waiting_players:100", NONCE + ":unknown_status:2",
        ]
        for payload in invalid_payloads:
            with self.subTest(payload=payload), self.assertRaisesRegex(
                    lan.auth.AuthError, "lan_probe_invalid_response"):
                lan.parse_result((payload + "\n" + NONCE + "\n").encode(), NONCE)

    def test_parser_ignores_unrelated_console_history(self):
        history = "unrelated history must stay hidden\n" + STALE_NONCE + ":waiting_players:4\n"
        output = (history + NONCE + ":waiting_players:1\n" + NONCE + "\n").encode()
        self.assertEqual(lan.parse_result(output, NONCE)["players"], 1)

    def test_parser_rejects_already_authenticated_or_released_session(self):
        for status, reason in (
                ("already_released", "session_already_configured_or_released"),
                ("admission_released", "admission_already_released"),
                ("credential_present", "credential_already_present")):
            with self.subTest(status=status):
                self.assertEqual(lan.parse_result(
                    (NONCE + ":" + status + ":0\n" + NONCE + "\n").encode(), NONCE),
                    {"ok": False,
                     "error": "lan_session_already_authenticated_restart_without_bridge",
                     "reason": reason})
        self.assertEqual(lan.parse_result(
            (NONCE + ":gate_not_ready:0\n" + NONCE + "\n").encode(), NONCE)["status"],
            "gate_not_ready")

    def test_nonce_rejects_code_injection_before_lua_generation(self):
        for nonce in ("", "x", NONCE + "'; error('unexpected')", NONCE.upper()):
            with self.subTest(nonce=nonce), self.assertRaisesRegex(
                    lan.auth.AuthError, "lan_probe_nonce_invalid"):
                lan.inspection_lua(nonce)

    def prepare_probe(self, runner):
        self.stack.enter_context(patch.object(lan.secrets, "token_hex", return_value="a" * 32))
        self.stack.enter_context(patch.object(lan.shutil, "which", return_value="node.exe"))
        self.stack.enter_context(patch.object(lan.auth, "ignored"))
        self.stack.enter_context(patch.object(lan.auth, "no_reparse"))
        self.stack.enter_context(patch.object(lan.subprocess, "run", side_effect=runner))

    def test_request_is_read_only_and_removed_after_success(self):
        requests = []

        def runner(args, **kwargs):
            path = Path(args[args.index("--file") + 1])
            requests.append(path)
            content = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(content[0]["name"], "dota_run_lua")
            code = content[0]["arguments"]["code"]
            self.assertEqual(code, lan.inspection_lua(NONCE))
            for forbidden in ("SetStr(", "SetCustomTeamAssignment", "FinishCustomGameSetup",
                              "LoadKeyValues(", "authenticate_player", "loading.init(", "require("):
                self.assertNotIn(forbidden, code)
            self.assertTrue(kwargs["capture_output"])
            return Mock(returncode=0, stdout=(NONCE + ":waiting_players:2\n" + NONCE + "\n").encode())

        self.prepare_probe(runner)
        self.assertEqual(lan.probe()["players"], 2)
        self.assertEqual(len(requests), 1)
        self.assertFalse(requests[0].exists())

    def test_temporary_request_removed_after_console_failure_timeout_and_parse_failure(self):
        for failure in (Mock(returncode=1, stdout=b"unrelated console data"),
                        subprocess.TimeoutExpired("node.exe", 15),
                        Mock(returncode=0, stdout=b"stale reply")):
            with self.subTest(failure=type(failure).__name__), ExitStack() as patches:
                patches.enter_context(patch.object(lan.secrets, "token_hex", return_value="a" * 32))
                patches.enter_context(patch.object(lan.shutil, "which", return_value="node.exe"))
                patches.enter_context(patch.object(lan.auth, "ignored"))
                patches.enter_context(patch.object(lan.auth, "no_reparse"))
                if isinstance(failure, Exception):
                    patches.enter_context(patch.object(lan.subprocess, "run", side_effect=failure))
                else:
                    patches.enter_context(patch.object(lan.subprocess, "run", return_value=failure))
                with self.assertRaises((lan.auth.AuthError, subprocess.TimeoutExpired)):
                    lan.probe()
                self.assertEqual(list((self.root / "output/ecs_backend_work").glob("*.json")), [])

    def test_file_collision_never_deletes_preexisting_request(self):
        path = self.root / "output/ecs_backend_work" / (NONCE + ".json")
        path.parent.mkdir(parents=True)
        path.write_text("existing file", encoding="utf-8")
        runner = Mock()
        self.prepare_probe(runner)
        with self.assertRaises(FileExistsError):
            lan.probe()
        self.assertEqual(path.read_text(encoding="utf-8"), "existing file")
        runner.assert_not_called()

    def test_main_does_not_print_exception_payload_or_console_history(self):
        for failure, expected in ((lan.auth.AuthError("node_unavailable"), "node_unavailable"),
                                  (OSError("private console payload"), "lan_local_probe_failed")):
            with self.subTest(failure=type(failure).__name__), \
                 patch.object(lan, "probe", side_effect=failure), redirect_stdout(io.StringIO()) as output:
                self.assertEqual(lan.main(), 1)
                result = json.loads(output.getvalue())
                self.assertEqual(result, {"ok": False, "error": expected})
                self.assertNotIn("private console payload", output.getvalue())

    def test_main_preserves_rejection_reason_and_nonzero_exit(self):
        rejection = lan.parse_result(
            (NONCE + ":credential_present:0\n" + NONCE + "\n").encode(), NONCE)
        with patch.object(lan, "probe", return_value=rejection), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(lan.main(), 1)
            self.assertEqual(json.loads(output.getvalue()), rejection)

    def test_generated_lua_counts_connected_unique_humans_and_never_prints_token(self):
        lua = shutil.which("lua.exe") or shutil.which("lua")
        if not lua:
            packages = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Packages"
            lua = next((str(path) for path in packages.glob("DEVCOM.Lua_*/bin/lua.exe")), None)
        if not lua:
            self.skipTest("Lua interpreter is required for generated LAN probe behavior tests")
        fixture = r"""
local output, token, released, started = {}, '', false, true
local function forbidden() error('read-only inspection mutated state') end
IsServer, IsInToolsMode = function() return true end, function() return true end
GetMapName, LoadKeyValues = function() return 'template_map' end, forbidden
Convars = {
  SetStr = forbidden,
  GetStr = function(_, name) assert(name == 'survival_fishing_api_token'); return token end,
  GetFloat = function(_, name) assert(name == 'host_timescale'); return 1 end,
}
DOTA_MAX_TEAM_PLAYERS, DOTA_TEAM_SPECTATOR, DOTA_CONNECTION_STATE_CONNECTED = 10, 1, 2
PlayerResource = {
  IsValidPlayerID = function(_, id) return id ~= 4 end,
  IsFakeClient = function(_, id) return id == 3 end,
  GetTeam = function(_, id) return id == 5 and 1 or 2 end,
  GetPlayer = function(_, id) if id == 6 then return nil end; return {} end,
  GetConnectionState = function(_, id) return id == 7 and 3 or 2 end,
  GetSteamAccountID = function(_, id)
    if id == 2 then return 1000 end -- Duplicate of player 0.
    if id == 8 then return 0 end
    if id == 9 then return nil end
    return 1000 + id
  end,
  SetCustomTeamAssignment = forbidden,
}
local loading = { snapshot = function() return { started = started } end,
  is_ready = function() return released end, init = forbidden, tick = forbidden }
package.loaded['systems/startup_loading_service'] = loading
print = function(value) output[#output + 1] = value end
local inspect = function()
""" + lan.inspection_lua(NONCE) + r"""
end
local function expect(status, count)
  output = {}
  inspect()
  assert(#output == 2, 'must output only status and confirmation')
  assert(output[1] == '""" + NONCE + r""":' .. status .. ':' .. tostring(count), output[1])
  assert(output[2] == '""" + NONCE + r"""')
end
expect('waiting_players', 2)
started = false
expect('gate_not_ready', 0)
started, released = true, true
expect('admission_released', 0)
released, token = false, 'fixture-private-token-must-not-leave-process'
expect('credential_present', 0)
loading.is_party_waiting = function() return true end
expect('waiting_players', 2)
loading.is_party_waiting = nil
released = true
expect('admission_released', 0)
released = false
token = ''
package.loaded['systems/startup_loading_service'] = nil
expect('gate_not_ready', 0)
package.loaded['systems/startup_loading_service'] = loading
PlayerResource.GetConnectionState = nil
expect('gate_not_ready', 0)
io.write('LAN_PROBE_LUA_PASS\n')
"""
        script = self.root / "probe.lua"
        script.write_text(fixture, encoding="utf-8")
        result = subprocess.run([lua, str(script)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(result.stdout.strip(), "LAN_PROBE_LUA_PASS")
        self.assertNotIn("fixture-private-token", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
