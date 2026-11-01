"""Meaningful admission/operator isolation checks; no key/SDK/OS/game actions."""
from pathlib import Path
import copy,importlib.util,json,sys,tempfile,unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('five_admission_test_build',Path(__file__).with_name('build_release.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
prior=sys.modules.get('build_release');sys.modules['build_release']=b
try:
 spec2=importlib.util.spec_from_file_location('five_admission_test_checks',Path(__file__).with_name('release_checks.py'))
 c=importlib.util.module_from_spec(spec2);spec2.loader.exec_module(c)
 prior_checks=sys.modules.get('release_checks');sys.modules['release_checks']=c
 try:
  pub=b.module('five_admission_test_publish',Path(__file__).with_name('publish.py'))
  native=b.module('five_admission_test_native',Path(__file__).with_name('native.py'))
 finally:
  if prior_checks is None:sys.modules.pop('release_checks',None)
  else:sys.modules['release_checks']=prior_checks
finally:
 if prior is None:sys.modules.pop('build_release',None)
 else:sys.modules['build_release']=prior

class ExactAdmissionTests(unittest.TestCase):
 def test_exact_five_only(self):
  self.assertEqual(b.exact_ids(list(reversed(b.APPROVED))),sorted(b.APPROVED))
  for ids in (list(b.ORIGINAL),list(b.APPROVED)+['76561198296534616'],list(b.APPROVED[:-1])+['76561198296534616'],list(b.APPROVED[:-1])+[int(b.ADDED)],list(b.APPROVED[:-1])+[b.ORIGINAL[0]]):
   with self.subTest(ids=ids),self.assertRaises(ValueError):b.exact_ids(ids)

 def test_literal_parser_rejects_dynamic_or_wrong_roster(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td).resolve();p=root/b.ACCESS;p.parent.mkdir(parents=True)
   def content(ids):return 'return {enabled=true,allowed_steamids={'+','.join(json.dumps(s) for s in ids)+'}}'
   p.write_text(content(b.APPROVED),encoding='utf8')
   self.assertEqual(b.parsed_ids(root,b.APPROVED),sorted(b.APPROVED))
   p.write_text(content(b.ORIGINAL),encoding='utf8')
   with self.assertRaises(ValueError):b.parsed_ids(root,b.APPROVED)
   self.assertEqual(b.parsed_ids(root,b.ORIGINAL),sorted(b.ORIGINAL))
   p.write_text(content(b.APPROVED)+'; dofile("unsafe.lua")',encoding='utf8')
   with self.assertRaises(ValueError):b.parsed_ids(root,b.APPROVED)

 def test_context_is_exact_and_restored_on_error(self):
  h=b.pack.handoff;before=(h.steamids,h.NATIVE_CLOUD_TESTERS,h.NATIVE_CLOUD_ENTRY_PINS)
  with self.assertRaisesRegex(RuntimeError,'probe'):
   with b.admission_context({b.HANDOFF:b'h',b.ROSTER:b'r'}):
    self.assertEqual(h.NATIVE_CLOUD_TESTERS,sorted(b.APPROVED));self.assertEqual(h.NATIVE_CLOUD_ENTRY_PINS[b.HANDOFF],b.sha(b'h'))
    with self.assertRaises(ValueError):h.steamids(list(b.ORIGINAL))
    with b.original_admission_context():self.assertEqual(h.steamids(list(b.ORIGINAL)),sorted(b.ORIGINAL))
    self.assertEqual(h.steamids(list(b.APPROVED)),sorted(b.APPROVED))
    raise RuntimeError('probe')
  self.assertIs(h.steamids,before[0]);self.assertIs(h.NATIVE_CLOUD_TESTERS,before[1]);self.assertIs(h.NATIVE_CLOUD_ENTRY_PINS,before[2])

 def test_installer_truthful_account_count_and_match_capacity(self):
  old={'tester_count':4,'max_players':4,'runtime_files':6917,'status':'VERIFIED_DRY_RUN','testers_sha256':'five-list-hash'}
  result=native.corrected_handoff_receipt(old)
  self.assertEqual(result['tester_count'],5);self.assertEqual(result['max_players'],4)
  self.assertEqual(result['testers_sha256'],old['testers_sha256']);self.assertEqual(old['tester_count'],4)

 def test_server_proof_does_not_replace_steam_auth(self):
  proof={'status':'PASS_FIVE_ACCOUNT_ADMISSION_ACTIVE','added_steamid64':b.ADDED,'approved_steamids64':list(b.APPROVED),'max_players':4,
   'web_policy_active':True,'archive_policy_active':True,'original_accounts_preserved':True,'payments_unchanged':True,
   'bundle_preserved':b.EXPECTED_BUNDLE,'no_real_player_auth_claimed':True,'unlisted_unchanged':True}
  pub.check_server(proof)
  for key,value in [('approved_steamids64',list(b.ORIGINAL)),('max_players',5),('payments_unchanged',False),('no_real_player_auth_claimed',False),('bundle_preserved','wrong')]:
   bad=copy.deepcopy(proof);bad[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):pub.check_server(bad)

 def test_source_projection_rejects_unknown_change(self):
  text=''.join(b.LEGACY_BLOCKS)+'rest\n'
  self.assertEqual(b.committed_projection(b.POLICY,text.encode()),b'rest\n')
  with self.assertRaises(ValueError):b.committed_projection(b.POLICY,b'rest\n')
  with self.assertRaises(ValueError):b.admission_patch('scripts/vscripts/unapproved.lua',b'untouched')
  with self.assertRaises(ValueError):b.once('duplicated duplicated','duplicated','x')

 def test_receipt_cannot_claim_new_identity_authenticated(self):
  pkg={'content_sha256':'content'}
  native_proof={'status':'PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY','release_sequence':b.SEQUENCE,'content_sha256':'content',
   'signed_resources_verified':6917,'protected_modules_verified':184,'cheats':False,'normal_default_verified':True,
   'tester_count':5,'max_players':4,'real_account_grants_verified':False,'multiplayer_verified':False,
   'markers':{n:True for n in ('signed_addon','server_activated','initialized','layout_ready','no_script_error')}}
  pub.check_native(pkg,native_proof)
  for key,value in [('cheats',True),('tester_count',4),('max_players',5),('content_sha256','other'),('real_account_grants_verified',True)]:
   invalid=copy.deepcopy(native_proof);invalid[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):pub.check_native(pkg,invalid)

if __name__=='__main__':unittest.main()
