"""Offline checks: no network, database, credentials or operator actions."""
import ast
from pathlib import Path
import unittest
import subprocess
import sys
import hashlib
import io
import json
from unittest.mock import patch

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
        for action in ['quiesce', 'protect-backup', 'activate', 'reconcile']:
            result = subprocess.run([sys.executable, '-B', str(FILE.with_name('driver.py')), action],
                                    capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'explicit_apply_required_for_live_changes', result.stderr)

    def health_files(self, *, approved=True):
        token = 'unit-test-approved-upstream-credential'
        files = {'/proc/42/environ': b'PLAYER_WEB_AUTH_UPSTREAM_BEARER=' + token.encode() + b'\x00',
                 '/etc/goufayu-ws4/pins.json': json.dumps({'workshop_id': '3824360109',
                    'sha256': [hashlib.sha256(token.encode()).hexdigest()] if approved else []}).encode()}
        return token, lambda path: files[path.as_posix()]

    def test_health_uses_existing_pinned_upstream_identity(self):
        token, read = self.health_files()
        def response(request, **kwargs):
            self.assertEqual(request.get_header('Authorization'), 'Bearer ' + token)
            return io.StringIO(json.dumps({'ok': True, 'config_hash': 'expected-test-hash'}))
        with patch.dict(self.scope, {'command': lambda args: b'42\n'}), patch.object(Path, 'read_bytes', read), \
                patch('urllib.request.urlopen', side_effect=response) as call:
            self.assertTrue(self.scope['health']('expected-test-hash'))
            self.assertEqual(call.call_count, 1)

    def test_health_rejects_unapproved_identity_before_http(self):
        token, read = self.health_files(approved=False)
        with patch.dict(self.scope, {'command': lambda args: b'42\n'}), patch.object(Path, 'read_bytes', read), \
                patch('urllib.request.urlopen') as call:
            with self.assertRaisesRegex(RuntimeError, 'approved_upstream_pin_required'):
                self.scope['health']('expected-test-hash')
            call.assert_not_called()


if __name__ == '__main__':
    unittest.main()
