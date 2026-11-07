"""Pure exact-review rejection/semantics tests; no repo writes or SDK."""
from pathlib import Path
import copy,hashlib,importlib.util,json,subprocess,unittest
from unittest.mock import patch

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


class CsvBuildInputReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Pin once, then read real checked-in inputs/generator/outputs. No
        # generated fixture, working-tree import, temp runtime tree or writes.
        cls.revision = subprocess.check_output(['git','--no-replace-objects','-C',str(m.ROOT),'rev-parse','HEAD']).decode().strip()
        def blob(path):
            return subprocess.check_output(['git','--no-replace-objects','-C',str(m.ROOT),'show',cls.revision+':'+path])
        cls.blob = staticmethod(blob)
        cls.blobs = {path: blob(path) for path in [m.CSV_GENERATOR,*m.CSV_OUTPUTS,*m.CSV_OUTPUTS.values()]}
        cls.blobs['operator:'+m.CSV_GENERATOR] = cls.blobs[m.CSV_GENERATOR]
        cls.pins = {'game':cls.revision,'content':'b'*40,'operator':cls.revision}

    def test_real_five_immutable_csvs_reproduce_all_runtime_bytes(self):
        result = m.validate_csv_build_inputs(self.blobs,self.pins)
        self.assertEqual(set(result),set(m.CSV_OUTPUTS))
        for path, checks in result.items():
            self.assertTrue(checks['complete_generated_bytes_equal'])
            self.assertEqual(checks['generated_lua_sha256'],m.sha(self.blobs[m.CSV_OUTPUTS[path]]))
            self.assertEqual(checks['csv_read_count'],1)
            self.assertEqual(checks['other_csv_or_template_reads'],0)
            self.assertEqual(checks['runtime_files_written'],0)
            self.assertFalse(checks['derived_unified_tooltip_rebuilt'])

    def test_challenge_and_tooltip_use_only_bound_memory_adapters(self):
        paths = {
            'data/csv/公共规则/tooltip_definitions.csv': 'scripts/vscripts/config/generated/tooltip_definitions.lua',
            'data/csv/挑战与奖励系统/challenge_definitions.csv': 'scripts/vscripts/config/generated/challenge_definitions.lua',
        }
        self.assertTrue(paths.items() <= m.CSV_OUTPUTS.items())
        blobs = {key:self.blobs[key] for key in (m.CSV_GENERATOR, 'operator:'+m.CSV_GENERATOR, *paths, *paths.values())}
        # The pinned real build() must use only the supplied CSV/output adapters,
        # never a working-tree CSV/template or an on-disk generated destination.
        with patch('builtins.open', side_effect=AssertionError('unexpected file I/O')), \
             patch.object(Path, 'read_bytes', side_effect=AssertionError('unexpected Path read')), \
             patch.object(Path, 'write_text', side_effect=AssertionError('unexpected Path write')):
            checks = m.validate_csv_build_inputs(blobs,self.pins)
        self.assertEqual(set(checks),set(paths))
        for path in paths:
            self.assertEqual(checks[path]['csv_read_count'],1)
            self.assertEqual(checks[path]['other_csv_or_template_reads'],0)
            self.assertTrue(checks[path]['complete_generated_bytes_equal'])
            missing=dict(blobs);missing.pop(paths[path])
            with self.assertRaises(KeyError):m.validate_csv_build_inputs(missing,self.pins)

    def test_any_generated_value_or_byte_drift_blocks(self):
        for path,target in m.CSV_OUTPUTS.items():
            with self.subTest(path=path):
                blobs=dict(self.blobs);blobs[target]+=b'\n'
                with self.assertRaisesRegex(ValueError,'csv_generated_lua_bytes_differ'):
                    m.validate_csv_build_inputs(blobs,self.pins)

    def test_csv_value_or_schema_change_without_regenerated_lua_blocks(self):
        for path in m.CSV_OUTPUTS:
            with self.subTest(path=path):
                blobs=dict(self.blobs)
                # Changing a header changes all emitted field names, including
                # rows/by_id identity. No accepted value-only spot check.
                raw=blobs[path];start=3 if raw.startswith(b'\xef\xbb\xbf') else 0
                blobs[path]=raw[:start]+b'changed_'+raw[start:]
                with self.assertRaisesRegex(ValueError,'csv_generated_lua_bytes_differ'):
                    m.validate_csv_build_inputs(blobs,self.pins)

    def test_new_generator_read_api_rejected_before_execution(self):
        blobs=dict(self.blobs)
        changed=blobs[m.CSV_GENERATOR]+b'\nraise RuntimeError("unreviewed I/O executed")\n'
        blobs[m.CSV_GENERATOR]=blobs['operator:'+m.CSV_GENERATOR]=changed
        with self.assertRaisesRegex(ValueError,'csv_generator_readset_not_reviewed'):
            m.validate_csv_build_inputs(blobs,self.pins)

    def test_operator_generator_and_source_generator_must_be_identical(self):
        blobs=dict(self.blobs);blobs['operator:'+m.CSV_GENERATOR]+=b'\n'
        with self.assertRaisesRegex(ValueError,'csv_generator_source_operator_bytes_differ'):
            m.validate_csv_build_inputs(blobs,self.pins)

    def test_missing_required_generated_lua_cannot_be_ignored(self):
        blobs=dict(self.blobs);blobs.pop(next(iter(m.CSV_OUTPUTS.values())))
        with self.assertRaises(KeyError):m.validate_csv_build_inputs(blobs,self.pins)

    def test_direct_or_dynamic_csv_runtime_load_is_blocking(self):
        path=next(iter(m.CSV_OUTPUTS))
        for text in ('io.open("'+path+'")','local p="data/csv/"; io.open(p .. name)'):
            sites=m.read_sites(text,{path},'lua')
            self.assertTrue(any(s['candidate_json_read'] or s['uncertain_data_ui_read'] for s in sites))
        self.assertEqual(m.read_sites('-- Source: '+Path(path).name,{path},'lua'),[])

    def test_reference_scan_prefilter_keeps_computed_csv_namespace_loaders(self):
        source_path='scripts/vscripts/computed.lua'
        for prefix in ('data/csv/', r'data\\csv\\'):
            text='local p="'+prefix+'"; require(p .. name)'
            class Sources:
                pins={'game':'a'*40,'content':'b'*40}
                facts={'game:'+source_path:{'git_oid':'1'*40,'sha256':m.sha(text.encode())}}
                def grep(self,role,patterns,fixed=True):
                    if role != 'game': return []
                    found=any(p in text if fixed else m.re.search(p,text) for p in patterns)
                    return [source_path] if found else []
                def get(self,role,path): return text.encode()
            scan=m.reference_scan(Sources(),set(m.CSV_OUTPUTS))
            self.assertEqual(len(scan['runtime_read_blockers']),1)
            self.assertEqual(scan['runtime_read_blockers'][0]['reason'],'RUNTIME_JSON_READ_OR_UNCERTAIN_NAMESPACE')

    def test_full_review_keeps_csv_runtime_targets_and_rejects_unknown_csv(self):
        blobs=dict(self.blobs);manifest=json.loads(self.blob(m.MANIFEST))
        paths={m.ATLAS,m.MANIFEST,m.REGISTRY,*m.EVIDENCE,
               *(p for p in manifest['source_hashes'] if p.startswith('data/ui/registry_history/')),
               *m.CSV_OUTPUTS}
        for path in paths|{m.JS,m.LUA}:blobs[path]=self.blob(path)
        blobs['content:'+m.CONTENT_JS]=blobs[m.JS]
        facts={'game:'+p:{'git_oid':'1'*40,'sha256':m.sha(blobs[p])} for p in paths}
        rows=[{'inventory_status':'UNMAPPED_SOURCE_PENDING',
               'source':{'path':p,'repo':'game','head_oid':'1'*40},
               'candidate':{'sha256':m.sha(blobs[p])}} for p in sorted(paths)]
        scope={'observed_commits':{k:self.pins[k] for k in ('game','content')},'decisions':rows}
        scan={'runtime_read_blockers':[],'references':{}}
        review=m.make_reviews(scope,'a'*64,self.pins,blobs,facts,scan,'b'*64)
        csv_reviews={r['source_id'][5:]:r for r in review['reviews'] if r['source_id'][5:] in m.CSV_OUTPUTS}
        self.assertEqual(len(csv_reviews),5)
        for path,row in csv_reviews.items():
            self.assertEqual(row['runtime_targets_requiring_separate_generator_or_compiler_binding'],[m.CSV_OUTPUTS[path]])
            self.assertFalse(row['standalone_runtime_file_required'])
            self.assertFalse(row['authority_granted'])
        rows.append({'inventory_status':'UNMAPPED_SOURCE_PENDING','source':{'path':'data/csv/英雄系统/unreviewed.csv'}})
        with self.assertRaisesRegex(ValueError,'unmapped_set_not_exact_reviewed_paths'):
            m.make_reviews(scope,'a'*64,self.pins,blobs,facts,scan,'b'*64)

    def test_downstream_collector_accepts_csv_only_with_required_runtime_binding(self):
        from test_complete_collect_inputs import case, c
        value=case();review=value['review']['reviews'][0];old=review['source_id']
        path=next(iter(m.CSV_OUTPUTS));new='game:'+path
        value['facts'][new]=value['facts'].pop(old)
        row=next(r for r in value['base_inventory']['rows'] if r['source']['path']==old.split(':',1)[1])
        row['source']['path']=path
        review['source_id']=new
        review['classification']='EXACT_CSV_BUILD_INPUT_REPRODUCED_BY_IMMUTABLE_GENERATOR'
        required='scripts/vscripts/protected.lua'
        review['runtime_targets_requiring_separate_generator_or_compiler_binding']=[required]
        result=c.assemble(**value)
        self.assertFalse(result['blockers'])
        self.assertIn(new,result['projection']['coverage_ledger']['non_runtime_reviews'])
        value['targets'].pop(required)
        blocked=c.assemble(**value)
        self.assertTrue(any(r['source_id']==new for r in blocked['blockers']))

if __name__=='__main__':unittest.main()
