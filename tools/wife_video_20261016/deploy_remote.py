"""Hash-pinned, additive wife-collection release operator; run only after review.

No gateway, order, login or real-player command is used. Publication preserves
all old reducers and adds exactly one approved immutable configuration. An exact
candidate/config-hash SQL branch preserves the existing compatibility policy for
every other release. Backup and rollback sources precede the first mutation.
"""
from __future__ import annotations

from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import contextlib
import copy
import fcntl
import hashlib
import importlib.util
import io
import json
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

STAGE = Path(__file__).resolve().parent
BASE = Path("/opt/goufayu/releases")


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def save(name, value):
    path = STAGE / name
    need(not path.is_symlink(), "report_symlink_refused")
    temporary = path.with_name(path.name + "." + secrets.token_hex(4))
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.chmod(0o600)
    os.replace(temporary, path)


def plan():
    data = json.loads((STAGE / "release_plan.json").read_bytes())
    need(data["version"] == 1 and len(data["candidate"]) == 64, "release_plan_invalid")
    return data


def paths():
    data = plan()
    prefix = "20261016-wife-" + data["candidate"][:12]
    return data, Path(data["old_release"]), BASE / prefix, BASE / (prefix + "-rollback")


def current(expected):
    data = plan()
    need((BASE / "current").is_symlink() and (BASE / "current").resolve() == expected, "archive_release_changed_since_review")
    need(Path("/opt/goufayu/payments/current").resolve() == Path(data["payment_release"]), "payment_release_changed_since_review")


def manifest_check(root, files):
    for name, digest in files.items():
        relative = PurePosixPath(name)
        need(not relative.is_absolute() and ".." not in relative.parts and "\\" not in name, "unsafe_manifest_path")
        path = root / name
        need(not path.is_symlink() and path.is_file() and sha(path) == digest, "manifest_checksum_mismatch:" + name)


def baseline():
    data, old, _, _ = paths()
    need(sha(old / "release_manifest.json") == data["old_manifest"], "baseline_manifest_changed")
    need(sha(old / "backend/archive_backend/service.py") == data["old_service"], "baseline_service_changed")
    original = json.loads((old / "release_manifest.json").read_bytes())
    manifest_check(old, original["files"])
    need(json.loads((old / "addon/server/bundles/current.json").read_bytes())["hash"] == data["base"], "baseline_bundle_changed")
    return original


def payment_deploy():
    return load("wife_payment_connection", Path(plan()["payment_release"]) / "deploy.py")


def health():
    data = plan()
    result = {}
    for name, port in (("archive", 8765), ("payment", 8766)):
        with urllib.request.urlopen("http://127.0.0.1:" + str(port) + "/health", timeout=5) as response:
            body = json.load(response)
            need(response.status == 200 and body.get("ok") is True, "health_failed:" + name)
            result[name] = body
    return result


def backup():
    data, old, _, _ = paths()
    current(old)
    baseline()
    health()
    directory = Path("/var/backups/goufayu-wife") / data["candidate"]
    need(not directory.exists(), "backup_directory_exists")
    directory.mkdir(mode=0o700, parents=True)
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        payment_deploy().backup()
    database = json.loads(captured.getvalue().splitlines()[-1])
    dump = Path(database["local_backup"])
    need(dump.is_file() and dump.stat().st_size > 0 and dump.with_suffix(".sha256").read_text().strip() == sha(dump), "database_backup_invalid")
    with payment_deploy().connection() as connection:
        connection.execute("SET TRANSACTION READ ONLY")
        definition = connection.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
        need(hashlib.sha256(definition.encode()).hexdigest() == data["old_sync_function"], "archive_sync_function_changed")
        (directory / "archive_sync_config_before.sql").write_text(definition)
        connection.rollback()
    with tarfile.open(directory / "release_sources.tar.gz", "x:gz") as archive:
        for name in [*baseline()["files"], "release_manifest.json"]:
            archive.add(old / name, arcname=name, recursive=False)
    record = {"status": "BACKED_UP", "created_utc": datetime.now(timezone.utc).isoformat(),
        "directory": str(directory), "database_backup": str(dump), "database_sha256": sha(dump),
        "source_sha256": sha(directory / "release_sources.tar.gz"), "offsite": False}
    save("backup.json", record)
    return record


