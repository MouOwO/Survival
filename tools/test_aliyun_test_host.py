from contextlib import ExitStack, nullcontext, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import aliyun_test_host as host


SECRET = "synthetic-test-token-never-echo-0123456789"
EXPECTED = "SHA256:" + "A" * 43
OTHER = "SHA256:" + "B" * 43


def completed(output=b"", code=0, error=b""):
    return subprocess.CompletedProcess([], code, output, error)


class HostTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "game/dota_addons/survival"
        self.root.mkdir(parents=True)
        self.key = self.root / "test-private-key"
        self.key.touch()  # Empty synthetic fixture only.
        self.environment = self.root / "test.env"
        self.environment.touch()
        self.settings = {"ssh_key": self.key, "environment": self.environment,
                         "known_hosts": self.root / "known-hosts"}
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(host, "ROOT", self.root))

    def patch(self, obj, name, **kwargs):
        return self.stack.enter_context(patch.object(obj, name, **kwargs))

    def identity_outputs(self, *outputs):
        self.patch(host.shutil, "which", side_effect=lambda name: name)
        return self.patch(host, "run_public", side_effect=outputs)

    def test_identity_requires_matching_key_in_current_agent(self):
        run = self.identity_outputs(completed(("256 " + EXPECTED + " fixture\n").encode()),
                                    completed(("256 " + OTHER + " other\n256 " + EXPECTED + " wanted\n").encode()))
        self.assertEqual(host.ssh_identity(self.key), EXPECTED)
        self.assertEqual(run.call_args_list[1].args[0], ["ssh-add.exe", "-l"])

    def test_empty_or_wrong_agent_identity_has_fixed_actionable_error(self):
        self.patch(host.shutil, "which", side_effect=lambda name: name)
        for output, code in ((b"The agent has no identities.", 1),
                             (("256 " + OTHER + " " + SECRET).encode(), 0)):
            with patch.object(host, "run_public", side_effect=[
                    completed(("256 " + EXPECTED).encode()), completed(output, code)]):
                with self.assertRaisesRegex(host.HostError, "ssh_key_not_loaded_in_current_user_agent") as raised:
                    host.ssh_identity(self.key)
                self.assertNotIn(SECRET, str(raised.exception))

    def test_agent_service_and_bad_key_errors_do_not_echo_tool_output(self):
        self.patch(host.shutil, "which", side_effect=lambda name: name)
        for results, code in (([completed(("256 " + EXPECTED).encode()),
                               completed(SECRET.encode(), 2, SECRET.encode())], "ssh_agent_unavailable"),
                              ([completed(SECRET.encode(), 1, SECRET.encode())], "ssh_key_fingerprint_unavailable")):
            with patch.object(host, "run_public", side_effect=results):
                with self.assertRaises(host.HostError) as raised:
                    host.ssh_identity(self.key)
                self.assertEqual(str(raised.exception), code)
                self.assertNotIn(SECRET, str(raised.exception))

    def credential_fixture(self):
        self.patch(host.sys, "stdin", new=Mock(isatty=lambda: True))
        self.patch(host.config, "load", return_value=self.settings)
        password = self.patch(host.getpass, "getpass", return_value=SECRET)
        for name in ("no_reparse", "ignored", "require_ntfs"):
            self.patch(host.auth, name)
        acl = self.patch(host.auth, "private_acl")
        save = self.patch(host.config, "save", return_value=self.settings)
        target = self.root / "output/ecs_backend_work/game-test.env"
        return target, password, acl, save

    def test_credential_applies_acl_while_empty_before_writing_only_expected_field(self):
        target, _, acl, save = self.credential_fixture()
        order = []

        def protect(path):
            self.assertEqual(path, target)
            self.assertEqual(path.read_bytes(), b"")
            order.append("acl")

        def configured(values, root):
            self.assertEqual(order, ["acl"])
            self.assertEqual(target.read_text(encoding="utf-8"), "FISHING_API_TOKEN=" + SECRET + "\n")
            self.assertEqual(values, {"environment": target})
            self.assertEqual(root, self.root)
            order.append("saved")

        acl.side_effect, save.side_effect = protect, configured
        result = host.create_credential()
        self.assertTrue(result["ok"])
        self.assertEqual(order, ["acl", "saved"])
        self.assertNotIn(SECRET, json.dumps(result))
        self.assertEqual(self.environment.read_bytes(), b"")

    def test_acl_failure_removes_empty_file_and_never_saves_configuration(self):
        target, _, acl, save = self.credential_fixture()

        def fail(path):
            self.assertEqual(path.read_bytes(), b"")
            raise host.auth.AuthError("temporary_auth_acl_failed")

        acl.side_effect = fail
        with self.assertRaises(host.auth.AuthError):
            host.create_credential()
        self.assertFalse(target.exists())
        save.assert_not_called()

    def test_config_write_failure_removes_created_private_credential(self):
        target, _, _, save = self.credential_fixture()
        save.side_effect = host.config.ConfigError("local_config_write_failed")
        with self.assertRaises(host.config.ConfigError):
            host.create_credential()
        self.assertFalse(target.exists())

    def test_existing_managed_environment_is_never_overwritten_or_prompted(self):
        target, prompt, acl, save = self.credential_fixture()
        target.parent.mkdir(parents=True)
        target.write_bytes(b"existing-secret-preserve")
        with self.assertRaisesRegex(host.HostError, "managed_credential_already_exists"):
            host.create_credential()
        self.assertEqual(target.read_bytes(), b"existing-secret-preserve")
        prompt.assert_not_called()
        acl.assert_not_called()
        save.assert_not_called()

    def test_invalid_config_is_rejected_before_credential_prompt_or_write(self):
        target, prompt, acl, _ = self.credential_fixture()
        with patch.object(host.config, "load", side_effect=host.config.ConfigError("local_config_schema_invalid")):
            with self.assertRaises(host.config.ConfigError):
                host.create_credential()
        prompt.assert_not_called()
        acl.assert_not_called()
        self.assertFalse(target.exists())

    def test_offline_checks_never_connect_to_tunnel_or_http(self):
        (self.root / "maps").mkdir()
        (self.root / "maps/template_map.vpk").touch()
        dota = self.root.parents[1] / "bin/win64/dota2.exe"
        dota.parent.mkdir(parents=True)
        dota.touch()
        self.patch(host.config, "load", return_value=self.settings)
        self.patch(host.shutil, "which", return_value="synthetic-tool.exe")
        self.patch(host.tunnel, "verify_known_hosts")
        self.patch(host, "ssh_identity", return_value=EXPECTED)
        self.patch(host.auth, "read_api_token", return_value=SECRET)
        self.patch(host.auth, "check_acl", return_value={"ok": True})
        self.patch(host, "asset_identity", return_value={"map_sha256": "a" * 64})
        connect = self.patch(host.tunnel, "connect", side_effect=AssertionError("network forbidden"))
        ready = self.patch(host.auth, "ready", side_effect=AssertionError("network forbidden"))
        probe = self.patch(host.auth, "probe", side_effect=AssertionError("game forbidden"))
        result = host.check()
        self.assertTrue(result["ok"])
        self.assertNotIn(SECRET, json.dumps(result))
        connect.assert_not_called()
        ready.assert_not_called()
        probe.assert_not_called()
        for error, code in ((PermissionError(SECRET), "local_file_access_denied"),
                            (subprocess.TimeoutExpired([SECRET], 15), "local_command_timeout")):
            with self.subTest(code=code), patch.object(host.auth, "read_api_token", side_effect=error):
                failed = host.check()
            self.assertFalse(failed["ok"])
            environment = next(item for item in failed["checks"] if item["check"] == "api_environment")
            self.assertEqual(environment["error"], code)
            self.assertNotIn(SECRET, json.dumps(failed))

    def test_online_check_stops_before_any_network_when_local_checks_fail(self):
        failure = {"ok": False, "checks": [{"check": "ssh_agent_identity", "ok": False}]}
        self.patch(host, "check", return_value=failure)
        connect = self.patch(host.tunnel, "connect")
        ready = self.patch(host.auth, "ready")
        self.assertEqual(host.online_check(), failure)
        connect.assert_not_called()
        ready.assert_not_called()

    def test_online_ready_follows_local_checks_and_owned_tunnel_without_game_injection(self):
        order = []
        self.patch(host, "check", side_effect=lambda: order.append("local") or {"ok": True, "build": {}})
        self.patch(host.config, "load", return_value=self.settings)
        self.patch(host.tunnel, "state_lock", return_value=nullcontext())
        self.patch(host.tunnel, "connect", side_effect=lambda *args: order.append("tunnel") or {"ok": True})
        self.patch(host.auth, "read_api_token", side_effect=lambda path: order.append("token") or SECRET)
        ready = self.patch(host.auth, "ready", side_effect=lambda token: order.append("ready"))
        inject = self.patch(host.auth, "inject", side_effect=AssertionError("game forbidden"))
        result = host.online_check()
        self.assertEqual(order, ["local", "tunnel", "token", "ready"])
        ready.assert_called_once_with(SECRET)
        inject.assert_not_called()
        self.assertNotIn(SECRET, json.dumps(result))
        self.assertEqual(result["status"], "backend_ready_game_not_yet_authenticated")

    def test_main_hides_exception_command_stderr_and_secret(self):
        output = io.StringIO()
        with patch.object(host, "check", side_effect=subprocess.CalledProcessError(
                1, ["tool", SECRET], output=SECRET, stderr=SECRET)), \
             patch("sys.argv", ["host", "check"]), redirect_stdout(output):
            self.assertEqual(host.main(), 1)
        self.assertEqual(json.loads(output.getvalue()), {"ok": False, "error": "local_host_setup_failed"})
        self.assertNotIn(SECRET, output.getvalue())


if __name__ == "__main__":
    unittest.main()
