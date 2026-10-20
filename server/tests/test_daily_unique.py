"""Real daily worker claims and exact contribution repair previews."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT),str(ROOT/'server')]
from archive_backend.bundle import Bundle,build
from archive_backend.service import ArchiveService
from archive_backend.daily_unique import preview,catalog,render_constraint_sql
from server.tests.test_archive_backend import Database,App


class DayDatabase(Database):
    today=19900
    def rpc(self,name,payload):
        result=super().rpc(name,payload)
        if name=='archive_prepare' and not result.get('done'):
            operation=self.ops[(payload['p_account'],payload['p_id'])]
            operation['command'].update(today=self.today,day_key=str(self.today))
            result=self.resume(payload['p_account'],payload['p_id'])
        return result


class DailyUniqueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua=os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1') or 'C:/Program Files/lua/bin/lua5.1.exe'
        cls.temp=tempfile.TemporaryDirectory(prefix='daily-unique-worker-');cls.addClassCleanup(cls.temp.cleanup)
        digest=build(ROOT,Path(cls.temp.name),False);cls.bundle=Bundle(Path(cls.temp.name)/digest)

    def setUp(self):
        self.db=DayDatabase(self.bundle);self.app=App(self.db);self.service=ArchiveService(self.app,self.bundle,self.lua)
        self.account=self.app._database_account_id('100');self.profile=self.db.profile(self.account)
        self.profile['entitlements']['archive_pass']={'active':False}
        self.profile['save']['content_inventory']={}
        self.profile['save']['archive']={'daily_rewards':{'first_day':19900,'claimed':{},'count':0,'item_counts':{}},
            'commerce':{'balances':{'shop_points':7,'u_coin':11}},'unrelated':{'preserve':True}}
        self.n=0

    def claim(self,day,pass_active=False,count=None,token=None):
        self.n+=1
        self.db.today=day
        if count is not None:self.profile['save']['archive']['daily_rewards']['count']=count
        self.profile['entitlements']['archive_pass']={'active':pass_active}
        payload={'account_id':'100','config_hash':self.bundle.hash,'command':{
            'id':token or 'daily-unique:test:'+str(self.n),'kind':'daily_claim','target_day':day}}
        return self.service.command(payload),payload

    def test_first_three_rewards_store_one_apply_once_and_convert_two_then_all_three(self):
        stats=copy.deepcopy(self.profile['save']['gameplay_stats'])
        first,payload=self.claim(19900)
        self.assertTrue(first['ok'],first)
        daily=self.profile['save']['archive']['daily_rewards']
        self.assertEqual(daily['item_counts']['daily_growth_gem'],1)
        self.assertEqual(self.profile['save']['gameplay_stats']['hero_attack_per_second'],stats['hero_attack_per_second']+1)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances'],{'shop_points':57,'u_coin':11})
        after=copy.deepcopy(self.profile)
        self.assertEqual(self.service.command(payload),first);self.assertEqual(self.profile,after)
        second,_=self.claim(19901,count=7)
        self.assertTrue(second['ok'],second)
        self.assertEqual(daily['item_counts']['daily_growth_gem'],1)
        self.assertEqual(self.profile['save']['gameplay_stats']['hero_attack_per_second'],stats['hero_attack_per_second']+1)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],132)

    def test_complete_schedule_21_claims_unique_9_effects_and_real_reward_conversion(self):
        # Each of nine R rewards occurs three times, with three awarded copies.
        # 81 real copies -> 9 unlocks + 72 duplicates, not 81 stored upgrades.
        for day in range(19900,19921):self.assertTrue(self.claim(day,True)[0]['ok'])
        saved=self.profile['save'];counts=saved['archive']['daily_rewards']['item_counts']
        self.assertEqual(len(counts),12);self.assertTrue(all(value==1 for value in counts.values()))
        self.assertEqual(saved['archive']['commerce']['balances']['shop_points'],7+72*25)
        rows,_=catalog(self.bundle)
        expected={row['field_id']:row['default_value'] for row in self.bundle.configs['player_gameplay_stats']['rows']}
        for row in rows:
            for field,value in zip(row['effect_ids'],row['effect_values']):expected[field]=expected.get(field,0)+float(value)
        for field in ('hero_attack_per_second','wall_health_regen_per_second','hero_attributes_per_second',
                      'tower_attack_flat','wall_initial_health','initial_wood','wall_damage_block',
                      'hero_initial_attributes','initial_gold','starjoy_points'):
            self.assertEqual(saved['gameplay_stats'][field],expected[field],field)
        # One more claim after all three milestones cannot award 3*400 points.
        before=saved['archive']['commerce']['balances']['shop_points']
        self.assertTrue(self.claim(19921,True)[0]['ok'])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],before+75)

    def test_expired_pass_keeps_milestones_and_purchase_init_does_not_grant_or_convert(self):
        daily=self.profile['save']['archive']['daily_rewards'];daily['count']=21
        before=copy.deepcopy(self.profile)
        self.profile['entitlements']['archive_pass']={'active':True}
        init=self.service.command({'account_id':'100','config_hash':self.bundle.hash,
            'command':{'id':'daily-unique:init:purchase','kind':'daily_init'}})
        self.assertTrue(init['ok']);self.assertEqual(self.profile['save']['archive']['daily_rewards']['item_counts'],{})
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],7)
        self.assertTrue(self.claim(19900,True)[0]['ok'])
        counts=self.profile['save']['archive']['daily_rewards']['item_counts']
        self.assertTrue(all(counts[id]==1 for id in ('daily_wealth_talisman','daily_ancient_tree','daily_forest_origin')))
        before_stats=copy.deepcopy(self.profile['save']['gameplay_stats'])
        wallet=self.profile['save']['archive']['commerce']['balances']['shop_points']
        self.assertTrue(self.claim(19901,False)[0]['ok'])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['shop_points'],wallet+50)
        for field in ('starjoy_points','starjoy_points_earned','hero_attribute_bonus_pct'):
            self.assertEqual(self.profile['save']['gameplay_stats'][field],before_stats[field])

    def test_lost_reply_and_rejected_same_day_do_not_duplicate_points_or_stats(self):
        self.db.lose_reply=True
        with self.assertRaises(TimeoutError):self.claim(19900,token='daily-unique:lost:claim')
        committed=copy.deepcopy(self.profile)
        result,_=self.claim(19900,token='daily-unique:lost:claim')
        self.assertTrue(result['ok']);self.assertEqual(self.profile,committed)
        result,_=self.claim(19900,token='daily-unique:same:day')
        self.assertFalse(result['ok']);self.assertEqual(self.profile,committed)

    def test_unrepaired_multi_count_blocks_claim_and_init_without_dropping_old_effects(self):
        self.profile['save']['archive']['daily_rewards']['item_counts']={'daily_growth_gem':3}
        self.profile['save']['gameplay_stats']['hero_attack_per_second']=3
        before=copy.deepcopy(self.profile)
        result,_=self.claim(19900)
        self.assertFalse(result['ok']);self.assertEqual(result['error'],'daily_unique_migration_required')
        self.assertEqual(self.profile,before)
        result=self.service.command({'account_id':'100','config_hash':self.bundle.hash,
            'command':{'id':'daily-unique:init:old','kind':'daily_init'}})
        self.assertEqual(result['error'],'daily_unique_migration_required');self.assertEqual(self.profile,before)

    def test_exact_preview_deducts_only_extra_daily_contributions_compensates_once(self):
        saved=self.profile['save'];daily=saved['archive']['daily_rewards']
        daily['item_counts']={'daily_growth_gem':7,'daily_wood_gem':3,'daily_wealth_talisman':1}
        saved['gameplay_stats'].update(hero_attack_per_second=107,initial_wood=109)
        # initial wood: default10 + daily wood9 + monthly50 + other-source40.
        before=copy.deepcopy(self.profile);plan=preview(self.profile,self.bundle)
        self.assertEqual(self.profile,before)
        self.assertEqual(plan['deltas'],{'hero_attack_per_second':-6,'initial_wood':-6})
        self.assertEqual(plan['gameplay_stats']['hero_attack_per_second'],101)
        self.assertEqual(plan['gameplay_stats']['initial_wood'],103)
        self.assertEqual(plan['converted_points'],200)
        self.assertEqual(plan['archive']['commerce']['balances'],{'shop_points':207,'u_coin':11})
        repaired=copy.deepcopy(self.profile);repaired['save'].update(archive=plan['archive'],gameplay_stats=plan['gameplay_stats'])
        again=preview(repaired,self.bundle)
        self.assertEqual(again['converted_points'],0);self.assertFalse(again['deltas']);self.assertEqual(again['changed_items'],0)

    def test_ambiguous_or_insufficient_effect_budget_refuses_without_touching_data(self):
        saved=self.profile['save'];saved['archive']['daily_rewards']['item_counts']={'daily_growth_gem':3}
        for value in (0,2,None):
            with self.subTest(value=value):
                saved['gameplay_stats']['hero_attack_per_second']=value
                before=copy.deepcopy(self.profile)
                with self.assertRaises(ValueError):preview(self.profile,self.bundle)
                self.assertEqual(self.profile,before)
        saved['gameplay_stats']['hero_attack_per_second']=3
        saved['content_inventory']['daily_growth_gem']=1
        with self.assertRaisesRegex(ValueError,'dual_inventory'):preview(self.profile,self.bundle)
        saved['content_inventory']={};saved['archive']['daily_rewards']['item_counts']={'daily_ancient_tree':2}
        with self.assertRaisesRegex(ValueError,'effect_requires_review'):preview(self.profile,self.bundle)

    def test_database_whitelist_contains_all_ids_and_both_historical_aliases(self):
        ddl=render_constraint_sql(self.bundle)
        self.assertIn('archive_unique_points_20261019_check',ddl)
        for identity in ('daily_growth_gem','daily_forest_origin','lottery_nature_crystal',
                         'lottery_flame_crystal','lottery_bombardment_crystal','lottery_burst_crystal'):
            self.assertIn(identity,ddl)

    def test_daily_projection_has_all_12_unlocks_and_keeps_three_awarded_copies_distinct(self):
        def project():
            source='package.path='+json.dumps(self.bundle.directory.as_posix()+'/?.lua;')+'..package.path;'
            source+='local input=require("core/json_decoder").decode(io.read("*a"));'
            source+='for name,config in pairs(input.configs) do local m={rows=config.rows,by_id={}};for _,row in ipairs(config.rows) do m.by_id[row[config.key]]=row end;package.loaded["config/generated/"..name]=m end;'
            source+='local p=input.profile;local d=require("systems/archive_daily_rewards");'
            source+='io.write(require("core/json_encoder").encode({rows=d.points(p),snapshot=d.snapshot(p,19900,false)}))'
            result=subprocess.run([self.lua,'-e',source],input=json.dumps({'profile':self.profile,'configs':self.bundle.configs}).encode(),capture_output=True,check=True)
            return json.loads(result.stdout)
        fresh=project();self.assertEqual(len(fresh['rows']),12)
        self.assertTrue(all(row['count']==0 and row['unlocked']==0 and row['count_known']==1
                            and row['max_owned']==1 and row['target']==1 for row in fresh['rows']))
        self.assertTrue(self.claim(19900)[0]['ok'])
        after=project();growth=next(row for row in after['rows'] if row['id']=='daily_growth_gem')
        self.assertEqual((growth['count'],growth['unlocked'],growth['duplicate_points'],growth['duplicate_currency']),(1,1,25,'shop_points'))
        reward=after['snapshot']['cycle'][0]['rewards'][0]
        self.assertEqual((reward['count'],reward['max_owned'],reward['owned_count'],reward['duplicate_points']),(3,1,1,25))

    def test_wallet_overflow_cannot_apply_first_unlock_effect_before_failed_save(self):
        self.profile['save']['archive']['commerce']['balances']['shop_points']=9007199254740990
        before=copy.deepcopy(self.profile)
        result,_=self.claim(19900)
        self.assertFalse(result['ok']);self.assertEqual(result['error'],'settlement_failed')
        self.assertEqual(self.profile,before)


if __name__=='__main__':unittest.main(verbosity=2)
