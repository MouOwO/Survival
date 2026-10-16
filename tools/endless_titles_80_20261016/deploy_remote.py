"""Hash-pinned archive-only endless-title publication; execution belongs to the root agent.

No player/profile/login, gateway, order or cash catalog operation is called.
Backup precedes all writes. Validation rolls back every fixture/function/config.
Activation commits only one guarded function and one immutable archive config.
"""
from __future__ import annotations
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import argparse, contextlib, copy, hashlib, importlib.util, io, json, os
import re, secrets, shutil, subprocess, sys, tarfile, time, urllib.request

try:
    import fcntl
except ImportError:
    fcntl = None

STAGE = Path(__file__).resolve().parent
BASE = Path("/opt/goufayu/releases")
OLD = BASE / "20261016-collection-rarity-fbf16c3e996f"
TARGET = BASE / "20261016-endless-titles-v1"
ROLLBACK = BASE / "20261016-endless-titles-rollback-v1"
PAY = Path("/opt/goufayu/payments/20261015-payment02")
BEFORE = "fbf16c3e996fa377f0d3cacd726c919f93958ecaf8be94a52b89ee08719f52e9"
OLD_MANIFEST = "b5b4b6908997af67a9663bfbb273b994ec36ca853ae85a9c08168ce88e7a3b96"
OLD_SERVICE = "3f87fd4b219c20fedac5176c2ea7153f4e639dced48badc571781019755b6993"
PAY_MANIFEST = "ab18979b1194a3a3877b3a0635ff9f970e2838ff97783227d2e27a06571b1419"
CASH_HASH = "b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe"
OLD_SYNC = "c4e7fcf889562fcd436b925510cca2d1c787bf515634c108797c00d134223ce1"
APPLY_SHA = "6bef548e25b839749ce042748aa3f79ad5ae43c6fa898bedd785c9b940f038f5"
SYNC = "public.archive_sync_config(text,jsonb)"
APPLY = "payments.apply_effects(text,jsonb,boolean)"
TABLES = 28
EXPECTED_PLAN_SHA = None
EXPECTED_OPERATOR_SHA = None
ALLOWED_CONFIGS = {"archive_titles"}
ALLOWED_CSV = {"data/csv/存档系统/archive_titles.csv"}
ALLOWED_SOURCES = {"systems/archive_titles.lua", "systems/archive_settlement.lua"}
CANDIDATE = "60d6ce00a7d3257b6982492fdfdf68aa8deacdb4d46f837248ecfbef5ebdec94"
TITLE_SYNC = '    require("systems/archive_titles").sync(archive)\n'
FUNCTION_SECURITY = {
    "sync": {"owner": "goufayu_owner", "security_definer": True,
        "configuration": ["search_path=pg_catalog, public, extensions, pg_temp"],
        "acl": "{goufayu_owner=X/goufayu_owner,goufayu_app=X/goufayu_owner}"},
    "payment": {"owner": "goufayu_owner", "security_definer": True,
        "configuration": ["search_path=pg_catalog, public, pg_temp"],
        "acl": "{goufayu_owner=X/goufayu_owner}"},
}



def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def save(name, data):
    path = STAGE / name
    need(not path.is_symlink(), "report_symlink_refused")
    temporary = path.with_name(path.name + "." + secrets.token_hex(4))
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    temporary.chmod(0o600)
    os.replace(temporary, path)


def plan():
    path = STAGE / "release_plan.json"
    need(EXPECTED_PLAN_SHA and sha(path) == EXPECTED_PLAN_SHA, "release_plan_changed")
    need(EXPECTED_OPERATOR_SHA and sha(Path(__file__)) == EXPECTED_OPERATOR_SHA, "deployment_operator_changed")
    data = json.loads(path.read_bytes())
    expected = {"version": 1, "kind": "endless_titles_80_only", "base": BEFORE, "candidate": CANDIDATE,
        "old_release": str(OLD), "target_release": str(TARGET), "rollback_release": str(ROLLBACK),
        "old_manifest": OLD_MANIFEST, "old_service": OLD_SERVICE, "payment_release": str(PAY),
        "payment_manifest": PAY_MANIFEST, "payment_catalog_hash": CASH_HASH,
        "payment_enabled_products": 44, "old_sync_function": OLD_SYNC}
    need(all(data.get(k) == v for k, v in expected.items()), "release_plan_baseline_mismatch")
    for field in ("candidate", "new_sync_function", "cfg_pg_sha256", "tar_sha256"):
        need(re.fullmatch(r"[0-9a-f]{64}", str(data.get(field, ""))), "release_plan_digest_invalid:" + field)
    need(data["candidate"] != BEFORE and isinstance(data.get("files"), dict), "release_plan_candidate_invalid")
    return data


