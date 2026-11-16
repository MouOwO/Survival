"""Fixed-route byte statistics and per-actor conditional read contract."""
from pathlib import Path
import unittest,json,copy,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server')]
from server.tests import test_profile_cache as t
from tools.loadtest_lab.wire_client import WireClient,aggregate_reports,WIRE_MODE,profile_cache_header
from tools.loadtest_lab.guard import profile_read_cache_mode
class RouteStatsTests(unittest.TestCase):
 def exchange(self,c,path,raw=b'{"ok":true}',status=200,method='POST'):
  c.headers(method,path,'synthetic-auth-never-log')
  try:c.decode(method,path,raw,status)
  except ValueError:pass
 def client(self):return WireClient(measure_routes=True)
 def test_legacy_default_report_shape_unchanged(self):
  self.assertNotIn('route_bytes_v1',WireClient().report());r=aggregate_reports([WireClient().report()],WIRE_MODE);self.assertNotIn('route_bytes_v1',r)
 def test_success_errors_and_bad_empty_responses_reconcile(self):
  c=self.client();self.exchange(c,'/v1/profile');self.exchange(c,'/v1/profile',b'{"ok":false,"error":"frontend_busy"}',503);self.exchange(c,'/v1/profile',b'',0);self.exchange(c,'/v1/profile',b'bad',200)
  r=aggregate_reports([c.report()],WIRE_MODE);row=r['route_bytes_v1']['rows'][0]
  self.assertEqual((row['requests'],row['responses'],row['non_200_responses'],row['parsed_http_errors'],row['decode_failures']),(4,4,2,1,2))
 def test_unknown_paths_and_authorization_never_export(self):
  c=self.client();self.exchange(c,'/unknown/account-123456789?token=secret');text=json.dumps(c.report());self.assertNotIn('123456789',text);self.assertNotIn('token=secret',text);self.assertNotIn('synthetic-auth-never-log',text);self.assertEqual(c.report()['route_bytes_v1']['rows'][0]['id'],0)
 def test_bucket_boundaries_and_totals(self):
  c=self.client()
  for size in [128,129,512,513,1024,1025,4096,4097,16384,16385,65536,65537]:
   self.exchange(c,'/v1/profile',b'{"x":"'+b'a'*(size-8)+b'"}')
  report=aggregate_reports([c.report()],WIRE_MODE)['route_bytes_v1'];row=report['rows'][0];self.assertEqual(sum(row['body_histogram']),12);self.assertEqual(row['max_body_bytes'],65537)
 def test_cancelled_exchange_keeps_route_and_original_counters(self):
  c=self.client();c.headers('POST','/v1/archive/command','synthetic');E=type('GreenletExit',(BaseException,),{});c.note_incomplete(E(),'POST','/v1/archive/command');r=aggregate_reports([c.report()],WIRE_MODE);self.assertEqual(r['incomplete_exchanges']['greenlet_exit'],1);self.assertEqual(r['route_bytes_v1']['rows'][0]['incomplete_exchanges'],1)
 def test_multi_worker_sum_and_max_not_average(self):
  a=self.client();b=self.client();self.exchange(a,'/v1/profile');self.exchange(b,'/v1/profile',b'{"ok":true,"data":123}');r=aggregate_reports([a.report(),b.report()],WIRE_MODE);row=r['route_bytes_v1']['rows'][0];self.assertEqual(row['responses'],2);self.assertEqual(row['body_bytes'],r['counters']['response_body_bytes']);self.assertEqual(row['max_body_bytes'],22)
 def test_snapshot_is_detached(self):
  c=self.client();self.exchange(c,'/v1/profile');r=c.report();r['route_bytes_v1']['rows'][0]['body_histogram'][0]=99;self.assertEqual(c.report()['route_bytes_v1']['rows'][0]['body_histogram'][0],1)
 def test_corrupted_routes_histograms_and_mode_mix_rejected(self):
  c=self.client();self.exchange(c,'/v1/profile');base=c.report()
  for mutate in [lambda r:r['route_bytes_v1']['rows'].append(copy.deepcopy(r['route_bytes_v1']['rows'][0])),lambda r:r['route_bytes_v1']['rows'][0].update(id=1000),lambda r:r['route_bytes_v1']['rows'][0]['body_histogram'].__setitem__(0,True),lambda r:r['counters'].__setitem__('response_body_bytes',1)]:
   r=copy.deepcopy(base);mutate(r)
   with self.assertRaises(ValueError):aggregate_reports([r],WIRE_MODE)
  with self.assertRaises(ValueError):aggregate_reports([base,WireClient().report()],WIRE_MODE)
 def test_inflight_requests_visible_without_faking_completion(self):
  c=self.client();c.headers('POST','/v1/profile','synthetic');r=aggregate_reports([c.report()],WIRE_MODE);row=r['route_bytes_v1']['rows'][0];self.assertEqual((row['requests'],row['responses']),(1,0))

