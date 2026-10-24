import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ws4_relay_test", Path(__file__).with_name("steam_tls_relay.py"))
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)


class NativeCall:
    def __init__(self, callback):
        self.callback = callback

    def __call__(self, *args):
        return self.callback(*args)


class KernelFixture:
    """No real process is opened; emulate the values written by Win32 APIs."""
    def __init__(self, executable, *, found=True, created=42, terminate=True, wait=0):
        self.calls = []
        self.handle = 123
        def opened(flags, inherit, pid):
            self.calls.append(("open", flags, pid))
            return self.handle if found else 0
        def times(handle, creation, exit_time, kernel_time, user_time):
            self.calls.append(("times", handle))
            creation._obj.dwHighDateTime = created >> 32
            creation._obj.dwLowDateTime = created & 0xFFFFFFFF
            return 1
        def image(handle, flags, path, size):
            self.calls.append(("image", handle))
            path.value = executable
            size._obj.value = len(executable)
            return 1
        def terminated(handle, code):
            self.calls.append(("terminate", handle))
            return int(terminate)
        def waited(handle, timeout):
            self.calls.append(("wait", handle, timeout))
            return wait
        self.OpenProcess = NativeCall(opened)
        self.GetProcessTimes = NativeCall(times)
        self.QueryFullProcessImageNameW = NativeCall(image)
        self.TerminateProcess = NativeCall(terminated)
        self.WaitForSingleObject = NativeCall(waited)
        self.CloseHandle = NativeCall(lambda handle: self.calls.append(("close", handle)))


class TemporaryRelayTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.executable = str((Path(self.temporary.name) / "ssh.exe").resolve())
        self.argv = [self.executable, *relay.arguments()[1:]]
        self.receipt = Path(self.temporary.name) / "receipt.json"

    def identity(self, kernel, **kwargs):
        return relay.process_identity(42424, kernel=kernel, command_reader=lambda pid: "fixture-command",
                                      argv_parser=lambda raw: self.argv, **kwargs)

    def prepared_stop(self, kernel, *, error=0, argv=None):
        expected = self.identity(KernelFixture(self.executable))
        self.receipt.write_text(json.dumps(expected), encoding="utf-8")
        original = relay.process_identity
        def invoke(pid, **kwargs):
            return original(pid, kernel=kernel, last_error=lambda: error,
                            command_reader=lambda value: "fixture-command",
                            argv_parser=lambda raw: self.argv if argv is None else argv, **kwargs)
        return patch.object(relay, "RECEIPT", self.receipt), patch.object(relay, "process_identity", side_effect=invoke)

    def test_default_does_not_start_or_stop(self):
        with patch.object(relay, "start") as start, patch.object(relay, "stop") as stop:
            with patch("sys.argv", ["relay"]), patch("builtins.print"):
                self.assertEqual(relay.main(), 0)
            start.assert_not_called()
            stop.assert_not_called()

    def test_fixed_forward_and_pinned_ssh_have_no_general_proxy(self):
        args = relay.arguments()
        self.assertEqual(args[args.index("-R") + 1], "127.0.0.1:18768:steamcommunity.com:443")
        self.assertEqual(args[-1], "root@47.110.238.248")
        self.assertIn("StrictHostKeyChecking=yes", args)
        self.assertIn("ExitOnForwardFailure=yes", args)
        self.assertIn("-N", args)
        self.assertNotIn("-D", args)
        self.assertNotIn("ProxyCommand", " ".join(args))
        self.assertIn('UserKnownHostsFile="' + (relay.ROOT / "tools/deploy/goufayu_test_known_hosts").resolve().as_posix() + '"', args)

    def test_start_and_stop_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit), patch("sys.stderr"):
            relay.parser().parse_args(["--start", "--stop"])

    def test_owned_stop_checks_and_waits_on_the_same_handle(self):
        kernel = KernelFixture(self.executable)
        receipt, identity = self.prepared_stop(kernel)
        with receipt, identity:
            self.assertTrue(relay.stop()["ok"])
        self.assertFalse(self.receipt.exists())
        self.assertIn(("terminate", kernel.handle), kernel.calls)
        self.assertIn(("wait", kernel.handle, 10000), kernel.calls)
        self.assertEqual(kernel.calls[-1], ("close", kernel.handle))
        self.assertEqual(kernel.calls[0][1] & 0x00101001, 0x00101001)

    def test_only_error_87_clears_a_missing_process_receipt(self):
        for error in (5, 0, 6):
            with self.subTest(error=error):
                kernel = KernelFixture(self.executable, found=False)
                receipt, identity = self.prepared_stop(kernel, error=error)
                before = self.receipt.read_bytes()
                with receipt, identity, self.assertRaisesRegex(RuntimeError, "relay_process_access_failed"):
                    relay.stop()
                self.assertEqual(self.receipt.read_bytes(), before)
                self.assertFalse(any(call[0] == "terminate" for call in kernel.calls))
        kernel = KernelFixture(self.executable, found=False)
        receipt, identity = self.prepared_stop(kernel, error=87)
        with receipt, identity:
            self.assertTrue(relay.stop()["ok"])
        self.assertFalse(self.receipt.exists())

    def test_reused_pid_or_other_executable_is_not_stopped(self):
        for kernel in (KernelFixture(self.executable, created=43),
                       KernelFixture(str(Path(self.executable).with_name("other.exe")))):
            receipt, identity = self.prepared_stop(kernel)
            with receipt, identity, self.assertRaises(RuntimeError):
                relay.stop()
            self.assertTrue(self.receipt.exists())
            self.assertFalse(any(call[0] == "terminate" for call in kernel.calls))
            self.assertEqual(kernel.calls[-1], ("close", kernel.handle))

    def test_other_ssh_forward_host_key_or_identity_is_not_stopped(self):
        mutations = []
        for original, replacement in ((relay.FORWARD, "127.0.0.1:29000:127.0.0.1:29000"),
                                      (self.argv[-1], "root@other.invalid"),
                                      ("StrictHostKeyChecking=yes", "StrictHostKeyChecking=no")):
            changed = list(self.argv)
            changed[changed.index(original)] = replacement
            mutations.append(changed)
        changed = list(self.argv)
        changed[changed.index("-i") + 1] = "other-private-key"
        mutations.append(changed)
        changed = list(self.argv)
        option = next(value for value in changed if value.startswith("UserKnownHostsFile="))
        changed[changed.index(option)] = "UserKnownHostsFile=other-known-hosts"
        mutations.extend((changed, [*self.argv[:-1], "-D", "1080", self.argv[-1]]))
        for argv in mutations:
            with self.subTest(change=mutations.index(argv)):
                kernel = KernelFixture(self.executable)
                receipt, identity = self.prepared_stop(kernel, argv=argv)
                with receipt, identity, self.assertRaisesRegex(RuntimeError, "relay_process_is_not_owned_forward"):
                    relay.stop()
                self.assertTrue(self.receipt.exists())
                self.assertFalse(any(call[0] == "terminate" for call in kernel.calls))

    def test_failed_or_unconfirmed_termination_keeps_the_receipt(self):
        for kernel, error in ((KernelFixture(self.executable, terminate=False), "relay_stop_failed"),
                              (KernelFixture(self.executable, wait=0x102), "relay_stop_not_confirmed")):
            receipt, identity = self.prepared_stop(kernel)
            with receipt, identity, self.assertRaisesRegex(RuntimeError, error):
                relay.stop()
            self.assertTrue(self.receipt.exists())

    def test_legacy_or_invalid_receipt_cannot_target_a_process(self):
        expected = self.identity(KernelFixture(self.executable))
        for value in ({key: item for key, item in expected.items() if key != "command_sha256"},
                      dict(expected, command_sha256="untrusted"), dict(expected, pid=True)):
            self.receipt.write_text(json.dumps(value), encoding="utf-8")
            with patch.object(relay, "RECEIPT", self.receipt), patch.object(relay, "process_identity") as identity:
                with self.assertRaisesRegex(RuntimeError, "relay_receipt_invalid"):
                    relay.stop()
                identity.assert_not_called()
            self.assertTrue(self.receipt.exists())

    @unittest.skipUnless(os.name == "nt", "Windows argv parser only; no processes opened")
    def test_native_argv_parser_preserves_quoted_paths_and_fixed_options(self):
        self.assertEqual(relay.split_command_line(subprocess.list2cmdline(self.argv)), self.argv)

    @unittest.skipUnless(os.name == "nt", "Windows command construction; subprocess is mocked")
    def test_command_reader_is_hidden_and_queries_only_the_requested_pid(self):
        def directory(buffer, capacity):
            buffer.value = str(Path(self.temporary.name) / "System32")
            return len(buffer.value)
        kernel = SimpleNamespace(GetSystemDirectoryW=NativeCall(directory))
        command = subprocess.list2cmdline(self.argv)
        completed = SimpleNamespace(returncode=0, stdout=json.dumps(command).encode("utf-8"))
        with patch.object(relay.ctypes, "WinDLL", return_value=kernel), \
             patch.object(relay.subprocess, "run", return_value=completed) as run:
            self.assertEqual(relay.command_line(42424), command)
        args = run.call_args.args[0]
        self.assertEqual(Path(args[0]).name.lower(), "powershell.exe")
        self.assertIn("-NonInteractive", args)
        self.assertIn("-Filter 'ProcessId = 42424'", args[-1])
        self.assertEqual(run.call_args.kwargs["creationflags"], subprocess.CREATE_NO_WINDOW)
        self.assertEqual(run.call_args.kwargs["timeout"], 10)
        completed.stdout = b"private-non-json-process-detail"
        with patch.object(relay.ctypes, "WinDLL", return_value=kernel), \
             patch.object(relay.subprocess, "run", return_value=completed):
            with self.assertRaisesRegex(RuntimeError, "^relay_process_command_unavailable$"):
                relay.command_line(42424)


if __name__ == "__main__":
    unittest.main()
