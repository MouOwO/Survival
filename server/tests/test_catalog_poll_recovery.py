"""Explicit catalogue-read fault model; raw failures and strict mode stay intact."""
from pathlib import Path
import unittest,json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server')]
from tools.loadtest_lab.workload import CompactRooms
from tools.loadtest_lab.guard import catalog_poll_recovery_mode
from tools.loadtest_lab.wire_client import WireClient,http_error_label

class Player:
 def __init__(self,index=0,mode='retain-v1'):
  self.identity={'account_id':str(4000000000+index)};self.cfg={'account_start':4000000000,'accounts':8,'client_workload':'client-v3'}
  if mode is not None:self.cfg['catalog_poll_recovery']=mode
  self._compact_room=None;self.now=0.;self.actions=[];self.calls=0;self.wire=WireClient(measure_routes=True)
 def clock(self):return self.now
 def catalog(self,label=None):
  self.calls+=1;action=self.actions.pop(0)if self.actions else 200
  if isinstance(action,BaseException):raise action
  if isinstance(action,tuple):action,advance=action;self.now+=advance
  if type(action)is dict:return action
  status=action;body=b''if status==0 else json.dumps({'ok':False,'error':'frontend_busy'}if status==503 else {'ok':True,'unchanged':True}).encode()
  self.wire.headers('POST','/v1/lottery/catalog','synthetic')
  try:value=self.wire.decode('POST','/v1/lottery/catalog',body,status)
  except ValueError:
   if status==0:raise ValueError(http_error_label(0,None))
   raise
  if status!=200:raise ValueError(http_error_label(status,value))
  return value

