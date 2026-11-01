"""Pure synthetic v03 fork checks. No real plan, key, SDK or installation."""
from contextlib import ExitStack,nullcontext,redirect_stdout
from pathlib import Path
from unittest.mock import Mock,patch
import copy
import importlib.util
import io
import json
import tempfile
import unittest

DIRECTORY=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('portrait_v03_test_builder',DIRECTORY/'build_release.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
spec=importlib.util.spec_from_file_location('portrait_v03_test_checks',DIRECTORY/'release_checks.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)


def manifest(values):
    rows=[dict(path=name,**b.checks(raw)) for name,raw in sorted(values.items())]
    result=dict(schema=2,kind='runtime_release_allowlist',hash_algorithms=['md5','sha256'],files=rows,
        file_count=len(rows),bytes=sum(row['bytes'] for row in rows),by_directory={},future={'preserved':True})
    result['content_sha256']=b.sha(b.pack.runtime.manifest_payload(result))
    b.pack.runtime.validate_manifest(result);return result


def fixture():
    # Existing D-source contract remains real read-only input; this alternate
    # combat pair is deliberately synthetic and never an official proof.
    values={name:(b.ROOT/name).read_bytes() for name in b.PAYLOADS[:12]}
    pins=copy.deepcopy(b.COMPILED)
    for pin in list(pins.values())[:2]:
        raw=(b.ROOT/pin['source']).read_bytes()
        values[pin['source']]=raw.replace(b'\r\n',b'\n') if pin['source_normalization']!='IDENTITY' else raw
    source=b'// SYNTHETIC compiler fixture\nconst anchor = "query";\n'
    compiled=b'SYNTHETIC_COMPILED_NOT_RUNTIME'
    values[b.ARCHIVE]=b'-- SYNTHETIC reviewed archive UI-wire source\nreturn {}\n'
    values[b.PAYLOADS[12]]=compiled;values[pins[b.PAYLOADS[12]]['source']]=source
    pins[b.PAYLOADS[12]].update(source_git_sha256=b.sha(source),source_sha256=b.sha(source),
        source_normalization='IDENTITY',compiled_sha256=b.sha(compiled))
    return values,pins


class ForkTests(unittest.TestCase):
    def setUp(self):
        archive=fixture()[0][b.ARCHIVE]
        self.pins=patch.multiple(b,ARCHIVE_SOURCE_SHA256=b.sha(archive),ARCHIVE_SOURCE_REVIEW_STATUS='ROOT_REVIEWED_UI_WIRE_ONLY')
        self.pins.start();self.addCleanup(self.pins.stop)

    def test_default_plan_is_static_without_git_baseline_file_output_or_key(self):
        with patch.object(b,'baseline',side_effect=AssertionError('No baseline reads')),\
                patch.object(b,'blob',side_effect=AssertionError('No Git')),\
                patch.object(b.pack.protect_data,'sign_manifest',side_effect=AssertionError('No keys')),\
                patch.object(b.inc,'write_new',side_effect=AssertionError('No writes')),redirect_stdout(io.StringIO()) as output:
            b.main([])
        result=json.loads(output.getvalue())
        self.assertEqual(result['status'],'STATIC_V03_PLAN_ONLY_NO_EFFECTS')
        self.assertEqual((result['payload_count'],result['proposed_file_count']),(14,6918))
        self.assertIsNone(result['source_revision']);self.assertFalse(result['steam_initialized'])
        self.assertFalse(result['ready_for_upload']);self.assertFalse(result['canonical_journal_written'])

    def test_static_plan_cannot_accept_report_key_or_commit(self):
        for args in [['--static-plan','--report','fake.json'],['--static-plan','--key','private.pem'],
                ['--static-plan','--source-revision','a'*40]]:
            with self.subTest(args=args),self.assertRaisesRegex(ValueError,'Static plan'):b.main(args)

    def test_scope_is_only_v01_twelve_plus_combat_no_reports_or_player_data(self):
        old=b.module('v03_scope_original_v01',b.ROOT/'tools/arcade_portrait_release_20261031/build_release.py')
        self.assertEqual(b.PAYLOADS[:12],old.PAYLOADS)
        self.assertEqual(b.PAYLOADS[12],'panorama/scripts/custom_game/combat_stats.vjs_c')
        self.assertEqual(b.PAYLOADS[13],b.ARCHIVE)
        frozen=b.module('v03_scope_frozen_v02',b.ROOT/'tools/arcade_portrait_release_v02_20261101/build_release.py')
        self.assertEqual(b.PAYLOADS[:13],frozen.PAYLOADS)
        self.assertEqual(b.COMPILED,frozen.COMPILED)
        self.assertEqual((b.SEQUENCE,b.BASE_SEQUENCE),(2026110103,2026103102))
        self.assertEqual(b.BASE_REPORT_SHA,old.BASE_REPORT_SHA)
        self.assertEqual(b.JOURNAL,old.JOURNAL)
        self.assertEqual(b.COMPILED[b.PAYLOADS[0]],old.COMPILED[old.PAYLOADS[0]])
        self.assertEqual(b.COMPILED[b.PAYLOADS[5]],old.COMPILED[old.PAYLOADS[5]])
        self.assertFalse(any(name.endswith(('.md','.json','.py')) for name in b.PAYLOADS))
        b.inc.disjoint([b.OVERLAY,b.VIEW,b.TRUSTED,b.UNSIGNED,b.OUTPUT,*b.FROZEN_V01_OUTPUTS,*b.FROZEN_V02_OUTPUTS])

    def test_missing_third_pin_blocks_final_collection_before_git_blobs(self):
        pins=copy.deepcopy(b.COMPILED);pins[b.PAYLOADS[12]]['compiled_sha256']=None
        with patch.object(b,'COMPILED',pins),patch.object(b,'immutable_revision',return_value='a'*40),patch.object(b,'blob') as reader:
            with self.assertRaisesRegex(ValueError,'PENDING_OFFICIAL_COMPILER_PROOF'):b.payloads('a'*40)
        reader.assert_not_called()

    def test_real_official_v04_combat_lf_crlf_and_compiled_artifact_are_bound(self):
        b.compiled_pins_ready()
        pin=b.COMPILED[b.PAYLOADS[12]]
        compiler=(b.ROOT/pin['source']).read_bytes()
        committed=compiler.replace(b'\r\n',b'\n')
        binding=b.compiled_source_pin(pin,committed)
        self.assertEqual(binding['git_blob']['sha256'],pin['source_git_sha256'])
        self.assertEqual(binding['compiler_input']['sha256'],pin['source_sha256'])
        self.assertEqual(binding['normalization'],'GIT_LF_TO_COMPILER_CRLF_ONLY')
        self.assertEqual(committed.replace(b'\n',b'\r\n'),compiler)
        compiled=(b.ROOT/b.PAYLOADS[12]).read_bytes()
        self.assertEqual(b.sha(compiled),pin['compiled_sha256'])
        self.assertEqual(len(compiled),221818)

    def test_unknown_pending_wrong_parent_journal_refused_and_history_preserved(self):
        files=[{'name':b.ITEM+'.vpk','bytes':42,'sha256':'a'*64}]
        report=dict(package_files=files,vpk_sha256='a'*64)
        state=dict(uploaded=True,workshop_id=b.ITEM,status='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST',
            owner='76561198845461206',app_id=570,visibility_requested=3,release_sequence=b.BASE_SEQUENCE,
            content_sha256=b.BASE_CONTENT,package_files=files,vpk_sha256='a'*64,vpk_bytes=42,
            legal_agreement_required=False,release_history=[{'synthetic_failed_attempt':index} for index in range(19)],
            previous_release={'synthetic':True})
        before=copy.deepcopy(state);b.require_parent_journal(state,report);self.assertEqual(state,before)
        for key,value in [('status','SUBMIT_REQUEST_PENDING'),('status','UNKNOWN'),('uploaded',False),
                ('release_sequence',2026110101),('vpk_sha256','b'*64),('owner','wrong')]:
            changed=dict(state,**{key:value});snapshot=copy.deepcopy(changed)
            with self.subTest(key=key,value=value),self.assertRaisesRegex(ValueError,'preserve unknown/pending'):
                b.require_parent_journal(changed,report)
            self.assertEqual(changed,snapshot)

    def test_missing_third_compiler_entry_is_not_silently_allowed(self):
        pins=dict(b.COMPILED);pins.pop(b.PAYLOADS[12])
        with patch.object(b,'COMPILED',pins),self.assertRaisesRegex(ValueError,'three distinct'):b.compiled_pins_ready()

    def test_immutable_thirteen_inputs_and_all_three_source_bindings(self):
        values,pins=fixture();bindings={}
        with patch.object(b,'COMPILED',pins),patch.object(b,'immutable_revision',return_value='a'*40),\
                patch.object(b,'blob',side_effect=lambda revision,name:values[name]) as reader:
            revision,actual=b.payloads('a'*40,source_bindings=bindings)
        self.assertEqual(revision,'a'*40);self.assertEqual(set(actual),set(b.PAYLOADS))
        self.assertEqual(reader.call_count,17);self.assertEqual(len(bindings),3)
        for pin in pins.values():
            self.assertEqual(bindings[pin['source']]['git_blob']['sha256'],pin['source_git_sha256'])
            self.assertEqual(bindings[pin['source']]['compiler_input']['sha256'],pin['source_sha256'])

    def test_third_pair_has_same_strict_lf_crlf_contract(self):
        raw=b'// SYNTHETIC LF\nconst q=1;\n'
        pin=dict(source='synthetic_combat.js',source_git_sha256=b.sha(raw),
            source_sha256=b.sha(raw.replace(b'\n',b'\r\n')),source_normalization='GIT_LF_TO_COMPILER_CRLF_ONLY',
            compiled_sha256='a'*64)
        binding=b.compiled_source_pin(pin,raw)
        self.assertNotEqual(binding['git_blob']['sha256'],binding['compiler_input']['sha256'])
        bad=dict(pin,source_normalization='STRIP_WHITESPACE')
        with self.assertRaisesRegex(ValueError,'Unreviewed'):b.compiled_source_pin(bad,raw)

    def test_wrong_third_artifact_or_d_entry_boundary_rejected(self):
        original,pins=fixture()
        for name in [b.PAYLOADS[12],b.PAYLOADS[3],b.ARCHIVE]:
            values=dict(original);values[name]=b'wrong'
            with self.subTest(name=name),patch.object(b,'COMPILED',pins),\
                    patch.object(b,'immutable_revision',return_value='a'*40),\
                    patch.object(b,'blob',side_effect=lambda revision,path:values[path]),self.assertRaises(ValueError):
                b.payloads('a'*40)

    def test_manifest_unknown_fields_directory_counts_and_old_rows_preserved(self):
        before=manifest({'scripts/vscripts/a.lua':b'a','resource/a.txt':b'b'})
        before['files'][0]['future_row']={'keep':True}
        original=copy.deepcopy(before)
        after,changed=b.projected(before,{'scripts/vscripts/new.lua':b'new'})
        self.assertEqual(before,original);self.assertEqual(after['future'],before['future'])
        self.assertEqual(after['files'][0]['future_row'],{'keep':True})
        self.assertEqual(after['by_directory'],{'resource':1,'scripts':2})
        self.assertEqual(set(changed),{'scripts/vscripts/new.lua'})

    def test_v01_plan_cannot_drive_v03_signing_or_read_any_key(self):
        v01=dict(status='PLAN_ONLY_NOT_SIGNED',release_sequence=2026110102,source_revision='a'*40)
        v03=dict(v01,release_sequence=2026110103)
        with patch.object(b,'reviewed_plan',return_value=v01),\
                patch.object(b,'plan',return_value=(v03,{},{},{},b'',[])),\
                patch.object(b.pack.handoff,'regular_path',side_effect=AssertionError('No key read')):
            with self.assertRaisesRegex(ValueError,'changed before key use'):
                b.build_signed('a'*40,Path('synthetic_plan'),'b'*64,Path('not_a_real_key'))

    def test_validator_rejects_a_twelve_file_report_before_baseline_access(self):
        with tempfile.TemporaryDirectory(prefix='v03_synthetic_report_') as temporary:
            directory=Path(temporary)
            report=dict(status='BUILT_SIGNED_PENDING_NATIVE_PERF_ACCEPTANCE',release_sequence=b.SEQUENCE,
                signature_valid=True,full_runtime_validator_passed=True,dry_run=False,payload_changed=False,
                workshop_upload_performed=False,workshop_id=b.ITEM,files=6918,protected_modules_preserved=184,
                all_difficulties_unlocked=False,archive_bundle_hash=b.EXPECTED_BUNDLE,
                changed_runtime_paths=sorted(b.PAYLOADS[:13]),added_runtime_paths=[b.PAYLOADS[1]],removed_runtime_paths=[])
            raw=json.dumps(report).encode();(directory/'package.json').write_bytes(raw)
            with patch.object(c,'b',b),patch.object(b,'REPORT',directory),\
                    patch.object(b,'baseline',side_effect=AssertionError('No parent reads')):
                with self.assertRaisesRegex(ValueError,'scope/counts'):c.validated_package(b.sha(raw))


    def test_archive_pin_missing_blocks_before_git_source_read(self):
        for changed in [dict(ARCHIVE_SOURCE_SHA256=None),dict(ARCHIVE_SOURCE_REVIEW_STATUS='PENDING_ROOT_SOURCE_REVIEW')]:
            with self.subTest(changed=changed),patch.multiple(b,**changed),patch.object(b,'blob') as reader:
                with self.assertRaisesRegex(ValueError,'PENDING_ARCHIVE_SOURCE_REVIEW'):b.payloads('a'*40)
            reader.assert_not_called()

    def test_seventeenth_review_is_from_new_source_not_old_trusted_directory(self):
        values,_=fixture();original={str(i):{'sha256':str(i)} for i in range(16)}
        with patch.object(b,'base_trusted_review',return_value=original.copy()):
            result=b.trusted_review({},values)
        self.assertEqual(len(result),17)
        self.assertEqual(result[b.ARCHIVE],b.checks(values[b.ARCHIVE]))
        self.assertEqual({k:v for k,v in result.items() if k!=b.ARCHIVE},original)
        review=b.archive_review('a'*40,values)
        self.assertEqual(review['source_revision'],'a'*40)
        self.assertFalse(review['all_gameplay_paths_verified']);self.assertFalse(review['protection_transform_required'])
        values[b.ARCHIVE]+=b'-- foreign change'
        with self.assertRaisesRegex(ValueError,'review mismatch'):b.archive_review('a'*40,values)

    def test_archive_is_not_selected_by_frozen_lua_protection_policy(self):
        policy=b.load(b.ROOT/'tools/lua_protection_policy.json')
        paths=[*policy['business_modules'],policy['generated_prefix']+'fixture.lua',b.ARCHIVE]
        selected=b.parent.parent.previous.base.protection.selected_files(paths,policy)
        self.assertNotIn(b.ARCHIVE,{row['path'] for row in selected})


    def test_archive_missing_pin_blocks_final_plan_before_baseline_or_git(self):
        with patch.object(b,'ARCHIVE_SOURCE_SHA256',None),patch.object(b,'baseline') as base,patch.object(b,'immutable_revision') as git:
            with self.assertRaisesRegex(ValueError,'PENDING_ARCHIVE_SOURCE_REVIEW'):b.plan('a'*40)
        base.assert_not_called();git.assert_not_called()

    def test_build_copies_seventeenth_review_from_new_payload_without_reading_old_archive(self):
        # This exercises the actual new exclusive write loop only. Signing,
        # auth, VPK and Git are mocks; these synthetic bytes are never runnable.
        values,_=fixture()
        with tempfile.TemporaryDirectory(prefix='v03_mock_trusted_') as temporary,ExitStack() as stack:
            folder=Path(temporary);base=folder/'old_trusted';base.mkdir()
            reviews={}
            for index in range(16):
                name='original_review_%02d.txt'%index;raw=b'unchanged original '+str(index).encode()
                (base/name).write_bytes(raw);reviews[name]=b.checks(raw)
            reviews[b.ARCHIVE]=b.checks(values[b.ARCHIVE])
            manifest={'content_sha256':'a'*64};report=dict(trusted_review_pins=reviews,rebuilt_archives=[],baseline_package_files=[],source_revision='a'*40)
            for name in ('OVERLAY','TRUSTED','VIEW','OUTPUT','UNSIGNED'):
                stack.enter_context(patch.object(b,name,folder/name))
            stack.enter_context(patch.object(b,'BASE_TRUSTED',base))
            stack.enter_context(patch.object(b,'reviewed_plan',return_value=report.copy()))
            stack.enter_context(patch.object(b,'plan',side_effect=lambda revision:(report.copy(),{},manifest,values,b'',[])))
            stack.enter_context(patch.object(b.parent.parent,'same_plan',return_value=True))
            stack.enter_context(patch.object(b.pack.handoff,'regular_path',side_effect=lambda path:path))
            stack.enter_context(patch.object(b.pack.protect_data,'external',side_effect=lambda path,**kwargs:path))
            stack.enter_context(patch.object(b.inc,'external'))
            stack.enter_context(patch.object(b.inc,'disjoint'))
            stack.enter_context(patch.object(b,'scene_maps',return_value=nullcontext()))
            stack.enter_context(patch.object(b,'baseline'))
            signer=stack.enter_context(patch.object(b.pack.protect_data,'sign_manifest'))
            stack.enter_context(patch.object(b.inc,'metadata',return_value=({}, {}, {})))
            stack.enter_context(patch.object(b.inc,'validate_merged',return_value=({},set(values))))
            stack.enter_context(patch.object(b.inc,'materialize'))
            stack.enter_context(patch.object(b.inc,'trusted_source',return_value=nullcontext()))
            stack.enter_context(patch.object(b.pack,'authenticate',return_value=(None,manifest,{'release_sequence':b.SEQUENCE},None)))
            stack.enter_context(patch.object(b.inc,'build_volumes',return_value=({},[{'sha256':'c'*64}])))
            stack.enter_context(patch.object(b.pack,'package_inventory',return_value=[]))
            stack.enter_context(patch.object(b.pack.runtime,'verify',return_value={'ok':True}))
            stack.enter_context(patch.object(b.pack.runtime,'digest',return_value='b'*64))
            result=b.build_signed('a'*40,folder/'review','a'*64,folder/'fake_keys'/'fake-key-never-read')
            self.assertEqual((b.TRUSTED/b.ARCHIVE).read_bytes(),values[b.ARCHIVE])
            self.assertEqual(len(b.inc.all_files(b.TRUSTED)),17)
            self.assertFalse((base/b.ARCHIVE).exists());signer.assert_called_once()
            self.assertTrue(result['signature_valid'])  # Mock-only field, no real crypto.


    def test_root_reviewed_archive_source_pin_is_exact_git_lf(self):
        # setUp uses synthetic pins for synthetic payload tests. These constants
        # deliberately inspect the separately loaded actual prepared builder.
        real=b.module('v03_archive_actual_constant',DIRECTORY/'build_release.py')
        raw=(real.ROOT/real.ARCHIVE).read_bytes()
        self.assertEqual(real.ARCHIVE_SOURCE_SHA256,'6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4')
        self.assertEqual(real.sha(raw.replace(b'\r\n',b'\n')),real.ARCHIVE_SOURCE_SHA256)
        self.assertEqual(real.ARCHIVE_SOURCE_REVIEW_STATUS,'ROOT_REVIEWED_UI_WIRE_ONLY')
        self.assertEqual(real.sha(raw),'51b554d203485c1ccad6fa9d91cd197cf91ff6400e572e3cdf8c7455f617cd4b')
        real.archive_pin_ready()


    def test_synthetic_final_plan_has_exact14_6918_preserved184_and_seventeen_reviews(self):
        values,pins=fixture();policy=b.load(b.ROOT/'tools/lua_protection_policy.json')
        before={name:b'old '+name.encode() for name in b.PAYLOADS if name!=b.PAYLOADS[1]}
        before.update({name:b'unchanged protected' for name in policy['business_modules']})
        before.update({policy['generated_prefix']+'synthetic_%03d.lua'%i:b'unchanged protected' for i in range(180)})
        for i in range(6917-len(before)):before['synthetic/filler_%04d.bin'%i]=b'unchanged'
        old=manifest(before);original16={str(i):dict(sha256=str(i)) for i in range(16)}
        with patch.object(b,'COMPILED',pins),patch.object(b,'immutable_revision',return_value='a'*40),                patch.object(b,'blob',side_effect=lambda revision,name:values[name]),                patch.object(b,'baseline',return_value=({'package_files':[]},old)),                patch.object(b,'base_trusted_review',return_value=original16.copy()),                patch.object(b.inc,'read_entries',return_value=[]),                patch.object(b.parent.parent.previous.base.parent,'rotation_plan',return_value=(b'', [[],[],[],[]],{0,3},[])),                patch.object(b.inc,'capacity',return_value=[]),patch.object(b.pack.runtime,'digest',return_value='c'*64):
            report,previous,after,changed,_,_=b.plan('a'*40)
        self.assertEqual(report['files'],6918);self.assertEqual(set(changed),set(b.PAYLOADS))
        self.assertEqual(report['protected_modules_preserved'],184)
        self.assertEqual(report['added_runtime_paths'],[b.PAYLOADS[1]])
        self.assertEqual(len(report['trusted_review_pins']),17)
        self.assertEqual(report['archive_source_review']['source_revision'],'a'*40)
        self.assertFalse(report['signature_valid']);self.assertFalse(report['signing_key_read'])
        protected={row['path'] for row in b.parent.parent.previous.base.protection.selected_files(list(before),policy)}
        afterrows={row['path']:row for row in after['files']}
        before_rows={row['path']:row for row in previous['files']}
        self.assertTrue(all(afterrows[name]==before_rows[name] for name in protected))


if __name__=='__main__':unittest.main()
