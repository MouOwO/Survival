"""Formal products, real packaged Lua and archive receipts; no external services."""
import copy, json, os, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT)]
from archive_backend.bundle import Bundle,build
from archive_backend.service import ArchiveService
from tests.test_archive_backend import Database,App

class StarjoyPurchaseTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.pointer=(ROOT/'server/bundles/current.json').read_bytes()
  cls.game=(ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes()
  cls.temp=tempfile.TemporaryDirectory(prefix='commerce-starjoy-');cls.addClassCleanup(cls.temp.cleanup)
  dest=Path(cls.temp.name);cls.bundle=Bundle(dest/build(ROOT,dest,update_game_config=False))
  cls.lua=os.environ.get('LUA_EXECUTABLE','C:/Program Files/lua/bin/lua5.1.exe')
 def setUp(self):
  self.db=Database(self.bundle);self.app=App(self.db);self.service=ArchiveService(self.app,self.bundle,self.lua)
  self.p=self.db.profile(self.app._database_account_id('100'));self.seq=0
  self.p['save']['archive']['commerce']={'balances':{'u_coin':1000000000,'shop_points':1000000000,'shop_gold':1000000000}}
  self.p['save']['content_inventory']={}
  self.p['save']['gameplay_stats'].update(starjoy_points=0,starjoy_points_earned=1000,starjoy_reward_level=5)
 def send(self,kind,account='100',**fields):
  self.seq+=1
  return self.service.command({'account_id':account,'config_hash':self.bundle.hash,'command':{'id':'same-match:'+kind+':'+str(self.seq),'kind':kind,**fields}})
 def buy(self,sku,request_id=None):
  return self.send('commerce_purchase',sku=sku,request_id=request_id or 'audit-purchase-'+str(self.seq+1))
 def test_spent_balance_keeps_new_purchase_earned_points(self):
  before=copy.deepcopy(self.p);r=self.buy('video_p004');self.assertTrue(r['ok'],r)
  s=self.p['save']['gameplay_stats'];self.assertEqual(s['starjoy_points'],68);self.assertEqual(s['starjoy_points_earned'],1068)
  self.assertEqual(s['initial_wood']-before['save']['gameplay_stats']['initial_wood'],200)
 def test_purchase_crosses_tier_and_second_purchase_never_replays_it(self):
  self.p['save']['gameplay_stats']['starjoy_points_earned']=1450
  self.assertTrue(self.buy('video_p004')['ok']);s=self.p['save']['gameplay_stats']
  self.assertEqual(s['starjoy_points_earned'],1518);self.assertEqual(s['starjoy_reward_level'],6)
  self.assertEqual(s['tower_critical_chance_pct'],3)
  self.assertTrue(self.buy('video_p011')['ok']);s=self.p['save']['gameplay_stats']
  self.assertEqual(s['starjoy_points_earned'],1586);self.assertEqual(s['starjoy_reward_level'],6);self.assertEqual(s['tower_critical_chance_pct'],3)
 def test_each_enabled_points_product_keeps_total_earned(self):
  count=0
  for product in self.bundle.configs['commerce_catalog']['rows']:
   reward=product['effects'].get('starjoy_points',0)
   if not product['enabled'] or not reward:continue
   with self.subTest(sku=product['sku']):
    self.setUp();s=self.p['save']['gameplay_stats'];s['vip_recharge_total_fen']=100000000
    r=self.buy(product['sku']);self.assertTrue(r['ok'],r)
    self.assertEqual(self.p['save']['gameplay_stats']['starjoy_points_earned'],1000+reward)
   count+=1
  self.assertGreater(count,20)
 def test_lost_reply_retry_does_not_regrant_or_redebit(self):
  self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.buy('video_p004','audit-lost-reply')
  after=copy.deepcopy(self.p)
  self.assertTrue(self.buy('video_p004','audit-lost-reply')['ok']);self.assertEqual(self.p,after)
  self.assertEqual(self.p['save']['gameplay_stats']['starjoy_points_earned'],1068)
 def test_rejected_purchase_changes_no_points_stats_or_inventory(self):
  self.p['save']['archive']['commerce']['balances']['u_coin']=0;before=copy.deepcopy(self.p)
  self.assertEqual(self.buy('video_p004')['error'],'commerce_balance_insufficient');self.assertEqual(self.p,before)
 def test_same_match_reconcile_handles_two_later_cash_tier_crossings(self):
  s=self.p['save']['gameplay_stats'];s.update(starjoy_points=0,starjoy_points_earned=1450,starjoy_reward_level=5);wall_before=s['wall_initial_health']
  self.assertTrue(self.send('starjoy_reconcile')['ok'])
  # Emulate authoritative SQL cash grant maintaining points and earned, never tiers.
  s=self.p['save']['gameplay_stats'];s['starjoy_points']+=68;s['starjoy_points_earned']+=68;self.p['revision']+=1
  self.assertTrue(self.send('starjoy_reconcile')['ok']);s=self.p['save']['gameplay_stats']
  self.assertEqual(s['starjoy_reward_level'],6);self.assertEqual(s['tower_critical_chance_pct'],3)
  after=copy.deepcopy(s);self.assertTrue(self.send('starjoy_reconcile')['ok']);self.assertEqual(s,after)
  s['starjoy_points']+=600;s['starjoy_points_earned']+=600;self.p['revision']+=1
  self.assertTrue(self.send('starjoy_reconcile')['ok']);s=self.p['save']['gameplay_stats']
  self.assertEqual(s['starjoy_reward_level'],7);self.assertEqual(s['tower_critical_chance_pct'],3);self.assertEqual(s['wall_initial_health'],wall_before+1000)
 def test_reconcile_lost_reply_and_other_player_are_isolated(self):
  s=self.p['save']['gameplay_stats'];s['starjoy_points_earned']=1518
  self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.send('starjoy_reconcile')
  after=copy.deepcopy(self.p);self.assertTrue(self.send('starjoy_reconcile')['ok']);self.assertEqual(self.p,after)
  other=self.db.profile(self.app._database_account_id('200'));other_before=copy.deepcopy(other)
  self.assertTrue(self.send('starjoy_reconcile')['ok']);self.assertEqual(other,other_before)
 def test_build_does_not_change_active_server_or_game_pointer(self):
  self.assertEqual(self.pointer,(ROOT/'server/bundles/current.json').read_bytes());self.assertEqual(self.game,(ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes())

if __name__=='__main__':unittest.main(verbosity=2)
