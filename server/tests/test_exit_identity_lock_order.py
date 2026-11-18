"""Real SQLite authority stays atomic; pending DB owners cannot hold lease_lock."""
from pathlib import Path
import os,sqlite3,tempfile,threading,time,unittest,sys
sys.path.insert(0,str(Path.cwd()/"server"))
from tools.loadtest_lab.identity import IdentityService
from player_web_auth.service import AuthError

class ExitLockOrderTests(unittest.TestCase):
 def setUp(self):
  base=Path('D:/Survival_本地工具/tests')if os.name=='nt'else Path(tempfile.gettempdir());self.tmp=tempfile.TemporaryDirectory(prefix='exit_lock_order_',dir=base);root=Path(self.tmp.name)
  self.cfg=dict(duration_seconds=120,purpose='capacity',run_id='a'*32,accounts=10,active=4,sources={})
  self.service=IdentityService(root,self.cfg,dict(auth_secret='1'*64,backend='2'*64,controller='3'*64),lambda path,raw:(200,b'{}'))
  self.payload={'run_id':'a'*32,'lease_id':'b'*32};self.reply=self.service.issue(self.payload)
 def tearDown(self):
  self.service.close();self.tmp.cleanup()
 def principal(self):
  return self.service.principal(self.reply['access_token'],dict(account_id=self.reply['account_id'],match_session_id=self.reply['match_session_id']))
 def queued_database_operation_does_not_own_lease(self,operation):
  service=self.service;entered=threading.Event();errors=[]
  def run():
   entered.set()
   try:operation()
   except BaseException as error:errors.append(type(error).__name__)
  service.lock.acquire();worker=threading.Thread(target=run);acquired=False
  try:
   worker.start();self.assertTrue(entered.wait(1));time.sleep(.03)
   acquired=service.lease_lock.acquire(timeout=.2)
   self.assertTrue(acquired,'DB waiter is holding the synthetic lease lock')
   service.counts();service.budget()
  finally:
   if acquired:service.lease_lock.release()
   service.lock.release();worker.join(2)
  self.assertFalse(worker.is_alive());self.assertEqual(errors,[])
 def test_release_waiter_leaves_ready_and_budget_accessible(self):
  self.queued_database_operation_does_not_own_lease(lambda:self.service.release(self.payload));self.assertEqual(self.service.active,0)
 def test_issue_waiter_leaves_ready_and_budget_accessible(self):
  other={'run_id':'a'*32,'lease_id':'c'*32};self.queued_database_operation_does_not_own_lease(lambda:self.service.issue(other));self.assertEqual(self.service.active,2)
 def test_close_waiter_leaves_measurement_lock_accessible(self):
  self.queued_database_operation_does_not_own_lease(self.service.close);self.assertTrue(self.service._database_closed)
 def test_revocation_committed_before_release_reply(self):
  self.principal();self.assertEqual(self.service.release(self.payload),{'ok':True})
  with self.assertRaises(AuthError):self.principal()
  self.assertEqual(self.service.db.execute('SELECT revoked FROM challenges').fetchone()[0],1)
  self.assertEqual(self.service.release(self.payload),{'ok':True});self.assertEqual(self.service.active,0)
 def test_concurrent_duplicate_release_only_decrements_once(self):
  barrier=threading.Barrier(3);errors=[]
  def run():
   try:barrier.wait();self.service.release(self.payload)
   except BaseException as error:errors.append(type(error).__name__)
  threads=[threading.Thread(target=run)for _ in range(2)]
  for t in threads:t.start()
  barrier.wait()
  for t in threads:t.join(2);self.assertFalse(t.is_alive())
  self.assertEqual(errors,[]);self.assertEqual(self.service.active,0);self.assertEqual(self.service.db.execute('SELECT revoked FROM challenges').fetchone()[0],1)
 def test_failed_sql_release_preserves_capability_and_counter(self):
  real=self.service.db
  class FailingDatabase:
   def __enter__(self):return self
   def __exit__(self,*args):return False
   def execute(self,*args):raise sqlite3.OperationalError('synthetic SQL failure')
  self.service.db=FailingDatabase()
  try:
   with self.assertRaises(sqlite3.OperationalError):self.service.release(self.payload)
  finally:self.service.db=real
  self.assertEqual(self.service.active,1);self.assertFalse(self.service.leases['b'*32]['released']);self.principal();self.service.release(self.payload)
 def test_issue_after_close_is_rejected_before_mutation(self):
  self.service.close();count=self.service.next_index
  with self.assertRaises(AuthError):self.service.issue({'run_id':'a'*32,'lease_id':'c'*32})
  self.assertEqual(self.service.next_index,count)

if __name__=='__main__':unittest.main()
