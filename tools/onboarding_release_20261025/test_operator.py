"""Exercise real release guards with local fixtures, without importing the operator.

Only AST-selected function definitions are compiled. No top-level operator
code, SSH transport, systemctl process or PostgreSQL connection is executed.
"""
from __future__ import annotations

import ast
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import unittest

HERE = Path(__file__).resolve().parent
FUNCTIONS = {"need", "activate", "apply", "check_rows", "sql_body"}


def operator_functions():
    tree = ast.parse((HERE / "remote_operator.py").read_text(encoding="utf-8"))
    nodes = [deepcopy(node) for node in tree.body
             if isinstance(node, ast.FunctionDef) and node.name in FUNCTIONS]
    assert {node.name for node in nodes} == FUNCTIONS
    return compile(ast.Module(body=nodes, type_ignores=[]),
                   "<real-onboarding-operator-functions>", "exec")


class Result:
    def __init__(self, rows):
        self.rows = rows

    def __iter__(self):
        return iter(self.rows)

    def fetchone(self):
        return self.rows[0]


class Connection:
    def __init__(self, harness):
        self.harness = harness
        self.applied = False
        self.ledger = deepcopy(harness.old_ledger)

    def __enter__(self):
        return self

    def __exit__(self, kind, value, traceback):
        if kind is not None:
            self.rollback()

    def execute(self, query, arguments=None):
        self.harness.actions.append(("sql", query))
        if query.startswith("SELECT EXISTS"):
            return Result([(self.harness.ledger_present,)])
        if query == "SELECT migration_id,to_jsonb(t) FROM public._goufayu_migrations t":
            values = deepcopy(self.harness.old_ledger_rows)
            if self.applied:
                for identity, digest in self.ledger.items():
                    values.setdefault(identity, {"migration_id": identity, "sha256": digest,
                                                 "applied_at": "new-time"})
                if self.harness.scenario == "old_ledger_timestamp_changed":
                    values["old/migration"]["applied_at"] = "unexpected-time"
            return Result(list(values.items()))
        if query.startswith("INSERT INTO public._goufayu_migrations"):
            self.ledger[arguments[0]] = arguments[1]
        if query.strip() == "SELECT 'ONBOARDING_MIGRATION_TEST';":
            self.applied = True
        if query == "SELECT count(*) FROM public.player_onboarding_state":
            return Result([(0,)])
        return Result([])

    def commit(self):
        self.harness.actions.append(("commit",))
        self.harness.ledger_present = True
        if self.harness.scenario == "commit_ack_lost":
            raise OSError("simulated_commit_ack_lost")

    def rollback(self):
        self.harness.actions.append(("rollback",))
        self.applied = False


