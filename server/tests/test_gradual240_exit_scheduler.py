import types,unittest,os
from server.tests.test_gradual_exit_scheduler import GradualSchedulerTests,support
@unittest.skipIf(support.HttpUser is None,'FixedLinuxLocustrequired')
class Gradual240SchedulerTests(unittest.TestCase):
 def test3500_exact240_single_owned_snapshot(self):
  import gevent
  ns,source,wave_type=GradualSchedulerTests().runtime(3500);ns['EXIT_MODE']='gradual240-v1';users=[];clock=types.SimpleNamespace(now=100.0);quit_calls=[]
  class Group:
   iterations=0
   def __iter__(self):self.iterations+=1;return iter([u._greenlet for u in users])
  group=Group();env=types.SimpleNamespace(runner=types.SimpleNamespace(user_greenlets=group,quit=lambda:quit_calls.append(1)))
  for _ in range(3500):
   u=source.__new__(source);u._greenlet=types.SimpleNamespace(args=(u,),dead=False);users.append(u)
  wave=wave_type(env,240,clock=lambda:clock.now,sleep=lambda seconds:setattr(clock,'now',clock.now+seconds));ns['DEPARTURE_WAVE']=wave;calls=[]
  for u in users:
   def stop(force=False,u=u):calls.append((u._exit_wave_intent,force));wave.finished(u)
   u.stop=stop
  wave.run();gevent.sleep(0);self.assertEqual(group.iterations,1);self.assertEqual(len(calls),3500);self.assertAlmostEqual(calls[0][0],100);self.assertAlmostEqual(calls[-1][0],340);self.assertTrue(all(not x[1]for x in calls));self.assertEqual(wave.finished_count,3500);self.assertEqual(wave.scheduled,3500);self.assertEqual(quit_calls,[1]);self.assertFalse(wave.cancelled);self.assertEqual(wave.report()['per_actor_cleanup_deadline_seconds'],45)
 def test_unsupported_window_cannot_silently_extend(self):
  ns,source,wave_type=GradualSchedulerTests().runtime(3500);env=types.SimpleNamespace(runner=types.SimpleNamespace(user_greenlets=[]))
  for seconds in(239,241,300,3600,True):
   with self.subTest(seconds=seconds),self.assertRaises(ValueError):wave_type(env,seconds)
if __name__=='__main__':unittest.main()
