"""Pure synthetic v02 fork checks. No real plan, key, SDK or installation."""
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import Mock,patch
import copy
import importlib.util
import io
import json
import tempfile
import unittest

DIRECTORY=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('portrait_v02_test_builder',DIRECTORY/'build_release.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
spec=importlib.util.spec_from_file_location('portrait_v02_test_checks',DIRECTORY/'release_checks.py')
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
    values[b.PAYLOADS[12]]=compiled;values[pins[b.PAYLOADS[12]]['source']]=source
    pins[b.PAYLOADS[12]].update(source_git_sha256=b.sha(source),source_sha256=b.sha(source),
        source_normalization='IDENTITY',compiled_sha256=b.sha(compiled))
    return values,pins


class ForkTests(unittest.TestCase):
    def test_default_plan_is_static_without_git_baseline_file_output_or_key(self):
        with patch.object(b,'baseline',side_effect=AssertionError('No baseline reads')),\
                patch.object(b,'blob',side_effect=AssertionError('No Git')),\
                patch.object(b.pack.protect_data,'sign_manifest',side_effect=AssertionError('No keys')),\
                patch.object(b.inc,'write_new',side_effect=AssertionError('No writes')),redirect_stdout(io.StringIO()) as output:
            b.main([])
        result=json.loads(output.getvalue())
        self.assertEqual(result['status'],'STATIC_V02_PLAN_ONLY_NO_EFFECTS')
        self.assertEqual((result['payload_count'],result['proposed_file_count']),(13,6918))
        self.assertIsNone(result['source_revision']);self.assertFalse(result['steam_initialized'])
        self.assertFalse(result['ready_for_upload']);self.assertFalse(result['canonical_journal_written'])

    def test_static_plan_cannot_accept_report_key_or_commit(self):
        for args in [['--static-plan','--report','fake.json'],['--static-plan','--key','private.pem'],
                ['--static-plan','--source-revision','a'*40]]:
            with self.subTest(args=args),self.assertRaisesRegex(ValueError,'Static plan'):b.main(args)

    def test_scope_is_only_v01_twelve_plus_combat_no_reports_or_player_data(self):
        old=b.module('v02_scope_original_v01',b.ROOT/'tools/arcade_portrait_release_20261031/build_release.py')
        self.assertEqual(b.PAYLOADS[:12],old.PAYLOADS)
        self.assertEqual(b.PAYLOADS[12],'panorama/scripts/custom_game/combat_stats.vjs_c')
        self.assertEqual((b.SEQUENCE,b.BASE_SEQUENCE),(2026110102,2026103102))
        self.assertEqual(b.BASE_REPORT_SHA,old.BASE_REPORT_SHA)
        self.assertEqual(b.JOURNAL,old.JOURNAL)
        self.assertEqual(b.COMPILED[b.PAYLOADS[0]],old.COMPILED[old.PAYLOADS[0]])
        self.assertEqual(b.COMPILED[b.PAYLOADS[5]],old.COMPILED[old.PAYLOADS[5]])
        self.assertFalse(any(name.endswith(('.md','.json','.py')) for name in b.PAYLOADS))
        b.inc.disjoint([b.OVERLAY,b.VIEW,b.TRUSTED,b.UNSIGNED,b.OUTPUT,*b.FROZEN_V01_OUTPUTS])

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
        self.assertEqual(reader.call_count,16);self.assertEqual(len(bindings),3)
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
        for name in [b.PAYLOADS[12],b.PAYLOADS[3]]:
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

    def test_v01_plan_cannot_drive_v02_signing_or_read_any_key(self):
        v01=dict(status='PLAN_ONLY_NOT_SIGNED',release_sequence=2026110101,source_revision='a'*40)
        v02=dict(v01,release_sequence=2026110102)
        with patch.object(b,'reviewed_plan',return_value=v01),\
                patch.object(b,'plan',return_value=(v02,{},{},{},b'',[])),\
                patch.object(b.pack.handoff,'regular_path',side_effect=AssertionError('No key read')):
            with self.assertRaisesRegex(ValueError,'changed before key use'):
                b.build_signed('a'*40,Path('synthetic_plan'),'b'*64,Path('not_a_real_key'))

    def test_validator_rejects_a_twelve_file_report_before_baseline_access(self):
        with tempfile.TemporaryDirectory(prefix='v02_synthetic_report_') as temporary:
            directory=Path(temporary)
            report=dict(status='BUILT_SIGNED_PENDING_NATIVE_PERF_ACCEPTANCE',release_sequence=b.SEQUENCE,
                signature_valid=True,full_runtime_validator_passed=True,dry_run=False,payload_changed=False,
                workshop_upload_performed=False,workshop_id=b.ITEM,files=6918,protected_modules_preserved=184,
                all_difficulties_unlocked=False,archive_bundle_hash=b.EXPECTED_BUNDLE,
                changed_runtime_paths=sorted(b.PAYLOADS[:12]),added_runtime_paths=[b.PAYLOADS[1]],removed_runtime_paths=[])
            raw=json.dumps(report).encode();(directory/'package.json').write_bytes(raw)
            with patch.object(c,'b',b),patch.object(b,'REPORT',directory),\
                    patch.object(b,'baseline',side_effect=AssertionError('No parent reads')):
                with self.assertRaisesRegex(ValueError,'scope/counts'):c.validated_package(b.sha(raw))


if __name__=='__main__':unittest.main()
