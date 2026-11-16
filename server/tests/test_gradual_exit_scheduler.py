import ast,time,types,unittest,os
from pathlib import Path
import server.tests.test_loadtest_normal_stop as support
@unittest.skipIf(support.HttpUser is None,'Use fixed Locust interpreter')
class GradualSchedulerTests(unittest.TestCase):
 def runtime(self,active):
  ns,source=support.NormalStopTests().actual();path=Path(os.environ.get('SURVIVAL_STOP_SOURCE',str(Path(__file__).resolve().parents[2]/'tools/loadtest_lab/locustfile.py')));tree=ast.parse(path.read_text(encoding='utf8'));nodes=[n for n in tree.body if isinstance(n,(ast.ClassDef,ast.FunctionDef))and n.name in ('DepartureWave','CleanupTimeout','cleanup_budget')];exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),str(path),'exec'),ns)
  ns.update(CFG={'active':active},EXIT_MODE='gradual120-v1',EXIT_SEMAPHORE=None,EXIT_METRICS=dict(active=0,peak=0,queued=0,completed=0,delay_ms=0),RUN_COUNTERS=dict.fromkeys(('start_attempts','start_blocked_after_failure','cleanup_attempts','cleanup_completed','cleanup_failed','cleanup_interrupted'),0),PROGRESS_INDEX=None,DEPARTURE_WAVE=None)
  return ns,source,ns['DepartureWave']
 def exercise(self,cancel=False):
  import gevent
  from locust.env import Environment
  from locust.event import Events
  from locust import constant
  ns,source,wave_type=self.runtime(2);state={'work_after_first_cleanup':0,'cleanup':0,'intents':[]}
  class Player:
   next_checkpoint=0
   def clock(self):return 1
   def checkpoint(self):
    if state['cleanup']:state['work_after_first_cleanup']+=1
    gevent.sleep(.002)
   def stop(self,*,intent_started):state['intents'].append(intent_started);gevent.sleep(.003);state['cleanup']+=1
  class Probe(source):
   wait_time=constant(.001)
   def on_start(self):self.player=Player();self.next_activity=float('inf');self._isolated_failure=False
  env=Environment(user_classes=[Probe],events=Events(),stop_timeout=1);runner=env.create_local_runner();holder={}
  def stopping(**kw):
   ns.update(RUN_STOPPING=True,RUN_STOPPING_AT=time.monotonic())
   if holder:holder['wave'].stop_dispatch()
  env.events.test_stopping.add_listener(stopping);runner.start(2,spawn_rate=100);gevent.sleep(.03);self.assertEqual(runner.user_count,2);wave=wave_type(env,2);holder['wave']=wave;ns['DEPARTURE_WAVE']=wave;wave.start()
  try:
   if cancel:gevent.sleep(.05);runner.quit()
   with gevent.Timeout(6):
    while runner.user_count:gevent.sleep(.01)
   gevent.sleep(.03);self.assertEqual(ns['RUN_COUNTERS']['cleanup_completed'],2);self.assertEqual(ns['RUN_COUNTERS']['cleanup_interrupted'],0)
   if cancel:
    self.assertTrue(wave.cancelled);self.assertTrue(wave.task.ready());self.assertEqual(wave.scheduled,1);self.assertEqual(wave.early_finished,1)
   else:
    self.assertFalse(wave.cancelled);self.assertEqual(wave.scheduled,2);self.assertEqual(wave.finished_count,2);self.assertEqual(wave.early_finished,0);self.assertGreater(state['work_after_first_cleanup'],10);self.assertAlmostEqual(max(state['intents'])-min(state['intents']),2,places=5)
  finally:
   if runner.user_count:runner.quit()
 def test_actual_actors_keep_business_until_personal_intent(self):self.exercise()
 def test_early_global_stop_cancels_owned_coordinator_and_stays_failure(self):self.exercise(True)
 def test_two_thousand_exact_times_single_snapshot_no_repeated_scan(self):
  import gevent
  ns,source,wave_type=self.runtime(2000);users=[];clock=types.SimpleNamespace(now=100.0);quit_calls=[]
  class Group:
   iterations=0
   def __iter__(self):self.iterations+=1;return iter([u._greenlet for u in users])
  group=Group();runner=types.SimpleNamespace(user_greenlets=group,quit=lambda:quit_calls.append(1));env=types.SimpleNamespace(runner=runner)
  for _ in range(2000):
   user=source.__new__(source);user._greenlet=types.SimpleNamespace(args=(user,),dead=False);users.append(user)
  wave=wave_type(env,120,clock=lambda:clock.now,sleep=lambda seconds:setattr(clock,'now',clock.now+seconds));ns['DEPARTURE_WAVE']=wave;calls=[]
  for u in users:
   def stop(force=False,u=u):calls.append((u._exit_wave_intent,force));wave.finished(u)
   u.stop=stop
  wave.run();gevent.sleep(0);self.assertEqual(group.iterations,1);self.assertEqual(len(calls),2000);self.assertAlmostEqual(calls[0][0],100);self.assertAlmostEqual(calls[-1][0],220);self.assertTrue(all(not x[1]for x in calls));self.assertEqual(wave.finished_count,2000);self.assertEqual(wave.scheduled,2000);self.assertEqual(quit_calls,[1]);self.assertFalse(wave.cancelled)
 def test_expired_personal45second_budget_does_not_start_a_write(self):
  from locust.env import Environment
  from locust.event import Events
  ns,source,_=self.runtime(2);ns['OBSERVE_OVERLOAD']=True;ns['OBSERVATION_COUNTS']={'cleanup_timeouts':0,'isolated_errors':0,'quarantined_actors':0};called=[];obj=source.__new__(source);obj.environment=Environment(events=Events(),stop_timeout=45);obj.player=types.SimpleNamespace(stop=lambda **kw:called.append(kw));obj._exit_wave_intent=time.monotonic()-46;obj.on_stop();self.assertEqual(called,[]);self.assertEqual(ns['RUN_COUNTERS']['cleanup_interrupted'],1);self.assertEqual(ns['RUN_COUNTERS']['cleanup_completed'],0)
 def early_clock(self,advances=True):
  import gevent
  from tools.loadtest_lab.workload import Player
  ns,source,wave_type=self.runtime(2000);clock=types.SimpleNamespace(now=100.0);sleeps=[];users=[];writes=[];failures=[];ns['fail_run']=lambda environment,reason:failures.append(reason)
  def sleep(seconds):
   sleeps.append(seconds)
   if advances:clock.now+=max(0,seconds-.0005)
  runner=types.SimpleNamespace(user_greenlets=[],quit=lambda:None);env=types.SimpleNamespace(runner=runner)
  for _ in range(2000):
   user=source.__new__(source);user._greenlet=types.SimpleNamespace(args=(user,),dead=False);users.append(user);runner.user_greenlets.append(user._greenlet)
  wave=wave_type(env,120,clock=lambda:clock.now,sleep=sleep);ns['DEPARTURE_WAVE']=wave
  for user in users:
   player=Player.__new__(Player);player.client_profile=types.SimpleNamespace(mode='client-v2');player.clock=lambda:clock.now;player._stop_session=lambda:True;player._workflow=lambda name,started,error,counters:writes.append((started,clock.now,error));user.player=player
   def stop(force=False,user=user):
    user.player.stop(intent_started=user._exit_wave_intent);wave.finished(user)
   user.stop=stop
  wave.run();gevent.sleep(0);return wave,sleeps,writes,failures
 def test_real_player_never_receives_future_intent_when_timer_wakes_early(self):
  wave,sleeps,writes,failures=self.early_clock();self.assertEqual(failures,[]);self.assertEqual(wave.scheduled,2000);self.assertEqual(wave.finished_count,2000);self.assertEqual(len(writes),2000);self.assertTrue(all(start<=now and error is None for start,now,error in writes));self.assertLessEqual(len(sleeps),4000);self.assertGreater(wave.early_timer_wakes,0);self.assertAlmostEqual(wave.max_timer_early_ms,.5,places=4);self.assertGreaterEqual(wave.last_offset_ms,120000)
 def test_clock_that_does_not_advance_is_bounded_and_never_false_success(self):
  wave,sleeps,writes,failures=self.early_clock(False);self.assertTrue(wave.cancelled);self.assertEqual(wave.scheduled,1);self.assertEqual(wave.finished_count,1);self.assertEqual(len(writes),1);self.assertLessEqual(len(sleeps),3);self.assertEqual(failures,['departure_wave_dispatch_failed'])
if __name__=='__main__':unittest.main()
