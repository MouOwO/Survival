"""Actual diagnostic helper and RPC dispatch tests; no network or SQL mocks as capacity proof."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import patch


class TraceAdmissionTests(unittest.TestCase):
    def helper(self):
        recipe=runpy.run_path(str(Path(__file__).parents[1]/'fishing_api_overrides/checkpoint_observation.py'))
        ns={'__name__':'fixed_trace_budget_test'}
        exec(compile(recipe['helper_source'](),'fixed_trace_budget_test','exec'),ns)
        ns['_clock']=lambda:10.0
        ns['_BUDGETS']={name:ns['Budget'](records=2,per_minute=2)for name in ns['_BUDGETS']}
        return ns

    def test_unsampled_actual_requests_keep_bytes_and_skip_business_stage_trace(self):
        ns=self.helper();seen=[];handler=types.SimpleNamespace(path='/v1/online-time/checkpoint')
        def request(handler):
            ns['identify']({'final':False})
            with ns['measure']('rpc'):seen.append(ns['_ACTIVE'].get()is not None)
            ns['sent'](200,6)
            return b'result'
        wrapped=ns['request_span'](request);output=io.StringIO()
        with contextlib.redirect_stdout(output):results=[wrapped(handler)for _ in range(7)]
        self.assertEqual(results,[b'result']*7)
        self.assertEqual(seen,[True,True,False,False,False,False,False])
        self.assertIsNone(ns['_ACTIVE'].get())
        records=[json.loads(line[len(ns['PREFIX']):])for line in output.getvalue().splitlines()]
        self.assertEqual(len(records),2)
        self.assertTrue(all(r['stages']['rpc'][0]==1 for r in records))
        self.assertEqual(ns['_BUDGETS']['other'].stats()['seen'],7)
        self.assertEqual(ns['_BUDGETS']['other'].stats()['inflight'],0)

    def test_final_diagnostics_remain_available_after_regular_budget_exhaustion(self):
        ns=self.helper();captured=[]
        def request(handler):
            ns['identify']({'final':handler.final})
            captured.append(ns['_ACTIVE'].get()is not None)
            ns['sent'](200,2)
        wrapped=ns['request_span'](request)
        with contextlib.redirect_stdout(io.StringIO()):
            for final in [False,False,False,True]:wrapped(types.SimpleNamespace(path='/v1/online-time/checkpoint',final=final))
        self.assertEqual(captured,[True,True,False,True])
        self.assertEqual(ns['_BUDGETS']['backend_final'].stats()['emitted'],1)

    def test_exception_preserved_and_reserved_budget_drained(self):
        ns=self.helper();error=RuntimeError('original_business_failure')
        def request(handler):
            ns['identify']({'final':True})
            raise error
        with contextlib.redirect_stdout(io.StringIO()),self.assertRaises(RuntimeError)as caught:
            ns['request_span'](request)(types.SimpleNamespace(path='/v1/online-time/checkpoint'))
        self.assertIs(caught.exception,error)
        self.assertEqual(ns['_BUDGETS']['backend_final'].stats()['inflight'],0)
        self.assertIsNone(ns['_ACTIVE'].get())

    def test_repeated_identification_and_finish_do_not_reserve_or_emit_twice(self):
        ns=self.helper();trace=ns['Trace']('/v1/online-time/checkpoint');token=ns['_ACTIVE'].set(trace)
        try:
            ns['identify']({'final':False});ns['identify']({'final':False})
            with contextlib.redirect_stdout(io.StringIO())as output:trace.finish();trace.finish()
            self.assertEqual(len(output.getvalue().splitlines()),1)
            self.assertEqual(ns['_BUDGETS']['other'].stats()['admitted'],1)
            self.assertEqual(ns['_BUDGETS']['other'].stats()['inflight'],0)
        finally:ns['_ACTIVE'].reset(token)

    def test_logging_failure_does_not_change_result_or_leak_reservation(self):
        ns=self.helper()
        class BadOutput:
            def write(self,text):raise OSError('log_unavailable')
        def request(handler):ns['identify']({'final':False});return b'exact'
        with contextlib.redirect_stdout(BadOutput()):result=ns['request_span'](request)(types.SimpleNamespace(path='/v1/online-time/checkpoint'))
        self.assertEqual(result,b'exact');self.assertEqual(ns['_BUDGETS']['other'].stats()['inflight'],0)

    def test_actual_RPC_job_keeps_original_call_and_omits_unsampled_timing_dictionary(self):
        from tools.loadtest_lab import rpc_process_pool as rpc
        ns=self.helper();observation=types.ModuleType('archive_backend._checkpoint_observation')
        observation.__dict__.update(ns)
        archive=types.ModuleType('archive_backend');archive._checkpoint_observation=observation
        bounded=types.ModuleType('fishing_api._bounded_pool');bounded.request_deadline=lambda _:contextlib.nullcontext()
        driver=types.ModuleType('fishing_api.postgres')
        class DatabaseError(Exception):pass
        driver.DatabaseError=DatabaseError
        fishing=types.ModuleType('fishing_api');fishing.__path__=[]
        calls=[]
        class Client:
            def rpc(self,name,payload):
                calls.append((name,payload))
                with ns['measure']('db_query'):return {'exact':[1,2,3]}
            def pool_stats(self):return {'busy':0}
        modules={'archive_backend':archive,'archive_backend._checkpoint_observation':observation,'fishing_api':fishing,'fishing_api._bounded_pool':bounded,'fishing_api.postgres':driver}
        results=[]
        with patch.dict(sys.modules,modules),patch.object(rpc,'_CLIENT',Client()),patch.object(rpc.time,'monotonic',return_value=10):
            for observed in (True,False):results.append(rpc._job('same_function',{'same':1},20,15,9,observed))
        self.assertEqual(calls,[('same_function',{'same':1})]*2)
        self.assertEqual(results[0]['result'],results[1]['result'])
        self.assertIn('db_query',results[0]['stages']);self.assertEqual(results[1]['stages'],{})
        self.assertEqual(results[0]['ok'],results[1]['ok'])


class MatureTraceProofTests(unittest.TestCase):
    def fixture(self):
        import hashlib
        p=Path(__file__).parents[1]/'fishing_api_overrides/checkpoint_observation.py'
        raw=p.read_bytes().replace(b'\r\n',b'\n');recipe=runpy.run_path(str(p))
        target='runtime/archive_backend/_checkpoint_observation.py';operator='operator/runtime_experiments/checkpoint_observation.py'
        output=recipe['helper_source']().encode('utf8');digest=lambda b:hashlib.sha256(b).hexdigest()
        cfg={'kind':'SURVIVAL_ISOLATED_LOADTEST','purpose':'capacity','csv_source_revision':'a'*40,'sources':{target:digest(output),operator:digest(raw)},'runtime_experiments':[{'id':'checkpoint-observation-v1','source_revision':'a'*40,'operator_sources':{operator:digest(raw)},'runtime_sha256':{target:digest(output)}}]}
        sources={operator:raw,target:output};parent={target:recipe['TRACE_HELPER_PARENT_SHA256']}
        return recipe,cfg,sources,parent

    def test_exact_helper_reverse_matches_original_and_rejects_unrelated_edit(self):
        import hashlib
        recipe,cfg,sources,parent=self.fixture();output=recipe['helper_source']();old=recipe['restore_helper_source'](output)
        self.assertEqual(hashlib.sha256(old.encode()).hexdigest(),recipe['TRACE_HELPER_PARENT_SHA256'])
        compile(old,'original_helper','exec')
        with self.assertRaises(ValueError):recipe['restore_helper_source'](output+'\n# unrelated change\n')

    def test_mature_proof_reads_two_fixed_sources_and_preserves_manifest(self):
        import copy
        from tools.loadtest_lab.mature_fixture import _trace_observation_parent
        recipe,cfg,sources,parent=self.fixture();before=copy.deepcopy(cfg);reads=[]
        def read(name):reads.append(name);return sources[name]
        self.assertEqual(_trace_observation_parent(cfg,read,parent),parent)
        self.assertEqual(cfg,before);self.assertEqual(len(reads),2)

    def test_mature_proof_rejects_changed_recipe_output_or_binding(self):
        import copy
        from tools.loadtest_lab.mature_fixture import _trace_observation_parent
        recipe,cfg,sources,parent=self.fixture()
        for path in sources:
            bad=dict(sources);bad[path]+=b'\n'
            with self.assertRaises(ValueError):_trace_observation_parent(cfg,bad.__getitem__,parent)
        for mutate in ('revision','operator','runtime','purpose'):
            bad=copy.deepcopy(cfg)
            if mutate=='revision':bad['runtime_experiments'][0]['source_revision']='b'*40
            elif mutate=='operator':bad['runtime_experiments'][0]['operator_sources']={}
            elif mutate=='runtime':bad['sources']['runtime/archive_backend/_checkpoint_observation.py']='b'*64
            else:bad['purpose']='production'
            with self.assertRaises(ValueError):_trace_observation_parent(bad,sources.__getitem__,parent)
        oldcfg=copy.deepcopy(cfg);oldcfg['sources']['runtime/archive_backend/_checkpoint_observation.py']=next(iter(parent.values()))
        self.assertEqual(_trace_observation_parent(oldcfg,lambda _:self.fail('legacy proof must not read new source'),parent),{})


if __name__=='__main__':unittest.main()
