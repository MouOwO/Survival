from __future__ import annotations

import base64
from contextlib import ExitStack, contextmanager
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

import aliyun_test_connection as tunnel


class TunnelTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows byte lock")
    def test_live_byte_lock_reports_busy_instead_of_read_permission_error(self):
        with tunnel.state_lock(self.state):
            with self.assertRaisesRegex(tunnel.TunnelError, "tunnel_operation_in_progress"):
                with tunnel.state_lock(self.state):
                    self.fail("second helper acquired the active lock")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state.json"

    def write_state(self):
        command = "ssh.exe -N recorded-args"
        state = {"version": 1, "pid": 41, "created": 123456,
                 "executable": "c:/windows/system32/openssh/ssh.exe",
                 "command_digest": tunnel.command_digest(command)}
        self.state.write_text(json.dumps(state), encoding="utf-8")
        return state, command

    @contextmanager
    def connect_fixture(self, *, old_identity=None, old_command="ssh.exe -N recorded-args",
                        old_error=None, free=True):
        """Simulate SSH and Windows handles without touching real processes."""
        key, hosts = self.root / "fixture-key", self.root / "fixture-known-hosts"
        key.write_text("unused fixture", encoding="utf-8")
        command = tunnel.ssh_command(str(Path("ssh.exe").resolve()), key.resolve(), hosts.resolve())
        new_command = subprocess.list2cmdline(command)
        old_handle, new_handle = Mock(), Mock()
        old_handle.identity.return_value = old_identity
        new_handle.identity.return_value = {
            "created": 654321, "executable": "c:/windows/system32/openssh/ssh.exe"}
        child = Mock(pid=42)
        child.poll.return_value = None

        def process_handle(pid, **kwargs):
            if pid == 41 and old_error:
                raise tunnel.TunnelError(old_error)
            wrapper = MagicMock()
            wrapper.__enter__.return_value = old_handle if pid == 41 else new_handle
            return wrapper

        with ExitStack() as stack:
            stack.enter_context(patch.object(tunnel, "verify_known_hosts"))
            stack.enter_context(patch.object(tunnel, "ensure_agent_running"))
            stack.enter_context(patch.object(tunnel.shutil, "which", return_value="ssh.exe"))
            availability = stack.enter_context(patch.object(tunnel, "port_free", return_value=free))
            factory = stack.enter_context(patch.object(tunnel, "ProcessHandle", side_effect=process_handle))
            process_command = stack.enter_context(patch.object(
                tunnel, "process_command", side_effect=lambda pid: old_command if pid == 41 else new_command))
            launch = stack.enter_context(patch.object(tunnel.subprocess, "Popen", return_value=child))
            stack.enter_context(patch.object(tunnel, "health", return_value=True))
            stack.enter_context(patch.object(tunnel, "listener_owned", return_value=True))
            yield {"key": key, "hosts": hosts, "old": old_handle, "new": new_handle,
                   "child": child, "launch": launch, "factory": factory,
                   "free": availability, "process_command": process_command}

    def test_host_key_must_match_console_pin_and_exact_target(self):
        raw = b"test-public-key"
        pin = "SHA256:" + base64.b64encode(hashlib.sha256(raw).digest()).decode().rstrip("=")
        encoded = base64.b64encode(raw).decode()
        hosts = self.root / "known_hosts"
        with patch.object(tunnel, "HOST_FINGERPRINT", pin):
            hosts.write_text(f"{tunnel.ECS_HOST} ssh-ed25519 {encoded}\n", encoding="utf-8")
            tunnel.verify_known_hosts(hosts)
            for value in (f"other-host ssh-ed25519 {encoded}",
                          f"{tunnel.ECS_HOST} ssh-rsa {encoded}",
                          f"{tunnel.ECS_HOST} ssh-ed25519 YWJj",
                          f"{tunnel.ECS_HOST} ssh-ed25519 {encoded}\nother-host ssh-ed25519 {encoded}"):
                hosts.write_text(value, encoding="utf-8")
                with self.subTest(value=value), self.assertRaisesRegex(tunnel.TunnelError, "host_key_pin_invalid"):
                    tunnel.verify_known_hosts(hosts)

    def test_ssh_only_forwards_loopback_with_pinned_authentication(self):
        command = tunnel.ssh_command("ssh.exe", Path("login-key"), Path("folder with spaces/known_hosts"))
        self.assertIn("127.0.0.1:8765:127.0.0.1:8765", command)
        for option in ("StrictHostKeyChecking=yes", "BatchMode=yes", "ExitOnForwardFailure=yes",
                       "IdentitiesOnly=yes", "PasswordAuthentication=no", "GlobalKnownHostsFile=none"):
            self.assertIn(option, command)
        self.assertEqual(command[command.index("-F") + 1], "none")
        self.assertIn('UserKnownHostsFile="folder with spaces/known_hosts"', command)
        self.assertNotIn("0.0.0.0", " ".join(command))
        self.assertNotIn("FISHING_API_TOKEN", " ".join(command))

    def test_connection_restarts_windows_agent_without_exposing_its_output(self):
        with patch.object(tunnel, "agent_failure_code", side_effect=[
                "ssh_agent_unavailable", "ssh_agent_unavailable",
                "ssh_public_key_authentication_failed"]), \
             patch.object(tunnel.time, "sleep"), \
             patch.object(tunnel.subprocess, "run", return_value=Mock(returncode=0)) as run:
            tunnel.ensure_agent_running()
        self.assertEqual(run.call_args.args[0], ["sc.exe", "start", "ssh-agent"])
        self.assertTrue(run.call_args.kwargs["capture_output"])

    def test_running_agent_is_not_restarted(self):
        with patch.object(tunnel, "agent_failure_code", return_value="ssh_public_key_authentication_failed"), \
             patch.object(tunnel.subprocess, "run") as run:
            tunnel.ensure_agent_running()
        run.assert_not_called()

    def test_public_key_failure_distinguishes_stopped_or_empty_agent(self):
        with patch.object(tunnel.shutil, "which", return_value="ssh-add.exe"), \
             patch.object(tunnel.subprocess, "run") as run:
            for code, expected in ((2, "ssh_agent_unavailable"),
                                   (1, "ssh_key_not_loaded_in_current_user_agent"),
                                   (0, "ssh_public_key_authentication_failed")):
                with self.subTest(code=code):
                    run.return_value.returncode = code
                    run.return_value.stderr = b""
                    self.assertEqual(tunnel.agent_failure_code(), expected)

    def test_busy_port_does_not_launch_or_stop_any_process(self):
        key = self.root / "key"
        key.write_text("unused fixture", encoding="utf-8")
        with patch.object(tunnel, "verify_known_hosts"), patch.object(tunnel.shutil, "which", return_value="ssh.exe"), \
             patch.object(tunnel, "port_free", return_value=False), patch.object(tunnel.subprocess, "Popen") as launch, \
             patch.object(tunnel, "ProcessHandle") as process:
            with self.assertRaisesRegex(tunnel.TunnelError, "local_port_8765_in_use"):
                tunnel.connect(self.state, key, self.root / "known_hosts")
            launch.assert_not_called()
            process.assert_not_called()

    def test_stop_checks_creation_identity_before_terminating_handle(self):
        state, command = self.write_state()
        for field, changed in (("created", 999999), ("executable", "other.exe")):
            identity = {"created": state["created"], "executable": state["executable"], field: changed}
            handle = Mock()
            handle.identity.return_value = identity
            with patch.object(tunnel, "ProcessHandle") as factory, \
                 patch.object(tunnel, "process_command", return_value=command):
                factory.return_value.__enter__.return_value = handle
                with self.subTest(field=field), self.assertRaisesRegex(tunnel.TunnelError, "tunnel_owner_mismatch"):
                    tunnel.stop(self.state)
                handle.terminate.assert_not_called()
                self.assertTrue(self.state.exists())

    def test_matching_pid_with_different_command_is_not_owned(self):
        state, _ = self.write_state()
        with self.assertRaisesRegex(tunnel.TunnelError, "tunnel_owner_mismatch"):
            tunnel.validate_owned(state, state, "ssh.exe someone-elses-tunnel")

    def test_stop_terminates_only_validated_process_handle(self):
        state, command = self.write_state()
        handle = Mock()
        handle.identity.return_value = state
        with patch.object(tunnel, "ProcessHandle") as factory, \
             patch.object(tunnel, "process_command", return_value=command):
            factory.return_value.__enter__.return_value = handle
            self.assertEqual(tunnel.stop(self.state), {"ok": True, "status": "stopped"})
            factory.assert_called_once_with(41, stopping=True)
            handle.terminate.assert_called_once_with()
            self.assertFalse(self.state.exists())

    def test_check_refuses_unrelated_listener_even_when_http_would_be_healthy(self):
        state, command = self.write_state()
        handle = Mock()
        handle.identity.return_value = state
        with patch.object(tunnel, "ProcessHandle") as factory, \
             patch.object(tunnel, "process_command", return_value=command), \
             patch.object(tunnel, "listener_owned", return_value=False), patch.object(tunnel, "health") as health:
            factory.return_value.__enter__.return_value = handle
            with self.assertRaisesRegex(tunnel.TunnelError, "owned_tunnel_listener_missing"):
                tunnel.check(self.state)
            health.assert_not_called()

    def test_identity_diagnostics_never_expose_command_or_secret_output(self):
        error = subprocess.CalledProcessError(1, ["internal", "sensitive-fixture"], stderr=b"sensitive-fixture")
        with patch.object(tunnel.subprocess, "run", side_effect=error):
            with self.assertRaises(tunnel.TunnelError) as raised:
                tunnel.process_command(123)
        self.assertEqual(str(raised.exception), "process_identity_unavailable")
        self.assertIsNone(raised.exception.__cause__)

    def test_connect_recovers_reused_pid_metadata_only_when_port_is_free(self):
        for field, changed in (("created", 999999), ("executable", "other.exe"),
                               ("command", "unrelated.exe --private-fixture")):
            with self.subTest(field=field):
                state, command = self.write_state()
                identity = {"created": state["created"], "executable": state["executable"]}
                if field == "command":
                    command = changed
                else:
                    identity[field] = changed
                log = self.state.with_suffix(".stderr")
                log.write_text("old log", encoding="utf-8")
                with self.connect_fixture(old_identity=identity, old_command=command) as fixture:
                    result = tunnel.connect(self.state, fixture["key"], fixture["hosts"])
                    self.assertEqual(result["status"], "connected")
                    self.assertEqual(json.loads(self.state.read_text())["pid"], 42)
                    fixture["old"].terminate.assert_not_called()
                    fixture["new"].terminate.assert_not_called()
                    fixture["child"].terminate.assert_not_called()
                    fixture["launch"].assert_called_once()
                    self.assertGreaterEqual(fixture["free"].call_count, 2)
                    if field != "command":
                        self.assertNotIn(41, [call.args[0] for call in fixture["process_command"].call_args_list])

    def test_connect_recovers_exited_process_without_termination(self):
        for error in ("tunnel_process_unavailable", "tunnel_process_exited"):
            with self.subTest(error=error):
                self.write_state()
                with self.connect_fixture(old_error=error) as fixture:
                    result = tunnel.connect(self.state, fixture["key"], fixture["hosts"])
                    self.assertTrue(result["ok"])
                    fixture["old"].terminate.assert_not_called()

    def test_connect_keeps_matching_live_process_without_listener(self):
        state, _ = self.write_state()
        with self.connect_fixture(old_identity=state) as fixture:
            with self.assertRaisesRegex(tunnel.TunnelError, "existing_tunnel_has_no_listener"):
                tunnel.connect(self.state, fixture["key"], fixture["hosts"])
            fixture["launch"].assert_not_called()
            fixture["old"].terminate.assert_not_called()
            self.assertEqual(json.loads(self.state.read_text()), state)

    def test_connect_keeps_state_when_process_identity_is_unavailable(self):
        state, _ = self.write_state()
        with self.connect_fixture(old_error="process_identity_unavailable") as fixture:
            with self.assertRaisesRegex(tunnel.TunnelError, "process_identity_unavailable"):
                tunnel.connect(self.state, fixture["key"], fixture["hosts"])
            fixture["launch"].assert_not_called()
            self.assertEqual(json.loads(self.state.read_text()), state)

    def test_recovery_rechecks_free_port_before_changing_metadata(self):
        state, _ = self.write_state()
        log = self.state.with_suffix(".stderr")
        log.write_text("preserve", encoding="utf-8")
        with self.connect_fixture(old_identity={**state, "created": 999999}) as fixture:
            fixture["free"].side_effect = [True, False]
            with self.assertRaisesRegex(tunnel.TunnelError, "local_port_8765_in_use"):
                tunnel.connect(self.state, fixture["key"], fixture["hosts"])
            fixture["launch"].assert_not_called()
            fixture["old"].terminate.assert_not_called()
            self.assertEqual(json.loads(self.state.read_text()), state)
            self.assertEqual(log.read_text(), "preserve")

    def test_busy_port_with_reused_pid_never_discards_metadata(self):
        state, _ = self.write_state()
        with self.connect_fixture(old_identity={**state, "created": 999999}, free=False) as fixture:
            with self.assertRaisesRegex(tunnel.TunnelError, "tunnel_owner_mismatch"):
                tunnel.connect(self.state, fixture["key"], fixture["hosts"])
            fixture["launch"].assert_not_called()
            fixture["old"].terminate.assert_not_called()
            self.assertEqual(json.loads(self.state.read_text()), state)

    def test_recovery_does_not_truncate_or_remove_an_open_stderr_log(self):
        state, _ = self.write_state()
        log = self.state.with_suffix(".stderr")
        log.write_text("preserve other handle", encoding="utf-8")
        original_unlink = Path.unlink

        def locked_unlink(path, *args, **kwargs):
            if path == log:
                raise PermissionError("sensitive-fixture")
            return original_unlink(path, *args, **kwargs)

        with self.connect_fixture(old_identity={**state, "created": 999999}) as fixture, \
             patch.object(Path, "unlink", locked_unlink):
            with self.assertRaises(tunnel.TunnelError) as raised:
                tunnel.connect(self.state, fixture["key"], fixture["hosts"])
            self.assertEqual(str(raised.exception), "stale_tunnel_log_unavailable")
            self.assertIsNone(raised.exception.__cause__)
            fixture["launch"].assert_not_called()
            fixture["old"].terminate.assert_not_called()
            self.assertEqual(json.loads(self.state.read_text()), state)
            self.assertEqual(log.read_text(), "preserve other handle")

    def test_new_launch_never_truncates_existing_unowned_log(self):
        log = self.state.with_suffix(".stderr")
        log.write_text("preserve unknown log", encoding="utf-8")
        with self.connect_fixture() as fixture:
            with self.assertRaisesRegex(tunnel.TunnelError, "tunnel_log_unavailable"):
                tunnel.connect(self.state, fixture["key"], fixture["hosts"])
            fixture["launch"].assert_not_called()
            fixture["factory"].assert_not_called()
            self.assertEqual(log.read_text(), "preserve unknown log")

    def test_incomplete_state_is_not_treated_as_proven_pid_reuse(self):
        for field, invalid in (("version", 2), ("created", None), ("executable", ""),
                               ("command_digest", "invalid")):
            with self.subTest(field=field):
                state, _ = self.write_state()
                state[field] = invalid
                self.state.write_text(json.dumps(state), encoding="utf-8")
                with self.connect_fixture() as fixture:
                    with self.assertRaisesRegex(tunnel.TunnelError, "tunnel_state_invalid"):
                        tunnel.connect(self.state, fixture["key"], fixture["hosts"])
                    fixture["launch"].assert_not_called()
                    fixture["factory"].assert_not_called()
                    self.assertEqual(json.loads(self.state.read_text()), state)


if __name__ == "__main__":
    unittest.main()
