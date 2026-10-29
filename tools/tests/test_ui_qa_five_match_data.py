"""Five persistent synthetic matches through real Python/Lua business code.

No network, PostgreSQL, Dota process, payment gateway or real account is used.
The database/engine/transport are test doubles. The archive worker, match-mode
projection, HTTP VScript provider and player-profile guards are production code.
This does not constitute five native games or a production deployment check.
"""
from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import types
import unittest

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output/ui_qa_20261025/data"
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
sys.path[:0] = [str(ROOT / "server"), str(ROOT / "server/tests"), str(ROOT)]
from archive_backend.bundle import Bundle, build
from archive_backend.service import ArchiveService, ArchiveError
from archive_backend import match_modes
from test_rich_match_modes import RichDatabase, RichApp


class ApiError(ValueError):
    def __init__(self, code, status):
        super().__init__(code)
        self.code, self.status = code, status


def projection_module():
    """Load the actual override with only its external API parser shimmed."""
    name = "_ui_qa_five_match_api"
    package = types.ModuleType(name)
    package.__path__ = []
    application = types.ModuleType(name + ".application")
    application.ApiError = ApiError
    application.ACCOUNT_ID = r"[0-9]{1,20}"
    application.OPAQUE_ID = r"[A-Za-z0-9_.:-]{8,128}"

    def string(payload, key, pattern):
        value = payload.get(key)
        if not isinstance(value, str) or not re.fullmatch(pattern, value):
            raise ApiError("request_field_invalid", 400)
        return value

    application._string = string
    spec = importlib.util.spec_from_file_location(
        name + ".match_profiles", ROOT / "server/fishing_api_overrides/match_profiles.py")
    module = importlib.util.module_from_spec(spec)
    previous = {key: sys.modules.get(key) for key in (name, name + ".application")}
    sys.modules[name], sys.modules[name + ".application"] = package, application
    try:
        spec.loader.exec_module(module)
    finally:
        for key, value in previous.items():
            if value is None:
                sys.modules.pop(key, None)
            else:
                sys.modules[key] = value
    match_modes.install(module)
    return module


class AuditedDatabase(RichDatabase):
    """Reuse reviewed in-memory receipts; persist them across all five matches."""
    def __init__(self, bundle):
        super().__init__(bundle)
        self.commits = []

    def rpc(self, name, payload):
        account = payload.get("p_account", payload.get("p_account_id"))
        operation = payload.get("p_id")
        if name not in ("archive_commit", "archive_commit_lottery", "archive_commit_challenge"):
            return super().rpc(name, payload)
        before = deepcopy(self.profile(account))
        try:
            return super().rpc(name, payload)
        finally:
            after = self.profile(account)
            if after != before:
                self.commits.append({"account_hash": account, "id": operation,
                    "rpc": name, "before_revision": before["revision"],
                    "after_revision": after["revision"]})


class PersistentFixture:
    modes = ("standard", "pure", "rich", "cold", "standard")
    accounts = tuple(str(81000001 + index) for index in range(4))

    def __init__(self, bundle):
        self.bundle = bundle
        self.database = AuditedDatabase(bundle)
        self.app = RichApp(self.database)
        self.app.gameplay_stats = {
            row["field_id"]: row["default_value"]
            for row in bundle.configs["player_gameplay_stats"]["rows"]}
        self.app._archive_modes_active = True
        self.api = projection_module()
        self.restart_service()
        self.seed_profiles = {}
        for index, account in enumerate(self.accounts):
            raw = self.raw(account)
            # Synthetic prior progress legally satisfies the N3/N5 admission
            # prerequisites. It is never written through an external service.
            raw["save"]["archive"] = {"standard_clear_counts": {"n3": 1, "n5": 1},
                "clear_counts": {"n3": 1, "n5": 1},
                "commerce": {"balances": {"u_coin": 50000 + index * 100,
                                            "shop_points": 20000, "shop_gold": 0}}}
            raw["save"]["content_inventory"] = {"lottery_ticket": 7 + index,
                                                    "special_lottery_ticket": index}
            raw["save"]["gameplay_stats"]["initial_wood"] += 200 + 10 * index
            self.seed_profiles[account] = deepcopy(raw)

    def restart_service(self):
        self.service = ArchiveService(self.app, self.bundle, str(LUA))
        self.app.archive = self.service

    def raw(self, account):
        return self.database.profile(self.app._database_account_id(account))

    def identity(self, account, session):
        return {"account_id": account, "match_session_id": session}

    def login(self, account, session, mode):
        return self.api.login(self.app, dict(self.identity(account, session), mode=mode))

    def view(self, account, session):
        identity = self.identity(account, session)
        context = self.api.context(self.app, identity)
        return self.api.project(self.app, identity, self.service.profile(identity), context)

    def send(self, account, session, command):
        return self.service.command(dict(self.identity(account, session),
            config_hash=self.bundle.hash, command=command))


