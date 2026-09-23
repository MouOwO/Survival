from __future__ import annotations

from contextlib import ExitStack
import json
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
