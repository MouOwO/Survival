"""Isolated boundaries. No SSH, PostgreSQL, credentials, SDK or native clients."""
from pathlib import Path, PurePosixPath, PureWindowsPath
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
op=module('ticket_ws4_operator_test',HERE/'ws4_operator.py')
driver=module('ticket_ws4_driver_test',HERE/'ws4_register.py')
definitions=module('ticket_ws4_definitions_test',HERE/'definitions.py')
clone_checks=module('ticket_ws4_clone_contract_test',HERE/'clone_checks.py')
REGISTRY=definitions.compile_definitions({str(n):hashlib.sha256(('synthetic_fixture_'+str(n)).encode()).hexdigest() for n in (10,50,100,200)})
BASE={'count':128,'sha256':'a'*64}


class Cursor:
    def __init__(self,value):self.value=value
    def fetchone(self):return self.value


class FakeConnection:
    def __init__(self,collision=False,fail_insert=None):
        self.collision,self.fail_insert=collision,fail_insert
        self.statements=[];self.inserted=[];self.committed=False;self.rolled_back=False
    def execute(self,statement,args=None):
        self.statements.append((statement,args))
        if statement.startswith('SELECT pg_try_advisory'):return Cursor((True,))
        if statement.startswith('SELECT 1 FROM public.redemption_codes'):return Cursor((1,)if self.collision else None)
        if statement.startswith('INSERT INTO public.redemption_codes'):
            if self.fail_insert==len(self.inserted):raise RuntimeError('synthetic_insert_failure')
            self.inserted.append(args);return Cursor((args[0],))
        return Cursor(None)
    def __enter__(self):return self
    def __exit__(self,kind,value,tb):
        if kind:self.rolled_back=True;self.inserted=[]
        else:self.committed=True


@contextlib.contextmanager
def jsonb_fake():
    with patch.dict(sys.modules,{'psycopg':SimpleNamespace(), 'psycopg.types':SimpleNamespace(),
              'psycopg.types.json':SimpleNamespace(Jsonb=lambda value:value)}):yield