class FiveMatchDataTests(unittest.TestCase):
    reports = {}

    @classmethod
    def setUpClass(cls):
        cls.pointer_paths = (ROOT / "server/bundles/current.json",
            ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua")
        cls.pointers = [path.read_bytes() for path in cls.pointer_paths]
        cls.temporary = tempfile.TemporaryDirectory(prefix="ui-qa-five-match-")
        cls.addClassCleanup(cls.temporary.cleanup)
        destination = Path(cls.temporary.name)
        cls.bundle = Bundle(destination / build(ROOT, destination=destination,
                                                update_game_config=False))

    def assert_projection(self, fixture, account, session, view):
        context = fixture.database.sessions[(fixture.app._database_account_id(account), session)]
        raw = fixture.raw(account)
        self.assertEqual((view["account_id"], view["match_session_id"], view["revision"]),
                         (account, session, raw["revision"]))
        if context["mode"] == "pure":
            self.assertEqual(view["mode"], "pure")
            for field, default in context["defaults"].items():
                # The selected repeatable ticket does not confer stackable
                # attributes: this oracle is independent signed arithmetic.
                expected = default + raw["save"]["gameplay_stats"][field] - context["baseline"]["save"]["gameplay_stats"][field]
                spec = fixture.bundle.tables["player_gameplay_stats"][field]
                if isinstance(spec.get("min_value"), (int, float)):
                    expected = max(spec["min_value"], expected)
                if isinstance(spec.get("max_value"), (int, float)):
                    expected = min(spec["max_value"], expected)
                self.assertAlmostEqual(view["save"]["gameplay_stats"][field], expected, msg=field)
            for item in ("lottery_ticket", "special_lottery_ticket"):
                expected = raw["save"]["content_inventory"].get(item, 0) - context["baseline"]["save"]["content_inventory"].get(item, 0)
                self.assertEqual(view["save"]["content_inventory"].get(item, 0), max(0, expected))
        else:
            self.assertEqual(view["mode"], "standard")
            if context["mode"] in ("rich", "cold"):
                self.assertEqual(view["game_mode"], context["mode"])
            self.assertEqual(view["save"], raw["save"])
        self.assertEqual(view["account_profile"]["save"], raw["save"])
        self.assertEqual(view["account_profile"]["revision"], raw["revision"])

    def test_10_four_persistent_accounts_five_sessions(self):
        fixture = PersistentFixture(self.bundle)
        self.fixture = fixture
        product = self.bundle.tables["commerce_catalog"]["video_p001"]
        self.assertTrue(product["enabled"])
        self.assertEqual(product["purchase_limit"], 0)
        self.assertEqual(product["grants"]["items"], {"special_lottery_ticket": 1})
        price = product["price"]
        self.assertGreater(price, 0)
        report = {"scope": "persistent_synthetic_DB_real_Python_and_Lua_worker",
            "native_games": 0, "database_instances": 1, "account_count": 4,
            "bundle_hash": self.bundle.hash,
            "synthetic_steamids": [str(76561197960265728 + int(a)) for a in fixture.accounts],
            "session_count_per_account": 5, "modes": list(fixture.modes),
            "seed": deepcopy(fixture.seed_profiles), "rounds": [], "passed": False}
        self.reports["persistent_five_sessions"] = report
        previous_purchase = {}
        for number, mode in enumerate(fixture.modes, 1):
            session = "uiqa-match-" + str(number) + "-" + mode
            round_report = {"number": number, "mode": mode, "session": session, "accounts": []}
            report["rounds"].append(round_report)
            for index, account in enumerate(fixture.accounts):
                before = deepcopy(fixture.raw(account))
                others = {other: deepcopy(fixture.raw(other)) for other in fixture.accounts if other != account}
                login = fixture.login(account, session, mode)
                context = deepcopy(fixture.database.sessions[(fixture.app._database_account_id(account), session)])
                self.assertEqual(context["baseline"], before)
                self.assertEqual(fixture.login(account, session, mode), login)
                self.assertEqual(fixture.raw(account), before, "login is not a permanent grant")
                if mode == "pure":
                    self.assertEqual(login["save"]["gameplay_stats"], fixture.app.gameplay_stats)
                    self.assertEqual(login["save"]["content_inventory"], {})
                    self.assertNotIn("account_profile", login)
                else:
                    self.assertEqual(login["save"], before["save"])
                if account in previous_purchase:
                    # Commerce operation identity intentionally survives a
                    # reconnect/new match; a new session is not a second buy.
                    self.assertTrue(fixture.send(account, session, previous_purchase[account])["ok"])
                    self.assertEqual(fixture.raw(account), before,
                                     "prior-match purchase token replay cannot charge or deliver again")
                clear = {"kind": "mode_clear", "id": session + ":client-first",
                         "difficulty_id": "n1", "count": 1, "cooperative_win": 0}
                lost = number == 3 and index == 1
                fixture.database.lose_reply = lost
                if lost:
                    with self.assertRaises(TimeoutError):
                        fixture.send(account, session, clear)
                    committed = deepcopy(fixture.raw(account))
                    fixture.restart_service()
                    self.assertTrue(fixture.send(account, session, clear)["ok"])
                    self.assertEqual(fixture.raw(account), committed, "lost committed response cannot grant twice")
                else:
                    self.assertTrue(fixture.send(account, session, clear)["ok"])
                after_reward = deepcopy(fixture.raw(account))
                self.assertEqual(after_reward["revision"], before["revision"] + 1)
                scope = "clear_counts" if mode == "pure" else mode + "_clear_counts"
                expected = before["save"]["archive"].get(scope, {}).get("n1", 0) + 1
                self.assertEqual(after_reward["save"]["archive"][scope]["n1"], expected)
                self.assertEqual(after_reward["save"]["archive"]["mode_clear_counts"][mode]["n1"],
                                 before["save"]["archive"].get("mode_clear_counts", {}).get(mode, {}).get("n1", 0) + 1)
                self.assertTrue(fixture.send(account, session, dict(clear, id=session + ":new-wire-id"))["ok"])
                self.assertEqual(fixture.raw(account), after_reward)
                with self.assertRaisesRegex(ArchiveError, "archive_id_conflict"):
                    fixture.send(account, session, dict(clear, difficulty_id="n2"))
                self.assertEqual(fixture.raw(account), after_reward, "same clear receipt cannot change its business fields")
                reward_view = fixture.view(account, session)
                self.assert_projection(fixture, account, session, reward_view)
                purchase = {"kind": "commerce_purchase", "id": session + ":wire-purchase",
                            "sku": "video_p001", "request_id": "uiqa-purchase-" + str(number) + "-" + str(index)}
                lost_purchase = number == 4 and index == 2
                fixture.database.lose_reply = lost_purchase
                if lost_purchase:
                    with self.assertRaises(TimeoutError):
                        fixture.send(account, session, purchase)
                    purchased = deepcopy(fixture.raw(account))
                    fixture.restart_service()
                    self.assertTrue(fixture.send(account, session, purchase)["ok"])
                    self.assertEqual(fixture.raw(account), purchased)
                else:
                    self.assertTrue(fixture.send(account, session, purchase)["ok"])
                after = deepcopy(fixture.raw(account))
                self.assertEqual(after["revision"], before["revision"] + 2)
                self.assertEqual(after["save"]["archive"]["commerce"]["balances"]["u_coin"],
                    after_reward["save"]["archive"]["commerce"]["balances"]["u_coin"] - price)
                self.assertEqual(after["save"]["content_inventory"]["special_lottery_ticket"],
                    after_reward["save"]["content_inventory"].get("special_lottery_ticket", 0) + 1)
                self.assertEqual(after["save"]["content_inventory"]["lottery_ticket"],
                    after_reward["save"]["content_inventory"]["lottery_ticket"])
                self.assertTrue(fixture.send(account, session, purchase)["ok"])
                self.assertEqual(fixture.raw(account), after)
                previous_purchase[account] = deepcopy(purchase)
                final_view = fixture.view(account, session)
                self.assert_projection(fixture, account, session, final_view)
                # Recreating both the API projection object and worker service
                # retains the same DB baseline and committed receipts.
                fixture.api = projection_module()
                fixture.restart_service()
                self.assertEqual(fixture.view(account, session), final_view)
                self.assertEqual(fixture.database.sessions[(fixture.app._database_account_id(account), session)], context)
                for other, value in others.items():
                    self.assertEqual(fixture.raw(other), value, "one account cannot mutate another")
                round_report["accounts"].append({"account": account, "before": before,
                    "login": login, "after_reward": after_reward, "reward_view": reward_view,
                    "after": after, "final_view": final_view,
                    "lost_clear_reply": lost, "lost_purchase_reply": lost_purchase})
        for account in fixture.accounts:
            raw, seed = fixture.raw(account), fixture.seed_profiles[account]
            self.assertEqual(raw["revision"], seed["revision"] + 10)
            self.assertEqual(raw["save"]["content_inventory"]["special_lottery_ticket"],
                             seed["save"]["content_inventory"]["special_lottery_ticket"] + 5)
            self.assertEqual(raw["save"]["archive"]["commerce"]["balances"]["u_coin"],
                             seed["save"]["archive"]["commerce"]["balances"]["u_coin"] - 5 * price)
            self.assertEqual(raw["save"]["archive"]["standard_clear_counts"]["n1"], 2)
        self.assertEqual(len(fixture.database.sessions), 20)
        self.assertEqual(len(fixture.database.commits), 40)
        self.assertTrue(all(c["after_revision"] == c["before_revision"] + 1 for c in fixture.database.commits))
        report.update(passed=True, commits=deepcopy(fixture.database.commits),
                      cross_session_purchase_replays_without_mutation=16,
                      final={a: deepcopy(fixture.raw(a)) for a in fixture.accounts})
        completed = subprocess.run([str(LUA), str(ROOT / "tools/tests/ui_qa_five_match_client.lua")],
            cwd=ROOT, input=json.dumps(report, ensure_ascii=False), capture_output=True,
            text=True, encoding="utf-8", timeout=30,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.reports["lua_client"] = {"exit_code": completed.returncode,
            "stdout": completed.stdout, "stderr": completed.stderr,
            "scope": "real_VScript_HTTP_provider_and_profile_service_synthetic_engine_transport"}
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("UI_QA_FIVE_MATCH_CLIENT_PASS", completed.stdout)

    def test_20_scope_conflicts_and_rejected_purchase_have_no_mutations(self):
        fixture = PersistentFixture(self.bundle)
        account, other = fixture.accounts[:2]
        session = "uiqa-reject-session-standard"
        fixture.login(account, session, "standard")
        before = deepcopy(fixture.raw(account))
        with self.assertRaises(ApiError):
            fixture.login(account, session, "pure")
        self.assertEqual(fixture.raw(account), before)
        clear = {"kind": "mode_clear", "id": "untrusted-client-clear-id", "difficulty_id": "n1", "count": 1}
        with self.assertRaisesRegex(ArchiveError, "match_session_invalid"):
            fixture.send(other, session, clear)
        with self.assertRaisesRegex(ArchiveError, "match_clear_mode_mismatch"):
            fixture.send(account, session, dict(clear, kind="rich_clear"))
        self.assertEqual(fixture.raw(account), before)
        fixture.raw(account)["save"]["archive"]["commerce"]["balances"]["u_coin"] = 0
        unfunded = deepcopy(fixture.raw(account))
        purchase = {"kind": "commerce_purchase", "id": "reject-wire-purchase-one", "sku": "video_p001", "request_id": "reject-purchase-one"}
        self.assertEqual(fixture.send(account, session, purchase)["error"], "commerce_balance_insufficient")
        self.assertEqual(fixture.raw(account), unfunded)
        with self.assertRaisesRegex(ArchiveError, "archive_command_fields_invalid"):
            fixture.send(account, session, dict(purchase, price=0))
        self.assertEqual(fixture.raw(account), unfunded)
        self.assertEqual(fixture.database.commits, [])
        self.reports["negative_scope_and_wallet"] = {"passed": True,
            "mode_rebinding_rejected": True, "cross_account_session_rejected": True,
            "cross_mode_clear_rejected": True, "unfunded_purchase_atomic": True,
            "client_price_rejected": True, "permanent_commits": 0}

    def test_30_revision_conflict_preserves_concurrent_permanent_reward(self):
        fixture = PersistentFixture(self.bundle)
        account = fixture.accounts[0]
        session = "uiqa-concurrent-wallet-standard"
        fixture.login(account, session, "standard")
        before = deepcopy(fixture.raw(account))
        fixture.database.conflict = True
        purchase = {"kind": "commerce_purchase", "id": "uiqa-conflict-wire-purchase",
                    "sku": "video_p001", "request_id": "uiqa-conflict-purchase-one"}
        result = fixture.send(account, session, purchase)
        self.assertTrue(result["ok"])
        after = deepcopy(fixture.raw(account))
        self.assertEqual(after["revision"], before["revision"] + 2)
        self.assertEqual(after["save"]["gameplay_stats"]["initial_wood"],
                         before["save"]["gameplay_stats"]["initial_wood"] + 100)
        self.assertEqual(after["save"]["content_inventory"]["special_lottery_ticket"], 1)
        self.assertEqual(after["save"]["archive"]["commerce"]["balances"]["u_coin"],
                         before["save"]["archive"]["commerce"]["balances"]["u_coin"] -
                         self.bundle.tables["commerce_catalog"]["video_p001"]["price"])
        self.assertTrue(fixture.send(account, session, purchase)["ok"])
        self.assertEqual(fixture.raw(account), after)
        self.reports["revision_conflict"] = {"passed": True,
            "concurrent_wood_delta_preserved": 100, "revision_delta": 2,
            "purchase_item_delta": 1, "replay_changes": 0}

    @classmethod
    def tearDownClass(cls):
        cls.reports["production_bundle_pointers_unchanged"] = all(
            path.read_bytes() == raw for path, raw in zip(cls.pointer_paths, cls.pointers))
        if not cls.reports["production_bundle_pointers_unchanged"]:
            raise AssertionError("Production bundle pointer changed during isolated test")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    started = time.time()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(FiveMatchDataTests)
    with (OUTPUT / "five_match_data.log").open("w", encoding="utf-8") as log:
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    report = {"schema": 1, "scope": "offline_synthetic_cross_layer_data_only",
        "real_accounts_or_payments": False, "network_connections": 0, "native_games": 0,
        "tests_run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
        "passed": result.wasSuccessful(), "elapsed_seconds": round(time.time() - started, 3),
        "reports": FiveMatchDataTests.reports}
    source_paths = ("tools/tests/test_ui_qa_five_match_data.py",
        "tools/tests/ui_qa_five_match_client.lua", "server/archive_backend/service.py",
        "server/archive_backend/match_modes.py", "server/fishing_api_overrides/match_profiles.py",
        "scripts/vscripts/systems/player_profile_service.lua",
        "scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua")
    report["tested_source_sha256"] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in source_paths}
    (OUTPUT / "five_match_data.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("scope", "tests_run", "failures", "errors", "passed", "elapsed_seconds")}))
    if not result.wasSuccessful():
        print((OUTPUT / "five_match_data.log").read_text(encoding="utf-8"))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
