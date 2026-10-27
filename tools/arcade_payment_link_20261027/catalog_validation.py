"""Pure, isolated catalog validation. Never import legacy deploy/sync_catalog."""
from __future__ import annotations

import hashlib
import json


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def validate_catalog(package, wallet, reference, bundle, *, expected_bundle_hash, auxiliary_reference_hashes=None):
    from payment_backend.csv_catalog import SOURCES
    from payment_backend.commerce_bundles import compile_commerce
    from payment_backend.ucoin_catalog import COMMERCE_SOURCES, COMMERCE_TABLES, compile_payment_catalog
    if hashlib.sha256(canonical(bundle)).hexdigest() != expected_bundle_hash:
        raise ValueError("ws4_bundle_identity_changed")
    auxiliary_reference_hashes = auxiliary_reference_hashes or {}
    if set(auxiliary_reference_hashes) - {"商店系统/entitlement_definitions.csv"}:
        raise ValueError("catalog_auxiliary_source_not_allowed")
    for name in SOURCES + COMMERCE_SOURCES:
        desired = reference[name].replace("\r\n", "\n").encode()
        authority = bundle["csv_hashes"].get("data/csv/" + name)
        if authority is None:
            authority = auxiliary_reference_hashes.get(name)
        if not authority or hashlib.sha256(desired).hexdigest() != authority:
            raise ValueError("ws4_bundle_catalog_source_mismatch:" + name)
    for name in SOURCES:
        if hashlib.sha256(reference[name].lstrip("\ufeff").encode()).hexdigest() != package["reference_hashes"].get(name):
            raise ValueError("catalog_reference_changed:" + name)
    for table, name in zip(COMMERCE_TABLES, COMMERCE_SOURCES):
        if package["commerce_tables"][table] != reference[name].lstrip("\ufeff"):
            raise ValueError("catalog_wallet_reference_changed:" + name)
    catalog = compile_payment_catalog(package["tables"], package["commerce_tables"], reference)
    if canonical(catalog) != canonical(package["catalog"]):
        raise ValueError("cash_catalog_recompile_mismatch")
    if hashlib.sha256(canonical(catalog)).hexdigest() != package["catalog_hash"]:
        raise ValueError("cash_catalog_hash_mismatch")
    compiled_wallet = compile_commerce(package["commerce_tables"], reference, package["tables"]["payment_categories"])
    if canonical(wallet) != canonical(compiled_wallet):
        raise ValueError("wallet_catalog_recompile_mismatch")
    cash_count = sum(row["enabled"] for row in catalog["products"])
    wallet_count = sum(row["enabled"] for row in wallet["products"])
    if (cash_count, wallet_count) != (48, 125):
        raise ValueError("formal_enabled_catalog_count_changed")
    return {"cash_enabled": cash_count, "wallet_enabled": wallet_count,
            "cash_total": len(catalog["products"]), "wallet_total": len(wallet["products"]),
            "cash_catalog_hash": package["catalog_hash"],
            "wallet_catalog_hash": hashlib.sha256(canonical(wallet)).hexdigest()}


def assert_isolated_connection(connection):
    """Required by the future reviewed publisher; old :5432 is never valid."""
    info = connection.info
    if (info.host != "127.0.0.1" or info.port != 15432 or info.dbname != "goufayu_ws4"
            or info.user not in ("postgres", "goufayu_owner")):
        raise ValueError("ws4_catalog_owner_connection_required")
    value = connection.execute("SELECT current_database(),current_user").fetchone()
    if value[0] != "goufayu_ws4" or value[1] not in ("postgres", "goufayu_owner"):
        raise ValueError("ws4_catalog_database_identity_mismatch")
    return True