def record(name):
    value = json.loads((STAGE / name).read_bytes())
    need(value.get("plan_sha256") == EXPECTED_PLAN_SHA and value.get("operator_sha256") == EXPECTED_OPERATOR_SHA, "phase_record_changed:" + name)
    return value


def stamp(data):
    return {**data, "plan_sha256": EXPECTED_PLAN_SHA, "operator_sha256": EXPECTED_OPERATOR_SHA}


def current(expected):
    plan()
    pointer = BASE / "current"
    need(pointer.is_symlink() and pointer.resolve() == expected, "archive_release_changed_since_review")
    payment = PAY.parent / "current"
    need(payment.is_symlink() and payment.resolve() == PAY, "payment_release_changed_since_review")


def safe_relative(name):
    relative = PurePosixPath(name)
    need(name and not relative.is_absolute() and ".." not in relative.parts and "\\" not in name and ":" not in name
         and relative.as_posix() == name, "unsafe_manifest_path")
    return relative


def manifest_check(root, files):
    need(isinstance(files, dict) and bool(files), "empty_manifest")
    for name, digest in files.items():
        relative = safe_relative(name)
        need(re.fullmatch(r"[0-9a-f]{64}", str(digest)), "invalid_manifest_digest")
        path = root.joinpath(*relative.parts)
        need(not any(q.is_symlink() for q in (path, *path.parents) if q != root.parent), "manifest_symlink_refused")
        need(path.is_file() and sha(path) == digest, "manifest_checksum_mismatch:" + name)


def baseline():
    plan()
    need(sha(OLD / "release_manifest.json") == OLD_MANIFEST, "baseline_manifest_changed")
    need(sha(OLD / "backend/archive_backend/service.py") == OLD_SERVICE, "baseline_service_changed")
    metadata = json.loads((OLD / "release_manifest.json").read_bytes())
    manifest_check(OLD, metadata["files"])
    load("shop_old_manifest_check", OLD / "deploy/manage.py").validated_release(str(OLD))
    need(json.loads((OLD / "addon/server/bundles/current.json").read_bytes())["hash"] == BEFORE, "baseline_bundle_changed")
    need(sha(PAY / "manifest.json") == PAY_MANIFEST, "payment_manifest_changed")
    manifest_check(PAY, json.loads((PAY / "manifest.json").read_bytes()))
    return metadata


def payment_deploy():
    return load("shop_payment_connection", PAY / "deploy.py")


def function_state(connection, signature):
    row = connection.execute("""SELECT pg_get_functiondef(oid),pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text
        FROM pg_proc WHERE oid=%s::regprocedure""", (signature,)).fetchone()
    need(row is not None, "required_function_missing")
    return {"definition_sha256": hashlib.sha256(row[0].encode()).hexdigest(), "owner": row[1],
            "security_definer": row[2], "configuration": row[3], "acl": row[4]}, row[0]


