"""Eight rollback-only SQL admission checks; importing never opens a connection.

The caller installs the reviewed guard inside its validation transaction before
calling run_checks(). Every probe gets its own savepoint, including probes that
unexpectedly succeed. This module never commits or rolls back the caller's
transaction and never invokes player, account, purchase, or order operations.
"""
from __future__ import annotations

import copy
import hashlib
import re
import secrets


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def _rows(configuration, name, minimum=1):
    table = configuration.get("configs", {}).get(name, {})
    rows = table.get("rows") if isinstance(table, dict) else None
    need(isinstance(rows, list) and len(rows) >= minimum
         and all(isinstance(row, dict) for row in rows),
         "titles_negative_rows_missing:" + name)
    return rows


def _numeric_row(configuration, table, field):
    for row in _rows(configuration, table):
        value = row.get(field)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return row
    raise RuntimeError("titles_negative_numeric_field_missing:" + table + "." + field)


def _configuration_rows(connection):
    # Include every column, so a rollback must preserve old rows and metadata.
    return tuple(connection.execute(
        "SELECT config_hash, encode(sha256(convert_to(to_jsonb(c)::text,'UTF8')),'hex') "
        "FROM public.archive_config_sets AS c ORDER BY config_hash"
    ).fetchall())


def run_checks(connection, configuration, candidate, base):
    """Run seven malformed-candidate cases and one unapproved-target case.

    configuration is the complete plain-dict archive_sync_config payload. Both
    hashes come from the current reviewed release; no parent compatibility
    alias, collection item, currency value, or historical hash is assumed.
    """
    from psycopg.types.json import Jsonb

    need(connection.autocommit is False
         and connection.info.transaction_status.name == "INTRANS",
         "titles_negative_requires_existing_transaction")
    need(isinstance(configuration, dict) and isinstance(configuration.get("configs"), dict),
         "titles_negative_configuration_invalid")
    need(all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)
             for value in (candidate, base)) and candidate != base,
         "titles_negative_hashes_invalid")
    aliases = configuration.get("compatible_config_hashes")
    need(isinstance(aliases, dict) and aliases, "titles_negative_aliases_missing")
    source = next((digest for digest, rule in sorted(aliases.items())
                   if isinstance(rule, dict) and isinstance(rule.get("commands"), list)
                   and "commerce_purchase" in rule["commands"]
                   and isinstance(rule.get("upgrade_commands"), list)
                   and "commerce_purchase" not in rule["upgrade_commands"]), None)
    need(source is not None, "titles_negative_financial_alias_missing")

    unknown = hashlib.sha256(("archive_titles_unreviewed:" + candidate + ":" + base).encode()).hexdigest()
    before = _configuration_rows(connection)
    need(unknown not in aliases and unknown not in (candidate, base)
         and all(row[0] != unknown for row in before), "titles_negative_hash_collision")
    expected = "archive_titles_configuration_mismatch"
    fixtures = []

    wrong = copy.deepcopy(configuration)
    _numeric_row(wrong, "archive_titles", "required_wave")["required_wave"] += 1
    fixtures.append(("changed_title_threshold", candidate, wrong, expected))

    wrong = copy.deepcopy(configuration)
    rows = _rows(wrong, "archive_titles", 2)
    need(rows[0] != rows[1], "titles_negative_order_fixture_unchanged")
    rows[0], rows[1] = rows[1], rows[0]
    fixtures.append(("changed_title_order", candidate, wrong, expected))

    wrong = copy.deepcopy(configuration)
    _numeric_row(wrong, "player_gameplay_stats", "default_value")["default_value"] += 1
    fixtures.append(("changed_gameplay_default", candidate, wrong, expected))

    wrong = copy.deepcopy(configuration)
    _numeric_row(wrong, "commerce_catalog", "price")["price"] += 1
    fixtures.append(("changed_commerce_price", candidate, wrong, expected))

    wrong = copy.deepcopy(configuration)
    wrong["compatible_config_hashes"][unknown] = copy.deepcopy(aliases[source])
    fixtures.append(("unapproved_compatibility_alias", candidate, wrong, expected))

    wrong = copy.deepcopy(configuration)
    wrong["compatible_config_hashes"][source]["upgrade_commands"].append("commerce_purchase")
    fixtures.append(("expanded_financial_upgrade_allowlist", candidate, wrong, expected))

    wrong = copy.deepcopy(configuration)
    _numeric_row(wrong, "archive_social_items", "max_owned")["max_owned"] += 1
    fixtures.append(("changed_collection_ownership_limit", candidate, wrong, expected))

    fixtures.append(("unapproved_target_hash_uses_original_policy", unknown,
                     copy.deepcopy(configuration), "archive_compatibility_invalid"))
    need(len(fixtures) == 8, "titles_negative_fixture_count_invalid")

    checked = []
    nonce = secrets.token_hex(8)
    for index, (name, digest, config, expected_error) in enumerate(fixtures):
        savepoint = "titles_negative_" + nonce + "_" + str(index)
        connection.execute("SAVEPOINT " + savepoint)
        message = None
        state = None
        try:
            connection.execute("SELECT public.archive_sync_config(%s,%s)",
                               (digest, Jsonb(config))).fetchone()
        except Exception as error:
            state = getattr(error, "sqlstate", None)
            message = getattr(getattr(error, "diag", None), "message_primary", None)
        finally:
            connection.execute("ROLLBACK TO SAVEPOINT " + savepoint)
            connection.execute("RELEASE SAVEPOINT " + savepoint)
        need(_configuration_rows(connection) == before,
             "titles_negative_config_rows_changed:" + name)
        need(state == "P0001" and message == expected_error,
             "titles_negative_guard_failed:" + name + ":" + str(state) + ":" + str(message))
        checked.append({"name": name, "expected_error": expected_error,
                        "error": message, "sqlstate": state, "rolled_back": True})

    return {"status": "PASS", "cases": len(checked), "checks": checked,
            "all_config_rows_unchanged": True, "account_commands": 0,
            "orders_created": 0, "fixtures_committed": 0, "connections_opened": 0}