class CatalogPollRecoveryTests(unittest.TestCase):
 def pair(self,mode='retain-v1'):
  rooms=CompactRooms();a=Player(0,mode);b=Player(1,mode);rooms.join(a);rooms.join(b);return rooms,a,b
 def test_default_strict_failure_and_original_report_shape_unchanged(self):
  rooms,a,b=self.pair(None);a.now=30;a.actions=[0]
  with self.assertRaisesRegex(ValueError,'http_0'):rooms.tick(a)
  with self.assertRaisesRegex(ValueError,'compact_room_catalog_unavailable'):rooms.next_poll(b)
  self.assertIsNone(rooms.recovery_report());self.assertEqual(rooms.report()['room_failures'],1)
 def test_transport_read_failure_retains_verified_room_and_fixed_cadence(self):
  rooms,a,b=self.pair();a.now=30;a.actions=[0];rooms.tick(a)
  self.assertEqual(rooms.next_poll(a),60);self.assertEqual(rooms.next_poll(b),float('inf'));self.assertEqual(rooms.report()['room_periodic_catalog_failed'],1)
  rooms.tick(a);self.assertEqual(a.calls,2);a.now=60;rooms.tick(a);self.assertEqual(a.calls,3);self.assertEqual(rooms.report()['catalog_hits'],2)
  self.assertEqual(rooms.recovery_report(),{'id':'retain-v1','retained_poll_failures':1,'raw_failed_periodic_polls':1,'raw_failed_startup_polls':0})
  self.assertEqual(a.wire.report()['counters']['requests'],3);self.assertEqual(a.wire.report()['counters']['invalid_responses'],1)
 def test_explicit_busy_failure_remains_raw_HTTP_error(self):
  rooms,a,b=self.pair();a.now=30;a.actions=[503];rooms.tick(a)
  self.assertEqual(a.wire.report()['counters']['http_error_responses'],1);self.assertEqual(rooms.report()['room_failures'],1);self.assertEqual(rooms.recovery_report()['retained_poll_failures'],1)
 def test_slow_failure_skips_missed_intervals_without_poll_flood(self):
  rooms,a,b=self.pair();a.now=30;a.actions=[(0,65)];rooms.tick(a);self.assertEqual(a.now,95);self.assertEqual(rooms.next_poll(a),120);rooms.tick(a);self.assertEqual(a.calls,2)
 def test_startup_without_verified_catalogue_stays_fatal(self):
  rooms=CompactRooms();a=Player();a.actions=[0]
  with self.assertRaisesRegex(ValueError,'http_0'):rooms.join(a)
  b=Player(1)
  with self.assertRaisesRegex(ValueError,'compact_room_catalog_unavailable'):rooms.join(b)
  self.assertEqual(rooms.report()['room_startup_catalog_failed'],1);self.assertEqual(rooms.recovery_report()['retained_poll_failures'],0)
 def test_schema_and_identity_errors_remain_fatal(self):
  for error in ['business_wire_invalid','loadtest_profile_cache_identity_mismatch','catalog_revision_changed','http_403:player_session_required','http_502:upstream_response_invalid']:
   rooms,a,b=self.pair();a.now=30;a.actions=[ValueError(error)]
   with self.assertRaises(ValueError):rooms.tick(a)
   self.assertEqual(rooms.recovery_report()['retained_poll_failures'],0)
 def test_catalogue_mismatch_is_never_treated_as_transient(self):
  rooms,a,b=self.pair();a.now=30;a.actions=[{'ok':True,'unchanged':False}]
  with self.assertRaisesRegex(ValueError,'compact_room_catalog_miss'):rooms.tick(a)
  self.assertEqual(rooms.report()['catalog_misses'],1);self.assertEqual(rooms.recovery_report()['retained_poll_failures'],0)
 def test_cancellation_and_nonstandard_errors_are_not_suppressed(self):
  for error in [KeyboardInterrupt(),SystemExit(),RuntimeError('http_0:error_unavailable')]:
   rooms,a,b=self.pair();a.now=30;a.actions=[error]
   with self.assertRaises(type(error)):rooms.tick(a)
   self.assertEqual(rooms.recovery_report()['retained_poll_failures'],0)
 def test_owner_handoff_after_retained_failure_keeps_authenticated_schedule(self):
  rooms,a,b=self.pair();a.now=30;a.actions=[0];rooms.tick(a);rooms.leave(a);self.assertEqual(rooms.next_poll(b),60);b.now=60;rooms.tick(b);self.assertEqual(b.calls,1);rooms.leave(b);self.assertEqual(rooms.report()['rooms_remaining'],0)
 def test_repeated_transient_failures_are_counted_without_changing_raw_strict_gate(self):
  rooms,a,b=self.pair()
  for now in [30,60,90]:a.now=now;a.actions=[503];rooms.tick(a)
  self.assertEqual(rooms.report()['room_failures'],3);self.assertEqual(rooms.report()['room_periodic_catalog_failed'],3);self.assertEqual(a.wire.report()['counters']['http_error_responses'],3);self.assertEqual(rooms.recovery_report()['retained_poll_failures'],3)
 def test_mixed_run_modes_do_not_share_a_room(self):
  rooms,a,b=self.pair();foreign=Player(2,None)
  with self.assertRaisesRegex(ValueError,'compact_room_recovery_mode_changed'):rooms.join(foreign)
  self.assertEqual(foreign.calls,0);self.assertEqual(rooms.report()['rooms_opened'],1)
 def test_mode_validation_and_default(self):
  self.assertEqual(catalog_poll_recovery_mode({}),'baseline');self.assertEqual(catalog_poll_recovery_mode({'client_workload':'client-v3','catalog_poll_recovery':'retain-v1'}),'retain-v1')
  for value in [True,1,None,[],{},'retain','']:
   with self.assertRaisesRegex(ValueError,'catalog_poll_recovery_invalid'):catalog_poll_recovery_mode({'catalog_poll_recovery':value})
  with self.assertRaisesRegex(ValueError,'requires_compact'):catalog_poll_recovery_mode({'catalog_poll_recovery':'retain-v1','client_workload':'client-v2'})

if __name__=='__main__':unittest.main()
