"""Offline checks: no network, database, credentials or operator actions."""
import ast
from pathlib import Path
import unittest
import subprocess
import sys

FILE = Path(__file__).with_name('remote_operator.py')


class OperatorContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = FILE.read_text('utf8')
        cls.tree = ast.parse(cls.raw)
        cls.scope = {'STAGE_PATH': '/root/goufayu_upload/ws4-catalog-test', 'PLAN_DATA': {}}
        exec(compile(cls.raw, str(FILE), 'exec'), cls.scope)

    def test_wrapped_sql_keeps_internal_begin_and_commit_strings(self):
        body = self.scope['sql_body'](b'-- note\nBEGIN;\nCREATE FUNCTION a() RETURNS void AS $$ BEGIN PERFORM 1; END $$ LANGUAGE plpgsql;\nCOMMIT;\n')
        self.assertIn('$$ BEGIN PERFORM 1; END $$', body)
        self.assertFalse(body.strip().startswith('BEGIN;'))

    def test_plain_sql_preserved(self):
        self.assertEqual(self.scope['sql_body'](b'GRANT EXECUTE ON FUNCTION a() TO role;'), 'GRANT EXECUTE ON FUNCTION a() TO role;')

    def test_partial_wrapper_rejected(self):
        for raw in (b'BEGIN; SELECT 1;', b'SELECT 1; COMMIT;'):
            with self.assertRaisesRegex(RuntimeError, 'sql_transaction_wrapper_invalid'):
                self.scope['sql_body'](raw)

    def test_scope_and_recovery_guards(self):
        for marker in ["port=15432", "database == 'goufayu_ws4'", 'verified_fresh_offsite_backup_required',
                       'original_player_or_payment_rows_changed', 'ws4_auth_wrapper_changed',
                       'old_config_policy_changed', 'pending_cash_orders', 'SCHEMA_CLONE_VALIDATED_LIVE_UNCHANGED',
                       'schema_archive_must_not_include_player_data', 'schema_only=True']:
            self.assertIn(marker, self.raw)
        self.assertNotIn('DROP DATABASE', self.raw)
        self.assertNotIn('CASCADE', self.raw)
        self.assertNotIn("'/v1/payments/create'", self.raw)
        self.assertIn("'resume': resume", self.raw)

    def test_absent_role_compatibility_preserves_real_revocations(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('ws4_driver_test', FILE.with_name('driver.py'))
        driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
        original = b'REVOKE ALL ON FUNCTION f() FROM PUBLIC, anon, authenticated, service_role,goufayu_app;'
        self.assertEqual(driver.ws4_sql(original), b'REVOKE ALL ON FUNCTION f() FROM PUBLIC,service_role,goufayu_app;')
        self.assertEqual(driver.ws4_sql(b'REVOKE ALL ON FUNCTION f()\n from public,goufayu_app,anon,authenticated,service_role;'),
                         b'REVOKE ALL ON FUNCTION f()\n from public,goufayu_app,service_role;')
        root = FILE.parents[2]
        for name in ['target/202610250001_onboarding.sql','harden_onboarding.sql',
                     'target/202610220001_human_spec_mode_admission.sql','target/202610290001_archive_challenge_receipts.sql',
                     'harden_archive_challenge_receipts.sql']:
            import re
            value = driver.ws4_sql((root/'server/aliyun/database'/name).read_bytes())
            for clause in re.findall(rb'(?ims)^\s*(?:REVOKE|GRANT)\b[^;]*?\b(?:FROM|TO)\s+([^;]+);', value):
                self.assertNotRegex(clause, rb'\b(?:anon|authenticated)\b')

    def test_live_actions_require_explicit_apply_before_any_remote_work(self):
        for action in ['quiesce', 'protect-backup', 'activate']:
            result = subprocess.run([sys.executable, '-B', str(FILE.with_name('driver.py')), action],
                                    capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'explicit_apply_required_for_live_changes', result.stderr)


if __name__ == '__main__':
    unittest.main()