class Harness:
    def __init__(self, stage, scenario="success"):
        self.stage, self.scenario = stage, scenario
        self.old, self.new, self.safe = (Path("/releases") / name
                                        for name in ("OLD", "NEW", "SAFE"))
        self.pointer = self.old
        self.actions, self.reports = [], {}
        self.ledger_present = False
        self.old_ledger = {"old/migration": "original-checksum"}
        self.old_ledger_rows = {"old/migration": {
            "migration_id": "old/migration", "sha256": "original-checksum",
            "applied_at": "original-time"}}
        self.old_functions = {"existing_reward()": "original-function-hash"}
        self.before_rows = {"public._goufayu_migrations": (1, "old-ledger-hash"),
                            "public.survival_players": (2, "old-player-hash"),
                            "payments.orders": (3, "old-payment-hash")}
        self.original_snapshot = deepcopy((self.old_ledger_rows, self.old_functions,
                                           self.before_rows))
        self.stage.mkdir()
        dump = self.stage / "database.dump"
        dump.write_bytes(b"private local test fixture; no account data")
        digest = hashlib.sha256(dump.read_bytes()).hexdigest()
        saved = {"sha256": digest, "path": str(dump), "at": 0 if scenario == "expired" else 1000}
        (self.stage / "private_backup.json").write_text(json.dumps(saved), encoding="utf-8")
        if scenario != "ack_missing":
            (self.stage / "offsite_ack.json").write_text(
                json.dumps({"sha256": digest, "encrypted_verified": True}), encoding="utf-8")
        migrations = []
        for identity, name, raw, wrapped in (
            ("target/onboarding.sql", "migration.sql",
             b"BEGIN;\nSELECT 'ONBOARDING_MIGRATION_TEST';\nCOMMIT;\n", True),
            ("security/harden_onboarding.sql", "harden.sql",
             b"SELECT 'HARDEN_ONBOARDING_TEST';\n", False),
        ):
            path = self.stage / "overlay" / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(raw)
            migrations.append({"id": identity, "path": name,
                               "sha256": hashlib.sha256(raw).hexdigest(),
                               "transaction_wrapper": wrapped})
        self.globals = {
            "json": json, "re": re, "Path": Path,
            "STAGE": self.stage, "OLD": self.old, "NEW": self.new, "SAFE": self.safe,
            "P": {"migrations": migrations, "ledger": deepcopy(self.old_ledger),
                  "archive_bundle": "unchanged-reward-bundle"},
            "time": SimpleNamespace(time=lambda: 1000),
            "subprocess": SimpleNamespace(check_output=lambda *a, **kw: "inactive\n"),
            "sha": lambda raw: hashlib.sha256(raw).hexdigest(),
            "connection": lambda: Connection(self), "control": self.control,
            "switch": self.switch, "health": self.health, "payment_pin": self.payment_pin,
            "save": self.save, "baseline": self.baseline, "db_state": self.db_state,
            "rows_state": self.rows_state, "safe": lambda root, name: root / name,
        }
        exec(operator_functions(), self.globals)

    def activate(self):
        return self.globals["activate"]()

    def control(self, action):
        self.actions.append(("control", action))

    def switch(self, target):
        self.actions.append(("switch", target.name))
        self.pointer = target

    def health(self):
        self.actions.append(("health", self.pointer.name))
        if self.scenario == "new_health_failed" and self.pointer == self.new:
            raise RuntimeError("simulated_new_health_failed")

    def payment_pin(self):
        self.actions.append(("payment_pin",))

    def save(self, name, value):
        self.reports[name] = deepcopy(value)
        return value

    def baseline(self, conn):
        assert self.pointer == self.old
        self.actions.append(("baseline",))

    def db_state(self, conn):
        functions = deepcopy(self.old_functions)
        tables = ["public.survival_players", "public._goufayu_migrations", "payments.orders"]
        if conn.applied:
            functions.update({"initialize_player_onboarding()": "new-trigger",
                              "onboarding_state(text,text)": "new-state",
                              "onboarding_finish(text,text,text)": "new-finish"})
            tables.append("public.player_onboarding_state")
            if self.scenario == "old_function_changed":
                functions["existing_reward()"] = "unexpected-replacement"
        return {"ledger": deepcopy(conn.ledger), "functions": functions, "tables": tables}

    def rows_state(self, conn):
        self.actions.append(("rows_state", conn.applied))
        value = deepcopy(self.before_rows)
        if conn.applied:
            value["public._goufayu_migrations"] = (3, "new-ledger-hash")
            value["public.player_onboarding_state"] = (0, "empty-hash")
            if self.scenario == "old_business_row_changed":
                value["public.survival_players"] = (2, "unexpected-player-hash")
        return value


