"""Read-profile transport regressions: local auth/HTTP and real gameLua only."""
from pathlib import Path
import unittest,json,copy,hashlib,subprocess,os,shutil,tempfile,threading,http.client,sys
from dataclasses import replace
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server')]
from player_web_auth import profile_cache as cache
from player_web_auth import business_wire as codec
from player_web_auth.http_api import BoundedServer,handler
from player_web_auth import test_service as auth_tests
if os.environ.get('SURVIVAL_TEST_TMP_ROOT'):
    Path(os.environ['SURVIVAL_TEST_TMP_ROOT']).mkdir(parents=True,exist_ok=True)
    tempfile.tempdir=os.environ['SURVIVAL_TEST_TMP_ROOT']

def snapshot(account='123456789',mode='standard',revision=10):
 return dict(schema_version=1,account_id=account,match_session_id='test-match-session-123',mode=mode,revision=revision,entitlements={'vip':{'active':False}},achievements={},save={'gameplay_stats':{'attack':0,'crit':False},'content_inventory':{'ticket':1},'archive':{'rows':[{'id':'synthetic_item_'+str(i),'count':i}for i in range(30)]}},daily_limits={'day_key':'2026-11-16','rows':[]},public={'name':'合成档案🦊'})
def raw(v):return json.dumps(v,ensure_ascii=False,separators=(',',':')).encode()
def full(v):return json.loads(cache.pack_bytes(raw(v),'v1'))
def digest(v):return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,allow_nan=False,separators=(',',':')).encode()).hexdigest()
def same(v):return json.loads(cache.pack_bytes(raw(v),'v1:'+digest(v)))
def checkpoint(v):return {'ok':True,'request_id':'synthetic-checkpoint-123','grants':[{'id':'synthetic-grant-1','amount':1}],'profile':v}
def seed(v):return json.loads(cache.prepare_checkpoint_seed(raw(checkpoint(v)),'v1')[0])