class OperatorTests(unittest.TestCase):
    def test_four_rows_exact_tiers_and_no_other_reward(self):
        self.assertEqual(len(op.validate_registry(REGISTRY)),4)
        for mutate in (lambda r:r['codes'][0]['rewards']['products'][0]['grants']['items'].update(special_lottery_ticket=1),
                       lambda r:r['codes'][0].update(enabled=False),
                       lambda r:r['codes'][0].update(code_id='r_bad'),
                       lambda r:r['codes'][0]['rewards']['wallet'].update(u_coin=100)):
            bad=copy.deepcopy(REGISTRY);mutate(bad)
            with self.assertRaises(RuntimeError):op.validate_registry(bad)

    def test_short_transaction_only_inserts_four_and_preserves_existing(self):
        conn=FakeConnection()
        with jsonb_fake(),patch.object(op,'definitions_state',return_value=BASE),patch.object(op,'claims_state',return_value={'count':9,'sha256':'b'*64}):
            result=op.insert_four(conn,REGISTRY['codes'],BASE)
        self.assertEqual(result['inserted'],4)
        self.assertEqual(len(conn.inserted),4)
        writes=[sql for sql,args in conn.statements if sql.startswith(('INSERT','UPDATE','DELETE'))]
        self.assertTrue(all(sql==op.INSERT for sql in writes))
        self.assertNotIn('ON CONFLICT',op.INSERT)
        self.assertIn('RETURNING code_id',op.INSERT)
        self.assertTrue(result['normal_concurrent_claims_allowed'])
        lock=next(i for i,(sql,args)in enumerate(conn.statements)if sql.startswith('LOCK TABLE'))
        first_select=next(i for i,(sql,args)in enumerate(conn.statements)if sql.startswith('SELECT'))
        self.assertLess(lock,first_select,'RR snapshot must not be fixed before the table lock')

    def test_collision_stops_before_first_insert(self):
        conn=FakeConnection(collision=True)
        with jsonb_fake(),patch.object(op,'definitions_state',return_value=BASE),patch.object(op,'claims_state',return_value={'count':9,'sha256':'b'*64}):
            with self.assertRaisesRegex(RuntimeError,'new_code_identity_collision'):
                op.insert_four(conn,REGISTRY['codes'],BASE)
        self.assertEqual(conn.inserted,[])

    def test_any_insert_failure_rolls_back_all_four(self):
        conn=FakeConnection(fail_insert=2)
        with jsonb_fake(),patch.object(op,'definitions_state',return_value=BASE),patch.object(op,'claims_state',return_value={'count':9,'sha256':'b'*64}):
            with self.assertRaisesRegex(RuntimeError,'synthetic_insert_failure'):
                with conn:op.insert_four(conn,REGISTRY['codes'],BASE)
        self.assertTrue(conn.rolled_back);self.assertEqual(conn.inserted,[])

    def test_same_rr_snapshot_detects_own_claim_mutation(self):
        conn=FakeConnection()
        with jsonb_fake(),patch.object(op,'definitions_state',return_value=BASE),patch.object(op,'claims_state',side_effect=[{'count':9,'sha256':'b'*64},{'count':9,'sha256':'c'*64}]):
            with self.assertRaisesRegex(RuntimeError,'existing_claims_modified'):
                with conn:op.insert_four(conn,REGISTRY['codes'],BASE)
        self.assertTrue(conn.rolled_back)

    def test_old_definition_drift_refuses_without_writes(self):
        conn=FakeConnection()
        with jsonb_fake(),patch.object(op,'definitions_state',return_value={'count':129,'sha256':'c'*64}):
            with self.assertRaisesRegex(RuntimeError,'existing_definitions_changed'):
                op.insert_four(conn,REGISTRY['codes'],BASE)
        self.assertEqual(conn.inserted,[])

    def test_unknown_prior_apply_never_opens_database_or_retries(self):
        with tempfile.TemporaryDirectory()as temp:
            stage=Path(temp);(stage/'apply_intent.json').write_text('{}')
            with patch.object(op,'checked_stage',return_value=stage),patch.object(op,'operator_lock',return_value=contextlib.nullcontext()),patch.object(op,'baseline'),patch.object(op,'connect',side_effect=AssertionError('No retry')):
                with self.assertRaisesRegex(RuntimeError,'existing_apply_intent'):
                    op.apply({})

    def test_commit_reply_unknown_keeps_intent_and_blocks_second_apply(self):
        class LostCommit(FakeConnection):
            def __exit__(self,kind,value,tb):
                self.committed=True
                raise TimeoutError('synthetic_commit_reply_lost')
        with tempfile.TemporaryDirectory()as temp:
            stage=Path(temp);plan={'inventory':{'definitions':BASE}}
            payload=b'PGDMPsynthetic_full_backup';backup=stage/'full_backup.dump';backup.write_bytes(payload)
            for name,value in {'registry':REGISTRY,'clone':{'plan_sha256':op.sha(op.canonical(plan))},
                    'backup':{'path':str(backup),'sha256':op.sha(payload),'at':1000,'schema_only':False},
                    'offsite_ack':{'encrypted_roundtrip_verified':True,'sha256':op.sha(payload)}}.items():
                op.save(stage,name,value)
            connection=LostCommit()
            with patch.object(op,'checked_stage',return_value=stage),patch.object(op,'operator_lock',return_value=contextlib.nullcontext()),\
                 patch.object(op,'baseline'),patch.object(op.time,'time',return_value=1001),\
                 patch.object(op,'connect',return_value=connection)as opened,patch.object(op,'insert_four',return_value={'inserted':4}):
                with self.assertRaises(TimeoutError):op.apply(plan)
                self.assertTrue(connection.committed)
                self.assertEqual(op.load(stage,'apply_unknown')['status'],'PRESERVE_PENDING_VERIFY_ONLY')
                self.assertTrue((stage/'apply_intent.json').exists());self.assertFalse((stage/'applied.json').exists())
                with self.assertRaisesRegex(RuntimeError,'existing_apply_intent'):op.apply(plan)
                self.assertEqual(opened.call_count,1)

    def test_stale_full_backup_refuses_before_intent_or_database(self):
        with tempfile.TemporaryDirectory()as temp:
            stage=Path(temp);plan={'inventory':{'definitions':BASE}}
            for name,value in {'clone':{'plan_sha256':op.sha(op.canonical(plan))},
                    'backup':{'at':0,'schema_only':False},'offsite_ack':{}}.items():op.save(stage,name,value)
            with patch.object(op,'checked_stage',return_value=stage),patch.object(op,'operator_lock',return_value=contextlib.nullcontext()),\
                 patch.object(op,'baseline'),patch.object(op.time,'time',return_value=901),\
                 patch.object(op,'connect',side_effect=AssertionError('No stale-backup write')):
                with self.assertRaisesRegex(RuntimeError,'fresh_full_dpapi'):op.apply(plan)
            self.assertFalse((stage/'apply_intent.json').exists())

    def test_database_name_and_stage_scopes_refuse_other_system(self):
        for name in ['goufayu_test','postgres','goufayu_ws4_ticket_bad','goufayu_ws4_ticket_123456789abc_more']:
            with self.assertRaisesRegex(RuntimeError,'database_scope_invalid'):op.connect(name)
        for name in ['/opt/goufayu/releases/run_123456789abc','/root/goufayu_upload/ticket_codes_20261102/../other']:
            with self.assertRaisesRegex(RuntimeError,'stage_scope_invalid'):op.stage_path({'stage':name})

    def test_clone_and_backup_share_existing_operator_file_lock(self):
        for action in ['clone','backup']:
            with patch.object(op,'operator_lock',return_value=contextlib.nullcontext())as lock,patch.object(op,action,return_value={'ok':True})as phase:
                self.assertTrue(op.dispatch(action,{})['ok']);lock.assert_called_once();phase.assert_called_once()

    def test_existing_redemption_and_admission_locks_release_on_partial_failure(self):
        self.assertEqual([p.as_posix()for p in op.LOCKS],['/var/lock/goufayu_admission_five.lock','/var/lock/goufayu_ws4_redemption.lock'])
        events=[]
        class Stream:
            def __init__(self,identifier):self.identifier=identifier;self.closed=False
            def fileno(self):return self.identifier
            def close(self):self.closed=True
        streams=[Stream(1),Stream(2)]
        def flock(fd,flags):
            events.append((fd,flags))
            if fd==2 and flags==5:raise BlockingIOError('synthetic_second_lock_owned')
        fake=SimpleNamespace(LOCK_EX=1,LOCK_NB=4,LOCK_UN=8,flock=flock)
        with patch.dict(sys.modules,{'fcntl':fake}),patch.object(Path,'open',side_effect=streams):
            with self.assertRaises(BlockingIOError):
                with op.operator_lock():raise AssertionError('Must not enter lease')
        self.assertTrue(all(s.closed for s in streams));self.assertEqual(events,[(1,5),(2,5),(1,8)])

    def test_clone_app_satisfies_real_archive_profile_contract(self):
        from archive_backend.service import ArchiveService
        calls=[]
        class Client:
            def rpc(self,name,args):
                calls.append((name,args))
                if name=='get_fishing_profile':return {'account_id':'synthetic_internal','save':{'content_inventory':{'lottery_ticket':10}}}
                if name in ('archive_online_pending','archive_pending'):return []
                if name=='ensure_player_gameplay_stats':return {'ok':True}
                raise AssertionError(name)
        app=clone_checks.make_app(Client(),{'100':'synthetic_internal'},{'initial_wood':0})
        service=ArchiveService.__new__(ArchiveService);service.app=app;service.bundle=SimpleNamespace(hash='synthetic_bundle')
        actual=service.profile({'account_id':'100'})
        self.assertEqual(actual['account_id'],'100');self.assertEqual(actual['save']['content_inventory']['lottery_ticket'],10)
        self.assertEqual(sum(name=='get_fishing_profile'for name,args in calls),2)
        self.assertTrue(any(name=='ensure_player_gameplay_stats'for name,args in calls))

    def test_clone_zero_price_balance_normalization_is_not_value_change(self):
        self.assertTrue(clone_checks.same_balances({}, {'u_coin':0}))
        self.assertTrue(clone_checks.same_balances({'u_coin':0}, {}))
        self.assertFalse(clone_checks.same_balances({}, {'u_coin':1}))
        self.assertFalse(clone_checks.same_balances({'u_coin':88,'shop_points':99}, {'u_coin':87,'shop_points':99}))
        self.assertFalse(clone_checks.same_balances({}, {'other_currency':1}))

    def test_verify_uses_same_rr_digest_count_and_start_validity(self):
        plan={'inventory':{'definitions':BASE,'payment_services':{'payment':1}}}
        expected=[(r['code_id'],r['code_hash'],r['label'],r['rewards'],True,0,None,True)for r in sorted(REGISTRY['codes'],key=lambda r:r['code_id'])]
        class ReadCursor(Cursor):
            def fetchall(self):return self.value
        class ReadConnection(FakeConnection):
            def __init__(self,count,started):super().__init__();self.count,self.started=count,started
            def execute(self,sql,args=None):
                self.statements.append((sql,args))
                if sql.startswith('SELECT code_id'):
                    values=copy.deepcopy(expected);values[0]=(*values[0][:-1],self.started);return ReadCursor(values)
                if sql.startswith('SELECT count(*)'):return Cursor((self.count,))
                return Cursor(None)
            def rollback(self):pass
        for count,started,preserved,want in [(132,True,BASE,True),(133,True,BASE,False),(132,False,BASE,False),(132,True,{'count':128,'sha256':'c'*64},False)]:
            with self.subTest(count=count,started=started),tempfile.TemporaryDirectory()as temp:
                stage=Path(temp);op.save(stage,'registry',REGISTRY);conn=ReadConnection(count,started)
                with patch.object(op,'checked_stage',return_value=stage),patch.object(op,'baseline')as baseline,\
                     patch.object(op,'connect',return_value=conn),patch.object(op,'definitions_state',return_value=preserved),\
                     patch.object(op,'payment_services',return_value={'payment':1}):
                    result=op.verify(plan)
                self.assertEqual(result['matching_four'],want);self.assertTrue(result['same_rr_verification_snapshot'])
                baseline.assert_called_once_with(plan,check_definitions=False)

    def test_default_driver_does_not_connect_or_write(self):
        with patch.object(driver,'remote',side_effect=AssertionError('No SSH')),patch.object(driver,'new_json',side_effect=AssertionError('No writes')),contextlib.redirect_stdout(io.StringIO())as out:
            self.assertEqual(driver.main([]),0)
        self.assertEqual(json.loads(out.getvalue())['production_writes'],0)

    def test_apply_and_phase_execution_require_explicit_flags_before_transport(self):
        for action in ['apply','upload','clone','backup','protect-backup']:
            with patch.object(driver,'remote',side_effect=AssertionError('No SSH')):
                with self.assertRaisesRegex(ValueError,'explicit_'):
                    driver.main([action,'--plan','dummy','--plan-sha','a'*64])

    def test_receipt_path_is_new_and_limited_to_operator_output(self):
        with tempfile.TemporaryDirectory()as temp,patch.object(driver,'OUT',Path(temp)):
            path=Path(temp)/'receipt.json';driver.new_json(path,{'ok':True})
            with self.assertRaises(FileExistsError):driver.new_json(path,{})
            with self.assertRaisesRegex(ValueError,'new_output_under_operator_root'):
                driver.new_json(Path(temp)/'nested/receipt.json',{})

    def test_local_plan_cannot_omit_operator_pins(self):
        with tempfile.TemporaryDirectory()as temp,patch.object(driver,'OUT',Path(temp)):
            path=Path(temp)/'plan.json';path.write_bytes(driver.canonical({'local_operator_inputs':{}}))
            with self.assertRaisesRegex(ValueError,'complete_operator_input_set'):
                driver.checked_plan(path,driver.sha(path.read_bytes()))

    def test_windows_planner_emits_posix_stage_accepted_by_real_server_guard(self):
        observed={'status':'READ_ONLY_WS4_TICKET_INVENTORY','database':'goufayu_ws4','connection_port':15432,
            'definitions':BASE,'bundle_hash':'d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'}
        with tempfile.TemporaryDirectory()as temp,patch.object(driver,'OUT',Path(temp)):
            folder=Path(temp);inventory=folder/'inventory.json';registry=folder/'registry.json';output=folder/'plan.json'
            inventory.write_bytes(driver.canonical(observed));registry.write_bytes(driver.canonical(REGISTRY))
            fake_operator=SimpleNamespace(STAGE_ROOT=PureWindowsPath('/root/goufayu_upload/ticket_codes_20261102'),validate_registry=op.validate_registry)
            def module_for_plan(name,path):return definitions if Path(path).name=='definitions.py'else fake_operator
            with patch.object(driver,'module',side_effect=module_for_plan),patch.object(driver.secrets,'token_hex',return_value='123456abcdef'):
                result=driver.create_plan(inventory,driver.sha(inventory.read_bytes()),registry,driver.sha(registry.read_bytes()),output)
            plan=json.loads(output.read_bytes());stage=plan['stage']
            self.assertEqual(stage,'/root/goufayu_upload/ticket_codes_20261102/run_123456abcdef')
            self.assertNotIn('\\',stage)
            # Execute the actual server path guard with POSIX semantics and
            # nonexistent-filesystem metadata, without Linux/SSH or source edits.
            with patch.object(op,'Path',PurePosixPath),patch.object(op,'STAGE_ROOT',PurePosixPath('/root/goufayu_upload/ticket_codes_20261102')),\
                 patch.object(PurePosixPath,'is_symlink',return_value=False,create=True):
                self.assertEqual(str(op.stage_path(plan)),stage)
                broken={'stage':str(PureWindowsPath(stage))}
                with self.assertRaisesRegex(RuntimeError,'stage_scope_invalid'):op.stage_path(broken)


if __name__=='__main__':unittest.main()
