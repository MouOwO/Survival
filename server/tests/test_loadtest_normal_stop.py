import ast,os,sys,unittest,types
from pathlib import Path
try:
 import gevent
 from gevent import GreenletExit
 from locust import User,task,constant
 from locust.env import Environment
 from locust.event import Events
 from locust.exception import StopUser
except ModuleNotFoundError:
 User=None

@unittest.skipIf(User is None,'Run this concurrency regression with the pinned Locust interpreter')
class NormalStopTests(unittest.TestCase):
 def activity(self):
  path=Path(os.environ.get('SURVIVAL_STOP_SOURCE',str(Path(__file__).resolve().parents[2]/'tools/loadtest_lab/locustfile.py')))
  assert path.name=='locustfile.py'and path.is_file()
  tree=ast.parse(path.read_text(encoding='utf8'));cls=next(n for n in tree.body if isinstance(n,ast.ClassDef)and n.name=='SyntheticPlayer');method=next(n for n in cls.body if isinstance(n,ast.FunctionDef)and n.name=='activity');method.decorator_list=[]
  import time,random
  ns=dict(RUN_STOPPING=False,RUN_FAILED=False,OBSERVE_OVERLOAD=False,CLIENT_PROFILE=types.SimpleNamespace(mode='client-v2'),time=time,random=random,StopUser=StopUser)
  def unexpected(*a,**kw):raise AssertionError('normal stop must not abort the run')
  ns['fail_run']=unexpected;exec(compile(ast.fix_missing_locations(ast.Module(body=[method],type_ignores=[])),str(path),'exec'),ns);return ns
 def test_normal_stop_does_not_touch_or_start_player_work(self):
  ns=self.activity();ns['RUN_STOPPING']=True
  with self.assertRaises(StopUser):ns['activity'](object())
 def test_actual_locust_scheduler_has_no_cancelled_exchanges_at_normal_stop(self):
  for iteration in range(4):
   ns=self.activity();state=dict(attempts=0,completed=0,cancelled=0,late=0,cleanup=0)
   class Player:
    next_checkpoint=0
    def clock(self):return 1
    def checkpoint(self):
     state['attempts']+=1;state['late']+=int(ns['RUN_STOPPING'])
     try:gevent.sleep(.002);state['completed']+=1
     except GreenletExit:state['cancelled']+=1;raise
   class Probe(User):
    wait_time=constant(.001)
    def on_start(self):self.player=Player();self.next_activity=float('inf');self._isolated_failure=False
    activity=task(ns['activity'])
    def on_stop(self):state['cleanup']+=1;gevent.sleep(.002)
   env=Environment(user_classes=[Probe],events=Events(),stop_timeout=1);env.events.test_stopping.add_listener(lambda **kw:ns.update(RUN_STOPPING=True));runner=env.create_local_runner();runner.start(256,spawn_rate=1000000);gevent.sleep(.04);self.assertEqual(runner.user_count,256);runner.quit()
   self.assertEqual(runner.user_count,0);self.assertEqual(state['cleanup'],256);self.assertGreater(state['attempts'],0);self.assertEqual(state['late'],0);self.assertEqual(state['cancelled'],0);self.assertEqual(state['attempts'],state['completed'])
if __name__=='__main__':unittest.main()
