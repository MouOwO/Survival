"""Test actual adapter policy without making HTTP;Linux component tests real IO."""
import ast,json,math,socket,types,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
source=(ROOT/'tools/loadtest_native/fast_transport.py').read_text(encoding='utf8');node=next(x for x in ast.parse(source).body if isinstance(x,ast.FunctionDef)and x.name=='install_budget')
class Timer:
    def __init__(self,*args):self.args=args
    def __enter__(self):return self
    def __exit__(self,*args):return False
scope={'json':json,'math':math,'socket':socket,'gevent':types.SimpleNamespace(Timeout=Timer)};exec(compile(ast.Module(body=[node],type_ignores=[]),'actual_fast_budget','exec'),scope)
class FastBudget(unittest.TestCase):
    def session(self,fn=None):
        self.calls=[]
        def send(*args,**kwargs):self.calls.append((args,kwargs));return 'one_reply'
        session=types.SimpleNamespace(request=fn or send);scope['install_budget'](session);return session
    def test_timeout_is_local_not_query_or_body_and_retries_zero(self):
        s=self.session();self.assertEqual(s.request('POST','/x',timeout=.5,json={'x':False}),'one_reply');args,k=self.calls[0];self.assertNotIn('timeout',k);self.assertEqual(k['max_retries'],0);self.assertFalse(k['allow_redirects']);self.assertEqual(json.loads(k['data']),{'x':False})
    def test_header_input_is_not_mutated(self):
        h={'Authorization':'synthetic'};s=self.session();s.request('POST','/x',json={'x':1},headers=h);self.assertEqual(h,{'Authorization':'synthetic'});self.assertEqual(self.calls[0][1]['headers']['Content-Type'],'application/json')
    def test_ambiguous_failure_is_not_replayed(self):
        seen=[]
        def fail(*a,**k):seen.append(1);raise OSError('synthetic_unknown_commit')
        s=self.session(fail)
        with self.assertRaises(OSError):s.request('POST','/x',json={'id':'same'})
        self.assertEqual(seen,[1])
    def test_nonfinite_JSON_is_rejected_before_send(self):
        s=self.session()
        with self.assertRaises(ValueError):s.request('POST','/x',json={'x':float('nan')})
        self.assertEqual(self.calls,[])
    def test_bad_deadlines_and_retry_overrides_are_rejected(self):
        s=self.session()
        for k in [{'timeout':True},{'timeout':0},{'timeout':36},{'timeout':float('inf')},{'max_retries':1}]:
            with self.subTest(k=k),self.assertRaises(ValueError):s.request('POST','/x',**k)
        self.assertEqual(self.calls,[])
if __name__=='__main__':unittest.main()
