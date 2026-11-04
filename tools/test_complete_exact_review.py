"""Pure exact-review rejection/semantics tests; no repo writes or SDK."""
from pathlib import Path
import copy,hashlib,importlib.util,json,unittest

SPEC=importlib.util.spec_from_file_location('exact_review',Path(__file__).parent/'complete_delivery_release_20261103/exact_review.py')
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)
PATH='data/ui/ui_compact_native08_observation_20261104.json'

def chain():
    first={'format':1,'generation':1,'parent_sha256':None,'records':[{'id':1,'key':'old','domain':'test','kind':'state','business_id':'old','tombstone':False}],
           'fields':[{'id':1,'name':'count','kind':'uint','min':0,'max':4294967295,'default':'unknown'}]}
    a=m.canonical(first);second=copy.deepcopy(first);second['generation']=2;second['parent_sha256']=m.sha(a)
    second['records'].append({'id':2,'key':'new','domain':'test','kind':'state','business_id':'new','tombstone':False})
    b=m.canonical(second);raws={'data/ui/registry_history/'+m.sha(x)+'.json':x for x in (a,b)}
    manifest={'registry_sha256':m.sha(b),'source_hashes':{p:m.sha(x) for p,x in raws.items()}}
    return b,manifest,raws

class ExactReviewTests(unittest.TestCase):
    def test_metadata_and_comments_are_not_runtime_read_calls(self):
        text='var source={"'+PATH+'":"hash","note":"LoadFile(\\\"'+PATH+'\\\")"};\n// LoadFile("'+PATH+'")\n'
        self.assertEqual(m.read_sites(text,{PATH}),[])
        self.assertEqual(m.read_sites('-- io.open("'+PATH+'")\nlocal text=[[LoadFile("'+PATH+'")]]',{PATH},'lua'),[])
    def test_javascript_decrement_does_not_hide_following_read_as_lua_comment(self):
        sites=m.read_sites('var count=1; --count; LoadFile("'+PATH+'")',{PATH})
        self.assertEqual(len(sites),1);self.assertTrue(sites[0]['candidate_json_read'])
    def test_actual_direct_loaders_are_rejected_not_metadata(self):
        for text in ['LoadKeyValues("'+PATH+'")','fs.readFileSync("'+PATH+'", "utf8")','io.open("'+PATH+'")','$.AsyncWebRequest("file://{resources}/'+PATH+'")']:
            sites=m.read_sites(text,{PATH});self.assertEqual(len(sites),1)
            self.assertTrue(sites[0]['candidate_json_read'] or sites[0]['uncertain_data_ui_read'])
    def test_dynamic_namespace_read_is_uncertain_and_failclosed(self):
        for text in ['io.open("data/ui/" .. name)', 'var prefix="data/ui/";readFileSync(computePath())']:
            sites=m.read_sites(text,{PATH});self.assertTrue(any(s['uncertain_data_ui_read'] for s in sites))
        self.assertFalse(m.read_sites('LoadKeyValues("scripts/npc/test.txt")',{PATH})[0]['candidate_json_read'])
    def test_exact_chain_parses_every_node_and_checks_current_raw_sha(self):
        raw,manifest,history=chain();checks=m.validate_lineage(raw,manifest,history)
        self.assertEqual(checks['nodes_parsed'],2);self.assertTrue(checks['exact_parent_chain'])
        bad=dict(history);bad.pop(next(iter(bad)))
        with self.assertRaisesRegex(ValueError,'history_exact'):m.validate_lineage(raw,manifest,bad)
    def test_same_prefix_extra_node_is_not_ignored(self):
        raw,manifest,history=chain();history['data/ui/registry_history/not-declared.json']=b'{}'
        with self.assertRaisesRegex(ValueError,'history_exact'):m.validate_lineage(raw,manifest,history)
    def test_sha_named_history_content_cannot_be_relabelled(self):
        raw,manifest,history=chain();name=next(iter(history));history[name]+=b' '
        with self.assertRaisesRegex(ValueError,'filename_or_manifest_sha'):m.validate_lineage(raw,manifest,history)
    def test_field_semantics_and_old_record_ids_cannot_change(self):
        for change in ('field','record'):
            raw,manifest,history=chain();node=json.loads(raw)
            if change=='field':node['fields'][0]['kind']='sint'
            else:node['records'][0]['key']='reused'
            replacement=m.canonical(node);history.pop('data/ui/registry_history/'+m.sha(raw)+'.json');history['data/ui/registry_history/'+m.sha(replacement)+'.json']=replacement
            manifest['registry_sha256']=m.sha(replacement);manifest['source_hashes']={p:m.sha(v) for p,v in history.items()}
            with self.assertRaises(ValueError):m.validate_lineage(replacement,manifest,history)
    def test_worktree_or_scope_retag_cannot_change_selected_sources(self):
        with self.assertRaisesRegex(ValueError,'scope_source_revisions'):
            m.make_reviews({'observed_commits':{'game':'a'*40,'content':'b'*40}},'f'*64,{'game':'c'*40,'content':'b'*40,'operator':'d'*40},{},{},{},'e'*64)
    def test_extra_unmapped_under_familiar_directory_still_blocks(self):
        pins={'game':'a'*40,'content':'b'*40,'operator':'c'*40}
        scope={'observed_commits':{k:pins[k] for k in ('game','content')},'decisions':[{'inventory_status':'UNMAPPED_SOURCE_PENDING','source':{'path':'data/ui/registry_history/unreviewed.json'}}]}
        with self.assertRaisesRegex(ValueError,'exact_reviewed_paths'):
            m.make_reviews(scope,'f'*64,pins,{m.MANIFEST:b'{"source_hashes":{}}'},{},{},'e'*64)


