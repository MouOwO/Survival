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
    def test_new_generated_history_node_is_exact_current_output_only(self):
        raw,manifest,history=chain();current='data/ui/registry_history/'+m.sha(raw)+'.json'
        manifest['source_hashes'].pop(current)
        checks=m.validate_lineage(raw,manifest,history)
        self.assertTrue(checks['current_history_is_generated_output'])
        self.assertEqual(checks['declared_input_history_nodes'],1)
        self.assertEqual(checks['nodes_parsed'],2)
        for change in ('missing_current','extra_node','wrong_current_bytes','missing_parent'):
            with self.subTest(change=change):
                bad=dict(history)
                if change=='missing_current':bad.pop(current)
                elif change=='extra_node':bad['data/ui/registry_history/'+'0'*64+'.json']=b'{}'
                elif change=='wrong_current_bytes':bad[current]+=b' '
                else:bad.pop(next(p for p in bad if p!=current))
                with self.assertRaises(ValueError):m.validate_lineage(raw,manifest,bad)
    def test_twelve_node_input_compatibility_and_thirteenth_output_gap_rejection(self):
        raw,manifest,history=chain();node=json.loads(raw)
        for generation in range(3,14):
            node=copy.deepcopy(node);node.update(generation=generation,parent_sha256=m.sha(raw))
            raw=m.canonical(node);history['data/ui/registry_history/'+m.sha(raw)+'.json']=raw
        current='data/ui/registry_history/'+m.sha(raw)+'.json'
        prior={p:v for p,v in history.items() if p!=current}
        old_raw=history['data/ui/registry_history/'+node['parent_sha256']+'.json']
        old_manifest={'registry_sha256':m.sha(old_raw),'source_hashes':{p:m.sha(v)for p,v in prior.items()}}
        old=m.validate_lineage(old_raw,old_manifest,prior)
        self.assertEqual(old['nodes_parsed'],12)
        self.assertFalse(old['current_history_is_generated_output'])
        new_manifest={'registry_sha256':m.sha(raw),'source_hashes':old_manifest['source_hashes']}
        self.assertEqual(m.validate_lineage(raw,new_manifest,history)['nodes_parsed'],13)
        for change in ('generation_gap','skip_parent','missing_parent'):
            with self.subTest(change=change):
                bad_node=copy.deepcopy(node)
                if change=='generation_gap':bad_node['generation']=14
                elif change=='skip_parent':bad_node['parent_sha256']=json.loads(old_raw)['parent_sha256']
                else:bad_node['parent_sha256']='0'*64
                bad_raw=m.canonical(bad_node);bad_hist=dict(prior)
                bad_hist['data/ui/registry_history/'+m.sha(bad_raw)+'.json']=bad_raw
                bad_manifest=dict(new_manifest,registry_sha256=m.sha(bad_raw))
                with self.assertRaises(ValueError):m.validate_lineage(bad_raw,bad_manifest,bad_hist)
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

    def test_actual_catalog_output_chain_and_input_registry_relation(self):
        manifest=json.loads(self.blob(m.MANIFEST))
        paths={m.MANIFEST,m.REGISTRY,m.ATLAS,m.JS,m.LUA,
               *(p for p in manifest['source_hashes']if p.startswith('data/ui/registry_history/')),
               'data/ui/registry_history/'+manifest['registry_sha256']+'.json'}
        blobs={p:self.blob(p)for p in paths};blobs['content:'+m.CONTENT_JS]=blobs[m.JS]
        registry=json.loads(blobs[m.REGISTRY])
        checks=m.validate_catalog(blobs)
        self.assertEqual(checks['nodes_parsed'],registry['generation'])
        self.assertGreaterEqual(checks['nodes_parsed'],12)
        # A skipped ancestor or arbitrary SHA cannot stand in for the direct
        # source registry, even though the complete output chain is still valid.
        parent=json.loads(blobs['data/ui/registry_history/'+registry['parent_sha256']+'.json'])
        for wrong in ('0'*64,parent['parent_sha256']):
            with self.subTest(wrong=wrong):
                changed=copy.deepcopy(manifest);changed['source_hashes'][m.REGISTRY]=wrong
                bad=dict(blobs);bad[m.MANIFEST]=m.canonical(changed)
                with self.assertRaisesRegex(ValueError,'input_registry_not_current_or_direct_parent'):
                    m.validate_catalog(bad)

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

    def test_reference_scan_matches_whole_filenames_not_generated_siblings(self):
        candidate='data/csv/挑战与奖励系统/challenge_definitions.csv'
        source_path='scripts/vscripts/config/generated/other.lua'
        samples=(
            ('-- Source: archive_challenge_definitions.csv',False),
            ('-- Source: building_challenge_definitions.csv',False),
            ('-- Source: challenge_definitions.csv.backup',False),
            ('-- Source: challenge_definitions.csv',True),
            ('-- Source: '+candidate,True),
            ('local f=io.open("challenge_definitions.csv")',True),
            ('local f=io.open("'+candidate+'")',True),
            ('local dir="data/csv/"; require(dir .. file)',True),
        )
        for text,blocked in samples:
            with self.subTest(text=text):
                class Sources:
                    pins={'game':'a'*40,'content':'b'*40}
                    facts={'game:'+source_path:{'git_oid':'1'*40,'sha256':m.sha(text.encode())}}
                    def grep(self,role,patterns,fixed=True):
                        if role != 'game':return []
                        return [source_path] if any(p in text if fixed else m.re.search(p,text) for p in patterns) else []
                    def get(self,role,path):return text.encode()
                scan=m.reference_scan(Sources(),{candidate})
                self.assertEqual(bool(scan['runtime_read_blockers']),blocked)
                if not blocked:self.assertEqual(scan['references'],{})

    def test_full_review_keeps_csv_runtime_targets_and_rejects_unknown_csv(self):
        blobs=dict(self.blobs);manifest=json.loads(self.blob(m.MANIFEST))
        paths={m.ATLAS,m.MANIFEST,m.REGISTRY,*m.EVIDENCE,
               *(p for p in manifest['source_hashes'] if p.startswith('data/ui/registry_history/')),
               'data/ui/registry_history/'+manifest['registry_sha256']+'.json',
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

class LocalizationMappingReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Immutable production inputs, not copied values or mocked localization
        # proof. This also exercises the actual generation-13 catalog lineage.
        cls.pins={role:m.compiler.run_git(root,'rev-parse','HEAD').decode().strip()
                  for role,root in (('game',m.ROOT),('content',m.pending.CONTENT))}
        cls.pins['operator']=cls.pins['game']
        sources=m.Sources(cls.pins)
        try:
            manifest=json.loads(sources.get('game',m.MANIFEST))
            paths={m.ATLAS,m.MANIFEST,m.REGISTRY,m.LOTTERY_SEED,*m.EVIDENCE,*m.CSV_OUTPUTS,
                   *(p for p in manifest['source_hashes']if p.startswith('data/ui/registry_history/')),
                   'data/ui/registry_history/'+manifest['registry_sha256']+'.json'}
            rows=[]
            for role,path in [('game',p)for p in sorted(paths)]+[('content',p)for p in sorted(m.localization.PATHS)]:
                raw=sources.get(role,path);fact=sources.facts[role+':'+path]
                rows.append({'inventory_status':'UNMAPPED_SOURCE_PENDING',
                    'source':{'repo':role,'path':path,'head_oid':fact['git_oid']},
                    'candidate':{'sha256':m.sha(raw)}})
            with patch.object(sources,'get',wraps=sources.get)as getter:
                cls.blobs=m.load_review_blobs(sources,rows,cls.pins)
                cls.get_calls=[tuple(call.args)for call in getter.call_args_list]
            cls.facts=copy.deepcopy(sources.facts)
            cls.scope={'observed_commits':{k:cls.pins[k]for k in ('game','content')},'decisions':rows}
        finally:sources.close()

    def review(self,scope=None,blobs=None,facts=None):
        return m.make_reviews(scope or self.scope,'a'*64,self.pins,blobs or self.blobs,
                              facts or self.facts,{'runtime_read_blockers':[],'references':{}},'b'*64)

    def test_real_six_pairs_are_runtime_projections_not_non_runtime_exclusions(self):
        result=self.review();rows=result['runtime_mapping_reviews']
        self.assertEqual(len(rows),6)
        self.assertEqual(result['scope']['actual_unmapped_count'],len(self.scope['decisions']))
        self.assertEqual(result['scope']['typed_runtime_mapping_count'],6)
        self.assertEqual(result['scope']['standalone_review_count'],len(result['reviews']))
        excluded={r['source_id']for r in result['reviews']}
        for row in rows:
            path=row['resource'];self.assertNotIn(row['source_id'],excluded)
            self.assertEqual(row['kind'],'localization_projection')
            self.assertTrue(row['standalone_runtime_file_required'])
            self.assertFalse(row['non_runtime_exclusion']);self.assertFalse(row['authority_granted'])
            self.assertEqual(row['runtime_targets_requiring_separate_generator_or_compiler_binding'],[path])
            self.assertEqual(row['localization_projection'],m.localization.verify_projection(path,self.blobs['content:'+path],self.blobs[path]))
            self.assertIn(('content',path),self.get_calls)
            self.assertIn(('game',path),self.get_calls)
            self.assertEqual(row['sources']['content:'+path]['source_revision'],self.pins['content'])
            self.assertEqual(row['sources']['game:'+path]['source_revision'],self.pins['game'])
        history=[r for r in result['reviews']if r['source_id'].startswith('game:data/ui/registry_history/')]
        self.assertEqual(len(history),json.loads(self.blobs[m.REGISTRY])['generation'])

    def test_source_swaps_extra_bytes_and_missing_counterpart_block_before_exclusion(self):
        path='panorama/localization/addon_english.txt'
        self.assertNotEqual(self.blobs[path],self.blobs['content:'+path])
        for change in ('source_swap','extra_content_bytes','extra_game_bytes','missing_game'):
            with self.subTest(change=change):
                bad=dict(self.blobs)
                if change=='source_swap':bad['content:'+path]=bad[path]
                elif change=='extra_content_bytes':bad['content:'+path]+=b'\n'
                elif change=='extra_game_bytes':bad[path]+=b'\n'
                else:bad.pop(path)
                with self.assertRaises((ValueError,KeyError)):self.review(blobs=bad)

    def test_projection_requires_actual_scope_oid_digest_and_dual_revision(self):
        path=next(iter(sorted(m.localization.PATHS)));key='content:'+path
        for change in ('scope_oid','scope_sha','content_revision','game_revision','duplicate'):
            with self.subTest(change=change):
                scope=copy.deepcopy(self.scope);facts=copy.deepcopy(self.facts)
                row=next(r for r in scope['decisions']if r['source']['repo']=='content'and r['source']['path']==path)
                if change=='scope_oid':row['source']['head_oid']='0'*40
                elif change=='scope_sha':row['candidate']['sha256']='0'*64
                elif change=='duplicate':scope['decisions'].append(copy.deepcopy(row))
                else:facts[('content:'if change=='content_revision'else'game:')+path]['source_revision']='0'*40
                with self.assertRaises(ValueError):self.review(scope=scope,facts=facts)

    def test_unknown_localization_path_and_missing_history_are_not_hidden(self):
        scope=copy.deepcopy(self.scope)
        scope['decisions'].append({'inventory_status':'UNMAPPED_SOURCE_PENDING',
            'source':{'repo':'content','path':'panorama/localization/addon_unreviewed.txt'}})
        with self.assertRaisesRegex(ValueError,'unmapped_set_not_exact_reviewed_paths'):self.review(scope=scope)
        blobs=dict(self.blobs);current=json.loads(blobs[m.MANIFEST])['registry_sha256']
        blobs.pop('data/ui/registry_history/'+current+'.json')
        with self.assertRaisesRegex(ValueError,'history_exact'):self.review(blobs=blobs)

    def test_runtime_review_alone_cannot_authorize_missing_collector_target(self):
        from test_complete_collect_inputs import case,c
        value=case();mapping=self.review()['runtime_mapping_reviews'][0]
        key=mapping['source_id'];path=mapping['resource']
        value['base_inventory']['rows'].append({'source':{'repo':'content','path':path,'head_oid':mapping['git_oid']},
            'resource':path,'status':'UNMAPPED_SOURCE_PENDING','history':[],'blocking':True})
        value['facts'][key]={'git_oid':mapping['git_oid'],'sha256':mapping['sha256'],'bytes':mapping['bytes']}
        value['review']['runtime_mapping_reviews']=[mapping]
        result=c.assemble(**value)
        self.assertTrue(any(row['source_id']==key for row in result['blockers']))


if __name__=='__main__':unittest.main()
