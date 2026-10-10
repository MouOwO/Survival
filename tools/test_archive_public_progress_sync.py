"""Verify public archive progress with isolated PostgreSQL rollback fixtures.

Deployment invokes verify(connection, migration_sql). No real player's data,
archive receipts, payment receipts or reward grants are changed by this test.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import re
import uuid
import unittest


class _RollbackFixtures(Exception):
    pass


def migration_body(source):
    inner = re.sub(r"(?im)^begin;\s*", "", source, count=1)
    inner = re.sub(r"(?im)^commit;\s*$", "", inner, count=1)
    if re.search(r"(?im)^commit;", inner):
        raise AssertionError("unexpected migration commit")
    return inner


def verify(connection, migration_sql):
    from psycopg.types.json import Jsonb

    checks = []
    nonce = uuid.uuid4().hex
    account = hashlib.sha256(("archive-public-progress:" + nonce).encode()).hexdigest()
    sql = migration_body(migration_sql)

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        checks.append(label)

    def definition():
        return connection.execute("SELECT pg_get_functiondef('public.fishing_profile_json(text)'::regprocedure)").fetchone()[0]

    def metadata():
        return connection.execute(
            "SELECT proowner,proacl::text,proconfig,prosecdef FROM pg_proc WHERE oid='public.fishing_profile_json(text)'::regprocedure"
        ).fetchone()

    def profile():
        return connection.execute("SELECT public.fishing_profile_json(%s)", (account,)).fetchone()[0]

    initial_definition = definition()
    initial_metadata = metadata()
    base_archive = {"online": {"map_level": 5, "coins": 123},
                    "shadow_counts": {"shadow_01": 2},
                    "fragment_counts": {"fragment_01": 21},
                    "completed": {"clear_n3_1": True}}
    inventory = {"archive_public_fixture_item": 3}
    try:
        with connection.transaction():
            connection.execute("INSERT INTO public.survival_players(account_id) VALUES (%s)", (account,))
            connection.execute("INSERT INTO public.player_gameplay_stats(player_id,initial_wood) VALUES (%s,444)", (account,))
            connection.execute(
                "INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES (%s,%s,%s)",
                (account, Jsonb(base_archive), Jsonb(inventory)))
            connection.execute(
                "INSERT INTO public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at) VALUES (%s,'vip',true,now()-interval '1 day',now()+interval '1 day')",
                (account,))
            before = profile()
            check(before["save"]["archive"] == base_archive, "fixture_archive_loaded")
            check(before["save"]["content_inventory"] == inventory, "fixture_inventory_loaded")
            check(before["save"]["gameplay_stats"]["initial_wood"] == 444, "fixture_stats_loaded")
            check(before["entitlements"]["vip"]["active"] is True, "fixture_vip_loaded")

            connection.execute(sql)
            updated_definition = definition()
            check(metadata() == initial_metadata, "ownership_acl_search_path_security_definer_preserved")
            check("payments.cleared_reward_grants" in updated_definition,
                  "cleared_reward_grants_visibility_filter_preserved")
            check("'achievements', '{}'::jsonb" in updated_definition,
                  "achievement_section_preserved_without_invented_score")
            connection.execute(sql)
            check(definition() == updated_definition, "migration_idempotent")

            def assert_projection(label, changes, wanted_difficulty, wanted_title=""):
                archive = copy.deepcopy(base_archive)
                archive.update(changes)
                connection.execute("UPDATE public.player_archive_state SET archive=%s WHERE account_id=%s",
                                   (Jsonb(archive), account))
                result = profile()
                check(result["public"] == {"highest_difficulty": wanted_difficulty, "title_id": wanted_title},
                      label + "_public_projection")
                expected = copy.deepcopy(before)
                expected["save"]["archive"] = archive
                expected.pop("public", None)
                actual = copy.deepcopy(result)
                actual.pop("public", None)
                check(actual == expected, label + "_private_sections_unchanged")
                check(connection.execute("SELECT archive FROM public.player_archive_state WHERE account_id=%s", (account,)).fetchone()[0] == archive,
                      label + "_projection_does_not_write_archive")

            assert_projection("new_player_default", {}, "N1")
            assert_projection("n3_clear", {"clear_counts": {"n1": 7, "n3": 1}}, "N3")
            assert_projection("n20_numeric_maximum", {"clear_counts": {"n9": 3, "n10": 1, "n20": 1}}, "N20")
            assert_projection("invalid_keys_ignored", {"clear_counts": {"n3": 1, "n0": 999, "n21": 999,
                "n01": 999, "N20": 999, "n99999999999999999999999": 999,
                "n20junk": 999, "20": 999}}, "N3")
            assert_projection("nonpositive_counts_ignored", {"clear_counts": {"n3": 1, "n20": 0, "n19": -1}}, "N3")
            assert_projection("nonnumber_counts_ignored", {"clear_counts": {"n3": 1, "n20": "1", "n19": True,
                "n18": None, "n17": [1], "n16": {"value": 1}}}, "N3")
            for invalid in (None, [], "n20", 20, True):
                assert_projection("invalid_counts_container_" + type(invalid).__name__, {"clear_counts": invalid}, "N1")
            assert_projection("persisted_title", {"equipped_title": "peak_perfection"}, "N1", "peak_perfection")
            assert_projection("removed_title", {"equipped_title": ""}, "N1", "")
            for invalid in (None, 123, True, ["peak_perfection"], {"title_id": "peak_perfection"}):
                assert_projection("invalid_title_" + type(invalid).__name__, {"equipped_title": invalid}, "N1")

            check(connection.execute("SELECT count(*) FROM public.archive_operations WHERE account_id=%s", (account,)).fetchone()[0] == 0,
                  "projection_does_not_create_reward_receipts")
            drift = updated_definition.replace("select jsonb_build_object(", "select /* isolated layout drift */ jsonb_build_object(", 1)
            check(drift != updated_definition, "layout_drift_fixture_constructed")
            try:
                with connection.transaction():
                    connection.execute(drift)
                    connection.execute(sql)
            except Exception as exc:
                check("archive_public_profile_layout_unexpected" in str(exc), "unexpected_layout_is_rejected")
            else:
                raise AssertionError("unexpected layout accepted")
            check(definition() == updated_definition, "rejected_layout_savepoint_rolled_back")
            raise _RollbackFixtures()
    except _RollbackFixtures:
        pass

    check(connection.execute("SELECT count(*) FROM public.survival_players WHERE account_id=%s", (account,)).fetchone()[0] == 0,
          "fixture_player_rolled_back")
    check(definition() == initial_definition, "migration_function_change_rolled_back")
    check(metadata() == initial_metadata, "original_function_metadata_restored")
    return {"ok": True, "checks": checks, "check_count": len(checks),
            "database_changes_committed": False, "real_player_values_changed": False}


class PublicProgressMigrationSourceTests(unittest.TestCase):
    def test_expected_source_matches_captured_production_function_exactly(self):
        root = Path(__file__).resolve().parents[1]
        baseline = root / "output/archive_full_sync_20261009/remote_payment.json"
        if not baseline.is_file():
            self.skipTest("captured production function source unavailable")
        source = (root / "server/migrations/202610090003_archive_public_progress_sync.sql").read_text(encoding="utf-8")
        expected = source.split("$expected$", 2)[1].replace("\n\n", "\n  \n")
        actual = next(row[1] for row in json.loads(baseline.read_text(encoding="utf-8"))["functions"]
                      if row[0] == "public.fishing_profile_json(text)")
        self.assertEqual(expected, actual)

    def test_test_runner_removes_outer_commit(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / "server/migrations/202610090003_archive_public_progress_sync.sql").read_text(encoding="utf-8")
        inner = migration_body(source)
        self.assertFalse(re.search(r"(?im)^(?:begin|commit);", inner))
        self.assertIn("payments.cleared_reward_grants", inner)
        self.assertNotIn("'achievement_score'", inner)


if __name__ == "__main__":
    unittest.main()
