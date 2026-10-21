"""Pure views use signed full-inventory bonus deltas without changing accounts."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import types
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import read_csv
from archive_backend.stackable_effects import project,difference


def override():
    # The real override imports four API contracts; projection never calls the
    # request parser. Keep this test independent of an external backend checkout.
    package=types.ModuleType('_stackable_test_api');package.__path__=[]
    application=types.ModuleType('_stackable_test_api.application')
    class ApiError(ValueError):
        def __init__(self,code,status):
            super().__init__(code);self.code=code;self.status=status
    application.ApiError=ApiError
    application.ACCOUNT_ID=r'[0-9]{1,20}'
    application.OPAQUE_ID=r'[A-Za-z0-9_.:-]{8,128}'
    application._string=lambda *args: None
    path=ROOT/'server/fishing_api_overrides/match_profiles.py'
    spec=importlib.util.spec_from_file_location('_stackable_test_api.match_profiles',path)
    module=importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules,{'_stackable_test_api':package,
                                '_stackable_test_api.application':application}):
        spec.loader.exec_module(module)
    return module


class StackablePureProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=override()
        tables={}
        for name,folder in [('archive_stackable_items','存档系统'),('player_gameplay_stats','玩家档案系统')]:
            source=read_csv(ROOT/'data/csv'/folder/(name+'.csv'))
            tables[name]={r[source['key']]:r for r in source['rows']}
        cls.bundle=types.SimpleNamespace(tables=tables)
        cls.defaults={r['field_id']:r.get('default_value',0) for r in tables['player_gameplay_stats'].values()}

    def fixture(self,old,new,**extra):
        baseline={'schema_version':1,'account_id':'100','revision':1,'entitlements':{},'achievements':{},'public':{},
                  'save':{'archive':{},'content_inventory':{'lottery_ember_of_legacy':old},
                          'gameplay_stats':copy.deepcopy(self.defaults)}}
        current=copy.deepcopy(baseline);current['revision']=2
        current['save']['content_inventory']['lottery_ember_of_legacy']=new
        current['save'].update(extra)
        context={'mode':'pure','match_session_id':'pure_stackable_0001','baseline':baseline,
                 'defaults':copy.deepcopy(self.defaults),'created_at':100}
        return current,context

    def view(self,current,context,**kwargs):
        app=types.SimpleNamespace(archive=types.SimpleNamespace(bundle=self.bundle))
        before=copy.deepcopy((current,context))
        result=self.api.project(app,{'account_id':'100'},current,context,**kwargs)
        self.assertEqual((current,context),before,'Projection cannot mutate an account or its durable baseline')
        return result

    def test_pure_50_to_51_gets_threshold_and_one_copy_growth(self):
        current,context=self.fixture(50,51)
        result=self.view(current,context)
        self.assertEqual(result['save']['content_inventory']['lottery_ember_of_legacy'],1)
        self.assertEqual(result['save']['gameplay_stats']['hero_attribute_growth'],100)
        self.assertAlmostEqual(result['save']['gameplay_stats']['hero_basic_attack_growth'],.1)
        self.assertTrue(result['save']['stackable_projection_applied'])
        self.assertEqual(result['account_profile'],current,'Real archive ownership stays visible separately')

    def test_new_account_first_copy_and_new_legacy_marker_are_not_double_counted(self):
        current,context=self.fixture(0,1,archive={'stackable_items':{'legacy_ember_growth':0}})
        result=self.view(current,context)
        self.assertAlmostEqual(result['save']['gameplay_stats']['hero_basic_attack_growth'],.1)
        current,context=self.fixture(1,2,archive={'stackable_items':{'legacy_ember_growth':.1}})
        context['baseline']['save']['lottery_applied_item_effects']={'lottery_ember_of_legacy':True}
        current['save']['lottery_applied_item_effects']={'lottery_ember_of_legacy':True}
        context['baseline']['save']['gameplay_stats']['hero_basic_attack_growth']=.1
        current['save']['gameplay_stats']['hero_basic_attack_growth']=.1
        result=self.view(current,context)
        self.assertAlmostEqual(result['save']['gameplay_stats']['hero_basic_attack_growth'],.1)

    def test_negative_highest_tier_delta_is_added_before_schema_clamping(self):
        current,context=self.fixture(600,601)
        self.assertEqual(difference(current['save'],context['baseline']['save'],self.bundle)['hero_attribute_growth'],-60)
        current['save']['gameplay_stats']['hero_attribute_growth']=80
        result=self.view(current,context)
        self.assertEqual(result['save']['gameplay_stats']['hero_attribute_growth'],20,
                         'Signed -60 is applied to the independently earned +80')
        current['save']['gameplay_stats']['hero_attribute_growth']=0
        self.assertEqual(self.view(current,context)['save']['gameplay_stats']['hero_attribute_growth'],0)

    def test_pure_reconnect_keeps_the_baseline_and_a_new_match_starts_at_defaults(self):
        current,context=self.fixture(50,51)
        first=self.view(current,context)
        self.assertEqual(self.view(current,context),first)
        restarted=override()
        self.assertEqual(restarted.project(types.SimpleNamespace(archive=types.SimpleNamespace(bundle=self.bundle)),
            {'account_id':'100'},current,context),first,'A fresh backend uses the same durable match baseline')
        context['baseline']=copy.deepcopy(current)
        result=self.view(current,context,login=True)
        self.assertEqual(result['save']['gameplay_stats'],self.defaults)
        self.assertNotIn('account_profile',result)

    def test_standard_response_keeps_full_account_inventory_and_no_skip_flag(self):
        current,context=self.fixture(50,51)
        context['mode']='standard'
        result=self.view(current,context)
        self.assertEqual(result['save'],current['save'])
        self.assertNotIn('stackable_projection_applied',result['save'])
        self.assertEqual(result['account_profile'],current)

    def test_helper_matches_lua_for_both_items_and_legacy_offsets(self):
        executable=os.environ.get('LUA_EXECUTABLE')
        if not executable:
            self.skipTest('Set LUA_EXECUTABLE for cross-language parity')
        source='package.path="scripts/vscripts/?.lua;"..package.path;'
        source+='local v=require("core/json_decoder").decode(io.read("*a"));'
        source+='io.write(require("core/json_encoder").encode(require("systems/archive_stackable_items").project(v)))'
        for count in (0,1,10,11,50,51,150,600,601,1500,1501):
            with self.subTest(count=count):
                save={'content_inventory':{'lottery_ember_of_legacy':count,'welfare_zongzi':min(count,150)},
                      'archive':{'stackable_items':{'legacy_ember_growth':.1}}}
                result=subprocess.run([executable,'-e',source],cwd=ROOT,input=json.dumps(save),
                                      capture_output=True,text=True,encoding='utf-8',check=True)
                actual=json.loads(result.stdout)
                actual={} if actual==[] else actual
                expected=project(save,self.bundle)
                self.assertEqual(actual.keys(),expected.keys())
                for field,value in actual.items():
                    self.assertAlmostEqual(value,expected[field])


if __name__=='__main__':
    unittest.main()