def invariants(connection, allowed_sync):
    data = plan()
    need(connection.execute("SELECT current_database()").fetchone()[0] == "goufayu_test", "unexpected_database")
    sync, _ = function_state(connection, SYNC)
    apply, _ = function_state(connection, APPLY)
    need(sync["definition_sha256"] in allowed_sync, "archive_sync_function_changed")
    need(sync["security_definer"] and apply["security_definer"], "function_security_invalid")
    for name, state in (("sync", sync), ("payment", apply)):
        need({key: state[key] for key in ("owner", "security_definer", "configuration", "acl")} == FUNCTION_SECURITY[name],
            "reviewed_function_security_changed:" + name)
    need(apply["definition_sha256"] == APPLY_SHA, "payment_function_changed")
    need(connection.execute("SELECT catalog_hash FROM payments.catalog_state WHERE singleton").fetchone()[0] == CASH_HASH, "payment_catalog_hash_changed")
    need(connection.execute("SELECT count(*) FROM payments.products WHERE enabled").fetchone()[0] == 44, "payment_product_count_changed")
    if (STAGE / "backup.json").exists():
        original = record("backup.json")
        need(apply == original["payment_function"], "payment_function_security_changed")
        security = {"owner", "security_definer", "configuration", "acl"}
        need({k: sync[k] for k in security} == {k: original["sync_function"][k] for k in security}, "sync_function_security_changed")
    return {"sync": sync, "payment": apply}


def health():
    result = {}
    for name, port in (("archive", 8765), ("payment", 8766)):
        with urllib.request.urlopen("http://127.0.0.1:" + str(port) + "/health", timeout=5) as response:
            body = json.load(response)
            need(response.status == 200 and body.get("ok") is True, "health_failed:" + name)
            result[name] = {"ok": body["ok"], "service": body.get("service")}
    return result