class ConditionalTests(unittest.TestCase):
 def test_full_then_same_and_schema_unchanged(self):
  v=snapshot();body=raw(v);frame=cache.pack_bytes(body,'v1');value=json.loads(frame);marker=value.pop('_hp');self.assertEqual(value,v);self.assertEqual(marker,[1,digest(v),0]);ack=cache.pack_bytes(body,'v1:'+marker[1]);self.assertEqual(json.loads(ack),{'_hp':[1,marker[1],1]});self.assertLess(len(ack),100)
 def test_existing_negotiated_wire_roundtrip_including_same(self):
  for body in [cache.pack_bytes(raw(snapshot()),'v1'),cache.pack_bytes(raw(snapshot()),'v1:'+digest(snapshot()))]:
   packed=codec.pack_bytes(body,codec.SCHEMA_HASH);v=json.loads(packed);decoded=codec.decode(v)if '_bw'in v else v;self.assertEqual(decoded,json.loads(body))
 def test_legacy_and_bad_headers_preserve_exact_original(self):
  body=raw(snapshot())
  for header in [None,True,1,'','v2','V1','v1:','v1:'+('a'*63),'v1:'+('A'*64),'v1:'+('g'*64),'v1:'+('a'*64)+'x','v1, v1']:
   self.assertIs(cache.pack_bytes(body,header),body)
 def test_same_revision_identity_mode_daily_entitlement_and_zero_changes_force_full(self):
  before=snapshot();header='v1:'+digest(before)
  changes=[lambda v:v.update(account_id='other'),lambda v:v.update(match_session_id='other-session'),lambda v:v.update(mode='pure'),lambda v:v.update(game_mode='rich'),lambda v:v['daily_limits'].update(day_key='next-day'),lambda v:v['entitlements']['vip'].update(active=True),lambda v:v['save']['gameplay_stats'].update(attack=False),lambda v:v['save']['gameplay_stats'].update(attack=None),lambda v:v['save']['gameplay_stats'].pop('attack')]
  for change in changes:
   v=copy.deepcopy(before);change(v);frame=json.loads(cache.pack_bytes(raw(v),header));self.assertEqual(frame['_hp'][2],0);frame.pop('_hp');self.assertEqual(frame,v)
 def test_failure_and_reserved_marker_never_suppressed(self):
  for v in [{'ok':False,'error':'denied','padding':'x'*400},{**snapshot(),'ok':False},{**snapshot(),'_hp':[1,'a'*64,0]}]:
   body=raw(v);self.assertIs(cache.pack_bytes(body,'v1:'+hashlib.sha256(body).hexdigest()),body)
 def test_malformed_duplicate_nonfinite_or_small_are_unchanged(self):
  for body in [b'bad',b'{}',b'[]',b'{"a":1,"a":2}',raw({'v':float('nan'),'padding':'a'*300}),b' '*300]:self.assertIs(cache.pack_bytes(body,'v1'),body)
 def test_size_reserve_prevents_consumer_budget_regression(self):
  body=b' '*cache.MAX_BYTES;self.assertIs(cache.pack_bytes(body,'v1'),body)
 def test_canonical_digest_ignores_member_order_but_keeps_all_types(self):
  v=snapshot();reordered=dict(reversed(list(v.items())));reordered['save']=dict(reversed(list(v['save'].items())))
  self.assertNotEqual(raw(v),raw(reordered));self.assertEqual(same(reordered),same(v));self.assertEqual(same(v),{'_hp':[1,digest(v),1]})
 def test_checkpoint_seed_preserves_every_write_result_and_seeds_read(self):
  v=snapshot();original=raw(checkpoint(v));body,parsed=cache.prepare_checkpoint_seed(original,'v1');self.assertEqual(parsed,json.loads(body));self.assertEqual(parsed.pop('_hp'),[1,digest(v),2]);self.assertEqual(parsed,checkpoint(v));self.assertTrue(body.startswith(original[:-1]));self.assertEqual(json.loads(cache.pack_bytes(raw(v),'v1:'+digest(v))),same(v))
 def test_checkpoint_invalid_optional_metadata_falls_back_to_original(self):
  cases=[snapshot(),{**checkpoint(snapshot()),'ok':False},{**checkpoint(snapshot()),'grants':{}},{**checkpoint(snapshot()),'_hp':[]},{**checkpoint(snapshot()),'profile':{}}]
  for v in cases:
   body=raw(v);result,prepared=cache.prepare_checkpoint_seed(body,'v1');self.assertIs(result,body);self.assertIsNone(prepared)
  for body in [b'bad',b'{"ok":true,"ok":true}',b'[]']:
   self.assertIs(cache.prepare_checkpoint_seed(body,'v1')[0],body)
 def test_prepared_codec_has_exact_legacy_bytes_without_scalar_reference_change(self):
  for v in [snapshot(),checkpoint(snapshot()),full(snapshot()),same(snapshot()),seed(snapshot())]:
   body=raw(v);self.assertEqual(codec.pack_bytes(body,codec.SCHEMA_HASH),codec._pack_decoded_bytes(body,json.loads(body),codec.SCHEMA_HASH))
 def test_actual_Lua_cache_and_provider_scenarios(self):
  a=snapshot();b=snapshot(revision=11);other=snapshot('987654321');pure=snapshot(mode='pure')
  data={'a':a,'full_a':full(a),'same_a':same(a),'b':b,'full_b':full(b),'same_b':same(b),'other':other,'full_other':full(other),'pure':pure,'full_pure':full(pure),'same_unknown':{'_hp':[1,'b'*64,1]}}
  data['checkpoint_a']=checkpoint(a);data['seed_a']=seed(a);data['checkpoint_b']=checkpoint(b);data['seed_b']=seed(b)
  data['wire_seed_b']=json.loads(codec.pack_bytes(raw(data['seed_b']),codec.SCHEMA_HASH))
  data['wire_full_a']=json.loads(codec.pack_bytes(raw(data['full_a']),codec.SCHEMA_HASH))
  data['wire_same_a']=json.loads(codec.pack_bytes(raw(data['same_a']),codec.SCHEMA_HASH))
  p=subprocess.run([os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1') or shutil.which('lua5.3') or 'C:/Program Files/lua/bin/lua5.1.exe',str(ROOT/'tools/test_profile_cache_provider.lua')],cwd=ROOT,input=raw(data),capture_output=True,timeout=45)
  self.assertEqual(p.returncode,0,p.stderr.decode('utf8',errors='replace'));self.assertIn('CONDITIONAL_PROVIDER_SCENARIOS_PASS',p.stdout.decode())

class RealAuthHttpTests(unittest.TestCase):
 def setUp(self):
  self.fx=auth_tests.ServiceTest('test_start_contains_only_public_verification_code_in_url');self.fx.setUp();self.fx.service.close();self.fx.service=self.fx.build(replace(self.fx.settings,isolated_local_progress=True));_,self.approved,_=self.fx.approved();self.calls=[];self.response=snapshot(self.fx.account);self.response['match_session_id']=self.fx.identity['match_session_id']
  def forward(path,body):self.calls.append((path,json.loads(body)));return 200,raw(self.response)
  self.fx.service.forward=forward;self.server=BoundedServer(('127.0.0.1',0),handler(self.fx.service));self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
 def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join(3);self.fx.tearDown()
 def request(self,advertised=None,token=None,path='/v1/profile',extra=None,wire=False):
  body=raw(self.fx.identity);c=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=5);c.putrequest('POST',path);c.putheader('Content-Type','application/json');c.putheader('Content-Length',str(len(body)));c.putheader('Authorization','Bearer '+(self.approved['access_token']if token is None else token))
  if advertised is not None:c.putheader(cache.HEADER,advertised)
  if extra is not None:c.putheader(cache.HEADER,extra)
  if wire:c.putheader(codec.HEADER,codec.SCHEMA_HASH)
  c.endheaders(body);r=c.getresponse();status=r.status;content=r.read();c.close();parsed=json.loads(content);return status,codec.decode(parsed)if codec.MARKER in parsed else parsed
 def test_every_same_reply_still_runs_real_auth_and_backend_forward(self):
  status,a=self.request('v1');self.assertEqual(status,200);h=a['_hp'][1];status,b=self.request('v1:'+h);self.assertEqual((status,b),(200,{'_hp':[1,h,1]}));self.assertEqual(len(self.calls),2)
  status,error=self.request('v1:'+h,token='invalid');self.assertEqual(status,403);self.assertNotIn('_hp',error);self.assertEqual(len(self.calls),2)
 def test_duplicate_negotiation_and_other_endpoints_keep_full(self):
  self.assertNotIn('_hp',self.request('v1',extra='v1')[1]);self.assertNotIn('_hp',self.request('v1',path='/v1/archive/config')[1])
 def test_single_parse_prepared_HTTP_path_uses_original_wire_contract(self):
  status,a=self.request('v1',wire=True);self.assertEqual(status,200);h=a['_hp'][1]
  status,b=self.request('v1:'+h,wire=True);self.assertEqual((status,b),(200,{'_hp':[1,h,1]}));self.assertEqual(len(self.calls),2)
 def test_request_payload_and_authorization_fingerprint_not_modified(self):
  self.request('v1');self.request('v1');self.assertEqual(self.calls[0],self.calls[1]);self.assertNotIn(cache.HEADER,json.dumps(self.calls))

 def test_default_auth_still_forbids_checkpoint_even_with_transport_header(self):
  current=self.fx.service.settings;self.fx.service.settings=replace(current,isolated_local_progress=False)
  try:
   status,value=self.request('v1',path='/v1/online-time/checkpoint');self.assertEqual((status,value['error']),(403,'player_route_not_allowed'));self.assertEqual(self.calls,[])
  finally:self.fx.service.settings=current
 def test_real_checkpoint_seed_is_complete_and_next_read_is_unchanged(self):
  snapshot=self.response;self.response=checkpoint(snapshot)
  status,result=self.request('v1',path='/v1/online-time/checkpoint',wire=True);self.assertEqual(status,200);marker=result.pop('_hp');self.assertEqual(result,checkpoint(snapshot));self.assertEqual(marker,[1,digest(snapshot),2])
  self.response=snapshot;status,reply=self.request('v1:'+marker[1],wire=True);self.assertEqual((status,reply),(200,{'_hp':[1,marker[1],1]}));self.assertEqual(len(self.calls),2)
  self.assertEqual(self.calls[0][0],'/v1/online-time/checkpoint');self.assertEqual(self.calls[0][1],self.calls[1][1])
 def test_write_failure_and_bad_header_are_never_replaced_by_seed(self):
  self.response={'ok':False,'error':'synthetic-conflict','grants':[],'profile':snapshot()};self.assertEqual(self.request('v1',path='/v1/online-time/checkpoint')[1],self.response)
  self.response=checkpoint(snapshot());self.assertEqual(self.request('v1',extra='v1',path='/v1/online-time/checkpoint')[1],self.response);self.assertEqual(len(self.calls),2)

if __name__=='__main__':unittest.main(verbosity=2)
