"""Audited production handler/RPC parity with isolated fake IO; never a live request."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
from copy import deepcopy
from email.message import Message
import importlib.util
import io
import json
from pathlib import Path
import sys
import threading
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
SOURCES=ROOT/'tools/public_beta_wire_release_20261106/parent_sources'
transform_path=ROOT/'tools/public_beta_wire_release_20261106/http_timing_patch.py'
transform_spec=importlib.util.spec_from_file_location('exact_http_timing_transforms',transform_path)
transforms=importlib.util.module_from_spec(transform_spec)
exec(compile(transform_path.read_bytes(),str(transform_path),'exec'),transforms.__dict__)


def load(name,raw):
    value=ModuleType(name);value.__package__=name.rpartition('.')[0]
    sys.modules[name]=value
    exec(compile(raw,name,'exec'),value.__dict__)
    return value


class ApiError(ValueError):
    def __init__(self,code,status):self.code,self.status=code,status


class SQL:
    def __init__(self,value):self.value=str(value)
    def format(self,*args):return SQL(self.value.format(*(arg.value for arg in args)))
    def join(self,args):return SQL(self.value.join(arg.value for arg in args))


def client(module,events,failure=None):
    class Cursor:
        def __enter__(self):return self
        def __exit__(self,*args):pass
        def execute(self,query,parameters):
            self.kind='role'if query==module._RUNTIME_CHECK else 'functions'if query==module._FUNCTION_CHECK else 'query'
            events.append(self.kind)
            if failure==self.kind:raise RuntimeError('PRIVATE_DRIVER_DETAIL')
        def fetchone(self):
            if self.kind=='role':return ('goufayu_app','goufayu_app','goufayu_test',failure=='permission',False,False,False,False,False,False)
            return ({'ok':True},)
        def fetchall(self):return [(signature,True)for signature in module.ALLOWED_FUNCTIONS]
    class Connection:
        def cursor(self):return Cursor()
        def commit(self):
            events.append('commit')
            if failure=='commit':raise RuntimeError('PRIVATE_COMMIT_DETAIL')
        def rollback(self):events.append('rollback')
        def close(self):events.append('close')
    def connect(*args,**kwargs):
        events.append('connect')
        if failure=='connect':raise RuntimeError('PRIVATE_CONNECTION_DETAIL')
        return Connection()
    value=module.PostgresRpcClient.__new__(module.PostgresRpcClient)
    value._dsn='PRIVATE_DSN_NEVER_LOG';value._connect_options={};value._connect=connect
    value._slots=threading.BoundedSemaphore(4)
    value._sql=SimpleNamespace(SQL=SQL,Identifier=SQL)
    value._Jsonb=lambda data,**kwargs:data
    return value


class HttpTimingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prefixes=('archive_backend','fishing_api')
        saved={key:value for key,value in sys.modules.items() if key.split('.')[0] in prefixes}
        def restore_modules():
            for key in list(sys.modules):
                if key.split('.')[0] in prefixes:
                    sys.modules.pop(key,None)
            sys.modules.update(saved)
        cls.addClassCleanup(restore_modules)
        sys.modules['archive_backend']=ModuleType('archive_backend')
        cls.timing=load('archive_backend.http_request_timing',(ROOT/'server/archive_backend/http_request_timing.py').read_bytes())
        package=ModuleType('fishing_api');package.__path__=[];sys.modules['fishing_api']=package
        for name,attributes in {
            'application':{'ApiError':ApiError,'FishingApplication':type('FishingApplication',(),{})},
            'config':{'ConfigError':ValueError,'Settings':object},
            'definitions':{'DefinitionError':ValueError,'load_definitions':None,'load_rule':None},
            'gameplay_stats':{'GameplayStatsError':ValueError,'load_gameplay_stats':None},
        }.items():
            value=ModuleType('fishing_api.'+name);value.__dict__.update(attributes);sys.modules[value.__name__]=value
        cls.supabase=load('fishing_api.supabase',(SOURCES/'supabase.py').read_bytes())
        service=ModuleType('archive_backend.service');service.ArchiveError=type('ArchiveError',(ValueError,),{})
        sys.modules[service.__name__]=service;cls.ArchiveError=service.ArchiveError
        profile=ModuleType('fishing_api.match_profiles')
        def context(app,payload):
            app.rpc_client.rpc('match_profile_context',{'p_account':'a'*64,'p_session':'fixture-session'})
            return {'mode':'standard'}
        profile.context=context
        profile.project=lambda app,payload,response,context:deepcopy(response)
        sys.modules[profile.__name__]=profile;package.match_profiles=profile
        cls.server_old=load('fishing_api.server_old',(SOURCES/'server.py').read_bytes())
        cls.server_new=load('fishing_api.server_new',transforms.server((SOURCES/'server.py').read_bytes()))
        cls.pg_old=load('fishing_api.pg_old',(SOURCES/'postgres.py').read_bytes())
        cls.pg_new=load('fishing_api.pg_new',transforms.postgres((SOURCES/'postgres.py').read_bytes()))

    def setUp(self):
        self.records=[]
        self.emit_patch=patch.object(self.timing,'_emit',side_effect=self.records.append)
        self.emit_patch.start();self.addCleanup(self.emit_patch.stop)

    def invoke(self,server,pg,kind='lottery_draw',failure=None,authorized=True):
        events=[];rpc=client(pg,events,failure if failure!='command'else None)
        def command(payload):
            if failure=='command':raise self.ArchiveError('fixture_rejection')
            rpc.rpc('ensure_player_gameplay_stats',{'p_account_id':'a'*64,'p_gameplay_stats':{}})
            rpc.rpc('archive_prepare',{'p_account':'a'*64,'p_id':'fixture-operation','p_hash':'b'*64,
                'p_fingerprint':'c'*64,'p_command':payload['command']})
            rpc.rpc('archive_commit_lottery',{'p_account':'a'*64,'p_id':'fixture-operation','p_revision':0,
                'p_archive':{},'p_deltas':{},'p_error':None,'p_inventory':{},'p_response':{}})
            return {'ok':True,'profile':{'account_id':'PRIVATE_ACCOUNT_NEVER_LOG'},'response':{'ok':True}}
        app=SimpleNamespace(rpc_client=rpc,authorized=lambda header:authorized,archive=SimpleNamespace(command=command))
        handler_type=server.make_handler(app);handler=handler_type.__new__(handler_type)
        payload={'account_id':'PRIVATE_ACCOUNT_NEVER_LOG','command':{'kind':kind,'count':10,'id':'PRIVATE_COMMAND_NEVER_LOG'}}
        body=json.dumps(payload).encode();handler.path='/v1/archive/command'
        handler.headers=Message();handler.headers['Content-Length']=str(len(body));handler.headers['Authorization']='PRIVATE_TOKEN_NEVER_LOG'
        handler.rfile=io.BytesIO(body);handler.wfile=io.BytesIO()
        statuses=[];handler.send_response=statuses.append
        handler.send_header=lambda *args:None;handler.end_headers=lambda:None
        handler.do_POST()
        return statuses,handler.wfile.getvalue(),events

    def test_actual_handler_and_rpc_success_parity_and_all_stage_counts(self):
        original=self.invoke(self.server_old,self.pg_old)
        current=self.invoke(self.server_new,self.pg_new)
        self.assertEqual(original,current)
        self.assertEqual(len(self.records),1)
        row=self.records[0]
        self.assertEqual(row['status'],200);self.assertEqual(row['body_bytes'],len(current[1]))
        self.assertEqual(row['rpcs'],{'match_profile_context':1,'ensure_player_gameplay_stats':1,
                                    'archive_prepare':1,'archive_commit_lottery':1})
        for stage in ('authorize','body','context','command','project','serialize','write'):
            self.assertEqual(row['stages'][stage][0],1)
        for stage in ('rpc','db_connect','db_guard','db_role_guard','db_function_guard','db_query','db_commit','db_close'):
            self.assertEqual(row['stages'][stage][0],4)
        self.assertNotIn('db_rollback',row['stages'])
        self.assertNotIn('PRIVATE',json.dumps(row))

    def test_failure_permission_rollback_and_commit_behaviour_identical(self):
        for failure in ('connect','permission','query','commit','command'):
            self.records.clear()
            with self.subTest(failure=failure):
                original=self.invoke(self.server_old,self.pg_old,failure=failure)
                current=self.invoke(self.server_new,self.pg_new,failure=failure)
                self.assertEqual(original,current)
                self.assertEqual(len(self.records),1)
                row=self.records[0]
                self.assertEqual(row['outcome'],'http_error')
                self.assertNotIn('PRIVATE',json.dumps(row))
                if failure=='permission':self.assertNotIn('query',current[2])

    def test_other_commands_and_denied_auth_are_quiet_and_unchanged(self):
        for values in ({'kind':'boss_kill'},{'authorized':False}):
            original=self.invoke(self.server_old,self.pg_old,**values)
            current=self.invoke(self.server_new,self.pg_new,**values)
            self.assertEqual(original,current)
        self.assertEqual(self.records,[])

    def test_threads_have_independent_records(self):
        barrier=threading.Barrier(2)
        @self.timing.request_span
        def run(handler):
            self.timing.identify({'command':{'kind':'lottery_draw','count':handler.count}})
            barrier.wait(timeout=2)
            with self.timing.rpc_span('PRIVATE_RPC_NAME'):pass
            self.timing.sent(200,handler.count)
        with ThreadPoolExecutor(2)as executor:
            list(executor.map(run,[SimpleNamespace(path='/v1/archive/command',count=n)for n in(1,10)]))
        self.assertEqual(sorted((r['count'],r['body_bytes'])for r in self.records),[(1,1),(10,10)])
        self.assertTrue(all(r['rpcs']=={'other':1}for r in self.records))
        self.assertNotIn('PRIVATE',json.dumps(self.records))

    def test_sink_failure_preserves_success_and_original_exception(self):
        self.emit_patch.stop()
        with patch.object(self.timing,'sys',SimpleNamespace(stdout=SimpleNamespace(write=lambda text:(_ for _ in()).throw(OSError()),flush=lambda:None))):
            self.assertEqual(self.invoke(self.server_new,self.pg_new)[0],[200])
        @self.timing.request_span
        def raises(handler):
            self.timing.identify({'command':{'kind':'benefit_claim'}})
            raise ValueError('private-original-exception')
        with patch.object(self.timing,'_emit',side_effect=OSError()):
            with self.assertRaisesRegex(ValueError,'private-original-exception'):
                raises(SimpleNamespace(path='/v1/archive/command'))
        self.assertIsNone(self.timing._ACTIVE.get())

    def test_record_budget_and_byte_limit(self):
        now=[0];budget=self.timing.Budget(clock=lambda:now[0],records=3,per_minute=2,lifetime=120)
        self.assertTrue(budget.take());self.assertTrue(budget.take());self.assertFalse(budget.take())
        now[0]=60;self.assertTrue(budget.take());self.assertFalse(budget.take())
        now[0]=120;self.assertFalse(budget.take())
        self.emit_patch.stop();stream=io.StringIO()
        with patch.object(self.timing,'_BUDGET',self.timing.Budget()),redirect_stdout(stream):
            self.invoke(self.server_new,self.pg_new)
        line=stream.getvalue();self.assertTrue(line.startswith(self.timing.PREFIX))
        self.assertLessEqual(len(line.encode()),self.timing.MAX_RECORD_BYTES)
        self.assertEqual(line.count('\n'),1)

    def test_pinned_transform_rejects_parent_drift(self):
        for name,method in(('server.py',transforms.server),('postgres.py',transforms.postgres)):
            with self.assertRaisesRegex(ValueError,'audited_source_changed'):
                method((SOURCES/name).read_bytes()+b'\n')


if __name__=='__main__':unittest.main()