class NativeClientCacheTests(unittest.TestCase):
 def exchange(self,c,body,ctx):
  c.headers('POST','/v1/profile','synthetic')
  return c.decode('POST','/v1/profile',body,request_body={},profile_context=ctx)
 def test_actual_full_hit_legacy_and_route_byte_reconciliation(self):
  c=WireClient(measure_routes=True);value=t.snapshot();ctx={'baseline':None};first=self.exchange(c,t.cache.pack_bytes(t.raw(value),'v1'),ctx);self.assertEqual(first,value);state=ctx['next_state'];first['save']['gameplay_stats']['attack']=99
  ctx={'baseline':state};same=self.exchange(c,t.cache.pack_bytes(t.raw(value),profile_cache_header(state)),ctx);self.assertEqual(same,value);self.assertEqual(ctx['kind'],'unchanged');same['save']['gameplay_stats']['attack']=99;self.assertEqual(state['snapshot']['save']['gameplay_stats']['attack'],0)
  ctx={'baseline':state};self.assertEqual(self.exchange(c,t.raw(value),ctx),value);self.assertEqual(ctx['kind'],'legacy');self.assertIsNone(ctx['next_state']);aggregate_reports([c.report()],WIRE_MODE)
 def test_profile_cache_failures_count_as_decoder_failures(self):
  c=WireClient(measure_routes=True)
  with self.assertRaisesRegex(ValueError,'profile_cache_miss'):self.exchange(c,t.raw(t.same(t.snapshot())),{'baseline':None})
  r=aggregate_reports([c.report()],WIRE_MODE);self.assertEqual(r['counters']['invalid_responses'],1);self.assertEqual(r['route_bytes_v1']['rows'][0]['decode_failures'],1)
 def test_extra_marker_fields_and_bools_are_rejected(self):
  for marker in [[True,'a'*64,1],[1,'a'*64,True],[1,'a'*64,2],[1,'a'*64]]:
   c=WireClient()
   with self.assertRaises(ValueError):self.exchange(c,t.raw({'_hp':marker}),{'baseline':None})
 def test_oversized_cache_keeps_valid_full_response(self):
  v=t.snapshot();v['padding']='x'*200000;c=WireClient();ctx={'baseline':None};actual=self.exchange(c,t.cache.pack_bytes(t.raw(v),'v1'),ctx);self.assertEqual(actual,v);self.assertIsNone(ctx['next_state'])
 def test_new_mode_default_and_invalid_values(self):
  self.assertEqual(profile_read_cache_mode({}),'baseline');self.assertEqual(profile_read_cache_mode({'profile_read_cache':'unchanged-v1'}),'unchanged-v1')
  for value in [True,1,None,[],{},'v1','']:
   with self.assertRaisesRegex(ValueError,'lab_profile_read_cache_invalid'):profile_read_cache_mode({'profile_read_cache':value})

 def test_complete_checkpoint_seed_then_hit_keeps_grants_and_fixed_counters(self):
  c=WireClient(measure_routes=True);ctx={'baseline':None};body=t.raw(t.seed(t.snapshot()));c.headers('POST','/v1/online-time/checkpoint','synthetic')
  result=c.decode('POST','/v1/online-time/checkpoint',body,profile_context=ctx);self.assertEqual(result,t.checkpoint(t.snapshot()));self.assertEqual(ctx['kind'],'seed');state=ctx['next_state'];result['profile']['save']['gameplay_stats']['attack']=99
  self.assertEqual(state['snapshot']['save']['gameplay_stats']['attack'],0);self.assertEqual(self.exchange(c,t.raw(t.same(t.snapshot())),{'baseline':state}),t.snapshot())
  report=aggregate_reports([c.report(),WireClient(measure_routes=True).report()],WIRE_MODE);self.assertEqual(report['profile_cache_v1']['responses'],2);self.assertEqual(report['profile_cache_v1']['seed'],1);self.assertEqual(report['profile_cache_v1']['unchanged'],1)
 def test_bad_optional_checkpoint_seed_keeps_full_business_result(self):
  for marker in [[True,'a'*64,2],[1,'bad',2],[1,'a'*64,1],[1,'a'*64,2,4]]:
   c=WireClient();v=t.checkpoint(t.snapshot());v['_hp']=marker;ctx={'baseline':None};c.headers('POST','/v1/online-time/checkpoint','synthetic');actual=c.decode('POST','/v1/online-time/checkpoint',t.raw(v),profile_context=ctx);self.assertEqual(actual,t.checkpoint(t.snapshot()));self.assertIsNone(ctx['next_state']);self.assertEqual(ctx['kind'],'seed_ignored');aggregate_reports([c.report()],WIRE_MODE)
 def test_cache_counter_corruption_rejected(self):
  c=WireClient();self.exchange(c,t.raw(t.full(t.snapshot())),{'baseline':None});base=c.report()
  for mutate in [lambda r:r['profile_cache_v1'].update(full=True),lambda r:r['profile_cache_v1'].update(full=0),lambda r:r['profile_cache_v1'].update(extra=1),lambda r:r['profile_cache_v1'].update(errors=-1)]:
   r=copy.deepcopy(base);mutate(r)
   with self.assertRaisesRegex(ValueError,'profile_cache_statistics'):aggregate_reports([r],WIRE_MODE)

if __name__=='__main__':unittest.main(verbosity=2)
