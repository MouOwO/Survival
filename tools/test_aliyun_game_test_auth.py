from __future__ import annotations

import base64
from contextlib import ExitStack
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import aliyun_game_test_auth as auth


TOKEN = "unit-test-token-never-print-0123456789"


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.generated = self.root / "scripts/vscripts/tests/c6_console_generated"
        self.output = self.root / "output"
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        for name, value in (("ROOT", self.root), ("GENERATED", self.generated), ("OUTPUT", self.output)):
            self.stack.enter_context(patch.object(auth, name, value))

    def environment(self, text=None):
        path = self.root / ".env"
        path.write_text(text or ('FISHING_ACCOUNT_ID_PEPPER=must-not-enter-game\n'
                                'OTHER_SECRET=must-not-enter-game\nFISHING_API_TOKEN=' + TOKEN + '\n'),
                        encoding="utf-8")
        return path

    def test_environment_selects_only_api_token_and_rejects_missing_and_controls(self):
        self.assertEqual(auth.read_api_token(self.environment()), TOKEN)
        for value in ('FISHING_API_TOKEN=x\n', 'FISHING_ACCOUNT_ID_PEPPER=' + TOKEN,
                      'FISHING_API_TOKEN=' + TOKEN + '\tsecret'):
            with self.subTest(value=value), self.assertRaises(auth.AuthError):
                auth.read_api_token(self.environment(value))

    def test_environment_matches_windows_bom_last_key_and_literal_quote_semantics(self):
        raw = '"' + TOKEN + " $literal#suffix\\n" + '"'
        text = ('FISHING_API_TOKEN=discarded-short-value\r\n'
                'FISHING_ACCOUNT_ID_PEPPER=never-parse-this\r\n'
                'fishing_api_token=' + raw + '\r\n')
        path = self.root / ".env"
        for encoding in ("utf-8", "utf-8-sig", "utf-16", "utf-32"):
            path.write_text(text, encoding=encoding)
            with self.subTest(encoding=encoding):
                self.assertEqual(auth.read_api_token(path), raw)

    def test_unavailable_console_probe_does_not_write_a_request(self):
        with patch.object(auth.tunnel, "check", return_value={"ok": True}), \
             patch.object(auth.socket, "create_connection", side_effect=ConnectionRefusedError), \
             patch.object(auth, "send_lua") as sender:
            with self.assertRaisesRegex(auth.AuthError, "tools_console_unavailable"):
                auth.probe(self.root / "state")
            sender.assert_not_called()

    def setup_injection(self, sender):
        self.stack.enter_context(patch.object(auth, "probe"))
        self.stack.enter_context(patch.object(auth, "ready"))
        self.stack.enter_context(patch.object(auth, "ignored"))
        self.stack.enter_context(patch.object(auth, "require_ntfs"))
        self.stack.enter_context(patch.object(auth, "send_lua", side_effect=sender))

    def test_token_is_only_in_acl_protected_kv_and_removed_after_success(self):
        captured = []
        def protected(path):
            self.assertEqual(path.read_bytes(), b"")
            captured.append(path)
        def send(code, nonce, request_path):
            self.assertEqual(len(captured), 1)
            self.assertIn(TOKEN, captured[0].read_text(encoding="utf-8"))
            self.assertNotIn(TOKEN, code + nonce + str(request_path))
            self.assertNotIn("must-not-enter-game", code + captured[0].read_text(encoding="utf-8"))
            self.assertIn("LoadKeyValues", code)
            self.assertIn("Convars:SetStr", code)
            self.assertIn(auth.recovery_lua(), code)
        self.setup_injection(send)
        self.stack.enter_context(patch.object(auth, "private_acl", side_effect=protected))
        result = auth.inject(self.root / "state", self.environment())
        self.assertTrue(result["temporary_credential_removed"])
        self.assertFalse(captured[0].exists())

    def test_console_failure_always_removes_temporary_credential(self):
        self.setup_injection(Mock(side_effect=auth.AuthError("tools_server_confirmation_missing")))
        self.stack.enter_context(patch.object(auth, "private_acl"))
        with self.assertRaisesRegex(auth.AuthError, "tools_server_confirmation_missing"):
            auth.inject(self.root / "state", self.environment())
        self.assertEqual(list(self.generated.glob("*.kv")), [])

    def test_acl_failure_happens_before_secret_write_and_cleans_empty_file(self):
        sender = Mock()
        self.setup_injection(sender)
        def rejected(path):
            self.assertEqual(path.read_bytes(), b"")
            raise auth.AuthError("temporary_auth_acl_failed")
        self.stack.enter_context(patch.object(auth, "private_acl", side_effect=rejected))
        with self.assertRaisesRegex(auth.AuthError, "temporary_auth_acl_failed"):
            auth.inject(self.root / "state", self.environment())
        sender.assert_not_called()
        self.assertEqual(list(self.generated.glob("*.kv")), [])

    def run_windows_acl_script(self, path, script):
        read_path = r"""
$ErrorActionPreference='Stop'
$reader=[IO.StreamReader]::new([Console]::OpenStandardInput(),[Text.UTF8Encoding]::new($false,$true),$false)
try { $path=$reader.ReadToEnd() } finally { $reader.Dispose() }
"""
        powershell = (Path(os.environ.get("SystemRoot", "C:/Windows")) /
                      "System32/WindowsPowerShell/v1.0/powershell.exe")
        result = subprocess.run(
            [str(powershell), "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand",
             base64.b64encode((read_path + script).encode("utf-16-le")).decode("ascii")],
            input=str(path).encode("utf-8"), capture_output=True, timeout=15,
            creationflags=subprocess.CREATE_NO_WINDOW)
        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
        return json.loads(result.stdout)

    def inspect_windows_acl(self, path):
        # Independently read the ACL; this child never modifies it.
        return self.run_windows_acl_script(path, r"""
$acl=[IO.File]::GetAccessControl($path)
$rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | ForEach-Object {
  @{sid=$_.IdentityReference.Value; rights=[int]$_.FileSystemRights;
    access=$_.AccessControlType.ToString(); inherited=$_.IsInherited}
})
$result=@{protected=$acl.AreAccessRulesProtected; rules=$rules;
  current=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;
  owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value;
  full_control=[int][Security.AccessControl.FileSystemRights]::FullControl}
[Console]::Out.Write(($result | ConvertTo-Json -Depth 4 -Compress))
""")

    def assert_private_windows_acl(self, actual, original_owner):
        expected = {actual["current"], "S-1-5-18", "S-1-5-32-544"}
        self.assertTrue(actual["protected"])
        self.assertIn(original_owner, expected)
        self.assertEqual(actual["owner"], original_owner)
        self.assertEqual(len(actual["rules"]), len(expected))
        self.assertEqual({rule["sid"] for rule in actual["rules"]}, expected)
        for rule in actual["rules"]:
            self.assertFalse(rule["inherited"])
            self.assertEqual(rule["access"], "Allow")
            self.assertEqual(rule["rights"], actual["full_control"])

    @unittest.skipUnless(os.name == "nt", "Windows ACLs require Windows")
    def test_private_acl_hidden_child_handles_unicode_spaces_and_restricts_actual_dacl(self):
        path = self.root / "ACL probe \u6743\u9650 \u6d4b\u8bd5.kv"
        path.touch()
        original = self.inspect_windows_acl(path)
        auth.private_acl(path)
        self.assertEqual(path.read_bytes(), b"")
        self.assert_private_windows_acl(self.inspect_windows_acl(path), original["owner"])

    @unittest.skipUnless(os.name == "nt", "Windows ACLs require Windows")
    def test_private_acl_succeeds_for_current_owner_without_take_ownership_permission(self):
        path = self.root / "owner-without-write-owner.kv"
        path.touch()
        preparation = self.run_windows_acl_script(path, r"""
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$existing=[IO.File]::GetAccessControl($path)
$acl=[Security.AccessControl.FileSecurity]::new()
if ($existing.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) {
  $acl.SetOwner($sid)
}
$acl.SetAccessRuleProtection($true,$false)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'TakeOwnership','Deny'))
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'Modify','Allow'))
[IO.File]::SetAccessControl($path,$acl)

# Reproduce the original combined ownership/DACL write against the empty file.
# Current ownership permits DACL changes, while the deny blocks WRITE_OWNER.
$legacy=[Security.AccessControl.FileSecurity]::new()
$legacy.SetOwner($sid)
$legacy.SetAccessRuleProtection($true,$false)
$allowed=@($sid.Value,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique
foreach ($value in $allowed) {
  $identity=[Security.Principal.SecurityIdentifier]::new($value)
  $legacy.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'))
}
$blocked=$false
try { [IO.File]::SetAccessControl($path,$legacy) } catch {
  if ($_.Exception.GetBaseException().HResult -ne -2147024891) { throw }
  $blocked=$true
}
[Console]::Out.Write((@{legacy_denied=$blocked} | ConvertTo-Json -Compress))
""")
        if not preparation["legacy_denied"]:
            self.skipTest("Enabled ownership privilege bypassed WRITE_OWNER deny; regression precondition unavailable")
        restricted = self.inspect_windows_acl(path)
        self.assertEqual(restricted["owner"], restricted["current"])
        self.assertTrue(any(rule["sid"] == restricted["current"] and rule["access"] == "Deny"
                            and rule["rights"] == 0x80000 for rule in restricted["rules"]))
        self.assertEqual(path.read_bytes(), b"")
        auth.private_acl(path)
        self.assertEqual(path.read_bytes(), b"")
        self.assert_private_windows_acl(self.inspect_windows_acl(path), restricted["owner"])

    def test_private_acl_only_exposes_allowlisted_failure_stage_and_numeric_code(self):
        cases = [
            (1, f"PRIVATE_ACL_FAILED|{stage}|80070005".encode(),
             f"temporary_auth_acl_failed:{stage}:0x80070005")
            for stage in ("read_path", "build_acl", "set_acl", "verify_acl")
        ]
        cases.extend((code, output, "temporary_auth_acl_failed") for code, output in (
            (1, TOKEN.encode()),
            (1, b"PRIVATE_ACL_FAILED|unknown_stage|80070005"),
            (1, b"PRIVATE_ACL_FAILED|set_acl|8007000a"),
            (1, b"PRIVATE_ACL_FAILED|set_acl|80070005\n" + TOKEN.encode()),
            (1, b"PRIVATE_ACL_READY"),
            (0, b"PRIVATE_ACL_READY\n" + TOKEN.encode()),
            (0, b""),
        ))
        for code, output, expected in cases:
            with self.subTest(code=code, output=output), patch.object(
                    auth.subprocess, "run", return_value=subprocess.CompletedProcess(
                        [], code, stdout=output, stderr=TOKEN.encode())):
                with self.assertRaises(auth.AuthError) as failure:
                    auth.private_acl(self.root / "empty.kv")
                self.assertEqual(str(failure.exception), expected)
                self.assertNotIn(TOKEN, str(failure.exception))

    def test_private_acl_timeout_and_unavailable_powershell_hide_raw_errors(self):
        for error, expected in (
            (subprocess.TimeoutExpired(["powershell.exe", TOKEN], 15,
                                       output=TOKEN.encode(), stderr=TOKEN.encode()), "timeout"),
            (OSError(TOKEN), "powershell_unavailable"),
        ):
            with self.subTest(expected=expected), patch.object(auth.subprocess, "run", side_effect=error):
                with self.assertRaises(auth.AuthError) as failure:
                    auth.private_acl(self.root / "empty.kv")
                self.assertEqual(str(failure.exception), "temporary_auth_acl_failed:" + expected)
                self.assertNotIn(TOKEN, str(failure.exception))

    def test_check_acl_is_local_secret_free_and_cleans_only_its_empty_probe(self):
        self.generated.mkdir(parents=True)
        sentinel = self.generated / "existing-file.kv"
        sentinel.touch()
        captured = []
        forbidden_calls = []
        for target, name in ((auth, "read_api_token"), (auth, "ready"), (auth, "probe"),
                             (auth, "send_lua"), (auth.tunnel, "check"),
                             (auth.socket, "create_connection"), (auth.http.client, "HTTPConnection")):
            forbidden_calls.append(self.stack.enter_context(patch.object(
                target, name, side_effect=AssertionError("ACL check must be local and secret-free"))))
        self.stack.enter_context(patch.object(auth, "ignored"))
        self.stack.enter_context(patch.object(auth, "require_ntfs"))

        def inspect_empty(path):
            self.assertEqual(path.parent, self.generated)
            self.assertEqual(path.read_bytes(), b"")
            captured.append(path)

        with patch.object(auth, "private_acl", side_effect=inspect_empty):
            result = auth.check_acl()
        self.assertEqual(result, {"ok": True, "status": "temporary_auth_acl_ready",
                                  "temporary_file_removed": True})
        self.assertEqual(len(captured), 1)
        self.assertFalse(captured[0].exists())
        self.assertEqual(list(self.generated.iterdir()), [sentinel])

        def reject_empty(path):
            inspect_empty(path)
            raise auth.AuthError("temporary_auth_acl_failed:set_acl:0x80070005")

        with patch.object(auth, "private_acl", side_effect=reject_empty):
            with self.assertRaisesRegex(auth.AuthError, "temporary_auth_acl_failed:set_acl:0x80070005"):
                auth.check_acl()
        self.assertEqual(len(captured), 2)
        self.assertFalse(captured[1].exists())
        self.assertEqual(list(self.generated.iterdir()), [sentinel])
        for forbidden in forbidden_calls:
            forbidden.assert_not_called()

    def test_unready_backend_never_creates_credential_file(self):
        self.setup_injection(Mock())
        with patch.object(auth, "ready", side_effect=auth.AuthError("authenticated_backend_not_ready")), \
             patch.object(auth, "private_acl") as acl:
            with self.assertRaisesRegex(auth.AuthError, "authenticated_backend_not_ready"):
                auth.inject(self.root / "state", self.environment())
            acl.assert_not_called()
        self.assertFalse(self.generated.exists())

    def test_non_tools_probe_refusal_never_reads_environment(self):
        with patch.object(auth, "probe", side_effect=auth.AuthError("tools_server_confirmation_missing")), \
             patch.object(auth, "read_api_token") as reader:
            with self.assertRaises(auth.AuthError):
                auth.inject(self.root / "state", self.root / ".env")
            reader.assert_not_called()
        for required in ("IsServer()", "IsInToolsMode()", "'template_map'", "Convars.SetStr", "host_timescale"):
            self.assertIn(required, auth.capabilities())

    def test_console_output_is_captured_and_only_exact_nonce_is_accepted(self):
        nonce = "NONSECRET_CONFIRMATION"
        command = "print('" + nonce + "')"
        with patch.object(auth, "ignored"), patch.object(auth.shutil, "which", return_value="node.exe"), \
             patch.object(auth.subprocess, "run") as runner:
            runner.return_value = Mock(returncode=0, stdout=("old-history " + TOKEN + "\n" + nonce + "\n").encode())
            auth.send_lua(command, nonce, self.output / "request.json")
            self.assertTrue(runner.call_args.kwargs["capture_output"])
            self.assertNotIn(TOKEN, str(runner.call_args.args))
            self.assertFalse((self.output / "request.json").exists())
            runner.return_value = Mock(returncode=0, stdout=("echo " + nonce + "\n").encode())
            with self.assertRaisesRegex(auth.AuthError, "tools_server_confirmation_missing"):
                auth.send_lua(command, nonce, self.output / "request2.json")

    def test_symlink_path_is_rejected_before_token_read(self):
        with patch.object(Path, "exists", return_value=True), \
             patch.object(Path, "lstat", return_value=Mock(st_mode=0o120777, st_file_attributes=0)), \
             patch.object(Path, "open") as opener:
            with self.assertRaisesRegex(auth.AuthError, "reparse_path_refused"):
                auth.read_api_token(self.root / ".env")
            opener.assert_not_called()

    def test_recovery_lua_preserves_pending_loaded_and_pure_mode_state(self):
        lua = shutil.which("lua.exe") or shutil.which("lua")
        if not lua:
            packages = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Packages"
            lua = next((str(path) for path in packages.glob("DEVCOM.Lua_*/bin/lua.exe")), None)
        if not lua:
            self.skipTest("Lua interpreter is required for the generated recovery behavior test")
        fixture = r"""
local selected_mode, auth_calls, load_calls, tick_calls = nil, {}, {}, 0
local authenticated, pending_auth, pending_load, loaded = {}, {}, {}, {}
DOTA_MAX_TEAM_PLAYERS, DOTA_TEAM_SPECTATOR = 10, 1
PlayerResource = {
  IsValidPlayerID = function(_, id) return id ~= 5 end,
  IsFakeClient = function(_, id) return id == 4 end,
  GetTeam = function(_, id) return id == 7 and 1 or 2 end,
  GetPlayer = function(_, id) return id ~= 8 and {} or nil end,
  GetSteamAccountID = function(_, id) return id == 6 and 0 or 9000 + id end,
}
local function forbidden() error('recovery must not reset or reinitialize any game service') end
local profiles = {
  init = forbidden, reset = forbidden,
  is_authenticated_for_account = function(id, account)
    assert(account == tostring(9000 + id), 'authentication must use the current Steam account')
    return authenticated[id] == true
  end,
  is_authenticating = function(id) return pending_auth[id] == true end,
  authenticate_player = function(id, reason)
    assert(not authenticated[id] and not pending_auth[id], 'authentication retry replaced healthy state')
    assert(reason == 'ecs_test_auth_ready')
    auth_calls[#auth_calls + 1] = id
    pending_auth[id] = true
  end,
  get_profile = function(id) return loaded[id] end,
  is_loading = function(id) return pending_load[id] == true end,
  load_player = function(id, reason)
    assert(selected_mode ~= nil, 'profile requested before choosing mode')
    assert(authenticated[id], 'profile requested before authentication completed')
    assert(not loaded[id] and not pending_load[id], 'existing profile/pending load overwritten')
    assert(reason == 'ecs_test_auth_ready')
    load_calls[#load_calls + 1] = { id = id, mode = selected_mode }
    pending_load[id] = true
  end,
}
local setup = { init = forbidden, reset = forbidden,
  select_mode = forbidden, get_mode = function() return selected_mode end,
  is_mode_selected = function() return selected_mode ~= nil end }
package.loaded['systems/player_profile_service'] = profiles
package.loaded['systems/match_setup_service'] = setup
package.loaded['systems/startup_loading_service'] = {
  init = forbidden, reset = forbidden, tick = function() tick_calls = tick_calls + 1 end,
}
local recovery = function()
""" + auth.recovery_lua() + r"""
end
local function reset(mode)
  selected_mode, auth_calls, load_calls, tick_calls = mode, {}, {}, 0
  authenticated, pending_auth, pending_load, loaded = {}, {}, {}, {}
  -- 0: missing auth; 1: pending auth; 2: authed/missing profile;
  -- 3: existing profile; 4: fake; 5: invalid; 6: no Steam account;
  -- 7: spectator; 8: no player entity; 9: authed/pending profile load.
  pending_auth[1] = true
  authenticated[2], authenticated[3], authenticated[9] = true, true, true
  pending_load[9] = true
  loaded[3] = { mode = mode or 'pure', revision = 42, permanent_items = { 'keep' } }
end
reset(nil)
local original = loaded[3]
recovery()
assert(#auth_calls == 1 and auth_calls[1] == 0, 'only a missing human auth may start')
assert(#load_calls == 0, 'mode-free entry must authenticate without loading a profile')
assert(tick_calls == 1 and loaded[3] == original and original.revision == 42)
recovery()
assert(#auth_calls == 1 and #load_calls == 0 and tick_calls == 2,
  'repeated recovery must not supersede in-flight authentication')

-- Authentication may finish asynchronously; a later recovery respects selected
-- pure mode and never replaces the existing pure profile with account defaults.
authenticated[0], pending_auth[0], selected_mode = true, false, 'pure'
recovery()
assert(#load_calls == 2 and load_calls[1].id == 0 and load_calls[2].id == 2)
assert(load_calls[1].mode == 'pure' and load_calls[2].mode == 'pure')
assert(loaded[3] == original and original.permanent_items[1] == 'keep')
recovery()
assert(#load_calls == 2 and #auth_calls == 1 and pending_auth[1],
  'recovery must preserve both kinds of pending request')
loaded[0], loaded[2], loaded[9] = { revision = 1 }, { revision = 2 }, { revision = 3 }
pending_load[0], pending_load[2], pending_load[9] = nil, nil, nil
recovery()
assert(#load_calls == 2 and loaded[3] == original, 'completed profiles must remain cached')

-- Conventional mode uses the same missing-only policy, without special default
-- loading or an automatic mode switch inserted by the injection helper.
reset('standard')
recovery()
assert(#auth_calls == 1 and #load_calls == 1 and load_calls[1].id == 2)
assert(load_calls[1].mode == 'standard' and loaded[3].mode == 'standard')

-- Early attachment must not require/init the loading module merely to tick it.
package.loaded['systems/startup_loading_service'] = nil
recovery()
assert(tick_calls == 1 and #auth_calls == 1 and #load_calls == 1)
print('AUTH_RECOVERY_LUA_PASS')
"""
        script = self.root / "recovery.lua"
        script.write_text(fixture, encoding="utf-8")
        result = subprocess.run([lua, str(script)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(result.stdout.strip(), "AUTH_RECOVERY_LUA_PASS")


if __name__ == "__main__":
    unittest.main()
