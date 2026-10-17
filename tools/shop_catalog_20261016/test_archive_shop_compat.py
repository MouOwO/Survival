"""Eight savepoint-only negative configuration checks, no accounts or orders."""
from __future__ import annotations
import copy
import hashlib


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def run_checks(connection, configuration, candidate, base):
    from psycopg.types.json import Jsonb
    need(isinstance(configuration, dict), "shop_test_configuration_invalid")
    fixtures = []
    wrong = copy.deepcopy(configuration)
    wrong["configs"]["unreviewed_source"] = {"key": "id", "rows": [{"id": "unknown"}]}
    fixtures.append(("unknown_configuration_table", candidate, wrong, "archive_shop_configuration_mismatch"))
    wrong = copy.deepcopy(configuration)
    rule = wrong["configs"]["player_gameplay_stats"]["rows"][0]
    rule["default_value"] = (rule.get("default_value") or 0) + 1
    fixtures.append(("changed_gameplay_default", candidate, wrong, "archive_shop_configuration_mismatch"))
    wrong = copy.deepcopy(configuration)
    catalog = wrong["configs"]["commerce_catalog"]["rows"]
    old_product = next(row for row in catalog if row["sku"] not in {"video_p140", "video_p151"})
    old_product["price"] += 1
    fixtures.append(("changed_existing_product_price", candidate, wrong, "archive_shop_configuration_mismatch"))
    unknown = hashlib.sha256(("shop-unreviewed-hash:" + candidate).encode()).hexdigest()
    need(unknown not in configuration["compatible_config_hashes"] and unknown != candidate, "negative_hash_collision")
    wrong = copy.deepcopy(configuration)
    wrong["compatible_config_hashes"][unknown] = copy.deepcopy(wrong["compatible_config_hashes"][base])
    fixtures.append(("unapproved_compatibility_alias", candidate, wrong, "archive_shop_configuration_mismatch"))
    wrong = copy.deepcopy(configuration)
    rows = wrong["configs"]["archive_social_items"]["rows"]
    index = next(i for i, row in enumerate(rows) if row.get("pool_id") == "wife")
    rows.pop(index)
    fixtures.append(("removed_previous_wife_collection_row", candidate, wrong, "archive_shop_configuration_mismatch"))
    wrong = copy.deepcopy(configuration)
    wrong["compatible_config_hashes"][base]["upgrade_commands"] = ["commerce_purchase"]
    fixtures.append(("expanded_financial_upgrade_allowlist", candidate, wrong, "archive_shop_configuration_mismatch"))
    wrong = copy.deepcopy(configuration)
    product = next(row for row in wrong["configs"]["commerce_catalog"]["rows"] if row["sku"] == "video_p151")
    product["ownership_quantity"] = product.get("ownership_quantity", 1) + 1
    fixtures.append(("changed_new_product_quantity", candidate, wrong, "archive_shop_configuration_mismatch"))
    fixtures.append(("unapproved_target_hash_uses_original_policy", unknown, copy.deepcopy(configuration), "archive_compatibility_invalid"))
    need(len(fixtures) == 8, "shop_negative_fixture_count_invalid")
    checked = []
    for index, (name, digest, config, expected) in enumerate(fixtures):
        savepoint = "shop_negative_" + str(index)
        connection.execute("SAVEPOINT " + savepoint)
        message = None
        state = None
        try:
            connection.execute("SELECT public.archive_sync_config(%s,%s)", (digest, Jsonb(config))).fetchone()
        except Exception as error:
            state = getattr(error, "sqlstate", None)
            diag = getattr(error, "diag", None)
            message = getattr(diag, "message_primary", None)
        finally:
            connection.execute("ROLLBACK TO SAVEPOINT " + savepoint)
            connection.execute("RELEASE SAVEPOINT " + savepoint)
        need(state == "P0001" and message == expected, "shop_negative_guard_failed:" + name)
        checked.append({"name": name, "expected_error": expected, "rolled_back": True})
    return {"status": "PASS", "cases": len(checked), "checks": checked,
            "account_commands": 0, "orders_created": 0, "fixtures_committed": 0}