class OperatorTests(unittest.TestCase):
    def test_missing_ack_and_expired_backup_restore_old_before_raising(self):
        for scenario, error in (("ack_missing", FileNotFoundError), ("expired", RuntimeError)):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                h = Harness(Path(directory) / "stage", scenario)
                with self.assertRaises(error):
                    h.activate()
                self.assertEqual(h.pointer, h.old)
                self.assertFalse(h.ledger_present)
                self.assertNotIn(("commit",), h.actions)
                self.assertIn(("control", "start"), h.actions)
                self.assertEqual(h.reports["activation_recovery"], {
                    "commit_acknowledged": False, "target": "OLD", "database_restored": False})

    def test_lost_commit_ack_uses_ledger_to_choose_safe_and_keeps_additive_data(self):
        with tempfile.TemporaryDirectory() as directory:
            h = Harness(Path(directory) / "stage", "commit_ack_lost")
            with self.assertRaisesRegex(OSError, "simulated_commit_ack_lost"):
                h.activate()
            self.assertTrue(h.ledger_present)
            self.assertEqual(h.pointer, h.safe)
            self.assertFalse(h.reports["activation_recovery"]["commit_acknowledged"])
            self.assertFalse(h.reports["activation_recovery"]["database_restored"])
            self.assertIn(("health", "SAFE"), h.actions)

    def test_new_health_failure_recovers_safe_after_successful_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            h = Harness(Path(directory) / "stage", "new_health_failed")
            with self.assertRaisesRegex(RuntimeError, "simulated_new_health_failed"):
                h.activate()
            self.assertEqual([item for item in h.actions if item[0] == "switch"],
                             [("switch", "NEW"), ("switch", "SAFE")])
            self.assertEqual(h.pointer, h.safe)
            self.assertTrue(h.reports["activation_recovery"]["commit_acknowledged"])
            self.assertIn(("health", "SAFE"), h.actions)

    def test_success_uses_repeatable_read_preserves_old_objects_and_resets_owner_role(self):
        with tempfile.TemporaryDirectory() as directory:
            h = Harness(Path(directory) / "stage")
            result = h.activate()
            self.assertTrue(result["ok"])
            self.assertEqual(h.pointer, h.new)
            self.assertEqual(result["bundle"], "unchanged-reward-bundle")
            self.assertEqual((h.old_ledger_rows, h.old_functions, h.before_rows), h.original_snapshot)
            self.assertEqual((result["new_migrations"], result["new_functions"], result["new_tables"]), (2, 3, 1))
            isolation = h.actions.index(("sql", "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"))
            reset = h.actions.index(("sql", "RESET ROLE"))
            second_rows = h.actions.index(("rows_state", True))
            commit = h.actions.index(("commit",))
            self.assertLess(isolation, h.actions.index(("baseline",)))
            self.assertLess(reset, second_rows)
            self.assertLess(second_rows, commit)
            self.assertNotIn("activation_recovery", h.reports)

    def test_real_apply_and_row_guards_reject_old_function_timestamp_or_business_mutations(self):
        for scenario, code in (("old_function_changed", "old_sql_function_modified"),
                               ("old_ledger_timestamp_changed", "old_ledger_row_modified"),
                               ("old_business_row_changed", "existing_business_rows_modified")):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                h = Harness(Path(directory) / "stage", scenario)
                with self.assertRaisesRegex(RuntimeError, code):
                    h.activate()
                self.assertFalse(h.ledger_present)
                self.assertNotIn(("commit",), h.actions)
                self.assertEqual(h.pointer, h.old)
                self.assertEqual(h.reports["activation_recovery"]["target"], "OLD")

    def test_row_guard_allows_only_ledger_append_and_empty_new_table(self):
        namespace = {"re": re}
        exec(operator_functions(), namespace)
        before = {"public._goufayu_migrations": (32, "original"),
                  "public.survival_players": (20, "unchanged")}
        after = {**before, "public._goufayu_migrations": (34, "appended"),
                 "public.player_onboarding_state": (0, "empty")}
        namespace["check_rows"](before, after)
        for field, value, error in (
            ("public.survival_players", (21, "changed"), "existing_business_rows_modified"),
            ("public.player_onboarding_state", (1, "leaked"), "probe_rows_leaked"),
            ("public.unrelated_table", (0, "unexpected"), "table_inventory_changed"),
        ):
            changed = deepcopy(after)
            changed[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, error):
                namespace["check_rows"](before, changed)

    def test_sql_wrapper_removal_preserves_inner_body_and_refuses_wrong_layout(self):
        namespace = {"re": re}
        exec(operator_functions(), namespace)
        body = "\nCREATE FUNCTION sample() RETURNS int LANGUAGE plpgsql AS $$\nBEGIN\n RETURN 1;\nEND; $$;\n"
        wrapped = ("\ufeff-- reviewed migration\nBEGIN;" + body + "COMMIT;\n").encode("utf-8")
        self.assertEqual(namespace["sql_body"](wrapped, True), body)
        self.assertEqual(namespace["sql_body"](b"REVOKE ALL ON TABLE example FROM PUBLIC;\n", False),
                         "REVOKE ALL ON TABLE example FROM PUBLIC;\n")
        for raw, wrapped in ((b"SELECT 1; COMMIT;", True),
                             (b"BEGIN; SELECT 1;", True),
                             (b"BEGIN; SELECT 1; COMMIT; SELECT 2;", True),
                             (b"BEGIN; SELECT 1; COMMIT;", False)):
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                namespace["sql_body"](raw, wrapped)


if __name__ == "__main__":
    unittest.main()
