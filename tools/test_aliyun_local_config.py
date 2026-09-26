from contextlib import nullcontext, redirect_stdout
import io
import json
import os
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

import aliyun_local_config as config


class LocalConfigTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.legacy = self.root / "legacy/.env"
        legacy = patch.object(config, "LEGACY_ENVIRONMENT", self.legacy)
        legacy.start()
        self.addCleanup(legacy.stop)

    def write(self, value):
        path = config.config_path(self.root)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_new_machine_defaults_need_no_old_drive_or_output_host_file(self):
        result = config.load(self.root)
        self.assertEqual(result["environment"], self.root / "output/ecs_backend_work/game-test.env")
        self.assertEqual(result["known_hosts"], self.root / "tools/deploy/goufayu_test_known_hosts")
        self.assertEqual(result["ssh_key"], Path.home() / ".ssh/goufayu_ecs_ed25519_v2")
        self.assertFalse(config.config_path(self.root).exists())

    def test_existing_developer_defaults_are_preserved(self):
        self.legacy.parent.mkdir()
        self.legacy.touch()
        old_hosts = self.root / "output/ecs_backend_work/ecs_hostkey_candidate.pub"
        old_hosts.parent.mkdir(parents=True)
        old_hosts.touch()
        result = config.load(self.root)
        self.assertEqual(result["environment"], self.legacy)
        self.assertEqual(result["known_hosts"], old_hosts)

    def test_save_relative_paths_and_load_again_after_cwd_changes(self):
        result = config.save({"environment": "local secrets/test.env",
                              "ssh_key": self.root / "dedicated admin key"}, self.root)
        self.assertEqual(result["environment"], self.root / "local secrets/test.env")
        self.assertEqual(config.load(self.root), result)
        stored = json.loads(config.config_path(self.root).read_text(encoding="utf-8"))
        self.assertEqual(set(stored), {"version", *config.PATH_KEYS})
        self.assertEqual(stored["version"], 1)
        self.assertFalse(list(config.config_path(self.root).parent.glob("*.tmp")))

    @unittest.skipUnless(os.name == "nt", "Windows drive paths")
    def test_other_drive_and_spaces_are_preserved(self):
        self.write({"version": 1, "environment": "F:/Test Game/secrets/game.env",
                    "ssh_key": "C:/Users/Administrator/.ssh/game-test"})
        result = config.load(self.root)
        self.assertEqual(result["environment"], Path("F:/Test Game/secrets/game.env"))
        self.assertEqual(result["ssh_key"], Path("C:/Users/Administrator/.ssh/game-test"))

    def test_partial_save_preserves_configured_paths(self):
        config.save({"environment": "private/first.env"}, self.root)
        result = config.save({"ssh_key": "private/second-key"}, self.root)
        self.assertEqual(result["environment"], self.root / "private/first.env")
        self.assertEqual(result["ssh_key"], self.root / "private/second-key")

    def test_unknown_secret_keys_and_versions_are_rejected_without_values(self):
        for value in ({"version": 1, "FISHING_API_TOKEN": "never-echo-test-secret"},
                      {"version": 1, "host": "other-server"},
                      {"version": True}, {"version": 2}, {}, ["never-echo-test-secret"]):
            with self.subTest(value_type=type(value).__name__):
                self.write(value)
                with self.assertRaises(config.ConfigError) as raised:
                    config.load(self.root)
                self.assertNotIn("never-echo-test-secret", str(raised.exception))

    def test_invalid_paths_are_rejected(self):
        for value in (None, 42, "", " path ", "../outside", "C:drive-relative", "\nsecret",
                      "x.env:secret", "https://server/secret", "\\\\server\\share\\key",
                      "a*b", str(config.config_path(self.root))):
            with self.subTest(value_type=type(value).__name__):
                self.write({"version": 1, "environment": value})
                with self.assertRaisesRegex(config.ConfigError, "local_config_path_invalid"):
                    config.load(self.root)

    def test_oversized_malformed_and_duplicate_json_are_rejected(self):
        path = self.write({"version": 1})
        for data, code in ((b" " * 8193, "local_config_too_large"),
                           (b"never-echo-test-secret", "local_config_read_failed"),
                           (b'{"version":1,"version":1}', "local_config_schema_invalid")):
            path.write_bytes(data)
            with self.assertRaisesRegex(config.ConfigError, code) as raised:
                config.load(self.root)
            self.assertNotIn("never-echo-test-secret", str(raised.exception))

    def test_reparse_config_is_rejected_before_open(self):
        path = self.write({"version": 1})
        original = Path.lstat

        def metadata(candidate):
            if candidate == path:
                return SimpleNamespace(st_mode=0o100600, st_file_attributes=0x400)
            return original(candidate)

        with patch.object(Path, "lstat", metadata), patch.object(Path, "open") as opened:
            with self.assertRaisesRegex(config.ConfigError, "local_config_reparse_not_allowed"):
                config.load(self.root)
            opened.assert_not_called()

    def test_failed_save_preserves_existing_and_removes_temporary(self):
        config.save({"environment": "private/original.env"}, self.root)
        path = config.config_path(self.root)
        original = path.read_bytes()
        with patch.object(Path, "replace", side_effect=PermissionError("never-echo-test-secret")):
            with self.assertRaisesRegex(config.ConfigError, "local_config_write_failed"):
                config.save({"environment": "private/new.env"}, self.root)
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse(list(path.parent.glob("*.tmp")))

    def test_save_refuses_to_overwrite_existing_unrecognized_content(self):
        path = self.write({"version": 1, "token": "never-echo-test-secret"})
        original = path.read_bytes()
        with self.assertRaises(config.ConfigError):
            config.save({"environment": "private/new.env"}, self.root)
        self.assertEqual(path.read_bytes(), original)


