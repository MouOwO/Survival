"""Freeze a reviewable WS4 payment candidate without changing live services."""
from __future__ import annotations

import base64
import ast
import hashlib
import json
from pathlib import Path
import sys

from catalog_validation import canonical

ROOT = Path(__file__).resolve().parents[2]
PAYMENT_BASE = "/opt/goufayu-ws4-payment"
PAYMENT_CONFIG = "/etc/goufayu-ws4-payment/config.json"
PAYMENT_UNIT = "goufayu-ws4-payment.service"
PUBLIC_BASE = "https://pay.xiaofengnet.com/ws4-payments"
WS4_BUNDLE_HASH = "47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e"
WS4_AUXILIARY_HASHES = {"商店系统/entitlement_definitions.csv": "f062937a94be09f9f1757461a07e92d9dd0fa2f5faeb2a7158c6e1d085249104"}
WS4_PWA_LOCATIONS_HASH = "0fd56607a17d320b01131a2c13465f2184bc041306aca1f2774137dccf09da0d"
TRANSPORT_PIN = "b94b2fada7995561f3ed73d4b85fad81279fe90346208815a6f9c6713b15b1c4"
SCHEMA_SOURCES = (
    "schema.sql", "upgrade_stat_shop.sql", "upgrade_test_shop.sql", "upgrade_csv_shop.sql",
    "upgrade_alipay.sql", "upgrade_alipay_qr.sql", "upgrade_starjoy_progress.sql",
    "upgrade_order_quantity.sql", "upgrade_monthly_pass.sql", "upgrade_commerce_bundles.sql",
    "upgrade_vip_recharge.sql", "upgrade_ucoin_recharge.sql", "upgrade_ucoin_rate_100.sql",
)


def regular(path):
    if path.is_symlink() or getattr(path, "is_junction", lambda: False)() or not path.is_file():
        raise ValueError("candidate_regular_source_required")
    if any(parent.is_symlink() or getattr(parent, "is_junction", lambda: False)() for parent in path.parents if parent != ROOT.parent):
        raise ValueError("candidate_source_parent_invalid")
    return path.read_bytes().replace(b"\r\n", b"\n")


