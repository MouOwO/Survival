"""Local PostgreSQL contract tests; never connects to the gameplay database.

Set DAILY_LIMITS_TEST_PORT to a disposable loopback PostgreSQL port 55000..55999.
The database name is fixed and must be created explicitly by the test runner.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / 'server/aliyun/database/target/202610200003_archive_daily_limits.sql'
PSQL = ROOT / 'output/video_shop_20261015/postgres_test/portable/pgsql/bin/psql.exe'
PORT = os.environ.get('DAILY_LIMITS_TEST_PORT', '')
ACCOUNT = 'a' * 64

# A retained grant/checkpoint implementation with real SQL writes and receipts.
# The migration must preserve these semantics while wrapping both grant paths.
FIXTURE = r'''
DO $$ BEGIN
 IF current_database()<>'survival_daily_limits_test' THEN RAISE EXCEPTION 'test_database_required'; END IF;
END $$;
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='goufayu_app') THEN CREATE ROLE goufayu_app; END IF;
END $$;
CREATE TABLE survival_players(account_id text PRIMARY KEY,profile_revision bigint NOT NULL DEFAULT 1);
CREATE TABLE player_gameplay_stats(player_id text PRIMARY KEY,reward_total numeric NOT NULL DEFAULT 0);
CREATE TABLE star_blessing_reward_definitions(reward_id text,definition_version integer,effect_scope text,
 value_min numeric,value_max numeric,PRIMARY KEY(reward_id,definition_version));
CREATE TABLE reward_grants(grant_id uuid PRIMARY KEY,account_id text,reward_id text,effect_scope text,
 amount numeric,granted_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE out_of_match_reward_idempotency(grant_id uuid PRIMARY KEY,account_id text,
 request_fingerprint text,response jsonb);
CREATE TABLE online_time_idempotency(request_id text PRIMARY KEY,account_id text,response jsonb);
CREATE TABLE online_time_sessions(account_id text PRIMARY KEY,session_id text);
CREATE TABLE archive_online_outbox(account_id text,request_id text,elapsed bigint,weighted bigint,created_at timestamptz);
CREATE TABLE archive_operations(account_id text,operation_id text,config_hash text,fingerprint text,
 command jsonb,event_at timestamptz,has_pass boolean,done boolean DEFAULT false,PRIMARY KEY(account_id,operation_id));
CREATE FUNCTION fishing_profile_json(p_account_id text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
 SELECT jsonb_build_object('save',jsonb_build_object('archive','{}'::jsonb),'revision',profile_revision)
 FROM survival_players WHERE account_id=p_account_id;
$$;
CREATE FUNCTION grant_out_of_match_reward(p_account_id text,p_grant_id uuid,p_reward_id text,
 p_definition_version integer,p_amount numeric) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE fingerprint text; saved out_of_match_reward_idempotency%ROWTYPE; result jsonb;
BEGIN
 fingerprint:=encode(digest(p_account_id||E'\n'||p_reward_id||E'\n'||p_definition_version::text||E'\n'||p_amount::text,'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_grant_id::text,0));
 SELECT * INTO saved FROM out_of_match_reward_idempotency WHERE grant_id=p_grant_id;
 IF FOUND THEN
  IF saved.request_fingerprint<>fingerprint THEN RAISE EXCEPTION 'grant_id_conflict'; END IF;
  RETURN saved.response;
 END IF;
 INSERT INTO reward_grants VALUES(p_grant_id,p_account_id,p_reward_id,'permanent',p_amount,now());
 UPDATE player_gameplay_stats SET reward_total=reward_total+p_amount WHERE player_id=p_account_id;
 UPDATE survival_players SET profile_revision=profile_revision+1 WHERE account_id=p_account_id;
 result:=jsonb_build_object('ok',true,'grant',jsonb_build_object('grant_id',p_grant_id,'reward_id',p_reward_id,'amount',p_amount),
  'profile',fishing_profile_json(p_account_id));
 INSERT INTO out_of_match_reward_idempotency VALUES(p_grant_id,p_account_id,fingerprint,result);
 RETURN result;
END;
$$;
CREATE FUNCTION checkpoint_online_time(p_account_id text,p_session_id text,p_request_id text,
 p_lease_seconds integer,p_definition_version integer,p_interval_min_seconds integer,p_interval_max_seconds integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE identifier uuid:=md5(p_account_id||p_request_id)::uuid; result jsonb;
BEGIN
 SELECT response INTO result FROM online_time_idempotency WHERE request_id=p_request_id AND account_id=p_account_id;
 IF FOUND THEN RETURN result; END IF;
 PERFORM 1 FROM player_gameplay_stats WHERE player_id=p_account_id FOR UPDATE;
 PERFORM grant_out_of_match_reward(p_account_id,identifier,'star_blessing_001',1,1);
 result:=jsonb_build_object('ok',true,'elapsed_seconds',61,'grants',jsonb_build_array(
  jsonb_build_object('grant_id',identifier,'reward_id','star_blessing_001','amount',1)));
 INSERT INTO online_time_idempotency VALUES(p_request_id,p_account_id,result);
 RETURN result;
END;
$$;
CREATE FUNCTION checkpoint_online_time(p_account_id text,p_session_id text,p_request_id text,
 p_lease_seconds integer,p_definition_version integer,p_interval_min_seconds integer,p_interval_max_seconds integer,p_final boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE response jsonb;
BEGIN
 IF p_final IS NULL THEN RAISE EXCEPTION 'online_time_payload_invalid'; END IF;
 response:=checkpoint_online_time(p_account_id,p_session_id,p_request_id,p_lease_seconds,p_definition_version,
  p_interval_min_seconds,p_interval_max_seconds);
 IF p_final THEN DELETE FROM online_time_sessions WHERE account_id=p_account_id AND session_id=p_session_id; END IF;
 RETURN response;
END;
$$;
INSERT INTO survival_players VALUES(repeat('a',64),1);
INSERT INTO player_gameplay_stats VALUES(repeat('a',64),0);
INSERT INTO star_blessing_reward_definitions VALUES('star_blessing_001',1,'permanent',1,2);
GRANT USAGE ON SCHEMA public TO goufayu_app,service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO goufayu_app,service_role;
'''


def sql(source, *, check=True):
    if not PORT.isdigit() or not 55000 <= int(PORT) <= 55999:
        raise RuntimeError('disposable_test_port_required')
    environment = dict(os.environ)
    for key in ('PGSERVICE', 'PGPASSWORD', 'PGPASSFILE', 'PGHOST', 'PGDATABASE'):
        environment.pop(key, None)
    environment['PGCLIENTENCODING'] = 'UTF8'
    completed = subprocess.run([str(PSQL), '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
        '-h', '127.0.0.1', '-p', PORT, '-U', 'postgres', '-d', 'survival_daily_limits_test'],
        input=source, text=True, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    if check and completed.returncode:
        raise AssertionError(completed.stderr)
    return completed


def value(source):
    result = sql(source).stdout.strip().splitlines()
    return json.loads(result[-1])


@unittest.skipUnless(PORT, 'set DAILY_LIMITS_TEST_PORT for disposable local PostgreSQL')
class DailyLimitsDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not PSQL.is_file():
            raise unittest.SkipTest('portable PostgreSQL tools unavailable')
        sql(FIXTURE)
        sql(MIGRATION.read_text(encoding='utf-8'))

    def setUp(self):
        sql('TRUNCATE reward_grants,out_of_match_reward_idempotency,fishing_daily_limit_receipts,'
            'online_time_idempotency,online_time_sessions,archive_online_outbox,archive_operations;'
            'UPDATE player_gameplay_stats SET reward_total=0;')

    def seed(self, count, *, yesterday=False):
        stamp = "now()-interval '1 day'" if yesterday else 'now()'
        sql("INSERT INTO reward_grants SELECT md5(i::text)::uuid,repeat('a',64),'star_blessing_001','permanent',1,"
            + stamp + ' FROM generate_series(1,' + str(count) + ') i;'
            'UPDATE player_gameplay_stats SET reward_total=' + str(count) + ';')

    def grant(self, identifier=None, amount=1):
        identifier = identifier or uuid.uuid4()
        return value("SELECT grant_out_of_match_reward(repeat('a',64),'" + str(identifier)
            + "'::uuid,'star_blessing_001',1," + str(amount) + ');')

    def checkpoint(self, request='checkpoint_test_1', *, final=False):
        return value("SELECT checkpoint_online_time(repeat('a',64),'session_test','" + request
            + "',180,1,600,600," + ('true' if final else 'false') + ");")

    def test_concurrent_last_slot_only_one_grant(self):
        self.seed(79)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.grant(), range(4)))
        self.assertEqual(sum(bool(r.get('grant')) for r in results), 1)
        self.assertEqual(value('SELECT count(*) FROM reward_grants;'), 80)
        self.assertEqual(value('SELECT reward_total FROM player_gameplay_stats;'), 80)

    def test_capped_receipt_stays_capped_after_day_reset(self):
        self.seed(80)
        identifier = uuid.uuid4()
        refused = self.grant(identifier)
        self.assertIsNone(refused['grant'])
        sql("UPDATE reward_grants SET granted_at=now()-interval '1 day';")
        self.assertEqual(self.grant(identifier), refused)
        self.assertTrue(self.grant()['grant'])

    def test_accepted_receipt_replays_at_cap_and_rejects_payload_conflict(self):
        self.seed(79)
        identifier = uuid.uuid4()
        first = self.grant(identifier)
        self.assertEqual(self.grant(identifier), first)
        failed = sql("SELECT grant_out_of_match_reward(repeat('a',64),'" + str(identifier)
            + "','star_blessing_001',1,2);", check=False)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('grant_id_conflict', failed.stderr)

    def test_checkpoint_keeps_online_seconds_without_phantom_rewards(self):
        self.seed(79)
        self.assertEqual(len(self.checkpoint()['grants']), 1)
        capped = self.checkpoint('checkpoint_test_2')
        self.assertEqual(capped['elapsed_seconds'], 61)
        self.assertEqual(capped['grants'], [])
        self.assertTrue(capped['daily_limit_reached'])
        self.assertEqual(self.checkpoint('checkpoint_test_2'), capped)
        saved = value("SELECT response FROM online_time_idempotency WHERE request_id='checkpoint_test_2';")
        self.assertEqual(saved, capped)
        sql("UPDATE reward_grants SET granted_at=now()-interval '1 day';")
        self.assertEqual(self.checkpoint('checkpoint_test_2'), capped, 'retry must retain original daily snapshot')

    def test_profile_uses_database_fishing_count_and_day_reset(self):
        self.seed(80, yesterday=True)
        self.grant()
        profile = value("SELECT fishing_profile_json(repeat('a',64));")
        row = profile['save']['daily_limits']['by_key']['fishing']
        self.assertEqual((row['earned'], row['remaining']), (1, 79))

    def test_eight_argument_final_cleanup_and_retry_preserve_capped_result(self):
        self.seed(80)
        sql("INSERT INTO online_time_sessions VALUES(repeat('a',64),'session_test');")
        result = self.checkpoint('final_checkpoint', final=True)
        self.assertEqual(result['grants'], [])
        self.assertTrue(result['daily_limit_reached'])
        self.assertEqual(value('SELECT count(*) FROM online_time_sessions;'), 0)
        self.assertEqual(self.checkpoint('final_checkpoint', final=True), result)

    def test_independent_eight_argument_implementation_is_filtered_too(self):
        signature = 'checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer,boolean)'
        original = value("SELECT to_json(pg_get_functiondef('" + signature + "'::regprocedure));")
        independent = r'''
CREATE OR REPLACE FUNCTION checkpoint_online_time_before_daily_limits(p_account_id text,p_session_id text,p_request_id text,
 p_lease_seconds integer,p_definition_version integer,p_interval_min_seconds integer,p_interval_max_seconds integer,p_final boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE identifier uuid:=md5(p_account_id||p_request_id)::uuid; result jsonb;
BEGIN
 SELECT response INTO result FROM online_time_idempotency WHERE request_id=p_request_id AND account_id=p_account_id;
 IF FOUND THEN RETURN result; END IF;
 PERFORM grant_out_of_match_reward(p_account_id,identifier,'star_blessing_001',1,1);
 result:=jsonb_build_object('ok',true,'elapsed_seconds',61,'grants',jsonb_build_array(
  jsonb_build_object('grant_id',identifier,'reward_id','star_blessing_001','amount',1)));
 INSERT INTO online_time_idempotency VALUES(p_request_id,p_account_id,result);
 IF p_final THEN DELETE FROM online_time_sessions WHERE account_id=p_account_id AND session_id=p_session_id; END IF;
 RETURN result;
END;
$$;
'''
        try:
            sql(independent)
            self.seed(80)
            result = self.checkpoint('independent_eight', final=True)
            self.assertEqual(result['grants'], [])
            self.assertTrue(result['daily_limit_reached'])
            self.assertEqual(self.checkpoint('independent_eight', final=True), result)
        finally:
            sql(original)

    def test_unfinished_online_outbox_keeps_original_beijing_date(self):
        sql("INSERT INTO archive_online_outbox VALUES(repeat('a',64),'delayed',60,60,now()-interval '1 day');"
            "INSERT INTO archive_operations(account_id,operation_id,command) VALUES(repeat('a',64),'online:delayed','{}');"
            "SELECT archive_online_pending(repeat('a',64),repeat('b',64));")
        result = value("SELECT jsonb_build_object('actual',command->>'day_key','expected',"
            "floor((extract(epoch from event.created_at)+28800)/86400)::bigint::text)"
            " FROM archive_operations op JOIN archive_online_outbox event ON op.operation_id='online:'||event.request_id;")
        self.assertEqual(result['actual'], result['expected'])

    def test_renamed_helpers_are_not_executable_by_runtime_role(self):
        permissions = value("SELECT jsonb_build_array("
            "has_function_privilege('goufayu_app','grant_out_of_match_reward_before_daily_limits(text,uuid,text,integer,numeric)','execute'),"
            "has_function_privilege('goufayu_app','checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer)','execute'),"
            "has_function_privilege('goufayu_app','checkpoint_online_time_before_daily_limits(text,text,text,integer,integer,integer,integer,boolean)','execute'),"
            "has_function_privilege('goufayu_app','checkpoint_online_time(text,text,text,integer,integer,integer,integer)','execute'),"
            "has_function_privilege('goufayu_app','checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean)','execute'),"
            "has_function_privilege('goufayu_app','grant_out_of_match_reward(text,uuid,text,integer,numeric)','execute'));")
        self.assertEqual(permissions, [False, False, False, False, True, True])

    def test_invalid_amount_at_cap_cannot_mint_a_receipt(self):
        self.seed(80)
        result = sql("SELECT grant_out_of_match_reward(repeat('a',64),gen_random_uuid(),'star_blessing_001',1,99);", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(value('SELECT count(*) FROM fishing_daily_limit_receipts;'), 0)

    def test_rollback_does_not_consume_quota(self):
        sql("BEGIN;SELECT grant_out_of_match_reward(repeat('a',64),gen_random_uuid(),'star_blessing_001',1,1);ROLLBACK;")
        self.assertEqual(value('SELECT count(*) FROM reward_grants;'), 0)
        self.assertEqual(value('SELECT reward_total FROM player_gameplay_stats;'), 0)

    def test_migration_reapplication_keeps_wrappers(self):
        sql(MIGRATION.read_text(encoding='utf-8'))
        self.seed(80)
        self.assertTrue(self.grant()['daily_limit_reached'])


if __name__ == '__main__':
    unittest.main()