def backup():
    data = plan(); current(OLD); original = baseline(); health()
    directory = Path("/var/backups/goufayu-endless-titles") / data["candidate"]
    need(not directory.exists() and not directory.is_symlink(), "backup_directory_exists")
    directory.mkdir(mode=0o700, parents=True); directory.chmod(0o700)
    with payment_deploy().connection() as connection:
        connection.execute("SET TRANSACTION READ ONLY")
        state = invariants(connection, {OLD_SYNC})
        for name, signature in (("archive_sync_config_before.sql", SYNC), ("apply_effects_unchanged.sql", APPLY)):
            (directory / name).write_text(function_state(connection, signature)[1], encoding="utf-8")
        connection.rollback()
    with tarfile.open(directory / "release_sources.tar.gz", "x:gz") as archive:
        for prefix, location, names in (("archive", OLD, [*original["files"], "release_manifest.json"]),
                ("payment", PAY, [*json.loads((PAY / "manifest.json").read_bytes()), "manifest.json"])):
            for name in names:
                archive.add(location / name, arcname=prefix + "/" + name, recursive=False)
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        payment_deploy().backup()
    details = json.loads(captured.getvalue().splitlines()[-1])
    dump = Path(details["local_backup"])
    need(dump.is_file() and dump.stat().st_size > 0 and dump.with_suffix(".sha256").read_text().strip() == sha(dump), "database_backup_invalid")
    result = stamp({"status": "BACKED_UP", "created_utc": datetime.now(timezone.utc).isoformat(),
        "directory": str(directory), "database_backup": str(dump), "database_sha256": sha(dump),
        "source_backup": str(directory / "release_sources.tar.gz"), "source_sha256": sha(directory / "release_sources.tar.gz"),
        "sync_function": state["sync"], "payment_function": state["payment"], "offsite": False})
    save("backup.json", result)
    (directory / "backup.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def backup_verified():
    result = record("backup.json")
    need(sha(result["database_backup"]) == result["database_sha256"], "database_backup_changed")
    need(sha(result["source_backup"]) == result["source_sha256"], "source_backup_changed")
    return result


def unpack():
    data = plan(); archive_path = STAGE / "overlay.tar.gz"; directory = STAGE / "payload"
    need(sha(archive_path) == data["tar_sha256"], "uploaded_tar_changed")
    need(not directory.exists() and not directory.is_symlink(), "payload_already_exists")
    directory.mkdir(mode=0o700)
    with tarfile.open(archive_path, "r:gz") as archive:
        seen = set()
        for member in archive.getmembers():
            safe_relative(member.name)
            need(member.isfile() and member.name not in seen, "unsafe_or_duplicate_tar_member")
            seen.add(member.name)
            target = directory / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source, target.open("xb") as sink:
                shutil.copyfileobj(source, sink)
            target.chmod(0o600)
    manifest_check(directory, data["files"])
    actual = {p.relative_to(directory).as_posix() for p in directory.rglob("*") if p.is_file()}
    need(actual == set(data["files"]), "unmanifested_payload_file")


def clone_release(destination, original, selected):
    data = plan()
    need(not destination.exists() and not destination.is_symlink(), "release_destination_exists")
    destination.mkdir(mode=0o755)
    for name in original["files"]:
        target = destination / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(OLD / name, target)
    shutil.copytree(STAGE / "payload/bundle" / data["candidate"], destination / "addon/server/bundles" / data["candidate"])
    if selected:
        (destination / "addon/server/bundles/current.json").write_text(json.dumps({"hash": data["candidate"], "protocol": 1}), encoding="utf-8")
    changed = sorted(name for name, digest in original["files"].items() if sha(destination / name) != digest)
    need(changed == (["addon/server/bundles/current.json"] if selected else []), "unrelated_release_file_changed")
    metadata = copy.deepcopy(original)
    metadata.update(release=destination.name, previous_release=OLD.name,
        archive_bundle=data["candidate"] if selected else BEFORE,
        description="Nine cosmetic title tiers by trusted endless progress; collection rarity, payments and other reducers preserved")
    metadata["files"] = {p.relative_to(destination).as_posix(): sha(p) for p in destination.rglob("*") if p.is_file()}
    (destination / "release_manifest.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for path in destination.rglob("*"):
        path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
    (destination / ".venv").symlink_to(OLD / ".venv", target_is_directory=True)
    load("shop_check_release_" + destination.name, destination / "deploy/manage.py").validated_release(str(destination))
    return {"release": str(destination), "changed_existing_files": changed, "manifest_sha256": sha(destination / "release_manifest.json")}


def prepare():
    current(OLD); original = baseline(); backup_verified(); unpack()
    result = stamp({"status": "PREPARED_NOT_ACTIVATED", "target": clone_release(TARGET, original, True),
        "rollback": clone_release(ROLLBACK, original, False)})
    save("prepared.json", result); prepared()
    return result


def row_map(table):
    key = table["key"]
    return {row[key]: row for row in table["rows"]}


def prepared():
    data = plan(); baseline(); backup_verified(); saved = record("prepared.json")
    manifest_check(STAGE / "payload", data["files"])
    for name, directory in (("target", TARGET), ("rollback", ROLLBACK)):
        need(sha(directory / "release_manifest.json") == saved[name]["manifest_sha256"], "prepared_manifest_changed")
        load("titles_prepared_" + name, directory / "deploy/manage.py").validated_release(str(directory))
        need(sha(directory / "backend/archive_backend/service.py") == OLD_SERVICE, "prepared_service_changed")
    sys.path.insert(0, str(TARGET / "backend"))
    from archive_backend.bundle import Bundle
    bundle = Bundle(TARGET / "addon/server/bundles" / data["candidate"])
    original = Bundle(OLD / "addon/server/bundles" / BEFORE)
    before = json.loads((original.directory / "bundle.json").read_bytes())
    after = json.loads((bundle.directory / "bundle.json").read_bytes())
    need(set(before) == set(after), "bundle_top_level_changed")
    for section, allowed in (("configs", ALLOWED_CONFIGS), ("csv_hashes", ALLOWED_CSV), ("sources", ALLOWED_SOURCES)):
        need(set(before[section]) == set(after[section]), "bundle_key_set_changed:" + section)
        changed = {key for key in before[section] if before[section][key] != after[section][key]}
        need(changed == allowed, "unapproved_bundle_change:" + section)
    need(all(before[key] == after[key] for key in before if key not in {"configs", "csv_hashes", "sources"}), "compatibility_or_protocol_changed")
    need(before.get("compatible_config_hashes", {}) == after.get("compatible_config_hashes", {}), "historical_alias_changed")
    need(BEFORE not in after.get("compatible_config_hashes", {}), "parent_alias_added")
    settlement = after["sources"]["systems/archive_settlement.lua"]
    need(settlement.count(TITLE_SYNC) == 1 and settlement.replace(TITLE_SYNC, "", 1) == before["sources"]["systems/archive_settlement.lua"], "preexisting_challenge_logic_changed")
    titles = after["configs"]["archive_titles"]["rows"]
    old_titles = before["configs"]["archive_titles"]["rows"]
    need(len(titles) == len(old_titles) == 9, "title_asset_set_changed")
    need([row.get("title_level") for row in titles] == list(range(1, 10)), "title_levels_invalid")
    need([row.get("required_wave") for row in titles] == list(range(1, 642, 80)), "title_thresholds_invalid")
    for previous, updated in zip(old_titles, titles):
        need(all(updated.get(key) == previous.get(key) for key in ("title_id", "display_name", "icon", "description", "enabled")), "existing_title_asset_changed")
        need(updated.get("default_unlocked") is False, "title_default_unlock_bypasses_progress")
    cfg = configuration(bundle)
    need(json.loads((STAGE / "payload/configuration.json").read_bytes()) == cfg, "payload_configuration_differs")
    allowed_payload = {"bundle/" + data["candidate"] + "/" + name for name in after["sources"]}
    allowed_payload |= {"bundle/" + data["candidate"] + "/bundle.json", "configuration.json", "upgrade_archive_titles_compat.sql", "test_archive_titles_compat.py", "smoke.py"}
    need(set(data["files"]) == allowed_payload, "unexpected_publication_payload")
    need(len(bundle.tables["commerce_catalog"]) == 125 and sum(row["enabled"] for row in bundle.tables["commerce_catalog"].values()) == 121, "commerce_count_changed")
    return bundle


def configuration(bundle):
    return {"configs": bundle.configs, "compatible_config_hashes": {
        key: {name: sorted(values) for name, values in rule.items()} for key, rule in bundle.compatible_config_hashes.items()}}


def table_state(connection):
    from psycopg import sql
    names = connection.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename").fetchall()
    need(len(names) == TABLES, "business_table_set_changed")
    return {schema + "." + name: connection.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema), sql.Identifier(name))).fetchone()
        for schema, name in names}