def build(root=ROOT, cloud_snapshot=None):
    root = Path(root)
    sys.path.insert(0, str(root / "server"))
    from payment_backend.csv_catalog import SOURCES, TABLES, build as compile_cash
    from payment_backend.commerce_bundles import compile_commerce
    from payment_backend.ucoin_catalog import COMMERCE_SOURCES, COMMERCE_TABLES, compile_payment_catalog
    from catalog_validation import validate_catalog
    from schema_contract import compile_contract
    function_contract = compile_contract(root / "server/payment_backend")
    route_ast = ast.parse((root / "tools/workshop_test/remote_web_auth.py").read_text(encoding="utf-8"))
    route_function = next(node for node in route_ast.body if isinstance(node, ast.FunctionDef) and node.name == "proxy_rules")
    route_bytes = ast.literal_eval(route_function.body[0].value)
    cloud = None
    if cloud_snapshot is None:
        package = compile_cash(root)
        reference_raw = {name: regular(root / "data/csv" / name) for name in SOURCES + COMMERCE_SOURCES}
    else:
        directory = Path(cloud_snapshot).resolve(strict=True)
        allowed = (ROOT / "output/arcade_payment_link_20261027").resolve()
        if directory.parent != allowed or not directory.name.startswith("cloud_sources_"):
            raise ValueError("fixed_cloud_source_snapshot_required")
        cloud = json.loads(regular(directory / "provenance.json"))
        bundle_raw = regular(directory / "bundle.json")
        if (cloud.get("missing_sources") or cloud["bundle_sha256"] != WS4_BUNDLE_HASH
                or cloud["bundle_sha256"] != hashlib.sha256(bundle_raw).hexdigest()
                or set(cloud["files"]) != set(SOURCES + COMMERCE_SOURCES)):
            raise ValueError("cloud_source_snapshot_incomplete")
        reference_raw = {name: regular(directory / "reference_csv" / name) for name in SOURCES + COMMERCE_SOURCES}
        for name, raw in reference_raw.items():
            if hashlib.sha256(raw).hexdigest() != cloud["files"][name]["sha256"]:
                raise ValueError("cloud_source_snapshot_changed")
        auxiliary = {name: row["sha256"] for name, row in cloud["files"].items() if not row["bundle_bound"]}
        if auxiliary != WS4_AUXILIARY_HASHES:
            raise ValueError("cloud_auxiliary_authority_changed")
        tables = {name: (root / "data/csv/商城支付系统" / (name + ".csv")).read_text(encoding="utf-8-sig") for name in TABLES}
        commerce_tables = {table: reference_raw[name].decode("utf-8-sig") for table, name in zip(COMMERCE_TABLES, COMMERCE_SOURCES)}
        clean_reference = {name: raw.decode("utf-8-sig") for name, raw in reference_raw.items()}
        catalog = compile_payment_catalog(tables, commerce_tables, clean_reference)
        package = {"tables": tables, "commerce_tables": commerce_tables,
                   "reference_hashes": {name: hashlib.sha256(clean_reference[name].encode()).hexdigest() for name in SOURCES},
                   "catalog": catalog, "catalog_hash": hashlib.sha256(canonical(catalog)).hexdigest()}
    reference = {name: raw.decode("utf-8-sig") for name, raw in reference_raw.items()}
    wallet = compile_commerce(package["commerce_tables"], reference, package["tables"]["payment_categories"])
    if cloud is not None:
        auxiliary = {name: row["sha256"] for name, row in cloud["files"].items() if not row["bundle_bound"]}
        validate_catalog(package, wallet, {name: raw.decode() for name, raw in reference_raw.items()},
                         json.loads(bundle_raw), expected_bundle_hash=cloud["bundle_sha256"], auxiliary_reference_hashes=auxiliary)
    cash_enabled = sum(row["enabled"] for row in package["catalog"]["products"])
    wallet_enabled = sum(row["enabled"] for row in wallet["products"])
    if (cash_enabled, wallet_enabled) != (48, 125):
        raise ValueError("formal_enabled_catalog_count_changed")
    files = {}
    source_paths = {}
    for path in sorted((root / "server/payment_backend").iterdir()):
        if path.suffix not in (".py", ".sql", ".txt") or path.name in ("deploy.py", "enable_account.py", "sync_catalog.py"):
            continue
        if path.suffix == ".py" and path.name.startswith("upgrade_"):
            continue
        name = "payment_backend/" + path.name
        files[name], source_paths[name] = regular(path), str(path.relative_to(root))
    for directory, names in (("player_web_auth", ("__init__.py", "service.py", "http_api.py", "run.py")),
                             ("lobby_backend", ("__init__.py", "service.py", "http_api.py"))):
        for name in names:
            path = root / "server" / directory / name
            key = directory + "/" + name
            files[key], source_paths[key] = regular(path), str(path.relative_to(root))
    for name, raw in reference_raw.items():
        files["reference_csv/" + name] = raw
    if cloud is not None:
        files["cloud-bundle.json"] = bundle_raw
        files["cloud-source-provenance.json"] = canonical(cloud)
    for table, text in package["tables"].items():
        files["payment_csv/" + table + ".csv"] = text.replace("\r\n", "\n").encode()
    files["catalog-package.json"], files["wallet-catalog.json"] = canonical(package), canonical(wallet)
    files["catalog_validation.py"] = regular(Path(__file__).with_name("catalog_validation.py"))
    for name in ("deploy_plan.py", "remote_review.py", "run.py", "catalog_validation.py", "restore_cloud_sources.py", "schema_contract.py", "activation_remote.py", "activate.py"):
        files["review_tools/" + name] = regular(Path(__file__).with_name(name))
    for name, raw in files.items():
        if name.endswith(".py"):
            compile(raw, name, "exec")
    source_hashes = {name: hashlib.sha256(raw).hexdigest() for name, raw in sorted(files.items())}
    plan = {
        "schema": 1, "kind": "WS4_PAYMENT_LINK_REVIEW_CANDIDATE", "day": "2026-10-27",
        "activation_implemented": False, "payments_enabled": False,
        "payment": {"base": PAYMENT_BASE, "config": PAYMENT_CONFIG, "unit": PAYMENT_UNIT,
                    "user": "goufayu-ws4-payment", "bind": "127.0.0.1", "port": 18769, "public_base": PUBLIC_BASE,
                    "dsn_identity": {"host": "127.0.0.1", "port": 15432, "dbname": "goufayu_ws4", "user": "goufayu_payment"},
                    "test_reset_enabled": False, "account_count": 4},
        "catalog": {"cash_enabled": cash_enabled, "wallet_enabled": wallet_enabled,
                    "cash_total": len(package["catalog"]["products"]), "wallet_total": len(wallet["products"]),
                    "cash_catalog_hash": package["catalog_hash"], "wallet_catalog_hash": hashlib.sha256(canonical(wallet)).hexdigest()},
        "required_bundle_sources": {"data/csv/" + name: hashlib.sha256(files["reference_csv/" + name]).hexdigest()
                                    for name in reference if cloud is None or cloud["files"][name]["bundle_bound"]},
        "auxiliary_reference_hashes": auxiliary if cloud is not None else {},
        "cloud_authority": {"bundle_sha256": cloud["bundle_sha256"], "source_provenance_sha256": hashlib.sha256(canonical(cloud)).hexdigest(),
                            "existing_bundle_and_archive_service_unchanged": True} if cloud is not None else None,
        "source_hashes": source_hashes, "source_paths": source_paths,
        "migration_source_hashes": {name: source_hashes["payment_backend/" + name] for name in SCHEMA_SOURCES},
        "schema_strategy": "COMPARE_ALL_TABLE_COLUMNS_CONSTRAINTS_FUNCTIONS_TRIGGERS_FIRST; DO_NOT_REPLAY_ALL_UPGRADES",
        "payment_function_contract": function_contract,
        "expected_pwa_locations_sha256": WS4_PWA_LOCATIONS_HASH,
        "authored_pwa_locations_sha256": hashlib.sha256(route_bytes).hexdigest(),
        "review_steps": [
            "Reconcile installed WS4 bundle CSV hashes with the frozen catalog; stop on mismatch.",
            "Compare complete WS4 payments metadata and function bodies with reviewed migration artifacts; select only proven gaps.",
            "Back up WS4 public/payments schemas and data privately on host before any SQL; never copy legacy rows.",
            "Validate selected migrations and catalog with synthetic accounts in a rollback-only WS4 transaction.",
            "Create independent service user/unit/release/config; reuse only read-only merchant key files and WS4 account pepper.",
            "Generate distinct DB password, game_token and checkout_key on the host; never export them.",
            "Grant isolated container payment role LOGIN/CONNECT and minimal payments function EXECUTE; no table or owner privileges.",
            "Publish frozen 48-enabled cash products and verify 125-enabled wallet definitions against the same bundle.",
            "Start only the new payment service at 18769 with scoped WS4 callback/checkout routes; keep old 8766 unchanged.",
            "Deploy a separate PWA release with PAYMENTS_ENABLED=0 first; validate authentic cloud profile reads before a separately reviewed enable=1.",
        ],
        "backup": {"scope": "ONLY_WS4_CONTAINER_PUBLIC_PAYMENTS_AND_WS4_ROLE_STATE",
                   "host_private_only": True, "old_auth_env_backup": "PRIVATE_HOST_ONLY_BEFORE_NEW_PWA_ACTIVATION",
                   "existing_services": ["goufayu-api.service", "goufayu-db.service", "goufayu-payment.service", "goufayu-ws4.service", "goufayu-ws4-db.service"],
                   "preserve_legacy_pids_pointers_and_callback_bytes": True},
        "rollback": ["Disable new PWA payments first; stop only the new WS4 payment unit and close only its new public prefix.",
                     "Restore exact prior isolated role privileges and PWA pointer/environment from private host backup.",
                     "Restore DB snapshot only before gateway activation and with proven unchanged order/grant ledger; otherwise retain all receipts and repair forward.",
                     "Never reset, delete or restore legacy orders, production profiles, old payment service or old callbacks."],
        "secret_policy": {"reuse_pepper_from": "/etc/goufayu-ws4/api.env", "reuse_merchant_config_from": "/etc/goufayu-payment/config.json",
                          "readonly_key_directories": ["/etc/goufayu-payment/wechat", "/etc/goufayu-payment/alipay"],
                          "new_secrets_generated_remote_only": ["database_password", "game_token", "checkout_key"],
                          "no_local_credentials": True},
    }
    identity = hashlib.sha256(canonical(plan)).hexdigest()
    plan["plan_sha256"] = identity
    plan["stage"] = "/root/goufayu_upload/ws4-payments-" + identity[:20]
    plan["payment"]["release"] = PAYMENT_BASE + "/releases/20261027-" + identity[:20]
    files["plan.json"] = canonical(plan)
    return plan, files


def encoded_files(files):
    return {name: base64.b64encode(raw).decode() for name, raw in files.items()}
