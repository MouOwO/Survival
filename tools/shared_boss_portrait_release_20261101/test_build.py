"""Isolated contracts: no SDK, signing, candidate build, install, GUI or cloud."""
from contextlib import nullcontext,redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock,patch
import copy,importlib.util,io,json,tempfile,unittest

HERE=Path(__file__).resolve().parent
def module(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('shared_boss_test_builder',HERE/'build_release.py')
v=module('shared_boss_test_validator',HERE/'validator.py')


def values():
    result={}
    for name in b.PAYLOADS:
        raw=(b.ROOT/name).read_bytes()
        result[name]=raw.replace(b'\r\n',b'\n') if Path(name).suffix in {'.lua','.txt'} else raw
    for pin in b.COMPILED.values():
        raw=(b.ROOT/pin['source']).read_bytes()
        result[pin['source']]=raw.replace(b'\r\n',b'\n') if pin['source_normalization']!='IDENTITY' else raw
    return result


def fixture():
    data=values();output={name:data[name] for name in b.PAYLOADS}
    old_values={name:('old_'+str(i)).encode() for i,name in enumerate(b.PAYLOADS) if name not in b.ADDED_RUNTIME_PATHS}
    extra='scripts/vscripts/deferred.lua';old_values[extra]=b'production old bytes'
    rows=[dict(path=name,**b.checks(raw)) for name,raw in sorted(old_values.items())]
    parent=dict(schema=2,kind='runtime_release_allowlist',hash_algorithms=['md5','sha256'],files=rows,
        file_count=len(rows),bytes=sum(row['bytes'] for row in rows),content_sha256='a'*64)
    def entry(raw):return dict(mode='100644',kind='blob',oid=b.sha(raw)[:40],bytes=len(raw))
    game={name:entry(raw) for name,raw in data.items()};game[extra]=entry(b'history not published')
    content={'panorama/scripts/custom_game/'+Path(pin['source']).name:entry(data[pin['source']]) for pin in b.COMPILED.values()}
    origins=b.ledger.frozen_origins(parent)
    snapshot=dict(source_anchors=dict(game=b.ledger.GAME_ANCHOR,content=b.ledger.CONTENT_ANCHOR),
        source_inventory=dict(game=copy.deepcopy(game),content=copy.deepcopy(content)),resource_origins=origins,
        resource_origins_sha256=b.ledger.sha(b.ledger.canonical(origins)),parent_manifest_sha256='b'*64,
        source_gap_audit_sha256='c'*64,binary_gap_audit_sha256='d'*64,
        deferred_sources={'game:'+extra:dict(repo='game',path=extra,git_sha256=b.sha(b'history not published'),
            status='DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK',safe_or_production_equivalent_claimed=False)})
    return data,output,parent,{'game':game,'content':content},snapshot,extra


class BuilderContracts(unittest.TestCase):
    def test_default_is_static_without_git_parent_io_keys_or_writes(self):
        with patch.object(b,'baseline',side_effect=AssertionError('no baseline')),patch.object(b,'blob',side_effect=AssertionError('no Git')),\
             patch.object(b.inc,'write_new',side_effect=AssertionError('no writes')),redirect_stdout(io.StringIO()) as output:
            b.main([])
        result=json.loads(output.getvalue())
        self.assertEqual((result['payload_count'],result['proposed_file_count']),(17,6919))
        self.assertEqual(result['status'],'STATIC_V07_PLAN_ONLY_NO_EFFECTS')
        self.assertFalse(result['signature_valid']);self.assertFalse(result['steam_initialized'])

    def test_static_rejects_source_key_report_and_content_revision(self):
        for args in [['--key','x'],['--source-revision','a'*40],['--report','x'],['--content-source-revision','b'*40],['--operator-revision','c'*40]]:
            with self.subTest(args=args),self.assertRaises(ValueError):b.main(['--static-plan',*args])

    def test_operator_recipe_is_bound_to_an_independent_immutable_commit(self):
        committed=b'reviewed operator\n';physical=committed.replace(b'\n',b'\r\n')
        source=Mock();source.read_bytes.return_value=physical
        with patch.object(b,'immutable_revision',return_value='c'*40) as immutable,\
             patch.object(b,'AUXILIARY_INPUTS',('tools/operator.py',)),\
             patch.object(b,'blob_at',return_value=committed) as blob,\
             patch.object(b.pack.protect_data,'source_path',return_value=source):
            revision,pins,bindings=b.operator_inputs('c'*40)
        immutable.assert_called_once_with('c'*40);blob.assert_called_once_with(b.ROOT,'c'*40,'tools/operator.py')
        self.assertEqual(revision,'c'*40)
        self.assertEqual(pins['tools/operator.py'],b.checks(physical))
        self.assertEqual(bindings['tools/operator.py'],dict(git_blob=b.checks(committed),
            physical_input=b.checks(physical),normalization='GIT_LF_TO_OPERATOR_CRLF_ONLY'))

    def test_dirty_operator_recipe_is_refused_even_when_runtime_source_is_unchanged(self):
        for physical in (b'reviewed operator\n# dirty\n',b'changed operator\r\n',b'reviewed operator\n\r\n'):
            source=Mock();source.read_bytes.return_value=physical
            with self.subTest(physical=physical),patch.object(b,'immutable_revision',return_value='c'*40),\
                 patch.object(b,'AUXILIARY_INPUTS',('tools/operator.py',)),\
                 patch.object(b,'blob_at',return_value=b'reviewed operator\n'),\
                 patch.object(b.pack.protect_data,'source_path',return_value=source):
                with self.assertRaisesRegex(ValueError,'DIRTY_OR_UNCOMMITTED_AUXILIARY_INPUT'):b.operator_inputs('c'*40)

    def test_missing_immutable_operator_commit_refuses_before_parent_or_key_io(self):
        with patch.object(b,'immutable_revision',side_effect=ValueError('Explicit immutable commit required')),\
             patch.object(b,'baseline',side_effect=AssertionError('no parent read')),\
             patch.object(b,'blob_at',side_effect=AssertionError('no Git blob read')):
            with self.assertRaisesRegex(ValueError,'immutable commit'):b.operator_inputs(None)

    def test_payload_reader_uses_no_replace_git_identity_and_checks_lfs_bytes(self):
        completed=SimpleNamespace(returncode=0,stdout=b'exact immutable source')
        with patch.object(b.subprocess,'run',return_value=completed) as run:
            self.assertEqual(b.blob('a'*40,'scripts/vscripts/example.lua'),completed.stdout)
        self.assertIn('--no-replace-objects',run.call_args.args[0])
        self.assertEqual(run.call_args.args[0][-1],'a'*40+':scripts/vscripts/example.lua')
        raw=b'resolved exact payload';pointer=('version https://git-lfs.github.com/spec/v1\noid sha256:'+b.sha(raw)+'\nsize '+str(len(raw))+'\n').encode()
        source=Mock();source.read_bytes.return_value=raw
        with patch.object(b,'blob_at',return_value=pointer),patch.object(b.pack.protect_data,'source_path',return_value=source):
            self.assertEqual(b.blob('a'*40,'models/example.vmdl_c'),raw)
            source.read_bytes.return_value=b'foreign bytes'
            with self.assertRaisesRegex(ValueError,'LFS payload differs'):b.blob('a'*40,'models/example.vmdl_c')

    def test_scope_preserves_fourteen_and_adds_only_three_boss_paths(self):
        previous=b.module('original_v06_scope',b.ROOT/'tools/arcade_portrait_release_v06_20261101/build_release.py')
        self.assertEqual(b.PAYLOADS[:14],previous.PAYLOADS)
        self.assertEqual(b.COMPILED,previous.COMPILED)
        self.assertEqual((b.SEQUENCE,b.BASE_SEQUENCE),(2026110107,2026110104))
        self.assertEqual(set(b.ADDED_RUNTIME_PATHS),{b.PAYLOADS[1],b.PAYLOADS[15]})
        self.assertTrue(set(b.PAYLOADS).isdisjoint(b.ADMISSION_PATHS))
        b.inc.disjoint([b.VIEW,b.OVERLAY,b.TRUSTED,b.UNSIGNED,b.OUTPUT,*b.FROZEN_V06_OUTPUTS])

    def test_immutable_collection_uses_real_three_compiler_and_boss_pins(self):
        data=values();bindings={}
        with patch.object(b,'immutable_revision',return_value='a'*40),patch.object(b,'blob',side_effect=lambda rev,name:data[name]):
            revision,output=b.payloads('a'*40,source_bindings=bindings)
        self.assertEqual(len(output),17);self.assertEqual(len(bindings),3)
        for name,expected in b.BOSS_SOURCE_PINS.items():self.assertEqual(b.sha(output[name]),expected)

    def test_changed_or_missing_boss_review_refuses_before_plan(self):
        data=values();data[b.PAYLOADS[15]]=b'unknown new registry'
        with patch.object(b,'immutable_revision',return_value='a'*40),patch.object(b,'blob',side_effect=lambda rev,name:data[name]):
            with self.assertRaisesRegex(ValueError,'SHARED_BOSS_SOURCE_REVIEW'):b.payloads('a'*40)

    def test_trusted_reviews_are_eighteen_parent_plus_four_new_sources(self):
        data=values();parent={str(i):{'sha256':str(i)} for i in range(18)}
        with patch.object(b,'base_trusted_review',return_value=parent):reviews=b.trusted_review({},data)
        self.assertEqual(len(reviews),22)
        self.assertEqual(set(reviews).intersection(b.PAYLOADS),set(b.ADDITIONAL_SOURCE_REVIEWS))

    def test_missing_ledger_pin_refuses_before_read(self):
        with patch.object(b.ledger,'REVIEWED_BASELINE_SHA256',None),patch.object(Path,'read_bytes',side_effect=AssertionError('no read')):
            with self.assertRaisesRegex(ValueError,'PENDING_ROOT_REVIEWED'):b.ledger.load_baseline({},'a'*64)

    def test_concrete_source_baseline_is_complete_and_honest(self):
        data=json.loads((HERE/'source_baseline_0104.json').read_bytes())
        self.assertEqual(len(data['resource_origins']),6917)
        self.assertEqual(len(data['deferred_sources']),220)
        self.assertFalse(data['source_anchor_is_full_published_tree'])
        self.assertEqual(data['source_gap_audit_sha256'],'33fdc7ed7c0ef7a4b61c5aecca5bfc4d42eb6cec8143161529a137563574990b')
        self.assertTrue(all(row['safe_or_production_equivalent_claimed'] is False for row in data['deferred_sources'].values()))

    def test_native_admission_missing_refuses_before_package_or_sdk(self):
        with patch.object(v,'NATIVE_ADMISSION_MODULE',None),patch.object(v.c,'validated_package',side_effect=AssertionError('no package')):
            with self.assertRaisesRegex(ValueError,'PENDING_REAL_NATIVE'):v.validate_release({'release_sequence':b.SEQUENCE,'READY':True})

    def test_unreviewed_native_policy_bytes_refuse_before_package_or_sdk(self):
        with patch.object(v,'NATIVE_ADMISSION_MODULE',HERE/'native_admission.py'),\
             patch.object(v,'NATIVE_ADMISSION_SHA256','0'*64),\
             patch.object(v.c,'validated_package',side_effect=AssertionError('no package')):
            with self.assertRaisesRegex(ValueError,'native admission policy changed'):
                v.validate_release({'release_sequence':b.SEQUENCE,'READY':True})

    def test_real_plan_composes_seventeen_blobs_and_preserves_unknown_parent_fields(self):
        data=values();rows={name:dict(path=name,**b.checks(b'old runtime'),unknown_row_field='preserve')
            for name in b.PAYLOADS if name not in b.ADDED_RUNTIME_PATHS}
        for name in b.ADMISSION_PATHS:rows[name]=dict(path=name,**b.checks(b'official five accounts'),admission_extension=True)
        for i in range(6917-len(rows)):
            name='materials/frozen/%04d.vtex_c'%i;rows[name]=dict(path=name,**b.checks(b'frozen resource'))
        old=dict(schema=2,kind='runtime_release_allowlist',hash_algorithms=['md5','sha256'],
            files=[rows[name] for name in sorted(rows)],file_count=6917,bytes=sum(row['bytes'] for row in rows.values()),
            future_manifest_extension={'retained':True},content_sha256='a'*64)
        parent=dict(package_files=[{'name':'3824360109.vpk','sha256':'d'*64}])
        lineage=dict(complete=True,unknown_changes=[],source_revisions={'game':'a'*40,'content':'b'*40},
            actual_parent_manifest_sha256='e'*64,parent_resource_origins_sha256='f'*64,resource_origins_sha256='1'*64)
        with patch.object(b,'immutable_revision',side_effect=lambda value:value),\
             patch.object(b,'operator_inputs',return_value=('c'*40,{'tools/recipe.py':b.checks(b'recipe')},{'exact_binding':True})),\
             patch.object(b,'baseline',return_value=(parent,old)),\
             patch.object(b,'blob',side_effect=lambda revision,name:data[name]),\
             patch.object(b,'source_lineage',return_value=lineage),\
             patch.object(b,'base_trusted_review',return_value={str(i):{'sha256':str(i)} for i in range(18)}),\
             patch.object(b,'load',return_value={}),\
             patch.object(b.parent.parent.previous.base.protection,'selected_files',return_value=[{'path':'protected/%d.lua'%i} for i in range(184)]),\
             patch.object(b.inc,'read_entries',return_value=[]),\
             patch.object(b.parent.parent.previous.base.parent,'rotation_plan',return_value=(b'',[],set(),[])),\
             patch.object(b.inc,'capacity',return_value=[]),\
             patch.object(b.pack.runtime,'digest',return_value='2'*64):
            report,_,after,changed,_,_=b.plan('a'*40,'b'*40,'c'*40)
        self.assertEqual(len(changed),17);self.assertEqual(after['file_count'],6919)
        self.assertEqual(report['operator_revision'],'c'*40);self.assertFalse(report['operator_source_is_runtime_source'])
        self.assertEqual(report['source_revisions'],lineage['source_revisions'])
        self.assertEqual(len(report['source_artifact_pins']),3);self.assertEqual(len(report['trusted_review_pins']),22)
        self.assertEqual(after['future_manifest_extension'],old['future_manifest_extension'])
        by_path={row['path']:row for row in after['files']}
        self.assertTrue(all(by_path[name]==rows[name] for name in b.ADMISSION_PATHS))
        self.assertEqual(by_path[b.PAYLOADS[14]]['unknown_row_field'],'preserve')
        self.assertFalse(report['signature_valid']);self.assertFalse(report['ready_for_upload'])


class LineageContracts(unittest.TestCase):
    def audit(self,mutate=None,edit_blob=None):
        data,output,parent,trees,snapshot,extra=fixture()
        if mutate:mutate(trees,snapshot,extra)
        namespace=SimpleNamespace(**vars(b))
        namespace.blob_at=lambda root,rev,name:(edit_blob(name) if edit_blob and name==extra else
            b'history not published' if name==extra else data.get(name,data.get('panorama/src/scripts/custom_game/'+Path(name).name)))
        def read_tree(root,rev):return trees['content' if root==b.ledger.CONTENT_ROOT else 'game']
        with patch.object(b.ledger,'load_baseline',return_value=snapshot),patch.object(b.git_export,'git_tree',side_effect=read_tree):
            return b.ledger.audit(namespace,'a'*40,'b'*40,parent,output,{pin['source']:{} for pin in b.COMPILED.values()})

    def test_actual_parent_diff_includes_old_fourteen_even_when_already_in_anchor(self):
        result=self.audit()
        self.assertEqual(set(result['changed_runtime_paths']),set(b.PAYLOADS))
        self.assertFalse(result['full_head_publication_claimed'])
        self.assertEqual(len(result['deferred_sources']),1)
        self.assertEqual(len(result['resource_origins']),18)

    def test_unknown_runtime_change_after_anchor_is_not_deferred(self):
        def mutate(trees,snapshot,extra):trees['game']['scripts/vscripts/unknown.lua']={'kind':'blob','mode':'100644','oid':'1'*40,'bytes':1}
        with self.assertRaisesRegex(ValueError,'NEW_UNREVIEWED_RUNTIME'):self.audit(mutate)

    def test_changed_deferred_identity_or_bytes_fails_closed(self):
        def mutate(trees,snapshot,extra):trees['game'][extra]['oid']='2'*40
        with self.assertRaisesRegex(ValueError,'NEW_UNREVIEWED_RUNTIME'):self.audit(mutate)
        with self.assertRaisesRegex(ValueError,'changed_deferred_source'):self.audit(edit_blob=lambda _:b'new source not reviewed')

    def test_removed_deferred_source_is_not_silently_kept(self):
        def mutate(trees,snapshot,extra):del trees['game'][extra]
        with self.assertRaisesRegex(ValueError,'NEW_UNREVIEWED_RUNTIME'):self.audit(mutate)

    def test_unmapped_content_edit_fails_even_if_game_artifact_is_unchanged(self):
        def mutate(trees,snapshot,extra):trees['content']['panorama/scripts/custom_game/unmapped.js']={'kind':'blob','mode':'100644','oid':'3'*40,'bytes':1}
        with self.assertRaisesRegex(ValueError,'NEW_UNREVIEWED_RUNTIME'):self.audit(mutate)

    def test_admitted_source_cannot_be_a_git_symlink(self):
        def mutate(trees,snapshot,extra):trees['game'][b.PAYLOADS[15]]['mode']='120000'
        with self.assertRaisesRegex(ValueError,'invalid_source_file_mode'):self.audit(mutate)

    def test_complete_source_and_compiler_bindings_keep_origin_digests(self):
        result=self.audit()
        self.assertEqual(result['resource_origins_sha256'],b.ledger.sha(b.ledger.canonical(result['resource_origins'])))
        for name in b.COMPILED:self.assertEqual(result['resource_origins'][name]['kind'],'BOUND_OFFICIAL_COMPILER_ARTIFACT')


class HistoricalParentContracts(unittest.TestCase):
    def fixture(self,temp):
        trusted=Path(temp);(trusted/'review.lua').write_bytes(b'historical source')
        signature=dict(release_sequence=2026110104,signature_valid=True,content_sha256=b.BASE_CONTENT)
        manifest=dict(content_sha256=b.BASE_CONTENT,file_count=6917)
        report=dict(status='BUILT_SIGNED_FIVE_ACCOUNT_PENDING_NATIVE_AND_SERVER',release_sequence=2026110104,
            signature_valid=True,full_runtime_validator_passed=True,dry_run=False,payload_changed=False,files=6917,
            content_sha256=b.BASE_CONTENT,source_revision='a'*40,package_files=[{'sha256':'p'}],
            auxiliary_input_pins={'tools/changed_sdk_helper.py':{'sha256':'historical-not-current'}},
            trusted_review_pins={'review.lua':b.checks(b'historical source')})
        record=dict(status='UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED',release_sequence=2026110104,runtime_files=6917,
            protected_modules=184,steam_manifest='7025356658517360342',content_sha256=b.BASE_CONTENT,
            package_files=report['package_files'],source_revision='a'*40,download_receipt={'path':'receipt.json','sha256':'r'*64})
        receipt=dict(status='OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED',release_sequence=2026110104,
            content_sha256=b.BASE_CONTENT,steam_manifest=record['steam_manifest'],signed_resources_verified=6917,
            protected_modules_verified=184,verification={'signature_valid':True,'package_files':report['package_files']})
        ns=SimpleNamespace(**vars(b));ns.BASE_TRUSTED=trusted
        mapping={b.BASE_REPORT:report,b.BASE_RECORD:record,b.ROOT/'receipt.json':receipt};ns.load=lambda path:mapping[path]
        runtime=SimpleNamespace(digest=lambda path:{b.BASE_REPORT:b.BASE_REPORT_SHA,b.BASE_RECORD:b.BASE_RECORD_SHA,b.ROOT/'receipt.json':'r'*64}[path])
        handoff=SimpleNamespace(POLICY=Path('policy.json'),trusted_policy=lambda path:({'integrity':{'minimum_release_sequence':1,'trusted_key_id':'key'}},Path('public.pem')),
            require_single_map=Mock(),require_reviewed_gate=Mock(),configured_ids=lambda path:sorted(b.APPROVED))
        ns.pack=SimpleNamespace(runtime=runtime,handoff=handoff,verify_signed_snapshot=Mock(return_value=signature),
            authenticate=Mock(return_value=(b.BASE,manifest,signature,{})),package_inventory=Mock(return_value=report['package_files']),verify_vpk=Mock())
        ns.inc=SimpleNamespace(metadata=lambda path:(manifest,{},{}),trusted_source=lambda path:nullcontext())
        ns.scene_maps=lambda:nullcontext()
        return ns,report,record,receipt

    def test_current_sdk_bytes_are_not_historical_runtime_authentication(self):
        with tempfile.TemporaryDirectory() as temp:
            ns,*_=self.fixture(temp)
            report,manifest,signed=b.historical_parent.validate(ns,full=False)
            self.assertEqual(manifest['file_count'],6917)
            self.assertIn('tools/changed_sdk_helper.py',report['auxiliary_input_pins'])
            ns.pack.verify_signed_snapshot.assert_called_once()
            ns.pack.authenticate.assert_not_called()

    def test_official_receipt_or_full_vpk_changes_still_refuse(self):
        with tempfile.TemporaryDirectory() as temp:
            ns,report,record,receipt=self.fixture(temp);receipt['protected_modules_verified']=183
            with self.assertRaisesRegex(ValueError,'official0104 download'):b.historical_parent.validate(ns)
            receipt['protected_modules_verified']=184;ns.pack.package_inventory.return_value=[]
            with self.assertRaisesRegex(ValueError,'five VPK'):b.historical_parent.validate(ns,full=True)


if __name__=='__main__':unittest.main()