def transaction(connection, publish):
    connection.execute("SET TRANSACTION ISOLATION LEVEL " + ("READ COMMITTED" if publish else "REPEATABLE READ"))
    connection.execute("SET LOCAL lock_timeout='5s'")
    connection.execute("SET LOCAL statement_timeout='90s'")
    connection.execute("SET ROLE goufayu_owner")
    for name in ("payments.order_quantity.publish", "payments.catalog.publish", "survival.wife_collection.publish", "survival.shop_catalog.publish", "survival.endless_titles.publish"):
        connection.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (name,))
    if publish:
        from psycopg import sql
        names = connection.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename").fetchall()
        need(len(names) == TABLES, "business_table_set_changed")
        connection.execute(sql.SQL("LOCK TABLE {} IN EXCLUSIVE MODE").format(sql.SQL(",").join(sql.Identifier(s, n) for s, n in names)))


def migrate(connection, bundle):
    data = plan()
    prior, _ = function_state(connection, SYNC)
    need(prior["definition_sha256"] == OLD_SYNC, "sync_function_changed_since_review")
    connection.execute((STAGE / "payload/upgrade_archive_titles_compat.sql").read_text(encoding="utf-8"))
    after, _ = function_state(connection, SYNC)
    need(after["definition_sha256"] == data["new_sync_function"], "updated_sync_function_digest_invalid")
    need({k: v for k, v in prior.items() if k != "definition_sha256"} == {k: v for k, v in after.items() if k != "definition_sha256"}, "sync_function_security_metadata_changed")
    return prior, after


