"""Offline safety checks: no shell, ECS, container, DB, or real secret access."""
import importlib.util
import io
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from contextlib import ExitStack
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


bridge = module("pg17_client")
manage = module("manage")
backup = module("backup")


class DeploymentSafetyTests(unittest.TestCase):
    def test_prepare_restores_private_umask_and_checks_service_user(self):
        with tempfile.TemporaryDirectory() as folder:
            release = Path(folder)
            mask = [0o077]
            observed = []

            def umask(value):
                previous = mask[0]
                mask[0] = value
                return previous

            def run(command):
                observed.append((command, mask[0]))

            with mock.patch.object(manage, "validated_release", return_value=release), \
                 mock.patch.object(manage.shutil, "which", return_value="/usr/bin/python3.11"), \
                 mock.patch.object(manage.os, "umask", side_effect=umask), \
                 mock.patch.object(manage, "run", side_effect=run), \
                 mock.patch("builtins.print"):
                manage.prepare(SimpleNamespace(release=str(release), wheelhouse=None))
            self.assertEqual(mask[0], 0o077)
            self.assertEqual([value for command, value in observed if "venv" in command or "pip" in command], [0o022, 0o022])
            check, check_mask = observed[-1]
            self.assertEqual(check[:4], ["runuser", "-u", "goufayu", "--"])
            self.assertEqual(check_mask, 0o077)
            self.assertIn("-B", check)
            self.assertIn("import psycopg", check[-1])

    def test_prepare_failure_restores_callers_umask(self):
        with mock.patch.object(manage, "validated_release", return_value=HERE), \
             mock.patch.object(manage.shutil, "which", return_value="/usr/bin/python3.11"), \
             mock.patch.object(manage.os, "umask", side_effect=[0o077, 0o022]) as umask, \
             mock.patch.object(manage, "run", side_effect=[None, RuntimeError("venv_failed")]), \
             self.assertRaisesRegex(RuntimeError, "venv_failed"):
            manage.prepare(SimpleNamespace(release=str(HERE), wheelhouse=None))
        self.assertEqual(umask.call_args_list, [mock.call(0o022), mock.call(0o077)])

    def test_provision_account_guard_rejects_privilege_and_extra_groups(self):
        git_bash = Path("C:/Program Files/Git/bin/bash.exe")
        bash = str(git_bash) if git_bash.is_file() else shutil.which("bash")
        if not bash:
            self.skipTest("bash not installed for isolated account guard check")
        source = (HERE / "provision_host.sh").read_text()
        function = "validate_service_account() {" + source.split("validate_service_account() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        for uid, group_gid, primary, groups, expected in (
            (991, 991, 991, "991", 0),
            (0, 991, 991, "991", 1),
            (991, 0, 0, "0", 1),
            (991, 991, 0, "0 991", 1),
            (991, 991, 991, "991 10", 1),
            (991, 991, 991, "991 0", 1),
        ):
            # Only the function is executed; every account lookup is mocked.
            harness = f'''getent() {{ printf '%s\\n' 'goufayu:x:{group_gid}:'; }}
id() {{ case "$1" in -u) echo {uid};; -g) echo {primary};; -G) echo '{groups}';; *) return 1;; esac; }}
{function}
validate_service_account
'''
            with self.subTest(uid=uid, group_gid=group_gid, primary=primary, groups=groups):
                completed = subprocess.run([bash, "-c", harness], capture_output=True, text=True)
                self.assertEqual(completed.returncode, expected, completed.stderr)

    def unit_fixture(self, folder, stack):
        root = Path(folder)
        release, state, config, units = [root / name for name in ("release", "state", "config", "units")]
        for directory in (release / "deploy", state, config, units):
            directory.mkdir(parents=True)
        names = ("goufayu-api.service", "goufayu-backup.service", "goufayu-backup.timer", "goufayu.logrotate", "backup.env.example")
        for name in names:
            (release / "deploy" / name).write_bytes((HERE / name).read_bytes())
        logrotate = root / "logrotate"
        stack.enter_context(mock.patch.object(manage, "validated_release", return_value=release))
        for name, value in (("STATE", state), ("CONFIG", config), ("UNIT_DIRECTORY", units), ("LOGROTATE_FILE", logrotate)):
            stack.enter_context(mock.patch.object(manage, name, value))
        stack.enter_context(mock.patch.object(manage.os, "chown", create=True))
        stack.enter_context(mock.patch("builtins.print"))
        return release, state, config, units, logrotate

    def test_unit_candidates_validate_before_backup_and_install_repeats_without_rewrite(self):
        with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
            release, state, config, units, logrotate = self.unit_fixture(folder, stack)
            original = b"old approved unit\r\n# retain exact original bytes\r\n"
            destinations = [units / name for name in ("goufayu-api.service", "goufayu-backup.service", "goufayu-backup.timer")] + [logrotate]
            for destination in destinations:
                destination.write_bytes(original)
            actions = []

            def fake_run(command):
                actions.append(command[0])
                if command[0] in ("systemd-analyze", "logrotate"):
                    for destination in destinations:
                        self.assertEqual(destination.read_bytes(), original)
                    self.assertFalse((state / "config-backups").exists())
                elif command[:2] == ["systemctl", "daemon-reload"]:
                    manifests = list((state / "config-backups").glob("*/manifest.json"))
                    self.assertEqual(len(manifests), 1)
                    records = json.loads(manifests[0].read_text())["files"]
                    self.assertEqual(len(records), 4)
                    for record in records:
                        self.assertEqual((manifests[0].parent / record["saved"]).read_bytes(), original)
                        self.assertEqual(record["sha256"], hashlib.sha256(original).hexdigest())

            with mock.patch.object(manage, "run", side_effect=fake_run):
                manage.install_units(SimpleNamespace(release=str(release)))
            self.assertEqual(actions, ["systemd-analyze", "logrotate", "systemctl"])
            for destination in destinations:
                source_name = "goufayu.logrotate" if destination == logrotate else destination.name
                self.assertEqual(destination.read_bytes(), (release / "deploy" / source_name).read_bytes())
            backup_before = list((state / "config-backups").iterdir())
            with mock.patch.object(manage, "run") as child, mock.patch.object(manage, "atomic_write") as writer:
                manage.install_units(SimpleNamespace(release=str(release)))
            writer.assert_not_called()
            self.assertEqual([call.args[0][0] for call in child.call_args_list], ["systemd-analyze", "logrotate"])
            self.assertEqual(list((state / "config-backups").iterdir()), backup_before)

    def test_failed_candidate_validation_does_not_change_system_configuration(self):
        with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
            release, state, config, units, logrotate = self.unit_fixture(folder, stack)
            original = units / "goufayu-api.service"
            original.write_bytes(b"existing unit")
            with mock.patch.object(manage, "run", side_effect=RuntimeError("verification_rejected")), \
                 self.assertRaisesRegex(RuntimeError, "verification_rejected"):
                manage.install_units(SimpleNamespace(release=str(release)))
            self.assertEqual(original.read_bytes(), b"existing unit")
            self.assertFalse(logrotate.exists())
            self.assertFalse((config / "backup.env").exists())
            self.assertFalse((state / "config-backups").exists())

    def test_unit_startup_does_not_require_current_for_validation_or_append_syntax(self):
        for name in ("goufayu-api.service", "goufayu-backup.service"):
            text = (HERE / name).read_text()
            self.assertIn("ExecStart=/bin/sh -c 'exec /opt/goufayu/releases/current/.venv/bin/python", text)
            self.assertIn("StandardOutput=journal", text)
            self.assertNotIn("StandardOutput=append:", text)
        api = (HERE / "goufayu-api.service").read_text()
        self.assertIn("ReadWritePaths=/var/log/goufayu/api.log\n", api)
        self.assertIn(">> /var/log/goufayu/api.log 2>&1'", api)

    def test_existing_role_credentials_are_checked_readonly_never_rotated(self):
        admin = mock.Mock()
        admin.execute.return_value.fetchall.return_value = [("goufayu_migrator",), ("goufayu_app",)]
        connections = []

        def connect(**kwargs):
            connections.append(kwargs)
            self.assertEqual(kwargs["options"], "-c default_transaction_read_only=on")
            self.assertEqual(kwargs["dbname"], "goufayu_test")
            probe = mock.MagicMock()
            probe.__enter__.return_value.execute.return_value.fetchone.return_value = (kwargs["user"], "goufayu_test")
            return probe

        with mock.patch.dict(manage.sys.modules, {"psycopg": mock.Mock(connect=connect)}), \
             mock.patch.object(manage, "private_read", return_value="dummy-existing-role-password"):
            plan = manage.role_password_plan(admin)
            manage.configure_role_passwords(admin, plan)
        self.assertEqual(plan, {})
        self.assertEqual({item["user"] for item in connections}, {"goufayu_app", "goufayu_migrator"})
        self.assertEqual(admin.execute.call_count, 1)
        self.assertTrue(admin.execute.call_args.args[0].startswith("SELECT rolname"))

    def test_only_missing_roles_receive_a_new_password(self):
        admin = mock.Mock()
        admin.execute.return_value.fetchall.return_value = [("goufayu_app",)]
        probe = mock.MagicMock()
        probe.__enter__.return_value.execute.return_value.fetchone.return_value = ("goufayu_app", "goufayu_test")
        sql = mock.Mock()
        fake_psycopg = mock.Mock(sql=sql)
        fake_psycopg.connect.return_value = probe
        with mock.patch.dict(manage.sys.modules, {"psycopg": fake_psycopg}), \
             mock.patch.object(manage, "private_read", return_value="dummy-new-role-password"):
            plan = manage.role_password_plan(admin)
            self.assertEqual(set(plan), {"goufayu_migrator"})
            manage.configure_role_passwords(admin, plan)
        sql.Identifier.assert_called_once_with("goufayu_migrator")
        sql.SQL.assert_called_once_with("ALTER ROLE {} PASSWORD {}")
        self.assertEqual(admin.execute.call_count, 2)

    def test_bad_existing_role_credentials_reject_bootstrap_before_any_mutation(self):
        admin = mock.MagicMock()
        admin.__enter__.return_value = admin
        admin.execute.return_value.fetchall.return_value = [("goufayu_app",)]
        fake_psycopg = mock.Mock()
        fake_psycopg.connect.side_effect = RuntimeError("dummy-hidden-password-in-driver-error")
        with mock.patch.dict(manage.sys.modules, {"psycopg": fake_psycopg}), \
             mock.patch.object(manage, "private_read", return_value="dummy-existing-role-password"), \
             mock.patch.object(manage, "validated_release", return_value=HERE), \
             mock.patch.object(manage, "admin_connection", return_value=admin), \
             mock.patch.object(manage, "bootstrap_sql") as bootstrap, \
             mock.patch.object(manage, "configure_role_passwords") as passwords, \
             self.assertRaisesRegex(RuntimeError, "^existing_role_credentials_rejected:goufayu_app$"):
            manage.db_init(SimpleNamespace(release=str(HERE), confirm_empty=True))
        bootstrap.assert_not_called()
        passwords.assert_not_called()
        self.assertEqual(admin.execute.call_count, 1)
        self.assertTrue(admin.execute.call_args.args[0].startswith("SELECT rolname"))

    def test_bad_existing_role_credentials_reject_trial_before_database_creation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            admin = mock.MagicMock()
            admin.__enter__.return_value = admin
            with mock.patch.dict(manage.sys.modules, {"psycopg": mock.Mock()}), \
                 mock.patch.object(manage, "STATE", root), \
                 mock.patch.object(manage, "validated_release", return_value=HERE), \
                 mock.patch.object(manage, "admin_connection", return_value=admin), \
                 mock.patch.object(manage, "role_password_plan", side_effect=RuntimeError("credentials_rejected")), \
                 self.assertRaisesRegex(RuntimeError, "credentials_rejected"):
                manage.trial_restore(SimpleNamespace(release=str(HERE), backup=str(root), name="goufayu_restore_trial"))
            admin.execute.assert_not_called()

    def test_pgpass_escaping_keeps_colons_and_backslashes(self):
        fields = ["127.0.0.1", "5432", "*", "goufayu_app", "dummy:one\\two"]
        encoded = ":".join(manage.escape_pgpass(field) for field in fields)
        self.assertEqual(bridge.pass_fields(encoded), fields)

    def test_plaintext_dsn_and_arbitrary_flags_rejected(self):
        for args in (["--dbname=postgresql://dummy:secret@host/db"],
                     ["--dbname=service=x", "--command=DROP DATABASE anything"],
                     ["--dbname=service=x", "--format=directory"],
                     ["--dbname=service=x", "--dbname=service=y"]):
            with self.subTest(args=args), self.assertRaises(ValueError):
                bridge.parse_arguments("pg_dump", args)

    def test_real_dbtool_dump_arguments_preserve_snapshot_and_role(self):
        forwarded, service, output, source = bridge.parse_arguments("pg_dump", [
            "--dbname=service=goufayu_migrator", "--no-password", "--format=custom",
            "--schema=public", "--schema=extensions", "--extension=pgcrypto",
            "--no-owner", "--no-acl", "--no-publications", "--no-subscriptions",
            "--snapshot=00000003-000001A1-1", "--file=database.dump", "--role=goufayu_owner"])
        self.assertEqual(service, "goufayu_migrator")
        self.assertIn("--snapshot=00000003-000001A1-1", forwarded)
        self.assertIn("--role=goufayu_owner", forwarded)
        self.assertFalse(any("file=" in arg or "dbname=" in arg for arg in forwarded))
        self.assertEqual(output.name, "database.dump")
        self.assertIsNone(source)

    def test_restore_stream_and_password_never_enter_podman_argv(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source.dump"
            source.write_bytes(b"PGDMP\x01dummy")
            captured = {}

            def fake_run(command, **kwargs):
                captured["argv"] = command
                captured["env"] = kwargs["env"]
                captured["input"] = kwargs["stdin"].read()
                return mock.Mock(returncode=0)

            with mock.patch.object(bridge.sys, "platform", "linux"), \
                 mock.patch.object(bridge.os, "geteuid", return_value=0, create=True), \
                 mock.patch.object(bridge, "connection_environment", return_value={"PGPASSWORD": "dummy-private-value", "PGDATABASE": "goufayu_test"}), \
                 mock.patch.object(bridge.subprocess, "run", side_effect=fake_run):
                result = bridge.main(["pg_restore", "--dbname=service=goufayu_migrator", "--no-password",
                                      "--no-owner", "--no-acl", "--role=goufayu_owner", "--single-transaction",
                                      "--exit-on-error", str(source)])
            self.assertEqual(result, 0)
            self.assertEqual(captured["input"], source.read_bytes())
            self.assertNotIn("dummy-private-value", " ".join(captured["argv"]))
            self.assertNotIn(str(source), captured["argv"])
            self.assertEqual(captured["env"]["PGPASSWORD"], "dummy-private-value")
            self.assertEqual(captured["argv"][:3], ["podman", "exec", "-i"])
            self.assertNotIn("--file=-", captured["argv"])
            self.assertIn("--dbname=goufayu_test", captured["argv"])

    def test_restore_uses_validated_database_name_and_preserves_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "database.dump"
            source.write_bytes(b"PGDMP\x01dummy")
            for database in ("goufayu_test", "goufayu_restore_20260919"):
                with self.subTest(database=database), \
                     mock.patch.object(bridge.sys, "platform", "linux"), \
                     mock.patch.object(bridge.os, "geteuid", return_value=0, create=True), \
                     mock.patch.object(bridge, "connection_environment", return_value={"PGDATABASE": database}) as credentials, \
                     mock.patch.object(bridge.subprocess, "run", return_value=mock.Mock(returncode=7)) as child:
                    result = bridge.main(["pg_restore", "--dbname=service=reviewed_alias",
                                          "--no-password", "--single-transaction", "--exit-on-error", str(source)])
                self.assertEqual(result, 7)
                credentials.assert_called_once_with("reviewed_alias")
                command = child.call_args.args[0]
                self.assertEqual([argument for argument in command if argument.startswith("--dbname=")],
                                 ["--dbname=" + database])
                self.assertFalse(any(argument.startswith("--file=") for argument in command))
                self.assertNotIn("reviewed_alias", " ".join(command))

    def test_offline_schema_export_keeps_explicit_stdout_output_for_pg17(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / "database.dump", Path(folder) / "schema.sql"
            source.write_bytes(b"PGDMP\x01dummy")
            captured = {}

            def fake_run(command, **kwargs):
                captured["argv"] = command
                self.assertEqual(kwargs["stdin"].read(), source.read_bytes())
                self.assertIsNotNone(kwargs["stdout"])
                kwargs["stdout"].write(b"-- schema-only SQL output\n")
                return mock.Mock(returncode=0)

            with mock.patch.object(bridge.sys, "platform", "linux"), \
                 mock.patch.object(bridge.os, "geteuid", return_value=0, create=True), \
                 mock.patch.object(bridge, "connection_environment") as credentials, \
                 mock.patch.object(bridge.subprocess, "run", side_effect=fake_run):
                result = bridge.main(["pg_restore", "--schema-only", "--no-owner", "--no-acl",
                                      "--file=" + str(output), str(source)])
            self.assertEqual(result, 0)
            credentials.assert_not_called()
            self.assertEqual(captured["argv"], ["podman", "exec", "-i", "goufayu-db", "pg_restore",
                                               "--schema-only", "--no-owner", "--no-acl", "--file=-"])
            self.assertEqual(output.read_bytes(), b"-- schema-only SQL output\n")

    def test_restore_list_does_not_select_sql_output_mode(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "database.dump"
            source.write_bytes(b"PGDMP\x01dummy")
            with mock.patch.object(bridge.sys, "platform", "linux"), \
                 mock.patch.object(bridge.os, "geteuid", return_value=0, create=True), \
                 mock.patch.object(bridge, "connection_environment") as credentials, \
                 mock.patch.object(bridge.subprocess, "run", return_value=mock.Mock(returncode=0)) as child:
                result = bridge.main(["pg_restore", "--list", str(source)])
            self.assertEqual(result, 0)
            credentials.assert_not_called()
            self.assertEqual(child.call_args.args[0], ["podman", "exec", "-i", "goufayu-db", "pg_restore", "--list"])

    def test_dump_does_not_overwrite_existing_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            existing = Path(folder) / "database.dump"
            existing.write_bytes(b"existing-evidence")
            with mock.patch.object(bridge.sys, "platform", "linux"), \
                 mock.patch.object(bridge.os, "geteuid", return_value=0, create=True), \
                 mock.patch.object(bridge, "connection_environment", return_value={}), \
                 mock.patch.object(bridge.subprocess, "run") as child, \
                 mock.patch.object(bridge.sys, "stderr", new_callable=io.StringIO):
                result = bridge.main(["pg_dump", "--dbname=service=goufayu_migrator", "--file=" + str(existing)])
            self.assertEqual(result, 1)
            child.assert_not_called()
            self.assertEqual(existing.read_bytes(), b"existing-evidence")

    def test_env_quotes_roundtrip_without_shell_execution(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "api.env"
            secret = "dummy token '$literal`value`\\with space"
            path.write_text("FISHING_API_TOKEN=" + json.dumps(secret) + "\n", encoding="utf-8")
            self.assertEqual(manage.read_environment(path)["FISHING_API_TOKEN"], secret)

    def test_service_names_do_not_embed_password(self):
        config = manage.service_config("postgres")
        self.assertEqual(config["goufayu_app"]["dbname"], "goufayu_test")
        for section in config.sections():
            self.assertNotIn("password", config[section])
            self.assertEqual(config[section]["host"], "127.0.0.1")
        text = manage.config_text(config)
        self.assertIn("host=127.0.0.1", text)
        self.assertIn("dbname=goufayu_test", text)
        self.assertNotIn(" = ", text)

    def test_offsite_rejects_local_paths_and_same_ecs(self):
        for repository in ("/var/backups/local", "local:/mounted/backups", "sftp:root@localhost:/backup",
                           "sftp:root@47.110.238.248:/backup", "s3:http://remote.example/bucket",
                           "s3:https://name:password@remote.example/bucket"):
            with self.subTest(repository=repository), \
                 mock.patch.object(backup.socket, "gethostname", return_value="test-host"), \
                 mock.patch.object(backup.socket, "getfqdn", return_value="test-host"), \
                 self.assertRaises(ValueError):
                backup.validate_offsite(repository)

    def test_offsite_rejects_dns_alias_to_local_host(self):
        import ipaddress
        with mock.patch.object(backup, "resolved_addresses", return_value={ipaddress.ip_address("127.0.0.1")}), \
             mock.patch.object(backup, "interface_addresses", return_value=set()), \
             mock.patch.object(backup.socket, "getfqdn", return_value="test-host"):
            with self.assertRaisesRegex(ValueError, "local_not_offsite"):
                backup.validate_offsite("sftp:backup@alias.example:/backup")

    def test_offsite_accepts_independent_host(self):
        import ipaddress
        def addresses(host):
            return {ipaddress.ip_address("203.0.113.11" if host == "backup.example" else "127.0.0.1")}
        with mock.patch.object(backup, "resolved_addresses", side_effect=addresses), \
             mock.patch.object(backup, "interface_addresses", return_value=set()), \
             mock.patch.object(backup.socket, "getfqdn", return_value="test-host"):
            backup.validate_offsite("sftp:backup@backup.example:/backup")

    def test_library_failure_does_not_print_secret_diagnostics(self):
        with mock.patch.object(bridge.sys, "platform", "linux"), \
             mock.patch.object(bridge.os, "geteuid", return_value=0, create=True), \
             mock.patch.object(bridge, "connection_environment", side_effect=RuntimeError("dummy-hidden-credential")), \
             mock.patch.object(bridge.sys, "stderr", new_callable=io.StringIO) as diagnostic:
            result = bridge.main(["pg_dump", "--dbname=service=goufayu_migrator"])
        self.assertEqual(result, 1)
        self.assertNotIn("dummy-hidden-credential", diagnostic.getvalue())

    def test_missing_offsite_fails_but_retains_local_export(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state_path = root / "status.json"
            exports = []

            def fake_export(command, **kwargs):
                destination = Path(command[command.index("--output") + 1])
                destination.mkdir()
                (destination / "database.dump").write_bytes(b"retained-local-backup")
                exports.append(destination)
                return mock.Mock(returncode=0)

            fake_fcntl = mock.Mock(LOCK_EX=1, LOCK_NB=2)
            with mock.patch.object(backup.sys, "platform", "linux"), \
                 mock.patch.object(backup.os, "geteuid", return_value=0, create=True), \
                 mock.patch.object(backup.os, "umask", return_value=0o077), \
                 mock.patch.object(backup, "STATE", state_path), \
                 mock.patch.object(backup, "LOCK", root / "backup.lock"), \
                 mock.patch.dict(backup.sys.modules, {"fcntl": fake_fcntl}), \
                 mock.patch.dict(backup.os.environ, {"BACKUP_ROOT": str(root / "exports"), "OFFSITE_REQUIRED": "1"}, clear=True), \
                 mock.patch.object(backup.subprocess, "run", side_effect=fake_export), \
                 mock.patch.object(backup.sys, "stderr", new_callable=io.StringIO):
                result = backup.main()
            self.assertEqual(result, 1)
            state = json.loads(state_path.read_text())
            self.assertTrue(state["local_export_ok"])
            self.assertFalse(state["offsite_ok"])
            self.assertEqual(state["error"], "offsite_not_configured")
            self.assertEqual(len(exports), 1)
            self.assertEqual((exports[0] / "database.dump").read_bytes(), b"retained-local-backup")

    def test_release_manifest_detects_modified_and_unlisted_source(self):
        with tempfile.TemporaryDirectory() as folder:
            release = Path(folder) / "test-release"
            release.mkdir()
            source = release / "run.py"
            original = b"print('approved')\n"
            source.write_bytes(original)
            manifest = {"format": 1, "release": release.name, "files": {"run.py": hashlib.sha256(original).hexdigest()}}
            (release / "release_manifest.json").write_text(json.dumps(manifest))
            manage.verify_release_manifest(release)
            source.write_bytes(b"print('different')\n")
            with self.assertRaisesRegex(RuntimeError, "checksum_mismatch"):
                manage.verify_release_manifest(release)
            source.write_bytes(original)
            (release / "unexpected.py").write_text("pass\n")
            with self.assertRaisesRegex(RuntimeError, "unmanifested"):
                manage.verify_release_manifest(release)

    def test_release_manifest_rejects_path_traversal(self):
        with tempfile.TemporaryDirectory() as folder:
            release = Path(folder) / "test-release"
            release.mkdir()
            manifest = {"format": 1, "release": release.name, "files": {"../secret": "0" * 64}}
            (release / "release_manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(RuntimeError, "path_invalid"):
                manage.verify_release_manifest(release)

    def test_secret_control_characters_cannot_change_identity_via_env_escaping(self):
        for control in ("\t", "\b", "\x1f", "\x7f", "\n", "\r"):
            path = mock.Mock()
            path.is_symlink.return_value = False
            path.is_file.return_value = True
            path.stat.return_value = mock.Mock(st_uid=0, st_mode=0o100600)
            path.read_text.return_value = "dummy-value" + control + "remaining\n"
            with self.subTest(control=repr(control)), self.assertRaisesRegex(RuntimeError, "secret_file_invalid"):
                manage.private_read(path)

    def test_health_requires_authenticated_real_database_readiness(self):
        requested = []
        def response(request, timeout):
            url = request if isinstance(request, str) else request.full_url
            requested.append(request)
            body = {"ok": True} if url.endswith("/health") else {"ok": True, "database": "not-ready"}
            stream = io.BytesIO(json.dumps(body).encode())
            stream.status = 200
            return stream
        with mock.patch.object(manage, "read_environment", return_value={"FISHING_API_TOKEN": "dummy-token"}), \
             mock.patch.object(manage.urllib.request, "urlopen", side_effect=response), \
             self.assertRaisesRegex(RuntimeError, "database_readiness_failed"):
            manage.health()
        self.assertEqual(len(requested), 2)
        self.assertEqual(requested[1].full_url, "http://127.0.0.1:8765/ready")
        self.assertEqual(requested[1].get_header("Authorization"), "Bearer dummy-token")


if __name__ == "__main__":
    unittest.main()