def backup_verified():
    record = json.loads((STAGE / "backup.json").read_bytes())
    need(sha(record["database_backup"]) == record["database_sha256"], "database_backup_changed")
    need(sha(Path(record["directory"]) / "release_sources.tar.gz") == record["source_sha256"], "source_backup_changed")
    return record


def unpack():
    data = plan()
    directory = STAGE / "payload"
    need(not directory.exists(), "payload_already_exists")
    directory.mkdir(mode=0o700)
    with tarfile.open(STAGE / "wife_patch.tar.gz", "r:gz") as archive:
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            need(not path.is_absolute() and ".." not in path.parts and "\\" not in member.name and member.isfile(), "unsafe_tar_member")
            target = directory / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source, target.open("xb") as sink:
                shutil.copyfileobj(source, sink)
    need(json.loads((directory / "release_plan.json").read_bytes()) == data, "payload_plan_mismatch")
    manifest_check(directory, data["files"])
    need({p.relative_to(directory).as_posix() for p in directory.rglob("*") if p.is_file()} == set(data["files"]) | {"release_plan.json"}, "unmanifested_payload_file")


def clone_release(destination, original, activate_pointer):
    data, old, _, _ = paths()
    need(not destination.exists(), "release_destination_exists")
    destination.mkdir(mode=0o755)
    for name in original["files"]:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old / name, target)
    shutil.copytree(STAGE / "payload/bundle" / data["candidate"], destination / "addon/server/bundles" / data["candidate"])
    allowed = []
    if activate_pointer:
        (destination / "addon/server/bundles/current.json").write_text(json.dumps({"hash": data["candidate"], "protocol": 1}))
        allowed.append("addon/server/bundles/current.json")
        if data["added_stat_definitions"]:
            name = "addon/data/csv/玩家档案系统/player_gameplay_stats.csv"
            shutil.copyfile(STAGE / "payload" / name, destination / name)
            allowed.append(name)
    changed = sorted(name for name, digest in original["files"].items() if sha(destination / name) != digest)
    need(changed == sorted(allowed), "unrelated_release_file_changed")
    metadata = copy.deepcopy(original)
    metadata.update(release=destination.name, previous_release=old.name,
        archive_bundle=data["candidate"] if activate_pointer else data["base"], description="Reviewed video wife collection")
    metadata["files"] = {p.relative_to(destination).as_posix(): sha(p) for p in destination.rglob("*") if p.is_file()}
    (destination / "release_manifest.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    for path in destination.rglob("*"):
        path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
    (destination / ".venv").symlink_to(old / ".venv", target_is_directory=True)
    load("wife_validate_" + destination.name, destination / "deploy/manage.py").validated_release(str(destination))
    return {"release": str(destination), "changed_existing_files": changed,
            "manifest_sha256": sha(destination / "release_manifest.json")}


def prepare():
    data, old, target, rollback = paths()
    current(old)
    original = baseline()
    backup_verified()
    unpack()
    record = {"status": "PREPARED_NOT_ACTIVATED", "target": clone_release(target, original, True),
              "rollback": clone_release(rollback, original, False)}
    save("prepared.json", record)
    return record


def prepared():
    data, old, target, rollback = paths()
    baseline()
    backup_verified()
    record = json.loads((STAGE / "prepared.json").read_bytes())
    for name, directory in (("target", target), ("rollback", rollback)):
        need(sha(directory / "release_manifest.json") == record[name]["manifest_sha256"], "prepared_manifest_changed")
        load("wife_check_" + name, directory / "deploy/manage.py").validated_release(str(directory))
    sys.path.insert(0, str(target / "backend"))
    from archive_backend.bundle import Bundle
    bundle = Bundle(target / "addon/server/bundles" / data["candidate"])
    need(bundle.hash == data["candidate"], "prepared_bundle_changed")
    original = Bundle(old / "addon/server/bundles" / data["base"])
    before = json.loads((original.directory / "bundle.json").read_bytes())
    after = json.loads((bundle.directory / "bundle.json").read_bytes())
    source_name = "systems/archive_social_rewards.lua"
    patcher = load("wife_social_source_patch", STAGE / "social_source_patch.py")
    expected_sources = copy.deepcopy(before["sources"])
    expected_sources[source_name] = patcher.transform(expected_sources[source_name])
    need(after["sources"] == expected_sources and set(after["configs"]) == set(before["configs"]), "prepared_source_or_table_set_changed")
    selectors = {"archive_social_items": ("pool_id", "wife"), "archive_social_rules": ("pool_id", "wife"),
        "archive_categories": ("category_id", "wife"), "archive_challenge_definitions": ("challenge_id", "social_wife"),
        "archive_challenge_stats": ("challenge_id", "social_wife")}
    for name, old_table in before["configs"].items():
        new_table = after["configs"][name]
        count = len(old_table["rows"])
        need(new_table["key"] == old_table["key"] and new_table["rows"][:count] == old_table["rows"], "prepared_existing_rows_changed:" + name)
        extra = new_table["rows"][count:]
        if name in selectors:
            field, expected = selectors[name]
            expected_count = data["wife_count"] if name == "archive_social_items" else 10 if name == "archive_challenge_stats" else 1
            need(len(extra) == expected_count and all(row.get(field) == expected for row in extra), "prepared_nonwife_rows_added:" + name)
        elif name == "player_gameplay_stats":
            need(extra == data["added_stat_definitions"], "prepared_unreviewed_stat_additions")
        else:
            need(not extra, "prepared_unrelated_table_changed:" + name)
    need(all(after.get("compatible_config_hashes", {}).get(k) == value for k, value in before.get("compatible_config_hashes", {}).items()), "prepared_historical_alias_changed")
    added_aliases = set(after.get("compatible_config_hashes", {})) - set(before.get("compatible_config_hashes", {}))
    need(added_aliases == {data["base"]} and after["compatible_config_hashes"][data["base"]]["upgrade_commands"] == [], "prepared_unreviewed_alias")
    return bundle


def configuration(bundle):
    return {"configs": bundle.configs, "compatible_config_hashes": {
        key: {field: sorted(values) for field, values in rule.items()}
        for key, rule in bundle.compatible_config_hashes.items()}}


def function_state(connection):
    row = connection.execute("""SELECT pg_get_functiondef(oid),pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text
        FROM pg_proc WHERE oid='public.archive_sync_config(text,jsonb)'::regprocedure""").fetchone()
    return {"definition_sha256": hashlib.sha256(row[0].encode()).hexdigest(), "owner": row[1],
            "security_definer": row[2], "configuration": row[3], "acl": row[4]}, row[0]


def candidate_function(connection, bundle):
    from psycopg.types.json import Jsonb
    data = plan()
    _, old_definition = function_state(connection)
    need(hashlib.sha256(old_definition.encode()).hexdigest() == data["old_sync_function"], "sync_function_changed_since_review")
    # Bind this one new hash to the exact complete configuration. All other
    # hashes continue through every byte of the existing compatibility policy.
    config_hash = connection.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(configuration(bundle)),)).fetchone()[0]
    marker = " -- Compatibility is part of the immutable config record, not a mutable alias."
    need(old_definition.count(marker) == 1, "sync_extension_marker_changed")
    branch = """ -- Reviewed wife collection: one exact immutable candidate, no generic aliases.
 if p_hash='{candidate}' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'{config_hash}' then
   raise exception 'archive_wife_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
""".format(candidate=data["candidate"], config_hash=config_hash)
    updated = old_definition.replace(marker, branch + marker)
    need(updated.replace(branch, "", 1) == old_definition, "sync_extension_not_exactly_reversible")
    return updated