def register(connection, bundle):
    from psycopg.types.json import Jsonb
    data = plan(); cfg = configuration(bundle)
    config_sha = connection.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')", (Jsonb(cfg),)).fetchone()[0]
    need(config_sha == data["cfg_pg_sha256"], "postgres_configuration_digest_changed")
    before = {r[0]["config_hash"]: r[0] for r in connection.execute("SELECT to_jsonb(c) FROM public.archive_config_sets c")}
    need(bundle.hash not in before, "candidate_config_already_registered")
    result = connection.execute("SELECT public.archive_sync_config(%s,%s)", (bundle.hash, Jsonb(cfg))).fetchone()[0]
    need(result.get("ok") is True, "config_registration_failed")
    after = {r[0]["config_hash"]: r[0] for r in connection.execute("SELECT to_jsonb(c) FROM public.archive_config_sets c")}
    need(set(after) == set(before) | {bundle.hash} and all(after.get(k) == v for k, v in before.items()), "existing_configuration_rows_changed")
    need(after[bundle.hash]["config"] == cfg, "registered_configuration_differs")


def database_check(bundle, publish=False):
    data = plan(); current(OLD)
    with payment_deploy().connection() as connection:
        try:
            transaction(connection, publish)
            prior = invariants(connection, {OLD_SYNC}); before = table_state(connection)
            if not publish:
                connection.execute("SAVEPOINT rollback_title_negative_tests")
                migrate(connection, bundle)
                checked = load("title_negative_guard_tests", STAGE / "payload/test_archive_titles_compat.py").run_checks(connection, configuration(bundle), bundle.hash, BEFORE)
                need(checked.get("cases") == 8 and checked.get("status") == "PASS", "negative_guard_test_count_invalid")
                connection.execute("ROLLBACK TO SAVEPOINT rollback_title_negative_tests")
                need(table_state(connection) == before and invariants(connection, {OLD_SYNC}) == prior, "negative_fixtures_or_function_not_rolled_back")
                connection.execute("RELEASE SAVEPOINT rollback_title_negative_tests")
            old_meta, new_meta = migrate(connection, bundle)
            invariants(connection, {data["new_sync_function"]})
            register(connection, bundle)
            after = table_state(connection)
            changed = sorted(name for name in before if before[name] != after.get(name))
            need(changed == ["public.archive_config_sets"], "publication_changed_business_data:" + ",".join(changed))
            current(OLD)
            result = stamp({"status": "COMMITTED" if publish else "PASS_ROLLED_BACK", "table_count": TABLES,
                "changed_tables": changed, "old_sync_function": old_meta, "new_sync_function": new_meta,
                "all_player_order_cash_rows_preserved": True, "new_config_rows": 1, "fixtures_committed": 0})
            if not publish:
                result["negative_tests"] = checked
                connection.rollback()
            else:
                connection.commit()
            save("database_committed.json" if publish else "database_validation.json", result)
            return result
        except BaseException:
            connection.rollback()
            raise


def smoke(bundle):
    lua = shutil.which("lua5.1") or shutil.which("lua")
    need(lua is not None, "lua_interpreter_missing")
    result = load("title_worker_smoke", STAGE / "payload/smoke.py").run_checks(bundle.directory, lua)
    need(result.get("status") == "PASS", "worker_smoke_failed")
    return result


def validate():
    current(OLD); bundle = prepared()
    result = stamp({"status": "VALIDATED_NOT_ACTIVATED", "worker": smoke(bundle), "database": database_check(bundle)})
    save("validation.json", result)
    return result


def switch(directory):
    temporary = BASE / (".titles-current-" + secrets.token_hex(6))
    temporary.symlink_to(directory, target_is_directory=True)
    os.replace(temporary, BASE / "current")
    result = subprocess.run(["systemctl", "restart", "goufayu-api.service"], capture_output=True, timeout=35)
    need(result.returncode == 0, "archive_service_restart_failed")
    manage = load("shop_readiness_" + directory.name, directory / "deploy/manage.py")
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
    data = plan(); current(OLD); bundle = prepared()
    need(record("validation.json")["status"] == "VALIDATED_NOT_ACTIVATED", "validation_required")
    checked = smoke(bundle)
    database_check(bundle, publish=True)
    try:
        current(OLD); switch(TARGET)
        result = verify()
        result.update(status="DEPLOYED", worker=checked, previous_release=str(OLD), rollback_release=str(ROLLBACK), backup=record("backup.json"))
        save("activated.json", stamp(result))
        return stamp(result)
    except BaseException:
        rolled_back = False
        if (BASE / "current").resolve() == TARGET:
            switch(ROLLBACK); rolled_back = True
        save("activation_failed.json", stamp({"status": "CODE_ROLLED_BACK" if rolled_back else "ACTIVATION_INTERRUPTED",
            "current": str((BASE / "current").resolve()), "new_config_sql_and_reducer_retained": True}))
        raise


