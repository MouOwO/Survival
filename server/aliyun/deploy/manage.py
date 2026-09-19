"""Explicit host-side deployment steps. Never run against an unreviewed release.

No connection secrets are accepted as command-line arguments or printed. This
program does not start/recreate containers, alter DB storage, or drop databases.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request

BASE = Path("/opt/goufayu/releases")
CONFIG = Path("/etc/goufayu")
STATE = Path("/var/lib/goufayu")
SERVICE_FILE = CONFIG / "pg_service.conf"
DEPLOY = Path(__file__).resolve().parent
UNIT_DIRECTORY = Path("/etc/systemd/system")
LOGROTATE_FILE = Path("/etc/logrotate.d/goufayu")


def fail(code: str):
    raise RuntimeError(code)


def root_only():
    if sys.platform != "linux" or os.geteuid() != 0:
        fail("linux_root_required")


def run(args, **kwargs):
    # Never include DSNs, passwords, or an Authorization header in args.
    subprocess.run([str(x) for x in args], check=True, **kwargs)


def private_read(path: Path, minimum=1):
    if path.is_symlink() or not path.is_file():
        fail("secret_file_missing_or_symlink")
    info = path.stat()
    if info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o077:
        fail("secret_file_requires_root_owner_mode_0600")
    text = path.read_text(encoding="utf-8").rstrip("\r\n")
    if len(text) < minimum or any(ord(c) < 32 or ord(c) == 127 for c in text):
        fail("secret_file_invalid")
    return text


def atomic_write(path: Path, text: str | bytes, mode=0o600, uid=0, gid=0):
    if path.is_symlink():
        fail("refuse_symlink_destination")
    temporary = path.with_name(path.name + ".new." + secrets.token_hex(5))
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        binary = isinstance(text, bytes)
        options = {} if binary else {"encoding": "utf-8", "newline": "\n"}
        with os.fdopen(descriptor, "wb" if binary else "w", **options) as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chown(temporary, uid, gid)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def verify_release_manifest(path: Path):
    manifest_path = path / "release_manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        fail("release_manifest_missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    files = manifest.get("files")
    if manifest.get("format") != 1 or manifest.get("release") != path.name or not isinstance(files, dict) or not files:
        fail("release_manifest_invalid")
    for name, expected in files.items():
        relative = PurePosixPath(name)
        if (not isinstance(name, str) or not name or relative.is_absolute()
                or ".." in relative.parts or "\\" in name or ":" in name
                or relative.as_posix() != name or relative.parts[0] == ".venv"
                or name == "release_manifest.json"):
            fail("release_manifest_path_invalid")
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            fail("release_manifest_digest_invalid")
        source = path.joinpath(*relative.parts)
        if any(part.is_symlink() for part in (source, *source.parents) if part != path.parent):
            fail("release_manifest_symlink_rejected")
        if not source.is_file() or not source.resolve().is_relative_to(path.resolve()):
            fail("release_manifest_file_missing_or_outside_release")
        digest = hashlib.sha256()
        with source.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != expected:
            fail("release_manifest_checksum_mismatch")
    actual = {source.relative_to(path).as_posix() for source in path.rglob("*")
              if source.is_file() and source.relative_to(path).parts[0] != ".venv"
              and source.relative_to(path).as_posix() != "release_manifest.json"}
    if actual != set(files):
        fail("release_contains_unmanifested_or_missing_files")
    return manifest


def validated_release(value: str):
    path = Path(value).resolve(strict=True)
    if path.parent != BASE.resolve() or path.name == "current" or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,95}", path.name):
        fail("release_must_be_named_direct_child_of_releases")
    required = ["backend/run_fishing_api.py", "backend/fishing_api/server.py",
                "requirements.txt", "database/dbtool.py", "database/init_roles.sql",
                "addon/server/bundles/current.json", "deploy/goufayu-api.service"]
    if any(not (path / name).is_file() for name in required):
        fail("release_payload_incomplete")
    for directory in (path, BASE, BASE.parent):
        if directory.stat().st_uid != 0 or directory.stat().st_mode & 0o022:
            fail("release_parent_must_be_root_owned_not_group_or_world_writable")
    # A root-managed immutable source tree prevents service code replacing itself.
    for item in path.rglob("*"):
        if item.is_symlink():
            # Standard venv executable/lib symlinks are created by Python itself.
            if ".venv" not in item.relative_to(path).parts:
                fail("release_source_symlink_rejected")
            continue
        if item.stat().st_uid != 0 or item.stat().st_mode & 0o022:
            fail("release_must_be_root_owned_not_group_or_world_writable")
    verify_release_manifest(path)
    return path


def prepare(args):
    release = validated_release(args.release)
    python = shutil.which("python3.11")
    if not python:
        fail("python3_11_missing_run_host_provision")
    run([python, "-c", "import sys; assert sys.version_info[:2] == (3, 11)"])
    # Root's private umask must not make the dedicated service user's venv unreadable.
    previous_umask = os.umask(0o022)
    try:
        run([python, "-B", "-m", "venv", release / ".venv"])
        command = [release / ".venv/bin/python", "-B", "-m", "pip", "install", "--disable-pip-version-check"]
        if args.wheelhouse:
            command += ["--no-index", "--find-links", Path(args.wheelhouse).resolve(strict=True)]
        command += ["-r", release / "requirements.txt"]
        run(command)
    finally:
        os.umask(previous_umask)
    run(["runuser", "-u", "goufayu", "--", release / ".venv/bin/python", "-B", "-c",
         "import psycopg; assert psycopg.__version__.split('.')[0] == '3'"])
    for script in (release / "deploy/pg-bin").glob("*"):
        script.chmod(0o755)
    print("RELEASE_PREPARED (not activated)")


def capture_secrets(args):
    import getpass
    if not sys.stdin.isatty():
        fail("interactive_terminal_required_or_provision_root_only_secret_files")
    for filename, prompt, minimum in (
            ("postgres-password", "Existing PostgreSQL administrator password: ", 1),
            ("api-token", "Existing FISHING_API_TOKEN (preserve unchanged): ", 24),
            ("account-pepper", "Existing FISHING_ACCOUNT_ID_PEPPER (preserve unchanged): ", 32)):
        target = CONFIG / filename
        if target.exists():
            private_read(target, minimum)
            continue
        value = getpass.getpass(prompt)
        if len(value) < minimum or any(ord(character) < 32 or ord(character) == 127 for character in value):
            fail("secret_input_invalid")
        atomic_write(target, value + "\n")
    print("SECRET_FILES_READY (values not displayed)")


def escape_pgpass(value):
    return value.replace("\\", "\\\\").replace(":", "\\:")


def service_config(admin_user):
    parser = configparser.ConfigParser(interpolation=None)
    for alias, user in (("goufayu_admin", admin_user), ("goufayu_migrator", "goufayu_migrator"), ("goufayu_app", "goufayu_app")):
        parser[alias] = {"host": "127.0.0.1", "port": "5432", "dbname": "goufayu_test", "user": user,
                         "connect_timeout": "5", "sslmode": "disable", "application_name": alias}
    return parser


def config_text(parser):
    import io
    stream = io.StringIO()
    # libpq service files do not accept ConfigParser's default "key = value".
    parser.write(stream, space_around_delimiters=False)
    return stream.getvalue()


def configure(args):
    import pwd
    account = pwd.getpwnam("goufayu")
    token = private_read(Path(args.api_token_file), 24)
    pepper = private_read(Path(args.pepper_file), 32)
    administrator_password = private_read(CONFIG / "postgres-password")
    if not re.fullmatch(r"[a-z_][a-z0-9_]{0,62}", args.admin_user):
        fail("admin_user_invalid")
    lua = Path(args.lua).resolve(strict=True)
    if not lua.is_file() or not os.access(lua, os.X_OK):
        fail("lua_executable_required")
    # Explicitly preserve an existing deployment's player identity and API token.
    if (CONFIG / "api.env").exists():
        previous = read_environment(CONFIG / "api.env")
        if previous.get("FISHING_API_TOKEN") != token or previous.get("FISHING_ACCOUNT_ID_PEPPER") != pepper:
            fail("existing_identity_differs_do_not_rotate_during_migration")
    for name in ("app-password", "migrator-password"):
        target = CONFIG / name
        if not target.exists():
            atomic_write(target, secrets.token_urlsafe(48) + "\n")
    app_password = private_read(CONFIG / "app-password", 32)
    migrator_password = private_read(CONFIG / "migrator-password", 32)
    atomic_write(SERVICE_FILE, config_text(service_config(args.admin_user)), 0o640, 0, account.pw_gid)
    # Wildcard DB supports fresh isolated restore databases; credentials retain role scope.
    for filename, username, password, owner in (
            ("admin.pgpass", args.admin_user, administrator_password, 0),
            ("migrator.pgpass", "goufayu_migrator", migrator_password, 0),
            ("app.pgpass", "goufayu_app", app_password, account.pw_uid)):
        line = ":".join(escape_pgpass(v) for v in ("127.0.0.1", "5432", "*", username, password)) + "\n"
        atomic_write(CONFIG / filename, line, 0o600, owner, account.pw_gid if owner else 0)
    env = {"FISHING_API_HOST": "127.0.0.1", "FISHING_API_PORT": "8765",
           "FISHING_API_TOKEN": token, "FISHING_ACCOUNT_ID_PEPPER": pepper,
           "FISHING_REQUEST_TIMEOUT_SECONDS": "8", "FISHING_DATABASE_BACKEND": "postgres",
           "POSTGRES_DSN": "service=goufayu_app",
           "PGSERVICEFILE": str(SERVICE_FILE), "PGPASSFILE": str(CONFIG / "app.pgpass"),
           "SURVIVAL_ADDON_ROOT": str(BASE / "current/addon"),
           "SURVIVAL_ARCHIVE_HTTP": "1", "ARCHIVE_LUA_PATH": str(lua), "PAYMENT_MODE": "test"}
    # The static startup shell command never interpolates these environment values.
    atomic_write(CONFIG / "api.env", "".join(k + "=" + json.dumps(v, ensure_ascii=False) + "\n" for k, v in env.items()))
    print("CONFIG_WRITTEN (role passwords not yet applied; service not started)")


def read_environment(path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        parsed = shlex.split(value, posix=True)
        if len(parsed) != 1:
            fail("environment_file_format_invalid")
        result[key.strip()] = parsed[0]
    return result


def admin_connection(dbname="goufayu_test"):
    import psycopg
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(SERVICE_FILE)
    user = parser["goufayu_admin"]["user"]
    return psycopg.connect(host="127.0.0.1", port=5432, dbname=dbname, user=user,
                           password=private_read(CONFIG / "postgres-password"),
                           connect_timeout=5, autocommit=True)


def bootstrap_sql(release):
    lines = (release / "database/init_roles.sql").read_text(encoding="utf-8-sig").splitlines()
    result = []
    for line in lines:
        if line.lstrip().startswith("\\"):
            if line.strip() != "\\set ON_ERROR_STOP on":
                fail("unsupported_bootstrap_psql_directive")
        else:
            result.append(line)
    return "\n".join(result)


def db_init(args):
    release = validated_release(args.release)
    if not args.confirm_empty:
        fail("db_init_requires_confirm_empty_target")
    with admin_connection() as connection:
        new_passwords = role_password_plan(connection)
        # init_roles.sql independently rejects any existing business relations.
        connection.execute(bootstrap_sql(release))
        configure_role_passwords(connection, new_passwords)
    print("EMPTY_TARGET_ROLES_READY (schema/data not migrated)")


def role_password_plan(connection):
    """Authenticate existing roles before mutation; plan passwords for new roles only."""
    import psycopg
    filenames = {"goufayu_migrator": "migrator-password", "goufayu_app": "app-password"}
    existing = {row[0] for row in connection.execute(
        "SELECT rolname FROM pg_roles WHERE rolname = ANY(%s)", (list(filenames),)).fetchall()}
    passwords = {role: private_read(CONFIG / filename, 32) for role, filename in filenames.items()}
    for role in existing:
        try:
            # Validate against the existing test DB before bootstrap or creation
            # of a trial DB. Do not change credentials shared by other databases.
            with psycopg.connect(host="127.0.0.1", port=5432, dbname="goufayu_test",
                                 user=role, password=passwords[role], connect_timeout=5,
                                 autocommit=True, options="-c default_transaction_read_only=on") as probe:
                identity = probe.execute("SELECT current_user, current_database()").fetchone()
                if tuple(identity) != (role, "goufayu_test"):
                    fail("existing_role_identity_mismatch")
        except Exception:
            fail("existing_role_credentials_rejected:" + role)
    return {role: password for role, password in passwords.items() if role not in existing}


def configure_role_passwords(connection, new_passwords):
    if not new_passwords:
        return
    from psycopg import sql
    for role, password in new_passwords.items():
        connection.execute(sql.SQL("ALTER ROLE {} PASSWORD {}").format(sql.Identifier(role), sql.Literal(password)))


def install_units(args):
    release = validated_release(args.release)
    names = ("goufayu-api.service", "goufayu-backup.service", "goufayu-backup.timer")
    # Validate isolated candidates before touching any installed configuration.
    # ExecStart=/bin/sh keeps first-install verification independent of current.
    with tempfile.TemporaryDirectory(prefix="unit-validation-", dir=STATE) as temporary:
        candidates = Path(temporary)
        for name in names:
            shutil.copyfile(release / "deploy" / name, candidates / name)
        proposed_logrotate = candidates / "goufayu.logrotate"
        shutil.copyfile(release / "deploy/goufayu.logrotate", proposed_logrotate)
        run(["systemd-analyze", "verify", *[candidates / name for name in names]])
        run(["logrotate", "--debug", proposed_logrotate])

        plan = [(candidates / name, UNIT_DIRECTORY / name) for name in names]
        plan.append((proposed_logrotate, LOGROTATE_FILE))
        changed, originals = [], []
        for source, destination in plan:
            if destination.is_symlink() or (destination.exists() and not destination.is_file()):
                fail("installed_configuration_not_regular_file")
            if destination.exists() and destination.read_bytes() == source.read_bytes():
                continue
            changed.append((source, destination))
            if destination.exists():
                originals.append(destination)

        if originals:
            backup_parent = STATE / "config-backups"
            if backup_parent.is_symlink():
                fail("configuration_backup_directory_symlink_rejected")
            backup_parent.mkdir(mode=0o700, exist_ok=True)
            backup_parent.chmod(0o700)
            backup = backup_parent / ("install-units-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + secrets.token_hex(4))
            backup.mkdir(mode=0o700)
            records = []
            for original in originals:
                saved = backup / original.name
                data = original.read_bytes()
                info = original.stat()
                atomic_write(saved, data, 0o600)
                records.append({"path": str(original), "saved": saved.name,
                                "sha256": hashlib.sha256(data).hexdigest(),
                                "mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid, "gid": info.st_gid})
            atomic_write(backup / "manifest.json", json.dumps({"release": release.name, "files": records}, indent=2) + "\n")
            print("EXISTING_CONFIGURATION_BACKED_UP " + str(backup))

        # Every changed original is backed up before the first replacement.
        for source, destination in changed:
            atomic_write(destination, source.read_bytes(), 0o644)
    if not (CONFIG / "backup.env").exists():
        atomic_write(CONFIG / "backup.env", (release / "deploy/backup.env.example").read_text())
    if changed:
        run(["systemctl", "daemon-reload"])
    print("UNITS_INSTALLED (API, backup timer and nginx not enabled)")


def health():
    config = read_environment(CONFIG / "api.env")
    with urllib.request.urlopen("http://127.0.0.1:8765/health", timeout=3) as response:
        if response.status != 200 or json.load(response).get("ok") is not True:
            fail("api_liveness_failed")
    readiness = urllib.request.Request("http://127.0.0.1:8765/ready", method="GET",
                                       headers={"Authorization": "Bearer " + config["FISHING_API_TOKEN"]})
    with urllib.request.urlopen(readiness, timeout=10) as response:
        result = json.load(response)
        if response.status != 200 or result.get("ok") is not True or result.get("database") != "ready":
            fail("database_readiness_failed")
    request = urllib.request.Request("http://127.0.0.1:8765/v1/archive/config", data=b"{}", method="POST",
                                    headers={"Content-Type": "application/json", "Authorization": "Bearer " + config["FISHING_API_TOKEN"]})
    with urllib.request.urlopen(request, timeout=5) as response:
        result = json.load(response)
        expected = json.loads((BASE / "current/addon/server/bundles/current.json").read_text())["hash"]
        if result.get("ok") is not True or result.get("config_hash") != expected:
            fail("archive_readiness_hash_mismatch")
    print("LOCAL_HTTP_DATABASE_READY_AND_ARCHIVE_HASH_OK (not a payment/gameplay/restore acceptance)")


def activate(args):
    release = validated_release(args.release)
    if not (release / ".venv/bin/python").is_file() or not (CONFIG / "api.env").is_file():
        fail("prepare_and_configure_before_activation")
    run(["systemctl", "is-active", "--quiet", "goufayu-db.service"])
    current = BASE / "current"
    if current.exists() and not current.is_symlink():
        fail("current_must_be_symlink")
    if current.is_symlink():
        atomic_write(STATE / "previous-release", str(current.resolve()) + "\n")
    temporary = BASE / (".current-" + secrets.token_hex(5))
    temporary.symlink_to(release, target_is_directory=True)
    os.replace(temporary, current)
    run(["systemctl", "enable", "goufayu-api.service"])
    run(["systemctl", "restart", "goufayu-api.service"])
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            health()
            print("RELEASE_ACTIVATED; database and offsite backup acceptance remain separate")
            return
        except Exception:
            time.sleep(1)
    run(["systemctl", "stop", "goufayu-api.service"])
    fail("activation_not_ready_service_stopped_no_automatic_database_rollback")


def trial_restore(args):
    from psycopg import sql
    release = validated_release(args.release)
    if not re.fullmatch(r"goufayu_restore_[a-z0-9_]{1,40}", args.name):
        fail("restore_name_must_be_new_goufayu_restore_suffix")
    backup = Path(args.backup).resolve(strict=True)
    target = STATE / "restore" / args.name
    if target.exists():
        fail("restore_evidence_directory_already_exists")
    with admin_connection() as connection:
        new_passwords = role_password_plan(connection)
        # No IF NOT EXISTS: an existing target is never reused/cleared.
        # Owner role might not exist yet on the first trial of a pristine host.
        connection.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(args.name)))
    with admin_connection(args.name) as connection:
        connection.execute(bootstrap_sql(release))
        configure_role_passwords(connection, new_passwords)
    target.mkdir(parents=True, mode=0o700)
    parser = configparser.ConfigParser(interpolation=None)
    parser["goufayu_trial"] = {"host": "127.0.0.1", "port": "5432", "dbname": args.name,
                               "user": "goufayu_migrator", "connect_timeout": "5", "sslmode": "disable"}
    atomic_write(target / "pg_service.conf", config_text(parser))
    env = {**os.environ, "PGSERVICEFILE": str(target / "pg_service.conf"), "PGPASSFILE": str(CONFIG / "migrator.pgpass")}
    run([release / ".venv/bin/python", release / "database/dbtool.py", "--pg-bin", args.pg_bin,
         "trial-restore", "--target-service", "goufayu_trial", "--backup", backup], env=env)
    atomic_write(target / "result.json", json.dumps({"ok": True, "database": args.name, "backup": str(backup),
                                                   "note": "DB CLI restore comparison succeeded; target retained for inspection"}, indent=2) + "\n")
    print("ISOLATED_RESTORE_VERIFIED; target retained, production/test database unchanged")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for command, function in (("prepare", prepare), ("db-init", db_init), ("install-units", install_units), ("activate", activate)):
        child = sub.add_parser(command)
        child.add_argument("--release", required=True)
        child.set_defaults(function=function)
        if command == "prepare": child.add_argument("--wheelhouse")
        if command == "db-init": child.add_argument("--confirm-empty", action="store_true")
    child = sub.add_parser("configure")
    child.add_argument("--api-token-file", required=True)
    child.add_argument("--pepper-file", required=True)
    child.add_argument("--admin-user", default="postgres")
    child.add_argument("--lua", default="/usr/bin/lua")
    child.set_defaults(function=configure)
    child = sub.add_parser("health")
    child.set_defaults(function=lambda args: health())
    child = sub.add_parser("capture-secrets")
    child.set_defaults(function=capture_secrets)
    child = sub.add_parser("trial-restore")
    child.add_argument("--release", required=True)
    child.add_argument("--backup", required=True)
    child.add_argument("--name", required=True)
    child.add_argument("--pg-bin", default=str(BASE / "current/deploy/pg-bin"))
    child.set_defaults(function=trial_restore)
    args = parser.parse_args()
    try:
        root_only()
        args.function(args)
        return 0
    except Exception as error:
        # Library errors may contain a DSN or SQL statement. Do not echo them.
        code = str(error) if type(error) is RuntimeError else type(error).__name__
        print("DEPLOY_ERROR " + code, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
