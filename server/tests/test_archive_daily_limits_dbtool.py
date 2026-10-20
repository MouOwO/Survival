"""Offline publication inventory checks for the appended daily-limit migration."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('daily_limits_dbtool', ROOT / 'server/aliyun/database/dbtool.py')
dbtool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dbtool)
MIGRATION = ROOT / 'server/aliyun/database/target/202610200003_archive_daily_limits.sql'


class DailyLimitsPublicationTests(unittest.TestCase):
    def test_quota_objects_are_backup_allowed_but_not_new_application_rpcs(self):
        self.assertIn('fishing_daily_limit_receipts', dbtool.TABLES)
        for name in ('archive_fishing_daily_limit', 'archive_finalize_fishing_checkpoint',
                     'grant_out_of_match_reward_before_daily_limits',
                     'checkpoint_online_time_before_daily_limits', 'fishing_profile_json_before_daily_limits'):
            self.assertIn(name, dbtool.FUNCTIONS)
            self.assertFalse(any(signature.startswith(name+'(') for signature in dbtool.RPC_SIGNATURES))
        self.assertIn('checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean)', dbtool.RPC_SIGNATURES)
        self.assertNotIn('checkpoint_online_time(text,text,text,integer,integer,integer,integer)', dbtool.RPC_SIGNATURES)
        source = MIGRATION.read_text(encoding='utf-8')
        self.assertIn('public.star_blessing_reward_definitions%rowtype', source)
        self.assertNotIn('public.fishing_reward_definitions', source)

    def test_renamed_helpers_and_recreated_wrappers_are_in_expected_inventory(self):
        with tempfile.TemporaryDirectory(prefix='daily-limits-inventory-') as temporary:
            folder = Path(temporary)
            (folder/'before.sql').write_text('''
CREATE FUNCTION public.grant_out_of_match_reward(text,uuid,text,integer,numeric) RETURNS jsonb;
CREATE FUNCTION public.checkpoint_online_time(text,text,text,integer,integer,integer,integer) RETURNS jsonb;
CREATE FUNCTION public.checkpoint_online_time(text,text,text,integer,integer,integer,integer,boolean) RETURNS jsonb;
CREATE FUNCTION public.fishing_profile_json(text) RETURNS jsonb;
''', encoding='utf-8')
            (folder/'quota.sql').write_bytes(MIGRATION.read_bytes())
            tables, functions = dbtool.expected_prefix_objects(folder, [{'path':'before.sql'}, {'path':'quota.sql'}])
            self.assertIn('public.fishing_daily_limit_receipts', tables)
            for name in ('grant_out_of_match_reward', 'checkpoint_online_time', 'fishing_profile_json',
                         'archive_fishing_daily_limit', 'archive_finalize_fishing_checkpoint',
                         'grant_out_of_match_reward_before_daily_limits',
                         'checkpoint_online_time_before_daily_limits', 'fishing_profile_json_before_daily_limits'):
                self.assertIn('public.'+name, functions)

    def test_rename_inventory_observes_statement_order_and_ignores_comments(self):
        with tempfile.TemporaryDirectory(prefix='daily-limits-renames-') as temporary:
            folder = Path(temporary)
            (folder/'rename.sql').write_text('''
CREATE FUNCTION public.one() RETURNS jsonb;
ALTER FUNCTION public.one() RENAME TO two;
CREATE FUNCTION public.one() RETURNS jsonb;
DROP FUNCTION public.two();
-- ALTER FUNCTION public.one() RENAME TO ignored;
''', encoding='utf-8')
            _, functions = dbtool.expected_prefix_objects(folder, [{'path':'rename.sql'}])
            self.assertEqual(functions, {'public.one'})


if __name__ == '__main__':
    unittest.main()