@unittest.skipUnless(os.name == "nt", "Windows-only launchers")
class LauncherConfigTests(unittest.TestCase):
    def setUp(self):
        self.settings = {key: Path("F:/test paths") / key for key in config.PATH_KEYS}

    def test_tunnel_uses_settings_with_explicit_cli_override(self):
        import aliyun_test_connection as tunnel
        with patch.object(config, "load", return_value=self.settings), \
             patch.object(tunnel, "state_lock", return_value=nullcontext()), \
             patch.object(tunnel, "connect", return_value={"ok": True}) as connect, \
             patch("sys.argv", ["tunnel", "connect", "--key", "C:/override/key"]), \
             redirect_stdout(io.StringIO()):
            self.assertEqual(tunnel.main(), 0)
            self.assertEqual(connect.call_args.args[1:],
                             (Path("C:/override/key"), self.settings["known_hosts"]))

    def test_auth_uses_settings_with_explicit_cli_override(self):
        import aliyun_game_test_auth as auth
        for extra, expected in (([], self.settings["environment"]),
                                (["--environment", "C:/override/test.env"], Path("C:/override/test.env"))):
            with patch.object(config, "load", return_value=self.settings), \
                 patch.object(auth, "inject", return_value={"ok": True}) as inject, \
                 patch("sys.argv", ["auth", "inject", *extra]), redirect_stdout(io.StringIO()):
                self.assertEqual(auth.main(), 0)
                self.assertEqual(inject.call_args.args[1], expected)

    def test_invalid_config_emits_only_fixed_code_before_tunnel_actions(self):
        import aliyun_test_connection as tunnel
        output = io.StringIO()
        with patch.object(config, "load", side_effect=config.ConfigError("local_config_schema_invalid")), \
             patch.object(tunnel, "connect") as connect, \
             patch("sys.argv", ["tunnel", "connect"]), redirect_stdout(output):
            self.assertEqual(tunnel.main(), 1)
            connect.assert_not_called()
        self.assertEqual(json.loads(output.getvalue()),
                         {"ok": False, "error": "local_config_schema_invalid"})

    def test_bridge_passes_all_configured_paths_and_cli_override(self):
        import hammer_backend_bridge as bridge
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(config, "load", return_value=self.settings), \
             patch.object(bridge, "OUTPUT", Path(folder)), \
             patch.object(bridge, "run", return_value={"ok": True}) as run, \
             patch("sys.argv", ["bridge", "once", "--environment", "C:/override/game.env"]), \
             redirect_stdout(io.StringIO()):
            self.assertEqual(bridge.main(), 0)
        worker = run.call_args.args[0]
        self.assertEqual(worker.key, self.settings["ssh_key"])
        self.assertEqual(worker.known_hosts, self.settings["known_hosts"])
        self.assertEqual(worker.environment, Path("C:/override/game.env"))


if __name__ == "__main__":
    unittest.main()
