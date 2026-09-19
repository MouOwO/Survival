"""Use the existing PostgreSQL 17 container's client binaries without rebuilding it.

Only root may use this bridge. Host libpq service/password files stay on the
host; passwords are passed by environment variable name, never in argv. Host
dump paths are streamed on stdin/stdout, never written in the database volume.
The deliberately small CLI subset matches database/dbtool.py's exact commands.
"""
from __future__ import annotations

import configparser
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

TOOLS = {"pg_dump", "pg_restore", "psql"}
BARE_FLAGS = {"--no-password", "--no-owner", "--no-acl", "--no-publications", "--no-subscriptions",
              "--schema-only", "--single-transaction", "--exit-on-error", "--quiet", "--list"}
VALUE_FLAGS = {"--format", "--schema", "--extension", "--snapshot", "--role"}


def pass_fields(line):
    fields, part, escaped = [], [], False
    for character in line:
        if escaped:
            part.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == ":":
            fields.append("".join(part)); part = []
        else:
            part.append(character)
    if escaped:
        raise ValueError("invalid_pgpass_escape")
    fields.append("".join(part))
    return fields


def connection_environment(service):
    service_file = Path(os.environ.get("PGSERVICEFILE", "/etc/goufayu/pg_service.conf"))
    pass_file = Path(os.environ.get("PGPASSFILE", "/etc/goufayu/migrator.pgpass"))
    if service_file.is_symlink() or pass_file.is_symlink():
        raise ValueError("credential_symlinks_rejected")
    if pass_file.stat().st_uid != 0 or stat.S_IMODE(pass_file.stat().st_mode) & 0o077:
        raise ValueError("pgpass_must_be_root_0600")
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(service_file, encoding="utf-8")
    section = dict(parser[service])
    allowed = {"host", "port", "dbname", "user", "sslmode", "connect_timeout", "application_name"}
    if set(section) - allowed:
        raise ValueError("container_bridge_service_option_not_supported")
    if section.get("host") != "127.0.0.1" or section.get("port", "5432") != "5432":
        raise ValueError("container_bridge_only_supports_existing_local_database")
    database, username = section["dbname"], section["user"]
    if not re.fullmatch(r"goufayu_(test|restore_[a-z0-9_]+)", database):
        raise ValueError("container_bridge_database_not_allowed")
    password = None
    actual = ["127.0.0.1", "5432", database, username]
    for line in pass_file.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = pass_fields(line)
        if len(fields) == 5 and all(expected == "*" or expected == value for expected, value in zip(fields[:4], actual)):
            password = fields[4]
            break
    if password is None:
        raise ValueError("pgpass_entry_missing")
    result = {"PGHOST": "127.0.0.1", "PGPORT": "5432", "PGDATABASE": database, "PGUSER": username,
            "PGPASSWORD": password, "PGSSLMODE": section.get("sslmode", "disable"),
            "PGCONNECT_TIMEOUT": section.get("connect_timeout", "5"), "PGAPPNAME": "goufayu_pg17_bridge"}
    if os.environ.get("PGOPTIONS"):
        # Preserve the exporter’s read-only snapshot/session settings in pg_dump.
        if os.environ["PGOPTIONS"] != "-c default_transaction_read_only=on -c timezone=UTC -c datestyle=ISO,YMD":
            raise ValueError("unexpected_client_pgoptions")
        result["PGOPTIONS"] = os.environ["PGOPTIONS"]
    return result


def parse_arguments(tool, arguments):
    forwarded, service, output, source = [], None, None, None
    index = 0
    while index < len(arguments):
        item = arguments[index]
        if item.startswith("--dbname="):
            candidate = item[len("--dbname="):]
            match = re.fullmatch(r"service=([A-Za-z0-9_-]+)", candidate)
            if not match or service is not None:
                raise ValueError("only_one_libpq_service_alias_is_accepted")
            service = match[1]
        elif item.startswith("--file="):
            if output is not None:
                raise ValueError("duplicate_output")
            output = Path(item[len("--file="):]).resolve()
        elif item in {"--file", "-f"}:
            index += 1
            if index == len(arguments) or output is not None:
                raise ValueError("invalid_output")
            output = Path(arguments[index]).resolve()
        elif item in BARE_FLAGS:
            forwarded.append(item)
        elif any(item.startswith(flag + "=") for flag in VALUE_FLAGS):
            if item.startswith("--format=") and item != "--format=custom":
                raise ValueError("only_custom_dump_format_supported")
            forwarded.append(item)
        elif not item.startswith("-") and tool == "pg_restore" and source is None:
            source = Path(item).resolve(strict=True)
        else:
            raise ValueError("unsupported_pg_client_argument")
        index += 1
    if tool == "pg_dump" and not service:
        raise ValueError("dump_requires_service")
    if tool == "psql":
        # No free-form SQL or password-setting statements accepted by this bridge.
        raise ValueError("use_manage_py_for_role_configuration")
    if tool == "pg_restore" and source is None:
        raise ValueError("restore_requires_host_dump_file")
    return forwarded, service, output, source


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments or arguments[0] not in TOOLS:
        print("PG17_BRIDGE_ERROR tool_required", file=sys.stderr); return 2
    tool, arguments = arguments[0], arguments[1:]
    if sys.platform != "linux" or os.geteuid() != 0:
        print("PG17_BRIDGE_ERROR linux_root_required", file=sys.stderr); return 2
    try:
        if arguments == ["--version"]:
            result = subprocess.run(["podman", "exec", "goufayu-db", tool, "--version"], capture_output=True, check=True, text=True)
            if not re.search(r"\(PostgreSQL\) 17(?:\.|\s)", result.stdout):
                raise ValueError("postgresql_17_client_required")
            print(result.stdout.rstrip()); return 0
        forwarded, service, output, source = parse_arguments(tool, arguments)
        connection = connection_environment(service) if service else {}
        if tool == "pg_restore" and "--list" not in forwarded:
            if service is not None:
                # PGDATABASE alone does not select restore-to-database mode.
                # This is the already validated local database name, no DSN or
                # password; host/user/password remain in the scoped environment.
                forwarded.append("--dbname=" + connection["PGDATABASE"])
            elif output is not None:
                # The host owns --file's destination. PG17 still requires an
                # explicit SQL mode, so stdout feeds the host-side file writer.
                forwarded.append("--file=-")
        command = ["podman", "exec", "-i"]
        for key in connection:
            command += ["--env", key]  # Podman inherits the value by NAME only.
        command += ["goufayu-db", tool] + forwarded
        import contextlib
        with contextlib.ExitStack() as stack:
            reader = stack.enter_context(source.open("rb")) if source else subprocess.DEVNULL
            # Exclusive create prevents a failed/repeated backup overwriting evidence.
            writer = stack.enter_context(output.open("xb")) if output else None
            return subprocess.run(command, stdin=reader, stdout=writer,
                                  env={**os.environ, **connection}, check=False).returncode
    except Exception as error:
        # Never forward arbitrary library/connection exceptions containing secrets.
        code = str(error) if type(error) is ValueError else type(error).__name__
        print("PG17_BRIDGE_ERROR " + code, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
