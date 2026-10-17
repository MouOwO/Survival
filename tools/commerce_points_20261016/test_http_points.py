"""Real packaged worker and archive receipt tests for duplicate-funded commerce."""
import copy,hashlib,json,math,os,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path[:0]=[str(ROOT/'server'),str(ROOT)]
from archive_backend.bundle import Bundle,build,read_csv
from archive_backend.service import ArchiveService,ArchiveError,object_maps
from tests.test_archive_backend import Database,App
BASE='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
RATES={'n':5,'r':25,'sr':100,'ssr':400,'ur':1000}

class SeededService(ArchiveService):
 forced_quality=None
 def settle(self,profile,command,has_pass,shared_challenge_roll=None):
  if command['kind']!='lottery_draw' or not self.forced_quality:return super().settle(profile,command,has_pass,shared_challenge_roll)
  pool=command['pool_id'];weights={r['quality']:r['weight'] for r in self.bundle.configs['lottery_quality_weights']['rows'] if r['pool_id']==pool}
  lo=1
  for q in RATES:
   hi=lo+weights.get(q,0)-1
   if q==self.forced_quality:break
   lo=hi+1
  seed=next(n for n in range(1,200000) if lo<=((n*48271)%2147483647)*10000//2147483647+1<=hi)
  payload={'configs':self.bundle.configs,'profile':profile,'command':command,'has_pass':has_pass,'seed':seed,'server_time':2000000000}
  r=subprocess.run([self.lua,'worker.lua'],cwd=self.bundle.directory,input=json.dumps(payload).encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  return object_maps(json.loads(r.stdout))

class CommercePointsTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.pointer=(ROOT/'server/bundles/current.json').read_bytes();cls.game=(ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes()
  cls.temp=tempfile.TemporaryDirectory(prefix='commerce-duplicates-');cls.addClassCleanup(cls.temp.cleanup);dest=Path(cls.temp.name)
  current=dest/build(ROOT,dest,update_game_config=False)
  if os.environ.get('COMMERCE_POINTS_BASELINE')=='1':
   d=json.loads((current/'bundle.json').read_bytes());b=ROOT/'design_refs/commerce_points_20261016/baseline'
   d['sources']['systems/lottery_http_settlement.lua']=(b/'scripts/vscripts/systems/lottery_http_settlement.lua').read_text(encoding='utf-8-sig')
   d['configs']['lottery_item_definitions']=read_csv(b/'data/csv/抽奖系统/lottery_item_definitions.csv')
   raw=json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode();current=dest/hashlib.sha256(raw).hexdigest();current.mkdir()
   (current/'bundle.json').write_bytes(raw)
   for f,s in d['sources'].items():t=current/f;t.parent.mkdir(parents=True,exist_ok=True);t.write_text(s,encoding='utf-8',newline='\n')
  cls.bundle=Bundle(current);cls.bundle.compatible_config_hashes[BASE]={'commands':frozenset({'commerce_purchase','lottery_snapshot'}),'upgrade_commands':frozenset()}
  shutil.copytree(ROOT/'server/bundles'/BASE,dest/BASE)
  cls.lua=os.environ.get('LUA_EXECUTABLE','C:/Program Files/lua/bin/lua5.1.exe')
 def setUp(self):
  self.db=Database(self.bundle);self.app=App(self.db);self.service=SeededService(self.app,self.bundle,self.lua);self.n=0
  self.p=self.db.profile(self.app._database_account_id('100'));s=self.p['save'];s['content_inventory']={r['item_id']:r.get('max_owned',1) for r in self.bundle.configs['lottery_item_definitions']['rows']}
  s['content_inventory'].update(lottery_ticket=100,special_lottery_ticket=100)
  s['archive']={'commerce':{'balances':{'shop_points':0,'shop_gold':1000000}},'lottery_state':{'pools':{'map':{'draws':100}}}}
  s['gameplay_stats'].update(starjoy_points=37,starjoy_points_earned=1000,starjoy_reward_level=5)
 def payload(self,kind,account='100',digest=None,**fields):
  self.n+=1;operation='points-match:'+kind+':'+fields['request_id'] if kind.startswith('lottery_') and 'request_id' in fields else 'points-match:operation:'+str(self.n);return {'account_id':account,'config_hash':digest or self.bundle.hash,'command':{'kind':kind,'id':operation,**fields}}
 def send(self,kind,**fields):return self.service.command(self.payload(kind,**fields))
 def draw(self,q='n',count=1,request_id=None,pool=None):
  self.service.forced_quality=q;return self.send('lottery_draw',pool_id=pool or ('dragon_knight' if q=='ur' else 'map'),count=count,request_id=request_id or 'points-draw-'+str(self.n+1))
 def test_five_quality_rates_credit_only_mall_points(self):
  for q,rate in RATES.items():
   with self.subTest(quality=q):
    self.setUp();before=copy.deepcopy(self.p);r=self.draw(q);self.assertTrue(r['ok'],r)
    item=r['response']['results'][0];self.assertEqual(item['quality'],q);self.assertTrue(item['duplicate']);self.assertEqual(item['converted_points'],rate);self.assertEqual(item['converted_currency'],'shop_points')
    self.assertEqual(self.p['save']['archive']['commerce']['balances']['shop_points'],rate)
    for f in ['starjoy_points','starjoy_points_earned','starjoy_reward_level']:self.assertEqual(self.p['save']['gameplay_stats'][f],before['save']['gameplay_stats'][f])
 def test_ten_draw_points_equal_exact_reward_sum_and_one_ticket_debit(self):
  r=self.draw('n',count=10);self.assertTrue(r['ok'],r);items=r['response']['results'];self.assertEqual(len(items),10)
  total=sum(RATES[i['quality']] for i in items);self.assertEqual(self.p['save']['archive']['commerce']['balances']['shop_points'],total);self.assertEqual(r['response']['shop_points'],total)
  self.assertEqual(self.p['save']['content_inventory']['lottery_ticket'],90)
 def test_duplicates_can_immediately_buy_formal_shop_item(self):
  product=self.bundle.tables['commerce_catalog']['video_p117'];self.p['save']['content_inventory'].pop(product['item_id'],None)
  self.assertTrue(self.draw('ssr')['ok']);self.assertEqual(self.p['save']['archive']['commerce']['balances']['shop_points'],400)
  r=self.send('commerce_purchase',sku=product['sku'],request_id='points-buy-real-item');self.assertTrue(r['ok'],r)
  self.assertEqual(self.p['save']['archive']['commerce']['balances']['shop_points'],400-product['price']);self.assertEqual(self.p['save']['content_inventory'][product['item_id']],1)
  self.assertEqual(self.p['save']['gameplay_stats']['starjoy_points'],37)
 def test_lost_reply_and_repeated_request_never_double_credit(self):
  self.db.lose_reply=True
  with self.assertRaises(TimeoutError):self.draw('r',request_id='points-lost-reply')
  after=copy.deepcopy(self.p);r=self.draw('r',request_id='points-lost-reply');self.assertTrue(r['ok'],r);self.assertEqual(self.p,after)
  self.assertEqual(self.p['save']['archive']['commerce']['balances']['shop_points'],25)
 def test_other_player_and_read_snapshots_cannot_award(self):
  other=self.db.profile(self.app._database_account_id('200'));before=copy.deepcopy(other);self.assertTrue(self.draw('sr')['ok']);self.assertEqual(other,before)
  after=copy.deepcopy(self.p);snapshot=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash});self.assertTrue(snapshot['ok']);self.assertEqual(self.p,after)
  for s in snapshot['snapshots']:
   self.assertEqual(s['shop_points'],100);self.assertEqual(s['starjoy_points'],37)
   self.assertTrue(all(i['converted_currency']=='shop_points' for i in s['items']))
 def test_older_client_snapshot_matches_its_legacy_draw_currency(self):
  old=self.service.lottery_snapshot({'account_id':'100','config_hash':BASE});self.assertTrue(old['ok'],old)
  self.assertTrue(all('shop_points' not in s for s in old['snapshots']))
  self.assertTrue(all('converted_currency' not in i for s in old['snapshots'] for i in s['items']))
  current=self.service.lottery_snapshot({'account_id':'100','config_hash':self.bundle.hash});self.assertTrue(current['ok'])
  self.assertTrue(all(s['shop_points']==0 for s in current['snapshots']))
  self.assertTrue(all(i['converted_currency']=='shop_points' for s in current['snapshots'] for i in s['items']))
 def test_new_item_does_not_convert_to_points(self):
  for r in self.bundle.configs['lottery_item_definitions']['rows']:self.p['save']['content_inventory'].pop(r['item_id'],None)
  r=self.draw('r');self.assertTrue(r['ok'],r);self.assertFalse(r['response']['results'][0]['duplicate']);self.assertEqual(self.p['save']['archive']['commerce']['balances']['shop_points'],0)
 def test_wallet_overflow_rolls_back_ticket_inventory_and_save(self):
  self.p['save']['archive']['commerce']['balances']['shop_points']=9007199254740991;before=copy.deepcopy(self.p)
  r=self.draw('n');self.assertFalse(r['ok']);self.assertEqual(self.p,before)
 def test_gold_paused_for_current_and_older_client_without_mutation(self):
  for digest in [self.bundle.hash,BASE]:
   for sku in ['video_p037','video_p038']:
    with self.subTest(digest=digest,sku=sku):
     before=copy.deepcopy(self.p);r=self.send('commerce_purchase',digest=digest,sku=sku,request_id='pause-gold-'+str(self.n+1));self.assertFalse(r['ok']);self.assertEqual(r['error'],'shop_gold_not_open');self.assertEqual(self.p,before)
 def test_completed_old_gold_receipt_remains_queryable(self):
  request='old-gold-receipt';payload=self.payload('commerce_purchase',digest=BASE,sku='video_p037',request_id=request);cmd=self.service.validate(payload['command']);key=(self.app._database_account_id('100'),cmd['id'])
  self.db.ops[key]={'command':cmd,'done':True,'fingerprint':hashlib.sha256(json.dumps(cmd,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest(),'hash':BASE,'pass':False,'response':{'ok':True,'sku':'video_p037','currency':'shop_gold','price':10,'balance':990}}
  before=copy.deepcopy(self.p);r=self.service.command(payload);self.assertTrue(r['ok'],r);self.assertEqual(r['response']['balance'],990);self.assertEqual(self.p,before)
 def test_client_cannot_supply_points(self):
  before=copy.deepcopy(self.p)
  with self.assertRaises(ArchiveError):self.send('lottery_draw',pool_id='map',count=1,request_id='points-forge',shop_points=99999)
  self.assertEqual(self.p,before)
 def test_active_pointers_unchanged(self):
  self.assertEqual(self.pointer,(ROOT/'server/bundles/current.json').read_bytes());self.assertEqual(self.game,(ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua').read_bytes())
if __name__=='__main__':unittest.main(verbosity=2)