class LotteryBuildInputReviewTests(unittest.TestCase):
    def fixture(self):
        public={'schema':1,'snapshots':[{'selected_pool_id':pool,'items':[{'id':'same','name':'public','quantity':1}]} for pool in ('map','cultivation','dragon_knight','summer')]}
        text=json.dumps(public,sort_keys=True,separators=(',',':'))
        seed={'md5':hashlib.md5(text.encode()).hexdigest(),'config_hash':'a'*64,'catalog_json':text}
        raw=m.canonical(seed)
        return raw,{'source_hashes':{m.LOTTERY_SEED:m.sha(raw)}},{'auxiliary':{'lottery_public':public,'lottery_config_hash':seed['config_hash']}}
    def test_exact_build_input_matches_all_generated_public_fields(self):
        raw,manifest,data=self.fixture()
        result=m.validate_lottery_seed(raw,manifest,data)
        self.assertTrue(result['public_seed_embedded_exactly'])
        self.assertFalse(result['probabilities_or_rewards_modified_by_review'])
    def test_wrong_input_pin_or_catalog_md5_blocks_review(self):
        raw,manifest,data=self.fixture()
        with self.assertRaisesRegex(ValueError,'source_manifest_sha'):
            m.validate_lottery_seed(raw+b' ',manifest,data)
        value=json.loads(raw);value['md5']='0'*32;raw=m.canonical(value)
        manifest['source_hashes'][m.LOTTERY_SEED]=m.sha(raw)
        with self.assertRaisesRegex(ValueError,'document_md5'):
            m.validate_lottery_seed(raw,manifest,data)
    def test_same_name_but_changed_reward_or_config_cannot_be_excluded(self):
        for change in ('reward','config'):
            raw,manifest,data=self.fixture()
            if change=='reward':data['auxiliary']['lottery_public']['snapshots'][0]['items'][0]['quantity']=2
            else:data['auxiliary']['lottery_config_hash']='b'*64
            with self.assertRaisesRegex(ValueError,'not_exact_generated_runtime'):
                m.validate_lottery_seed(raw,manifest,data)
    def test_missing_pool_is_not_a_complete_public_seed(self):
        raw,manifest,data=self.fixture();seed=json.loads(raw)
        public=json.loads(seed['catalog_json']);public['snapshots'].pop()
        seed['catalog_json']=json.dumps(public);seed['md5']=hashlib.md5(seed['catalog_json'].encode()).hexdigest()
        raw=m.canonical(seed);manifest['source_hashes'][m.LOTTERY_SEED]=m.sha(raw)
        with self.assertRaisesRegex(ValueError,'four_public_pools'):
            m.validate_lottery_seed(raw,manifest,data)

if __name__=='__main__':unittest.main()
