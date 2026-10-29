"""Offline release-boundary checks; no SSH or database connections."""
from __future__ import annotations
import ast, hashlib, importlib.util, io, json, sys, tarfile, tempfile, time, unittest
from pathlib import Path
from unittest.mock import Mock, patch

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import server_deploy as driver
import server_remote_operator as remote

class ServerReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan=json.loads((driver.CANDIDATE/'plan.json').read_bytes())
        cls.seal=json.loads((driver.CANDIDATE/'seal.json').read_bytes())
    def test_parent_and_new_contracts_are_both_preserved(self):
        p=self.plan
        self.assertEqual(p['bundle'],'d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488')
        self.assertEqual(len(p['ledger']),34)
        self.assertEqual(len(p['app_rpcs']),18)
        self.assertIn('archive_endless_leaderboard()',p['app_rpcs'])
        self.assertIn('archive_bind_leaderboard_identity(text,text)',p['app_rpcs'])
        self.assertEqual([m['id'] for m in p['migrations']],['target/202610220001_human_spec_mode_admission.sql','target/202610290001_archive_challenge_receipts.sql','security/harden_archive_challenge_receipts.sql'])
        self.assertFalse(any(name.startswith(('payment','backend/payment')) for name in p['overlay']))
    def test_safe_keeps_parent_python_and_csv_but_matching_database_transport(self):
        p=self.plan
        self.assertFalse(any(name.startswith(('backend/archive_backend/','addon/data/csv/')) for name in p['safe_overlay']))
        self.assertEqual(p['safe_overlay']['backend/fishing_api/postgres.py'],p['overlay']['backend/fishing_api/postgres.py'])
        pointer=json.loads((driver.CANDIDATE/'safe_overlay/addon/server/bundles/current.json').read_bytes())
        self.assertEqual(pointer['hash'],p['archive_bundle'])
        pg=(driver.CANDIDATE/'overlay/backend/fishing_api/postgres.py').read_text(encoding='utf-8')
        self.assertIn('"archive_endless_leaderboard": _params()',pg)
        self.assertIn('"archive_commit_challenge": _params(',pg)
        self.assertIn('"ruins", "celestial"',pg)
    def test_full_seal_matches_each_member_and_refuses_modified_operator(self):
        raw=(driver.CANDIDATE/'release.tar.gz').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.seal['archive_sha256'])
        with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as stream:
            self.assertEqual(len(stream.getmembers()),len(self.seal['files']))
            for member in stream.getmembers():
                self.assertTrue(member.isfile())
                self.assertEqual(hashlib.sha256(stream.extractfile(member).read()).hexdigest(),self.seal['files'][member.name])
        for mode in ('prepare','backup','validate-clone','activate','verify','resume','rollback-safe'):
            ast.parse(driver.source_for(mode,self.seal))
    def test_path_and_sql_wrapper_guards_reject_escape_or_missing_wrapper(self):
        for name in ('../api.env','/etc/goufayu/api.env','x/../../etc','x\\api.env','file:stream'):
            with self.assertRaises(RuntimeError):remote.safe(Path('/root/fixed'),name)
        self.assertEqual(remote.sql_body(b'-- reviewed\nBEGIN; SELECT 1; COMMIT;').strip(),'SELECT 1;')
        with self.assertRaises(RuntimeError):remote.sql_body(b'SELECT 1;')
    def test_native_restore_uses_tcp_password_auth_not_root_peer_socket(self):
        args=remote.restore_arguments('postgres','goufayu_restore_archive_123456789abc_123456')
        self.assertIn('PGHOST=127.0.0.1',args)
        self.assertIn('PGPORT=5432',args)
        self.assertIn('PGPASSWORD',args)
        self.assertIn('--single-transaction',args)
        self.assertIn('--exit-on-error',args)
        self.assertNotIn('--clean',args)
    def test_public_schema_drop_is_limited_to_new_verified_empty_clone(self):
        clone='goufayu_restore_archive_123456789abc_123456'
        for identity,relations,functions,extensions in [('goufayu_test',0,0,0),(clone,1,0,0),(clone,0,1,0),(clone,0,0,1)]:
            conn=Mock();conn.execute.return_value.fetchone.return_value=(identity,relations,functions,extensions)
            with self.assertRaises(RuntimeError):remote.prepare_empty_clone(conn,clone,True)
            self.assertNotIn('DROP SCHEMA public',[call.args[0] for call in conn.execute.call_args_list])
        conn=Mock();conn.execute.return_value.fetchone.return_value=(clone,0,0,0)
        remote.prepare_empty_clone(conn,clone,True)
        self.assertEqual(conn.execute.call_args_list[-1].args,('DROP SCHEMA public',))
    def test_foreign_release_switch_refuses_before_replacing_any_pointer(self):
        op=remote.Operator.__new__(remote.Operator)
        op.old,op.new,op.safe=Path('/old'),Path('/new'),Path('/safe')
        op.current=Mock();op.current.resolve.return_value=Path('/somebody_else')
        with patch.object(remote.os,'replace') as replace:
            with self.assertRaisesRegex(RuntimeError,'pointer_ownership_changed'):op.switch(op.new,op.old)
            replace.assert_not_called()
    def test_failed_admission_does_not_stop_or_roll_back_another_api(self):
        with tempfile.TemporaryDirectory() as path:
            stage=Path(path);dump=stage/'backup.dump';dump.write_bytes(b'fixture')
            saved=dict(path=str(dump),sha256=remote.sha(dump.read_bytes()),at=time.time())
            for name,value in {'validated_clone':{'actual_app_transport_ready':True},'private_backup':saved,'offsite_ack':{'encrypted_verified':True,'sha256':saved['sha256']}}.items():
                (stage/(name+'.json')).write_text(json.dumps(value))
            op=remote.Operator.__new__(remote.Operator);op.stage=stage;op.new=Path('/new');op.safe=Path('/safe');op.p={}
            op.manifest=Mock();op.control=Mock();op.baseline=Mock(side_effect=RuntimeError('parent_pointer_changed'))
            conn=Mock();conn.__enter__=Mock(return_value=conn);conn.__exit__=Mock(return_value=False)
            op.connection=Mock(return_value=conn)
            with patch.object(remote.subprocess,'check_output',return_value='inactive'):
                with self.assertRaisesRegex(RuntimeError,'parent_pointer_changed'):op.activate()
            op.control.assert_not_called()

if __name__=='__main__':unittest.main()