def add_columns(connection):
    from psycopg import sql
    for row in plan()["added_stat_definitions"]:
        field = row["field_id"]
        existing = connection.execute("SELECT 1 FROM pg_attribute WHERE attrelid='public.player_gameplay_stats'::regclass AND attname=%s AND NOT attisdropped", (field,)).fetchone()
        need(existing is None, "new_stat_column_already_exists:" + field)
        kind = sql.SQL("bigint" if row["storage_type"] == "integer" else "numeric")
        connection.execute(sql.SQL("ALTER TABLE public.player_gameplay_stats ADD COLUMN {} {} NOT NULL DEFAULT 0").format(sql.Identifier(field), kind))
        lower = row.get("min_value", 0)
        maximum = row.get("max_value")
        condition = sql.SQL("{} >= {}").format(sql.Identifier(field), sql.Literal(lower))
        if maximum is not None:
            condition += sql.SQL(" AND {} <= {}").format(sql.Identifier(field), sql.Literal(maximum))
        connection.execute(sql.SQL("ALTER TABLE public.player_gameplay_stats ADD CONSTRAINT {} CHECK ({})").format(sql.Identifier("wife_" + field + "_bounds"), condition))


def table_state(connection):
    from psycopg import sql
    names = connection.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename").fetchall()
    added = [row["field_id"] for row in plan()["added_stat_definitions"]]
    result = {}
    for schema, name in names:
        expression = sql.SQL("to_jsonb(t)-{}::text[]").format(sql.Literal(added)) if (schema, name) == ("public", "player_gameplay_stats") else sql.SQL("to_jsonb(t)")
        result[schema + "." + name] = connection.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(({})::text,chr(10) ORDER BY ({})::text),'')) FROM {}.{} t").format(expression, expression, sql.Identifier(schema), sql.Identifier(name))).fetchone()
    return result


