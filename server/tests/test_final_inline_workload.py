"""Opted-in V4 removes only a proved duplicate HTTP refresh; counters stay honest."""
from pathlib import Path
import copy,hashlib,sys,unittest
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'));sys.path.insert(0,str(ROOT/'tools/loadtest_native'))
from loadtest_lab.workload_profiles import build_workload_profile,CSV_SOURCE,COMPACT_TARGET,COMPACT_METADATA,FINAL_CONSUMER_TARGET
from loadtest_lab.workload import Player,inline_final_profile_report
from loadtest_lab import workload
from tools.loadtest_native.native_stage_proof import inline_final_profile_count_checks
class FinalInlineWorkloadTests(unittest.TestCase):
 def setUp(self):
  with workload._INLINE_FINAL_LOCK:
   for key in workload._INLINE_FINAL_COUNTS:workload._INLINE_FINAL_COUNTS[key]=0
 def player(self,mode='client-v4',marker=1,revision=6,wrong_profile=False,missing_profile=False,read_error=False):
  raw=(ROOT/'data/csv/玩家档案系统/star_blessing_reward_definitions.csv').read_bytes();seed=(ROOT/'data/ui/lottery_catalog.json').read_bytes();consumer=(ROOT/'scripts/vscripts/systems/online_time_service.lua').read_bytes();meta=build_workload_profile(raw,mode,compact_seed=seed,final_consumer=consumer)
  cfg={'client_workload':mode,'workload_profile':meta,'sources':{CSV_SOURCE:hashlib.sha256(raw).hexdigest(),COMPACT_TARGET:hashlib.sha256(seed).hexdigest()},'lottery_catalog_md5':COMPACT_METADATA['catalog_md5'],'generator_transport':{'id':'linux-loopback-v1','loopback_ports':[29567]}}
  if mode=='client-v4':cfg['sources'][FINAL_CONSUMER_TARGET]=hashlib.sha256(consumer).hexdigest()
  row=next(r for r in meta['rules']if r['enabled']and r['effect_scope']=='permanent');grant={'grant_id':'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','reward_id':row['reward_id'],'definition_version':row['definition_version'],'amount':row['value_min']};calls=[]
  def profile(rev=6,account='123'):return {'schema_version':1,'account_id':account,'revision':rev,'save':{}}
  def transport(method,path,body,auth,name):
   calls.append((path,copy.deepcopy(body)))
   if path=='/v1/online-time/checkpoint':
    response={'ok':True,'profile':profile(revision,'999'if wrong_profile else'123'),'grants':[grant]}
    if marker is not None:response['final_profile_committed_v1']=marker
    if missing_profile:response.pop('profile')
    return response
   if path=='/v1/profile':return {'ok':False,'error':'synthetic_failure'}if read_error else {'ok':True,'profile':profile()}
   if path=='/_loadtest/release':return {'ok':True}
   raise AssertionError(path)
  p=Player(transport,cfg,'synthetic-controller');p.identity={'account_id':'123','match_session_id':'synthetic-session'};p.token='synthetic-token';p.session_logged_in=True;p.last_profile=profile(5);return p,calls
 def test_confirmed_final_saves_one_actual_HTTP(self):
  p,calls=self.player();p.checkpoint(final=True);self.assertEqual([x[0]for x in calls],['/v1/online-time/checkpoint']);self.assertTrue(calls[0][1]['response_capabilities']['final_profile_committed_v1']);self.assertTrue(p._final_checkpoint_confirmed);self.assertEqual(p.workload_counters['grant_followup_completed'],1);self.assertEqual(inline_final_profile_report()['inline_applied'],1)
 def test_legacy_v3_still_refreshes(self):
  p,calls=self.player(mode='client-v3');p.checkpoint(final=True);self.assertEqual(len(calls),2);self.assertEqual(calls[-1][0],'/v1/profile');self.assertNotIn('response_capabilities',calls[0][1]);self.assertEqual(inline_final_profile_report()['inline_applied'],0)
 def test_invalid_or_absent_marker_keeps_real_HTTP(self):
  for marker in [None,0,False,True,'1',2]:
   p,calls=self.player(marker=marker);p.checkpoint(final=True);self.assertEqual(len(calls),2)
 def test_regular_even_with_marker_keeps_real_HTTP(self):
  p,calls=self.player();p.checkpoint();self.assertEqual(len(calls),2);self.assertNotIn('response_capabilities',calls[0][1]);self.assertEqual(inline_final_profile_report()['final_responses'],0)
 def test_failed_or_stale_apply_falls_back(self):
  for args in [dict(revision=4),dict(wrong_profile=True),dict(missing_profile=True)]:
   p,calls=self.player(**args);p.checkpoint(final=True);self.assertEqual(len(calls),2);self.assertEqual(p.last_profile['revision'],6)
 def test_failed_fallback_preserves_final_ID_and_capability(self):
  p,calls=self.player(marker=None,read_error=True)
  for _ in range(2):
   with self.assertRaises(ValueError):p.checkpoint(final=True)
  requests=[b for path,b in calls if path=='/v1/online-time/checkpoint'];self.assertEqual(requests[0],requests[1]);self.assertFalse(p._final_checkpoint_confirmed);self.assertEqual(p.workload_counters['grant_followup_failed'],2);self.assertEqual(p._seen_grants,set())
 def ledger(self):
  p,calls=self.player();p.checkpoint(final=True);c=p.workload_counters;f={'inline_final_profile':inline_final_profile_report(),'run_state':{'workload_counters':c},'routes':[],'workflow_statistics':[{'name':'checkpoint_final','requests':1}]};return f,p.cfg
 def test_saved_HTTP_ledger_matches_logical_validation(self):
  f,cfg=self.ledger();self.assertTrue(all(inline_final_profile_count_checks(f,cfg).values()))
 def test_forged_inline_counts_or_missing_server_proof_rejected(self):
  f,cfg=self.ledger()
  for key,value in [('inline_applied',2),('marker_validated',0),('v',True),('eligible',0)]:
   bad=copy.deepcopy(f);bad['inline_final_profile'][key]=value;self.assertFalse(all(inline_final_profile_count_checks(bad,cfg).values()))
 def test_fake_HTTP_event_is_rejected(self):
  f,cfg=self.ledger();f['routes']=[{'method':'POST','name':'[grant-followup] /v1/profile','requests':1}];self.assertFalse(inline_final_profile_count_checks(f,cfg)['inline_final_transport_reconciled'])
if __name__=='__main__':unittest.main()
