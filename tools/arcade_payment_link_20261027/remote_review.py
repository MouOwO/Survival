"""Fixed host audit and new-stage preparation. No activation implementation."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import socket
import stat
import subprocess

SERVICES = ("goufayu-api.service", "goufayu-db.service", "goufayu-payment.service",
            "goufayu-ws4.service", "goufayu-ws4-db.service", "goufayu-ws4-web.service")
POINTERS = ("/opt/goufayu/releases/current", "/opt/goufayu/payments/current")
SHA = re.compile(r"[a-f0-9]{64}\Z")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def need(value, code):
    if not value:
        raise RuntimeError(code)


def regular(path):
    path = Path(path)
    need(path.is_file() and not path.is_symlink(), "regular_host_file_required")
    return path.read_bytes()


def command(args, data=None, timeout=15):
    done = subprocess.run(args, input=data, capture_output=True, timeout=timeout)
    need(done.returncode == 0, "fixed_host_command_failed")
    return done.stdout


def validate_plan(plan):
    identity = plan["plan_sha256"]
    need(isinstance(identity, str) and SHA.fullmatch(identity), "plan_identity_invalid")
    desired = copy.deepcopy(plan)
    desired.pop("plan_sha256")
    desired.pop("stage")
    desired["payment"].pop("release")
    need(hashlib.sha256(canonical(desired)).hexdigest() == identity, "plan_hash_mismatch")
    need(plan["stage"] == "/root/goufayu_upload/ws4-payments-" + identity[:20], "fixed_stage_required")
    need(plan["payment"]["release"] == "/opt/goufayu-ws4-payment/releases/20261027-" + identity[:20], "fixed_release_required")
    need(plan["payment"]["port"] == 18769 and plan["payment"]["dsn_identity"] == {
        "host": "127.0.0.1", "port": 15432, "dbname": "goufayu_ws4", "user": "goufayu_payment"}, "fixed_isolation_required")
    need(plan["payments_enabled"] is False and plan["activation_implemented"] is False, "preparation_only_required")


def baseline():
    result = {"services": {}, "pointers": {}}
    for name in SERVICES:
        values = command(["systemctl", "show", name, "--property=ActiveState,MainPID,FragmentPath"]).decode().splitlines()
        state = dict(line.split("=", 1) for line in values)
        fragment = Path(state["FragmentPath"])
        result["services"][name] = {"active": state["ActiveState"] == "active", "pid": int(state["MainPID"]),
                                   "unit_sha256": hashlib.sha256(regular(fragment)).hexdigest()}
    for pointer in POINTERS:
        target = Path(pointer).resolve(strict=True)
        result["pointers"][pointer] = str(target)
    return result


def env_values(path):
    values = {}
    for line in regular(path).decode().splitlines():
        if not line or line.lstrip().startswith("#"):
            continue
        key, sep, value = line.partition("=")
        need(sep and key not in values, "host_environment_invalid")
        values[key] = json.loads(value) if value.startswith('"') else value
    return values


def sql(select):
    need(select.lstrip().startswith("SELECT "), "read_only_select_required")
    need(";" not in select.strip().rstrip(";") and "\0" not in select, "one_read_only_statement_required")
    source = ("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSET LOCAL statement_timeout='6000ms';\n"
              "SET LOCAL lock_timeout='1000ms';\n" + select + "\nROLLBACK;\n").encode()
    data = command(["podman", "exec", "-i", "--user", "postgres", "--env", "PGPASSFILE=/dev/null",
                    "--env", "PGSERVICEFILE=/dev/null", "goufayu-ws4-db", "psql", "-X", "-w", "-qAt",
                    "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "goufayu_ws4"], source)
    rows = data.decode().splitlines()
    need(len(rows) == 1, "catalog_query_shape_invalid")
    return json.loads(rows[0])


def database_inventory():
    data = sql("""SELECT json_build_object(
      'database',current_database(),'read_only',current_setting('transaction_read_only')='on',
      'tables',(SELECT coalesce(json_agg(json_build_object('name',c.relname,'rls',c.relrowsecurity,
        'columns',(SELECT json_agg(json_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum)
          FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
        'constraints',(SELECT coalesce(json_agg(json_build_object('name',co.conname,'definition',pg_get_constraintdef(co.oid))),'[]') FROM pg_constraint co WHERE co.conrelid=c.oid)
        ) ORDER BY c.relname),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='payments' AND c.relkind='r'),
      'functions',(SELECT coalesce(json_agg(json_build_object('signature',p.oid::regprocedure::text,'name',p.proname,'definition',pg_get_functiondef(p.oid),'security_definer',p.prosecdef) ORDER BY p.proname,p.oid),'[]')
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='payments'),
      'order_triggers',(SELECT coalesce(json_agg(json_build_object('name',t.tgname,'enabled',t.tgenabled,'function',p.proname)),'[]') FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE t.tgrelid=to_regclass('payments.orders') AND NOT t.tgisinternal),
      'role',(SELECT json_build_object('login',r.rolcanlogin,'unprivileged',NOT(r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls),
        'connect',has_database_privilege(r.rolname,current_database(),'CONNECT')) FROM pg_roles r WHERE r.rolname='goufayu_payment')
    );""")
    need(data["database"] == "goufayu_ws4" and data["read_only"] is True, "isolated_read_only_identity_required")
    markers = ("entitlement_days", "validate_commerce_bundle", "u_coin_recharge_receipt", "receipt_quantity",
               "vip_recharge", "validate_order_quantity_snapshot", "1000", "100")
    for function in data["functions"]:
        definition = function.pop("definition")
        function["definition_sha256"] = hashlib.sha256(definition.encode()).hexdigest()
        function["contains"] = [marker for marker in markers if marker in definition]
    names = {row["name"] for row in data["functions"]}
    required = {"catalog", "create_order", "create_order_channel", "create_order_quantity", "get_order", "pending", "update_gateway", "deliver",
                "product_block", "apply_effects", "entitlement_days", "validate_commerce_bundle", "commerce_bundle_effects", "credit_vip_recharge",
                "receipt_quantity", "validate_order_quantity_snapshot", "recharge_wallet_balance", "catalog_pre_recharge",
                "validate_order_quantity_snapshot_pre_recharge"}
    data["missing_capability_functions"] = sorted(required - names)
    data["semantically_verified_for_publication"] = False
    data["requires_review_of_definitions_and_rollback_fixture_tests"] = True
    # Fixed, previously enumerated payments table names; aggregate counts only.
    tables = [row["name"] for row in data["tables"]]
    need(all(re.fullmatch(r"[a-z][a-z0-9_]{0,62}", name) for name in tables), "table_name_invalid")
    counts = ",".join("'" + name + "',(SELECT count(*) FROM payments.\"" + name + '\")' for name in tables)
    data["aggregate_counts"] = sql("SELECT json_build_object(" + counts + ");") if counts else {}
    return data


def audit(plan):
    validate_plan(plan)
    before = baseline()
    env = env_values("/etc/goufayu-ws4/api.env")
    roster = env.get("SURVIVAL_TEST_STEAM_IDS64", "").split(",")
    need(len(roster) == len(set(roster)) == 4 and all(re.fullmatch(r"7656119[0-9]{10}", x) for x in roster), "four_account_gate_required")
    addon = Path(env.get("SURVIVAL_ADDON_ROOT", ""))
    need(addon == Path("/opt/goufayu-ws4/releases/20261023-auth-v1/addon"), "fixed_ws4_addon_required")
    bundles = addon / "server/bundles"
    digest = json.loads(regular(bundles / "current.json"))["hash"]
    need(isinstance(digest, str) and SHA.fullmatch(digest), "ws4_bundle_hash_invalid")
    raw = regular(bundles / digest / "bundle.json")
    need(hashlib.sha256(raw).hexdigest() == digest, "ws4_bundle_content_hash_mismatch")
    bundle = json.loads(raw)
    matches = {name: bundle["csv_hashes"].get(name) == value for name, value in plan["required_bundle_sources"].items()}
    legacy = json.loads(regular("/etc/goufayu-payment/config.json"))
    secrets_present = all(isinstance(legacy.get(name), str) and len(legacy[name]) >= limit
                          for name, limit in (("pepper", 24), ("game_token", 24), ("checkout_key", 32)))
    state = database_inventory()
    semantic = function_semantics(plan["payment_function_contract"])
    with socket.socket() as probe:
        port_free = probe.connect_ex(("127.0.0.1", 18769)) != 0
    flags = env_values("/etc/goufayu-ws4-web/auth.env")
    pwa_locations = regular('/etc/nginx/goufayu-ws4-web.locations')
    pwa_directives = [line.strip() for line in pwa_locations.decode().splitlines()
                      if re.match(r'^\s*(?:location|proxy_pass|rewrite|return|limit_except|if)\b',line)]
    pwa_proxy_verified = (hashlib.sha256(pwa_locations).hexdigest() == plan['expected_pwa_locations_sha256'] and
                         pwa_directives == ['location = /ws4-web { return 308 /ws4-web/; }','location ^~ /ws4-web/ {',
                                            'limit_except GET POST { deny all; }','proxy_pass http://127.0.0.1:18767/;'])
    result = {"ok": True, "kind": "WS4_PAYMENT_LINK_READ_ONLY_AUDIT", "plan_sha256": plan["plan_sha256"],
              "baseline": before, "ws4_schema": state, "bundle": {"hash": digest, "source_matches": matches, "all_sources_match": all(matches.values())},
              "function_semantics": semantic,
              "pwa_payment_prefix_proxy_verified": pwa_proxy_verified,
              "effective_payment_role": payment_role_permissions(),
              "four_accounts_verified": True, "ws4_pepper_present": len(env.get("FISHING_ACCOUNT_ID_PEPPER", "")) >= 24,
              "legacy_payment_configuration_complete": secrets_present, "alipay_enabled": legacy.get("alipay_enabled") is True,
              "alipay_checkout_mode": legacy.get("alipay_checkout_mode", "page_pay"),
              "payment_port_free": port_free, "new_payment_paths_absent": all(not Path(name).exists() for name in (
                  "/opt/goufayu-ws4-payment", "/etc/goufayu-ws4-payment", "/etc/systemd/system/goufayu-ws4-payment.service")),
              "pwa_payments_enabled": flags.get("PLAYER_WEB_AUTH_PAYMENTS_ENABLED", "0") == "1",
              "steam_tls_relay_enabled": flags.get("PLAYER_WEB_AUTH_STEAM_TLS_RELAY", "0") == "1",
              "activation_pins": {"nginx_sha256": hashlib.sha256(regular('/etc/nginx/nginx.conf')).hexdigest(),
                                  "pwa_locations_sha256": hashlib.sha256(pwa_locations).hexdigest(),
                                  "web_environment_sha256": hashlib.sha256(regular('/etc/goufayu-ws4-web/auth.env')).hexdigest(),
                                  "legacy_payment_config_sha256": hashlib.sha256(regular('/etc/goufayu-payment/config.json')).hexdigest()},
              "unchanged": baseline() == before, "secrets_exported": False, "gateway_called": False,
              "user_or_order_rows_exported": False, "database_writes": False}
    need(result["unchanged"], "baseline_changed_during_audit")
    return result


def payment_role_permissions():
    return sql("""SELECT json_build_object('unprivileged',NOT(r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls),
      'login',r.rolcanlogin,'connect',has_database_privilege(r.rolname,current_database(),'CONNECT'),
      'memberships',(SELECT coalesce(json_agg(parent.rolname ORDER BY parent.rolname),'[]') FROM pg_auth_members m JOIN pg_roles parent ON parent.oid=m.roleid WHERE m.member=r.oid),
      'direct_tables',(SELECT coalesce(json_agg(n.nspname||'.'||c.relname ORDER BY n.nspname,c.relname),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','payments') AND c.relkind IN ('r','p','v','m','S')
        AND ((CASE WHEN c.relkind='S' THEN has_sequence_privilege(r.rolname,c.oid,'USAGE,SELECT,UPDATE')
          ELSE has_table_privilege(r.rolname,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
            OR has_any_column_privilege(r.rolname,c.oid,'SELECT,INSERT,UPDATE,REFERENCES') END) OR c.relowner=r.oid)),
      'execute_functions',(SELECT coalesce(json_agg(p.proname ORDER BY p.proname),'[]') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='payments' AND has_function_privilege(r.rolname,p.oid,'EXECUTE')))
      FROM pg_roles r WHERE r.rolname='goufayu_payment';""")


def function_semantics(contract):
    actual = sql("""SELECT coalesce(json_agg(json_build_object('name',p.proname,'arguments',oidvectortypes(p.proargtypes),
      'returns',format_type(p.prorettype,NULL),'language',l.lanname,'body',p.prosrc,'security_definer',p.prosecdef,
      'owner',r.rolname,'search_path',p.proconfig) ORDER BY p.proname),'[]'::json)
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_roles r ON r.oid=p.proowner
      JOIN pg_language l ON l.oid=p.prolang WHERE n.nspname='payments';""")
    need(len(actual) == len({row['name'] for row in actual}), "payment_function_overloads_unreviewed")
    actual = {row['name']: row for row in actual}
    differences = {}
    for name in sorted(set(actual) | set(contract)):
        if name not in actual or name not in contract:
            differences[name] = ['missing' if name not in actual else 'unexpected']
            continue
        row = actual[name]
        row['body_sha256'] = hashlib.sha256(row.pop('body').replace('\r\n','\n').strip().encode()).hexdigest()
        mismatch = [key for key in ('arguments','returns','language','security_definer','owner','search_path','body_sha256')
                    if row[key] != contract[name][key]]
        if mismatch:
            differences[name] = mismatch
    return {'functions': len(actual), 'exact_project_sources_match': not differences, 'differences': differences,
            'body_data_exported': False, 'database_writes': False}


def decode_files(plan, encoded):
    need(set(encoded) == set(plan["source_hashes"]) | {"plan.json"}, "stage_file_set_mismatch")
    decoded, total = {}, 0
    for name, value in encoded.items():
        path = PurePosixPath(name)
        need(not path.is_absolute() and ".." not in path.parts and "\\" not in name
             and "\0" not in name and path.as_posix() == name, "stage_relative_path_required")
        need(isinstance(value, str) and len(value) <= 3 * 1024 * 1024, "stage_file_too_large")
        raw = base64.b64decode(value, validate=True)
        total += len(raw)
        need(len(raw) <= 2 * 1024 * 1024 and total <= 16 * 1024 * 1024, "stage_files_too_large")
        expected = hashlib.sha256(canonical(plan)).hexdigest() if name == "plan.json" else plan["source_hashes"][name]
        need(hashlib.sha256(raw).hexdigest() == expected, "stage_source_hash_mismatch")
        if name.endswith(".py"):
            compile(raw, name, "exec")
        decoded[name] = raw
    return decoded


def prepare(plan, encoded):
    # Only a new root-private staging directory is writable in this phase.
    validate_plan(plan)
    decoded = decode_files(plan, encoded)
    before = baseline()
    stage = Path(plan["stage"])
    parent = stage.parent
    need(parent == Path("/root/goufayu_upload") and parent.is_dir() and not parent.is_symlink(), "private_stage_parent_required")
    need(parent.stat().st_uid == 0 and not stage.exists() and not stage.is_symlink(), "new_private_stage_required")
    stage.mkdir(mode=0o700)
    for name, raw in decoded.items():
        target = stage / name
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(raw)
    need(baseline() == before, "baseline_changed_during_prepare")
    return {"ok": True, "kind": "WS4_PAYMENT_LINK_SOURCE_STAGE_PREPARED", "plan_sha256": plan["plan_sha256"],
            "stage": str(stage), "files": len(decoded), "existing_services_unchanged": True,
            "services_started": False, "configuration_changed": False, "database_writes": False,
            "secrets_generated": False, "gateway_called": False}


def main(mode, plan, files=None):
    try:
        need(mode in ("audit", "prepare"), "activation_not_implemented")
        result = audit(plan) if mode == "audit" else prepare(plan, files)
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    except Exception as error:
        code = str(error) if isinstance(error, RuntimeError) and re.fullmatch(r"[a-z][a-z0-9_]{1,95}", str(error)) else "review_action_failed"
        print(json.dumps({"ok": False, "kind": "WS4_PAYMENT_LINK_REVIEW_FAILED", "error": code}))
        raise SystemExit(1) from None