def transaction(connection, publish):
    from psycopg import sql
    connection.execute("SET TRANSACTION ISOLATION LEVEL " + ("READ COMMITTED" if publish else "REPEATABLE READ"))
    connection.execute("SET LOCAL lock_timeout='5s'")
    connection.execute("SET LOCAL statement_timeout='90s'")
    connection.execute("SET ROLE goufayu_owner")
    need(connection.execute("SELECT current_database()").fetchone()[0] == "goufayu_test", "unexpected_database")
    connection.execute("SELECT pg_advisory_xact_lock(hashtext('survival.wife_collection.publish'))")
    names = connection.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename").fetchall()
    connection.execute(sql.SQL("LOCK TABLE {} IN EXCLUSIVE MODE").format(sql.SQL(",").join(sql.Identifier(s, n) for s, n in names)))


def register(connection, bundle):
    from psycopg.types.json import Jsonb
    before = {row[0]["config_hash"]: row[0] for row in connection.execute("SELECT to_jsonb(c) FROM public.archive_config_sets c")}
    cfg = configuration(bundle)
    result = connection.execute("SELECT public.archive_sync_config(%s,%s)", (bundle.hash, Jsonb(cfg))).fetchone()[0]
    need(result.get("ok") is True, "config_registration_failed")
    after = {row[0]["config_hash"]: row[0] for row in connection.execute("SELECT to_jsonb(c) FROM public.archive_config_sets c")}
    need(all(after.get(key) == value for key, value in before.items()) and set(after) == set(before) | {bundle.hash}, "existing_config_rows_modified")
    need(after[bundle.hash]["config"] == cfg, "registered_config_differs")


def database_check(bundle, commit=False):
    data, old, _, _ = paths()
    current(old)
    with payment_deploy().connection() as connection:
        try:
            transaction(connection, commit)
            before = table_state(connection)
            security, _ = function_state(connection)
            new_definition = candidate_function(connection, bundle)
            add_columns(connection)
            connection.execute(new_definition)
            after_security, _ = function_state(connection)
            need({k: v for k, v in security.items() if k != "definition_sha256"} == {k: v for k, v in after_security.items() if k != "definition_sha256"}, "sync_security_metadata_changed")
            register(connection, bundle)
            after = table_state(connection)
            changed = [name for name in before if before[name] != after.get(name)]
            need(set(changed) <= {"public.archive_config_sets"}, "business_rows_changed:" + ",".join(changed))
            current(old)
            if commit:
                connection.commit()
            else:
                connection.rollback()
            result = {"status": "COMMITTED" if commit else "PASS_ROLLED_BACK", "changed_tables": changed,
                "original_player_order_payment_rows_preserved": True, "old_sync_sha256": security["definition_sha256"],
                "new_sync_sha256": after_security["definition_sha256"], "added_columns": [r["field_id"] for r in data["added_stat_definitions"]]}
            save("database_committed.json" if commit else "database_validation.json", result)
            return result
        except BaseException:
            connection.rollback()
            raise


