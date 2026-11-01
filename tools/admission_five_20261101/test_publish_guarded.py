"""Offline guard/cover projection tests. No SDK initialization or network call."""
from contextlib import contextmanager
from pathlib import Path
import copy,functools,importlib.util,io,json,unittest

spec=importlib.util.spec_from_file_location('five_accounts_guard_test',Path(__file__).with_name('publish_guarded.py'))
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)

def fixture():
 parent={'uploaded':True,'release_sequence':2026103102,'content_sha256':g.PARENT_CONTENT,'workshop_id':'3824360109',
  'owner':'76561198845461206','app_id':570,'visibility_requested':3}
 raw=json.dumps(parent).encode();state={'raw':raw,'lock':False,'locks':0,'fresh':0,'published':0,'read_under_lock':[]}
 @contextmanager
 def locker(path):
  if state['lock']:raise AssertionError('recursive OS locking')
  state['lock']=True;state['locks']+=1
  try:yield
  finally:state['lock']=False
 def reader():state['read_under_lock'].append(state['lock']);return state['raw']
 def fresh(_):
  assert state['lock'];state['fresh']+=1
  return dict(g.EXPECTED_REMOTE)
 guard=g.Guard(locker,fresh,reader,functools.partial(g.parent_bytes,expected_sha=g.sha(raw)))
 return guard,state,parent

class ParentGuardTests(unittest.TestCase):
 def test_no_publish_without_sdk_lock(self):
  guard,state,_=fixture()
  with self.assertRaisesRegex(RuntimeError,'lock is held'):guard.before_publish(None,{'release_sequence':2026110104,'content_sha256':g.CONTENT})
  self.assertEqual(state['fresh'],0)

 def test_preflight_uses_one_lock_and_checks_before_frozen_publisher(self):
  guard,state,_=fixture()
  def original(*args,**kwargs):state['published']+=1;self.assertTrue(state['lock']);return 'readonly'
  result=g.guarded_publisher(guard,original)(None,{},None,None,{'release_sequence':2026110104,'content_sha256':g.CONTENT},g.STATE)
  self.assertEqual(result,'readonly');self.assertEqual((state['locks'],state['fresh'],state['published']),(1,1,1))
  self.assertTrue(all(state['read_under_lock']));self.assertFalse(state['lock'])

 def test_apply_reuses_existing_sdk_lock_without_recursive_locking(self):
  guard,state,_=fixture()
  def original(*args,**kwargs):state['published']+=1;self.assertTrue(state['lock']);return kwargs['apply']
  with guard.lock(g.STATE):
   result=g.guarded_publisher(guard,original)(None,{},None,None,{'release_sequence':2026110104,'content_sha256':g.CONTENT},g.STATE,apply=True,update_existing=True)
  self.assertTrue(result);self.assertEqual(state['locks'],1);self.assertEqual(state['published'],1)

 def test_parent_changed_during_fresh_query_refuses_before_publish(self):
  guard,state,_=fixture()
  def fresh(_):state['raw']+=b' ';return dict(g.EXPECTED_REMOTE)
  guard.fresh=fresh
  def original(*args,**kwargs):state['published']+=1
  with self.assertRaisesRegex(RuntimeError,'Canonical parent changed'):
   g.guarded_publisher(guard,original)(None,{},None,None,{'release_sequence':2026110104,'content_sha256':g.CONTENT},g.STATE)
  self.assertEqual(state['published'],0);self.assertFalse(guard.locked)

 def test_newer_parent_rejected_even_if_its_own_hash_matches(self):
  _,_,parent=fixture();parent['release_sequence']=2026110103;raw=json.dumps(parent).encode()
  with self.assertRaisesRegex(RuntimeError,'Exact successful3102'):g.parent_bytes(raw,g.sha(raw))

 def test_unapproved_remote_metadata_or_new_content_refused(self):
  for key,value in [('time_updated',1793457064),('total_files_bytes',3788093063),('content_bytes',3788093063),
    ('content_file','123'),('preview_url','https://images.steamusercontent.com/other'),
    ('metadata_sha256','other'),('title_description_sha256','other'),('tags','Custom Game,Other'),('visibility',2),('cached',True)]:
   item=dict(g.EXPECTED_REMOTE);item[key]=value
   with self.subTest(key=key),self.assertRaisesRegex(RuntimeError,'Remote no longer'):g.remote_parent(item)
  self.assertEqual(g.remote_parent(dict(g.EXPECTED_REMOTE)),g.EXPECTED_REMOTE)

 def test_unrelated_target_or_wrong_lock_refuses(self):
  guard,state,_=fixture()
  with self.assertRaisesRegex(RuntimeError,'canonical publication lock'):
   with guard.lock(g.STATE.with_name('other.json')):pass
  self.assertEqual(state['locks'],0)
  with guard.lock(g.STATE):
   with self.assertRaisesRegex(RuntimeError,'Only reviewed0104'):
    guard.before_publish(None,{'release_sequence':2026110103,'content_sha256':g.CONTENT})
   with self.assertRaisesRegex(RuntimeError,'nested'):
    with guard.lock(g.STATE):pass
  self.assertEqual(state['fresh'],0);self.assertFalse(guard.locked)

 def test_committed_cover_event_and_exact_asset_local_bytes(self):
  # Fixed, locally committed metadata/image checks only; no CDN/API requests.
  fields=g.approved_cover_fields()
  self.assertEqual(set(fields),g.COVER_KEYS);self.assertEqual(fields['cover_sha256'],g.COVER_SHA)
  self.assertEqual(fields['cover_bytes'],936610);self.assertTrue(fields['cover'].endswith('gou_fayu_workshop.jpg'))

 def test_projection_updates_only_seven_cover_fields(self):
  original={'title':'preserved title','description':'approved account text','tester_steamids64':['one','two'],
   'max_players':4,'runtime_content_sha256':g.CONTENT,'real_money_payments':True,'nested':{'keep':[1,2]},
   **{key:'old' for key in g.COVER_KEYS}}
  before=copy.deepcopy(original);fields={key:'new' for key in g.COVER_KEYS}
  result=g.project_cover(original,fields)
  self.assertEqual(original,before)
  self.assertEqual({k for k in result if result[k]!=before[k]},set(g.COVER_KEYS))
  with self.assertRaisesRegex(RuntimeError,'seven reviewed'):g.project_cover(original,{**fields,'title':'unapproved'})

 def test_large_sdk_state_is_logged_but_not_echoed(self):
  raw=io.StringIO();console=io.StringIO();stream=g.LogSummary(raw,console)
  line=json.dumps({'status':'VERIFIED_NO_PUBLICATION','state':{'history':'x'*146000}})+'\n'
  for start in range(0,len(line),1024):stream.write(line[start:start+1024])
  self.assertEqual(raw.getvalue(),line)
  answer=json.loads(console.getvalue());self.assertEqual(answer,{'status':'VERIFIED_NO_PUBLICATION'})
  self.assertLess(len(console.getvalue()),100)

if __name__=='__main__':unittest.main()
