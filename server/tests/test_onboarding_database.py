"""Real SQL tests on an explicitly created disposable loopback database only.

ONBOARDING_TEST_PORT must be a local test-cluster port in 55000..55999. This
suite never discovers a DSN or connects to a gameplay/payment database.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "output/video_shop_20261015/deps"))
PORT = os.environ.get("ONBOARDING_TEST_PORT", "")
MIGRATION = ROOT / "server/aliyun/database/target/202610250001_onboarding.sql"
OLD = "a" * 64
SESSION = "onboarding_database_session"
FIXTURE = r"""
DO $$ BEGIN
 IF current_database()<>'survival_onboarding_test' THEN RAISE EXCEPTION 'test_database_required'; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS extensions;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='goufayu_app') THEN CREATE ROLE goufayu_app; END IF;
END $$;
CREATE TABLE survival_players(account_id text PRIMARY KEY,profile_revision bigint NOT NULL DEFAULT 1);
CREATE TABLE player_gameplay_stats(player_id text PRIMARY KEY,attack integer NOT NULL DEFAULT 42);
CREATE TABLE player_archive_state(account_id text PRIMARY KEY,archive jsonb NOT NULL DEFAULT '{}');
CREATE TABLE match_profile_sessions(account_id text,match_session_id text,mode text);
INSERT INTO survival_players(account_id) VALUES(repeat('a',64));
INSERT INTO player_gameplay_stats(player_id) VALUES(repeat('a',64));
INSERT INTO player_archive_state(account_id,archive) VALUES(repeat('a',64),'{"clear_counts":{}}');
INSERT INTO match_profile_sessions VALUES(repeat('a',64),'onboarding_database_session','pure');
"""


@unittest.skipUnless(PORT.isdigit() and 55000 <= int(PORT) <= 55999, "ONBOARDING_TEST_PORT is not configured")
class OnboardingDatabaseTests(unittest.TestCase):
    @classmethod
    def connect(cls):
        import psycopg
        return psycopg.connect(host="127.0.0.1", port=int(PORT), dbname="survival_onboarding_test",
                               user="postgres", autocommit=True, connect_timeout=5)

    @classmethod
    def setUpClass(cls):
        cls.conn = cls.connect()
        cls.conn.execute(FIXTURE)
        cls.conn.execute(MIGRATION.read_text(encoding="utf-8-sig"))
        cls.conn.execute((ROOT / "server/aliyun/database/harden_onboarding.sql").read_text(encoding="utf-8-sig"))

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def new_account(self, mode="pure"):
        account = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        self.conn.execute("INSERT INTO survival_players(account_id) VALUES(%s)", (account,))
        self.conn.execute("INSERT INTO player_gameplay_stats(player_id) VALUES(%s)", (account,))
        self.conn.execute("INSERT INTO player_archive_state(account_id) VALUES(%s)", (account,))
        self.conn.execute("INSERT INTO match_profile_sessions VALUES(%s,%s,%s)", (account,SESSION,mode))
        return account

    def state(self, account, session=SESSION):
        return self.conn.execute("SELECT onboarding_state(%s,%s)", (account,session)).fetchone()[0]

    def finish(self, account, outcome, session=SESSION):
        return self.conn.execute("SELECT onboarding_finish(%s,%s,%s)", (account,session,outcome)).fetchone()[0]

    def test_old_account_with_zero_wins_remains_legacy_without_backfill(self):
        self.assertEqual(self.state(OLD), {"ok":True,"version":1,"required":False,"status":"legacy"})
        self.conn.execute("INSERT INTO survival_players(account_id) VALUES(%s) ON CONFLICT DO NOTHING", (OLD,))
        self.assertEqual(self.state(OLD)["status"], "legacy")
        self.assertEqual(self.finish(OLD,"completed"), {"ok":False,"error":"onboarding_not_required"})
        self.assertIsNone(self.conn.execute("SELECT 1 FROM player_onboarding_state WHERE account_id=%s", (OLD,)).fetchone())

    def test_new_account_trigger_is_atomic_and_independent_of_mode_and_rewards(self):
        for mode in ("pure","standard","rich"):
            account = self.new_account(mode)
            before = self.conn.execute("SELECT to_jsonb(p),to_jsonb(g),to_jsonb(a) FROM survival_players p "
                "JOIN player_gameplay_stats g ON p.account_id=g.player_id "
                "JOIN player_archive_state a USING(account_id) WHERE p.account_id=%s", (account,)).fetchone()
            self.assertEqual(self.state(account), {"ok":True,"version":1,"required":True,"status":"required"})
            self.assertEqual(self.finish(account,"completed")["status"], "completed")
            after = self.conn.execute("SELECT to_jsonb(p),to_jsonb(g),to_jsonb(a) FROM survival_players p "
                "JOIN player_gameplay_stats g ON p.account_id=g.player_id "
                "JOIN player_archive_state a USING(account_id) WHERE p.account_id=%s", (account,)).fetchone()
            self.assertEqual(before, after, "onboarding must not grant rewards or mutate a battle save")
        account = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        with self.conn.transaction(force_rollback=True):
            self.conn.execute("INSERT INTO survival_players(account_id) VALUES(%s)", (account,))
            self.assertIsNotNone(self.conn.execute("SELECT 1 FROM player_onboarding_state WHERE account_id=%s", (account,)).fetchone())
        self.assertIsNone(self.conn.execute("SELECT 1 FROM player_onboarding_state WHERE account_id=%s", (account,)).fetchone())

    def test_terminal_result_survives_retries_sessions_and_migration_reapplication(self):
        account = self.new_account()
        self.assertEqual(self.finish(account,"skipped")["status"], "skipped")
        timestamp = self.conn.execute("SELECT finished_at FROM player_onboarding_state WHERE account_id=%s", (account,)).fetchone()[0]
        self.assertEqual(self.finish(account,"completed")["status"], "skipped")
        self.conn.execute("INSERT INTO match_profile_sessions VALUES(%s,%s,'standard')", (account,SESSION+"_next"))
        self.assertEqual(self.state(account,SESSION+"_next")["status"], "skipped")
        self.conn.execute(MIGRATION.read_text(encoding="utf-8-sig"))
        self.assertEqual(self.state(account)["status"], "skipped")
        self.assertEqual(self.state(OLD)["status"], "legacy")
        self.assertEqual(timestamp,self.conn.execute("SELECT finished_at FROM player_onboarding_state WHERE account_id=%s", (account,)).fetchone()[0])

    def test_concurrent_terminal_outcomes_have_one_winner(self):
        account = self.new_account()
        def submit(outcome):
            with self.connect() as conn:
                return conn.execute("SELECT onboarding_finish(%s,%s,%s)", (account,SESSION,outcome)).fetchone()[0]
        with ThreadPoolExecutor(max_workers=8) as workers:
            results = list(workers.map(submit,["completed","skipped"]*4))
        self.assertEqual(len({item["status"] for item in results}),1)
        self.assertTrue(all(item["ok"] and item["required"] is False for item in results))

    def test_account_session_binding_and_unsafe_outcomes_are_rejected(self):
        account = self.new_account()
        self.assertEqual(self.state(account,SESSION+"_unknown"), {"ok":False,"error":"match_session_missing"})
        self.assertEqual(self.finish(account,"skipped",SESSION+"_unknown"), {"ok":False,"error":"match_session_missing"})
        for outcome in (None,"required","legacy","skip"):
            with self.assertRaises(Exception):
                self.finish(account,outcome)
        self.assertTrue(self.state(account)["required"])

    def test_only_app_role_may_use_rpcs_and_cannot_access_metadata_table(self):
        account = self.new_account()
        for role in ("anon","authenticated","service_role"):
            self.conn.execute("SET ROLE " + role)
            try:
                for sql,args in (("SELECT onboarding_state(%s,%s)",(account,SESSION)),
                                 ("SELECT onboarding_finish(%s,%s,'skipped')",(account,SESSION)),
                                 ("SELECT * FROM player_onboarding_state",())):
                    with self.assertRaises(Exception):
                        self.conn.execute(sql,args)
            finally:
                self.conn.execute("RESET ROLE")
        self.conn.execute("SET ROLE goufayu_app")
        try:
            self.assertTrue(self.state(account)["required"])
            self.assertEqual(self.finish(account,"skipped")["status"], "skipped")
            with self.assertRaises(Exception):
                self.conn.execute("SELECT * FROM player_onboarding_state")
        finally:
            self.conn.execute("RESET ROLE")
        for function in ("onboarding_state(text,text)","onboarding_finish(text,text,text)"):
            self.assertEqual(self.conn.execute("SELECT prosecdef,proconfig FROM pg_proc WHERE oid=%s::regprocedure",
                ("public."+function,)).fetchone(), (True,["search_path=pg_catalog, public, extensions, pg_temp"]))


if __name__ == "__main__":
    unittest.main()
