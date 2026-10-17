"""Offline published-bundle routing tests: real Lua workers and an in-memory RPC.

No database, SSH, order API or account writes. Both immutable bundle versions are
copied into a temporary sibling layout because recorded lottery replays resolve
their historical bundle beside the current bundle in production.
"""
from __future__ import annotations
import copy
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/shop_pricing_half_20261017'
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import Bundle
from archive_backend.config_compatibility import accepts,upgrades
from archive_backend.service import ArchiveService
from tests.test_archive_backend import Database,App

class RecordingDatabase(Database):
    def __init__(self,bundle):
        super().__init__(bundle);self.calls=[]
    def rpc(self,name,payload):
        self.calls.append((name,copy.deepcopy(payload)))
        return super().rpc(name,payload)

class PurchaseUpgradeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        plan=json.loads((OUT/'plan.json').read_bytes())
        cls.parent_hash=plan['parent_bundle'];cls.candidate_hash=plan['bundle']
        parent=OUT/'baseline/archive/addon/server/bundles'/cls.parent_hash
        candidate=OUT/'candidate/archive/addon/server/bundles'/cls.candidate_hash
        cls.temporary=tempfile.TemporaryDirectory(prefix='shop-price-routing-')
        cls.addClassCleanup(cls.temporary.cleanup)
        directory=Path(cls.temporary.name)
        for source in (parent,candidate):shutil.copytree(source,directory/source.name)
        cls.old=Bundle(directory/cls.parent_hash);cls.new=Bundle(directory/cls.candidate_hash)
        cls.lua=os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1') or shutil.which('lua')
        if not cls.lua:
            known=Path('C:/Program Files/lua/bin/lua5.1.exe')
            if known.is_file():cls.lua=str(known)
        assert cls.lua,'A native Lua 5.1 interpreter is required; no production services are used'

    def setUp(self):
        self.database=RecordingDatabase(self.new);self.app=App(self.database)
        self.service=ArchiveService(self.app,self.new,self.lua)
        self.account=self.app._database_account_id('100');self.profile=self.database.profile(self.account)
        self.profile['save']['archive']['commerce']={'balances':{'u_coin':10000,'shop_points':10000}}
        self.profile['save']['content_inventory']={'lottery_ticket':100}
        self.sku='video_p001'

    def purchase(self,token='half_price_upgrade_01'):
        return {'account_id':'100','config_hash':self.old.hash,
            'command':{'id':'price:purchase:01','kind':'commerce_purchase','sku':self.sku,'request_id':token}}

    def trace_workers(self,records):
        original=ArchiveService.settle
        def run(reducer,profile,command,has_pass,*args):
            records.append({'kind':command['kind'],'bundle':reducer.bundle.hash})
            return original(reducer,profile,command,has_pass,*args)
        return patch.object(ArchiveService,'settle',autospec=True,side_effect=run)

    def test_existing_catalog_display_and_unfinished_purchase_use_same_new_half_price(self):
        # Record an intent against the old release, then interrupt before any
        # worker runs or any wallet debit commits. The new release must resume it.
        old_service=ArchiveService(self.app,self.old,self.lua)
        with patch.object(old_service,'finish_prepared',return_value={'ok':False,'error':'test_interrupted_before_settlement'}):
            self.assertFalse(old_service.command(self.purchase())['ok'])
        pending=self.database.ops[(self.account,'commerce:half_price_upgrade_01')]
        self.assertFalse(pending['done']);self.assertEqual(pending['hash'],self.old.hash)
        traces=[]
        with self.trace_workers(traces):
            catalog=self.service.command({'account_id':'100','config_hash':self.old.hash,
                'command':{'id':'price:catalog:01','kind':'commerce_catalog'}})
            result=self.service.command(self.purchase())
        self.assertTrue(catalog['ok'],catalog);self.assertTrue(result['ok'],result)
        displayed=next(p['price'] for p in catalog['products'] if p['sku']==self.sku)
        original=self.old.tables['commerce_catalog'][self.sku]['price']
        self.assertEqual(displayed*2,original)
        self.assertEqual(result['response']['price'],displayed)
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['u_coin'],10000-displayed)
        self.assertEqual([r for r in traces if r['kind']=='commerce_purchase'],
                         [{'kind':'commerce_purchase','bundle':self.new.hash}])
        receipt=self.database.ops[(self.account,'commerce:half_price_upgrade_01')]
        self.assertEqual(receipt['hash'],self.old.hash,'The recorded intent hash remains immutable')
        self.assertEqual(sum(name=='archive_commit_lottery' for name,_ in self.database.calls),1)

    def test_original_completed_receipt_returns_original_price_without_second_settlement(self):
        request=self.purchase('old_completed_price_01')
        old_service=ArchiveService(self.app,self.old,self.lua)
        original=old_service.command(request)
        self.assertTrue(original['ok'],original)
        original_price=self.old.tables['commerce_catalog'][self.sku]['price']
        self.assertEqual(original['response']['price'],original_price)
        saved=copy.deepcopy(self.profile);receipts=copy.deepcopy(self.database.ops)
        commits=sum(name=='archive_commit_lottery' for name,_ in self.database.calls)
        with patch.object(ArchiveService,'settle',side_effect=AssertionError('A completed receipt must not settle again')):
            retry=self.service.command(request)
        self.assertEqual(retry['response'],original['response'])
        self.assertEqual(retry['response']['price'],original_price)
        self.assertEqual(self.profile,saved);self.assertEqual(self.database.ops,receipts)
        self.assertEqual(sum(name=='archive_commit_lottery' for name,_ in self.database.calls),commits)

    def test_historical_lottery_still_executes_recorded_bundle(self):
        self.assertTrue(accepts(self.new,self.old.hash,'lottery_draw'))
        self.assertFalse(upgrades(self.new,self.old.hash,'lottery_draw'))
        traces=[]
        with self.trace_workers(traces):
            result=self.service.command({'account_id':'100','config_hash':self.old.hash,
                'command':{'id':'price:lottery:01','kind':'lottery_draw','pool_id':'map','count':1,'request_id':'old_lottery_01'}})
        self.assertTrue(result['ok'],result)
        self.assertEqual(traces,[{'kind':'lottery_draw','bundle':self.old.hash}])
        self.assertEqual(self.profile['save']['archive']['commerce']['balances']['u_coin'],10000)
        old_cost=self.old.tables['lottery_pool_definitions']['map']['single_cost']
        self.assertEqual(self.profile['save']['content_inventory']['lottery_ticket'],100-old_cost)

    def test_only_current_online_parent_gains_commerce_upgrade_and_old_rules_are_exact(self):
        original=json.loads((self.old.directory/'bundle.json').read_bytes()).get('compatible_config_hashes',{})
        updated=json.loads((self.new.directory/'bundle.json').read_bytes()).get('compatible_config_hashes',{})
        self.assertEqual(len(original),8)
        self.assertEqual(set(updated),set(original)|{self.old.hash})
        for digest,rule in original.items():
            self.assertEqual(updated[digest],rule,'An older approved rule changed: '+digest)
        self.assertEqual(updated[self.old.hash]['upgrade_commands'],['commerce_purchase'])
        self.assertTrue(upgrades(self.new,self.old.hash,'commerce_purchase'))
        self.assertTrue(accepts(self.new,self.old.hash,'commerce_catalog'))
        self.assertTrue(accepts(self.new,self.old.hash,'lottery_draw'))
        self.assertFalse(upgrades(self.new,self.old.hash,'lottery_draw'))
        self.assertFalse(upgrades(self.new,self.old.hash,'lottery_exchange'))
        self.assertFalse(accepts(self.new,'0'*64,'commerce_purchase'))

if __name__=='__main__':
    runner=unittest.main(exit=False)
    result=runner.result
    report={'status':'PASS' if result.wasSuccessful() else 'FAIL','tests':result.testsRun,
        'failures':len(result.failures),'errors':len(result.errors),
        'candidate':getattr(PurchaseUpgradeTests,'candidate_hash',None),
        'parent':getattr(PurchaseUpgradeTests,'parent_hash',None),
        'database_connections':0,'ssh_connections':0,'real_purchases':0}
    (OUT/'archive_purchase_upgrade_tests.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    sys.exit(0 if result.wasSuccessful() else 1)