def smoke(bundle):
    lua = shutil.which("lua5.1") or shutil.which("lua")
    need(lua is not None, "lua_interpreter_missing")
    return load("wife_worker_smoke", STAGE / "smoke.py").run(bundle.directory, lua)


def validate():
    _, old, _, _ = paths()
    current(old)
    bundle = prepared()
    result = {"status": "VALIDATED_NOT_ACTIVATED", "worker": smoke(bundle), "database": database_check(bundle)}
    save("validation.json", result)
    return result


def switch(directory):
    temporary = BASE / (".wife-current-" + secrets.token_hex(6))
    temporary.symlink_to(directory, target_is_directory=True)
    os.replace(temporary, BASE / "current")
    subprocess.run(["systemctl", "restart", "goufayu-api.service"], check=True, timeout=35)
    manage = load("wife_active_health_" + directory.name, directory / "deploy/manage.py")
    for attempt in range(25):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                manage.health()
            return
        except Exception:
            if attempt == 24:
                raise RuntimeError("archive_readiness_failed")
            time.sleep(0.5)


def activate():
    data, old, target, rollback = paths()
    current(old)
    bundle = prepared()
    need(json.loads((STAGE / "validation.json").read_bytes())["status"] == "VALIDATED_NOT_ACTIVATED", "validation_required")
    checked = smoke(bundle)
    database_check(bundle, commit=True)
    try:
        current(old)
        switch(target)
        result = verify()
        result.update(status="DEPLOYED", worker=checked, previous_release=str(old), rollback_release=str(rollback),
                      backup=json.loads((STAGE / "backup.json").read_bytes()))
        save("activated.json", result)
        return result
    except BaseException:
        if (BASE / "current").resolve() == target:
            switch(rollback)
        save("activation_failed.json", {"status": "CODE_ROLLED_BACK", "new_immutable_config_and_reducers_retained": True,
                                       "current": str((BASE / "current").resolve())})
        raise


def verify():
    data, _, target, _ = paths()
    current(target)
    bundle = prepared()
    with contextlib.redirect_stdout(io.StringIO()):
        load("wife_verify_manage", target / "deploy/manage.py").health()
    with payment_deploy().connection() as connection:
        connection.execute("SET TRANSACTION READ ONLY")
        actual = connection.execute("SELECT config FROM public.archive_config_sets WHERE config_hash=%s", (data["candidate"],)).fetchone()
        need(actual and actual[0] == configuration(bundle), "published_configuration_differs")
        meta, _ = function_state(connection)
        committed = json.loads((STAGE / "database_committed.json").read_bytes())
        need(meta["definition_sha256"] == committed["new_sync_sha256"], "published_sync_function_differs")
        connection.rollback()
    return {"status": "VERIFIED", "archive_release": str(target), "archive_bundle": bundle.hash,
        "wife_count": data["wife_count"], "wife_draw_count": data["wife_draw_count"],
        "unavailable_wife_ids": data["unavailable_wife_ids"], "payment_release": data["payment_release"], "health": health(),
        "archive_service_sha256": sha(target / "backend/archive_backend/service.py"),
        "sync_function": meta, "all_old_reducers_retained": True, "gateway_requests": 0,
        "real_account_commands": 0, "test_fixture_rows_committed": 0}


if __name__ == "__main__":
    need(os.geteuid() == 0, "root_required")
    os.umask(0o022)
    sys.dont_write_bytecode = True
    with open("/var/lock/goufayu-wife-collection.lock", "w") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        action = sys.argv[1]
        need(action in {"backup", "prepare", "validate", "activate", "verify"}, "unsupported_action")
        result = globals()[action]()
        save(action + "_result.json", result)
        print(json.dumps(result, ensure_ascii=False))
