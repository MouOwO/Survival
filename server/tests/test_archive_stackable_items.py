"""Stackable welfare goods keep real quantities beside 96 unique point goods."""
import copy
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import build,Bundle
from archive_backend.unique_points import catalog,preview,limit_snapshot_ownership
from archive_backend.daily_unique import catalog as daily_catalog,render_constraint_sql


class StackableItemTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='stackable-items-test-')
        cls.addClassCleanup(cls.temp.cleanup)
        base=Path(cls.temp.name)
        cls.bundle=Bundle(base/build(ROOT,base,False))

    def test_only_ember_is_excluded_from_unique_points(self):
        items,aliases=catalog(self.bundle)
        self.assertEqual(len(items),96)
        self.assertNotIn('lottery_ember_of_legacy',items)
        self.assertNotIn('welfare_zongzi',items)
        self.assertEqual(items['lottery_nature_crystal'],5)
        ember=self.bundle.tables['lottery_item_definitions']['lottery_ember_of_legacy']
        self.assertEqual(ember['max_owned'],0)
        self.assertEqual(ember['duplicate_points'],0)
        self.assertFalse(ember.get('effect_ids'),'New quantities must not repeatedly add static stats')

    def test_unique_repair_preserves_all_ember_copies_without_compensation(self):
        inventory={'lottery_ember_of_legacy':1501,'welfare_zongzi':150,'lottery_nature_crystal':3}
        archive={'commerce':{'balances':{'shop_points':7}}}
        before=copy.deepcopy((inventory,archive))
        result=preview(inventory,archive,*catalog(self.bundle))
        self.assertEqual((inventory,archive),before)
        self.assertEqual(result['content_inventory']['lottery_ember_of_legacy'],1501)
        self.assertEqual(result['content_inventory']['welfare_zongzi'],150)
        self.assertEqual(result['converted_points'],10)
        self.assertEqual(result['archive']['commerce']['balances']['shop_points'],17)

    def test_public_unique_projection_does_not_clamp_ember(self):
        result={'snapshots':[{'items':[
            {'id':'lottery_ember_of_legacy','owned_count':1600,'max_owned':0,'at_max_owned':False},
            {'id':'lottery_nature_crystal','owned_count':3,'max_owned':1},
        ]}]}
        limit_snapshot_ownership(result,self.bundle)
        ember,other=result['snapshots'][0]['items']
        self.assertEqual((ember['owned_count'],ember['max_owned'],ember['at_max_owned']),(1600,0,False))
        self.assertEqual((other['owned_count'],other['max_owned']),(1,1))

    def test_daily_duplicate_rates_still_use_unique_quality_rates(self):
        rows,rates=daily_catalog(self.bundle)
        self.assertEqual(len(rows),12)
        self.assertEqual(rates['ur'],1000)

    def test_database_whitelist_excludes_ember_and_keeps_other_unique_items(self):
        sql=render_constraint_sql(self.bundle)
        payload=json.loads(re.search(r"rules constant jsonb := '(.*?)'::jsonb",sql).group(1))
        self.assertEqual(len(payload['lottery']),96)
        self.assertNotIn('lottery_ember_of_legacy',payload['lottery'])
        self.assertIn('lottery_nature_crystal',payload['lottery'])
        migration=(ROOT/'server/aliyun/database/target/202610210002_archive_stackable_items.sql').read_text('utf-8')
        self.assertIn("identity='welfare_zongzi' AND amount>150",migration)
        self.assertIn("amount>9007199254740991",migration)
        self.assertIn('archive_stackable_items_20261021_check',migration)

    def test_item_names_and_descriptions_match_authoritative_rules(self):
        rules=self.bundle.configs['archive_stackable_items']['rows']
        base={r['item_id']:r for r in rules if r['mode']=='per_copy'}
        self.assertEqual(base['welfare_zongzi']['effect_value'],.05)
        self.assertEqual(base['lottery_ember_of_legacy']['effect_value'],.1)
        self.assertEqual(base['welfare_zongzi']['max_owned'],150)
        self.assertEqual(base['lottery_ember_of_legacy']['max_owned'],0)
        self.assertIn('最高档',base['lottery_ember_of_legacy']['description'])


if __name__=='__main__':
    unittest.main()
