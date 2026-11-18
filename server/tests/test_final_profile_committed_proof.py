"""The actual emitted runtime helper requires explicit final capability and saved profile."""
import copy,unittest
from server.fishing_api_overrides import checkpoint_profile_drain_patch as recipe
ns={};exec(recipe.FINAL_PROFILE_HELPER,ns);proof=ns['_final_profile_committed']
class FinalProfileProofTests(unittest.TestCase):
 def values(self):return ({'account_id':'123','final':True,'response_capabilities':{'final_profile_committed_v1':True}},{'ok':True,'profile':{'account_id':'123'}})
 def test_success_has_no_mutation(self):
  p,r=self.values();old=copy.deepcopy((p,r));self.assertTrue(proof(p,r));self.assertEqual((p,r),old)
 def test_capability_is_exact_boolean(self):
  for v in [None,False,0,1,'1',[],True]:
   p,r=self.values();p['response_capabilities']['final_profile_committed_v1']=v;self.assertEqual(proof(p,r),v is True)
 def test_final_and_success_are_exact_booleans(self):
  for key,which in [('final',0),('ok',1)]:
   for v in [None,False,0,1,'1',True]:
    p,r=self.values();(p if which==0 else r)[key]=v;self.assertEqual(proof(p,r),v is True)
 def test_missing_or_invalid_profile_never_proves(self):
  for value in [None,False,{},[],{'account_id':'456'},{'account_id':123}]:
   p,r=self.values();r['profile']=value;self.assertFalse(proof(p,r))
 def test_missing_identity_and_caps_never_prove(self):
  for key in ['account_id','response_capabilities']:
   p,r=self.values();p.pop(key);self.assertFalse(proof(p,r))
 def test_non_objects_never_prove(self):
  for value in [None,[],False,1,'x']:
   p,r=self.values();self.assertFalse(proof(value,r));self.assertFalse(proof(p,value))
 def test_marker_is_emitted_after_real_profile_call(self):
  self.assertIn('archive.profile(',recipe.FINAL_PROFILE_ANCHOR);self.assertNotIn('profile=',recipe.FINAL_PROFILE_HINT);self.assertIn('final_profile_committed_v1',recipe.FINAL_PROFILE_HINT)
if __name__=='__main__':unittest.main()
