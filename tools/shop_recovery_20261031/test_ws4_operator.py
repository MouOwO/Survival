"""Exercise scope, pinned authentication and rollback without any real I/O."""
from pathlib import Path
import hashlib,json,tempfile,unittest
from unittest.mock import Mock,patch


def scope():
    path=Path(__file__).with_name('ws4_operator.py')
    result={'STAGE_PATH':'/root/goufayu_upload/ws4-unit-fixture',
        'PLAN_DATA':{'release':'20261031-redemption-ws4-123456789abc','retained_services':{}}}
    exec(compile(path.read_bytes(),str(path),'exec'),result)
    return result


class OperatorTests(unittest.TestCase):
    def test_unrelated_database_is_rejected_before_opening_any_password(self):
        s=scope();s['Path']=Mock(side_effect=AssertionError('password_read'))
        for name in ('goufayu_test','postgres','goufayu_ws4_redeem_not_hex'):
            with self.assertRaisesRegex(RuntimeError,'database_scope_invalid'):s['connect'](name)
        s['Path'].assert_not_called()

    def test_sql_removes_only_the_outer_transaction(self):
        s=scope();body=s['sql_body'](b'-- note\nBEGIN;\nCREATE FUNCTION a() RETURNS void AS $$ BEGIN PERFORM 1; END $$ LANGUAGE plpgsql;\nCOMMIT;\n')
        self.assertIn('$$ BEGIN PERFORM 1; END $$',body)
        for raw in (b'BEGIN; SELECT 1;',b'SELECT 1; COMMIT;'):
            with self.assertRaisesRegex(RuntimeError,'sql_transaction_wrapper_invalid'):s['sql_body'](raw)

    def test_health_uses_the_existing_approved_pin_and_rejects_an_unknown_pin(self):
        token='FICTIONAL_INTERNAL_UPSTREAM_FOR_UNIT_TEST'
        for pinned in (True,False):
            s=scope();s['command']=Mock(return_value=b'123\n')
            mapping={'/proc/123/environ':b'PLAYER_WEB_AUTH_UPSTREAM_BEARER='+token.encode()+b'\0FISHING_API_TOKEN=WRONG_BASE_TOKEN\0',
                '/etc/goufayu-ws4/pins.json':json.dumps({'workshop_id':'3824360109','sha256':[hashlib.sha256(token.encode()).hexdigest()] if pinned else []}).encode()}
            s['Path']=lambda value:Mock(read_bytes=lambda:mapping[value])
            response=Mock();response.__enter__=Mock(return_value=response);response.__exit__=Mock(return_value=False)
            with patch('urllib.request.urlopen',return_value=response) as opening,patch('json.load',return_value={'ok':True,'config_hash':s['HASH']}):
                if pinned:
                    s['health']();self.assertEqual(opening.call_count,1)
                    self.assertEqual(opening.call_args.args[0].get_header('Authorization'),'Bearer '+token)
                else:
                    with self.assertRaisesRegex(RuntimeError,'approved_upstream_pin_required'):s['health']()
                    opening.assert_not_called()

    def test_resume_requires_an_owned_maintenance_receipt(self):
        s=scope()
        with tempfile.TemporaryDirectory() as directory:
            s['STAGE']=Path(directory);s['control']=Mock()
            with self.assertRaisesRegex(RuntimeError,'owned_maintenance_receipt_required'):s['resume']()
            s['control'].assert_not_called()

    def fixture_activation(self,*,fail_migration=False,fail_new_health=False):
        s=scope();temporary=tempfile.TemporaryDirectory();self.addCleanup(temporary.cleanup)
        root=Path(temporary.name);s['STAGE']=root;raw=b'SYNTHETIC_BACKUP_NO_PLAYER_DATA'
        (root/'backup.dump').write_bytes(raw)
        for name,value in [('validated_clone',{'ok':True}),('final_backup',{'path':str(root/'backup.dump'),'sha256':s['sha'](raw),'at':1000}),
                           ('offsite_ack',{'encrypted_verified':True,'sha256':s['sha'](raw)})]:
            (root/(name+'.json')).write_text(json.dumps(value))
        actions=[];receipts={}
        s.update(verify_parent=lambda:None,command=lambda args:b'0',control=lambda action:actions.append(action),
            switch=lambda target:actions.append(target),services=lambda:{},save=lambda name,value:receipts.setdefault(name,value))
        s['time']=Mock(time=lambda:1000)
        class Connection:
            def __enter__(self):return self
            def __exit__(self,*args):return False
            def execute(self,*args):return None
        s.update(connect=lambda:Connection(),pending=lambda conn:None)
        def migrate(conn,register):
            self.assertTrue(register)
            if fail_migration:raise RuntimeError('synthetic_migration_failure')
            return {'codes_registered':128}
        s['migrate']=migrate
        health_calls=[]
        def health():
            health_calls.append(True)
            if fail_new_health and len(health_calls)==1:raise RuntimeError('synthetic_new_api_failure')
        s['health']=health
        return s,actions,receipts

    def test_success_starts_only_the_new_api_after_committed_migration(self):
        s,actions,receipts=self.fixture_activation();result=s['activate']()
        self.assertEqual(actions,[s['NEW'],'start'])
        self.assertTrue(result['ok']);self.assertEqual(result['codes_registered'],128)
        self.assertNotIn('activation_failure',receipts)

    def test_migration_failure_restores_old_api_without_database_restore(self):
        s,actions,receipts=self.fixture_activation(fail_migration=True)
        with self.assertRaisesRegex(RuntimeError,'synthetic_migration_failure'):s['activate']()
        self.assertEqual(actions,['stop',s['OLD'],'start'])
        self.assertFalse(receipts['activation_failure']['database_migrated'])
        self.assertFalse(receipts['activation_failure']['database_restored'])

    def test_postcommit_health_failure_keeps_additive_schema_and_resumes_old_api(self):
        s,actions,receipts=self.fixture_activation(fail_new_health=True)
        with self.assertRaisesRegex(RuntimeError,'synthetic_new_api_failure'):s['activate']()
        self.assertEqual(actions,[s['NEW'],'start','stop',s['OLD'],'start'])
        self.assertTrue(receipts['activation_failure']['database_migrated'])
        self.assertFalse(receipts['activation_failure']['database_restored'])


if __name__=='__main__':unittest.main()