def verify():
    data = plan(); current(TARGET); bundle = prepared()
    with contextlib.redirect_stdout(io.StringIO()):
        load("shop_verify_readiness", TARGET / "deploy/manage.py").health()
    with payment_deploy().connection() as connection:
        connection.execute("SET TRANSACTION READ ONLY")
        state = invariants(connection, {data["new_sync_function"]})
        actual = connection.execute("SELECT config FROM public.archive_config_sets WHERE config_hash=%s", (bundle.hash,)).fetchone()
        need(actual and actual[0] == configuration(bundle), "published_configuration_differs")
        committed = record("database_committed.json")
        need(state["sync"] == committed["new_sync_function"], "published_sync_function_security_differs")
        connection.rollback()
    return stamp({"status": "VERIFIED", "archive_release": str(TARGET), "archive_bundle": bundle.hash,
        "payment_release": str(PAY), "payment_catalog_hash": CASH_HASH, "payment_enabled_products": 44,
        "commerce_products": 125, "commerce_enabled": 121, "title_tiers": 9,
        "title_threshold_step": 80, "changed_sources": sorted(ALLOWED_SOURCES), "health": health(), "sync_function": state["sync"],
        "archive_service_sha256": sha(TARGET / "backend/archive_backend/service.py"),
        "payment_source_unchanged": True, "all_old_reducers_retained": True,
        "gateway_requests": 0, "real_account_commands": 0, "test_fixture_rows_committed": 0})


def rollback():
    data = plan(); current(TARGET); prepared(); backup_verified()
    with payment_deploy().connection() as connection:
        connection.execute("SET TRANSACTION READ ONLY")
        invariants(connection, {data["new_sync_function"]})
        connection.rollback()
    switch(ROLLBACK); current(ROLLBACK)
    result = stamp({"status": "CODE_ROLLED_BACK", "archive_release": str(ROLLBACK), "archive_bundle": BEFORE,
        "candidate_sql_config_and_bundle_retained": True, "player_data_restored_or_deleted": False,
        "game_pointer_must_return_to_parent_before_new_matches": True, "health": health()})
    save("rollback.json", result)
    return result


def main():
    global EXPECTED_PLAN_SHA, EXPECTED_OPERATOR_SHA
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("backup", "prepare", "validate", "activate", "verify", "rollback"))
    parser.add_argument("--plan-sha", required=True)
    parser.add_argument("--operator-sha", required=True)
    args = parser.parse_args()
    EXPECTED_PLAN_SHA, EXPECTED_OPERATOR_SHA = args.plan_sha, args.operator_sha
    need(fcntl is not None and hasattr(os, "geteuid") and os.geteuid() == 0
        and STAGE == Path("/tmp/survival-endless-titles-20261016"), "approved_root_stage_required")
    need(STAGE.stat().st_uid == 0 and STAGE.stat().st_mode & 0o077 == 0, "private_root_stage_required")
    os.umask(0o022); sys.dont_write_bytecode = True
    with open("/var/lock/goufayu-endless-titles.lock", "w") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        plan()
        result = globals()[args.action]()
        save(args.action + "_result.json", stamp(result))
        print(json.dumps(stamp(result), ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Do not print connection errors, SQL bodies, credentials or profile data.
        code = str(error) if type(error) is RuntimeError and re.fullmatch(r"[a-zA-Z0-9_./:, -]{1,240}", str(error)) else type(error).__name__
        print(json.dumps({"status": "FAILED", "error": code}))
        sys.exit(1)
