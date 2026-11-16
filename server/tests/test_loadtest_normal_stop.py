import ast,os,unittest,types,time
from pathlib import Path
try:
 import gevent
 from gevent import GreenletExit
 from gevent.event import Event
 from gevent.lock import BoundedSemaphore
 from locust import HttpUser,TaskSet,task,constant
 from locust.env import Environment
 from locust.event import Events
 from locust.exception import StopUser
 from locust.user.task import LOCUST_STATE_STOPPING
except ModuleNotFoundError:HttpUser=None

@unittest.skipIf(HttpUser is None,'Use the fixed Locust interpreter for scheduler regression')
class NormalStopTests(unittest.TestCase):
 def actual(self):
  path=Path(os.environ.get('SURVIVAL_STOP_SOURCE',str(Path(__file__).resolve().parents[2]/'tools/loadtest_lab/locustfile.py')));assert path.name=='locustfile.py'and path.is_file()
  tree=ast.parse(path.read_text(encoding='utf8'));nodes=[n for n in tree.body if isinstance(n,ast.ClassDef)and n.name in ('ExitCooperativeTaskSet','SyntheticPlayer')]
  import random
  ns=dict(RUN_STOPPING=False,RUN_FAILED=False,RUN_STOPPING_AT=None,OBSERVE_OVERLOAD=False,CLIENT_PROFILE=types.SimpleNamespace(mode='client-v2'),time=time,random=random,StopUser=StopUser,HttpUser=HttpUser,TaskSet=TaskSet,task=task,Event=Event,BoundedSemaphore=BoundedSemaphore,LOCUST_STATE_STOPPING=LOCUST_STATE_STOPPING,EXIT_PROBE=None)
  def unexpected(*a,**kw):raise AssertionError('normal stop must not abort run')
  ns['fail_run']=unexpected;exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),str(path),'exec'),ns);return ns,ns['SyntheticPlayer']
 def test_normal_stop_does_not_start_another_activity(self):
  ns,source=self.actual();ns['RUN_STOPPING']=True
  with self.assertRaises(StopUser):source.activity(object())
 def exercise(self,wait):
  ns,source=self.actual();state=dict(attempts=0,completed=0,cancelled=0,late=0,cleanup_started=0,cleanup_completed=0,cleanup_interrupted=0)
  class Player:
   next_checkpoint=0
   def clock(self):return 1
   def checkpoint(self):
    state['attempts']+=1;state['late']+=int(ns['RUN_STOPPING'])
    try:gevent.sleep(.002);state['completed']+=1
    except GreenletExit:state['cancelled']+=1;raise
  class Probe(source):
   wait_time=constant(wait)
   def on_start(self):self.player=Player();self.next_activity=float('inf');self._isolated_failure=False
   def on_stop(self):
    state['cleanup_started']+=1
    try:gevent.sleep(.002);state['cleanup_completed']+=1
    except GreenletExit:state['cleanup_interrupted']+=1;raise
  env=Environment(user_classes=[Probe],events=Events(),stop_timeout=1);env.events.test_stopping.add_listener(lambda **kw:ns.update(RUN_STOPPING=True));runner=env.create_local_runner();runner.start(256,spawn_rate=1000000);gevent.sleep(.04);self.assertEqual(runner.user_count,256);began=time.monotonic();runner.quit();elapsed=time.monotonic()-began
  self.assertEqual(runner.user_count,0);self.assertEqual(state['cleanup_started'],256);self.assertEqual(state['cleanup_completed'],256);self.assertEqual(state['cleanup_interrupted'],0);self.assertGreater(state['attempts'],0);self.assertEqual(state['late'],0);self.assertEqual(state['cancelled'],0);self.assertEqual(state['attempts'],state['completed']);self.assertLess(elapsed,.8)
 def test_actual_scheduler_finishes_every_cleanup(self):
  for _ in range(4):self.exercise(.001)
 def test_long_wait_is_woken_without_cancelling_cleanup(self):self.exercise(30)
 def test_forced_stop_keeps_parent_failure_path(self):
  from unittest.mock import patch
  ns,source=self.actual()
  if 'stop' not in source.__dict__:return
  ns['RUN_STOPPING']=True;obj=source.__new__(source)
  with patch.object(HttpUser,'stop',return_value='forced')as parent:
   self.assertEqual(source.stop(obj,force=True),'forced');parent.assert_called_once_with(force=True)
 def test_bounded_finalizers_keep_common_intent_and_release_slots(self):
  ns,source=self.actual()
  if not hasattr(source,'_finish_with_exit_policy'):return
  ns.update(EXIT_MODE='queue64-v1',EXIT_SEMAPHORE=BoundedSemaphore(64),EXIT_METRICS=dict(active=0,peak=0,queued=0,completed=0,delay_ms=0),RUN_STOPPING_AT=50)
  calls=[]
  class Player:
   def stop(self,*,intent_started):
    calls.append(intent_started);gevent.sleep(.003)
  users=[]
  for _ in range(100):
   obj=source.__new__(source);obj.player=Player();users.append(obj)
  jobs=[gevent.spawn(obj._finish_with_exit_policy)for obj in users];gevent.joinall(jobs,raise_error=True)
  self.assertEqual(calls,[50]*100);self.assertEqual(ns['EXIT_METRICS']['completed'],100);self.assertEqual(ns['EXIT_METRICS']['active'],0);self.assertEqual(ns['EXIT_METRICS']['peak'],64);self.assertGreater(ns['EXIT_METRICS']['queued'],0);self.assertEqual(ns['EXIT_SEMAPHORE'].counter,64)
 def test_jitter_keeps_global_intent_and_three_second_bound(self):
  from unittest.mock import patch
  ns,source=self.actual()
  if not hasattr(source,'_finish_with_exit_policy'):return
  ns.update(EXIT_MODE='jitter3-v1',EXIT_SEMAPHORE=None,EXIT_METRICS=dict(active=0,peak=0,queued=0,completed=0,delay_ms=0),RUN_STOPPING_AT=50)
  calls=[]
  class Player:
   identity={'account_id':60}
   def stop(self,*,intent_started):calls.append(intent_started)
  obj=source.__new__(source);obj.player=Player()
  with patch('gevent.sleep')as sleep:obj._finish_with_exit_policy();sleep.assert_called_once_with(3)
  self.assertEqual(calls,[50]);self.assertEqual(ns['EXIT_METRICS']['delay_ms'],3000);self.assertEqual(ns['EXIT_METRICS']['completed'],1)

if __name__=='__main__':unittest.main()
