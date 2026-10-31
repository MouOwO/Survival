"""Offline admission/manifest/unsigned-boundary checks; no real keys or Steam."""
from pathlib import Path
import copy
import json
import sys
import tempfile
import unittest
from unittest.mock import Mock,patch
import build_release as b


def manifest(values):
    rows=[{'path':name,**b.checks(raw)} for name,raw in sorted(values.items())]
    value=dict(schema=2,kind='runtime_release_allowlist',hash_algorithms=['md5','sha256'],
        files=rows,file_count=len(rows),bytes=sum(row['bytes'] for row in rows),by_directory={},
        source_root='historical diagnostic source',future_metadata={'keep':['all','fields']})
    value['content_sha256']=b.sha(b.pack.runtime.manifest_payload(value))
    b.pack.runtime.validate_manifest(value)
    return value


def save(path,value):
    raw=(json.dumps(value)+'\n').encode();path.write_bytes(raw);return b.sha(raw)


class BuildAdmissionTests(unittest.TestCase):
    def test_real_renderer_git_lf_reconstructs_only_the_pinned_compiler_crlf(self):
        pin=b.COMPILED[b.PAYLOADS[0]]
        compiler_input=(b.ROOT/pin['source']).read_bytes()
        committed=compiler_input.replace(b'\r\n',b'\n')
        result=b.compiled_source_pin(pin,committed)
        self.assertEqual(result['git_blob']['sha256'],pin['source_git_sha256'])
        self.assertEqual(result['compiler_input']['sha256'],pin['source_sha256'])
        self.assertNotEqual(result['git_blob']['sha256'],result['compiler_input']['sha256'])
        self.assertEqual(result['normalization'],'GIT_LF_TO_COMPILER_CRLF_ONLY')
        self.assertEqual(committed.replace(b'\n',b'\r\n'),compiler_input)

    def test_compiler_binding_rejects_mixed_cr_or_unapproved_text_conversion(self):
        committed=b'a\r\nb\n'
        pin=dict(source='synthetic.js',source_git_sha256=b.sha(committed),source_sha256=b.sha(committed),
            source_normalization='GIT_LF_TO_COMPILER_CRLF_ONLY',compiled_sha256='c'*64)
        with self.assertRaisesRegex(ValueError,'LF only'):b.compiled_source_pin(pin,committed)
        pin['source_normalization']='STRIP_WHITESPACE'
        with self.assertRaisesRegex(ValueError,'Unreviewed'):b.compiled_source_pin(pin,committed)

    def test_real_commerce_source_binding_remains_byte_identical(self):
        pin=b.COMPILED[b.PAYLOADS[5]]
        committed=(b.ROOT/pin['source']).read_bytes()
        result=b.compiled_source_pin(pin,committed)
        self.assertEqual(result['git_blob'],result['compiler_input'])
        self.assertEqual(result['normalization'],'IDENTITY')

    def test_payload_collection_records_both_git_and_compiler_hashes(self):
        values={name:(b.ROOT/name).read_bytes() for name in b.PAYLOADS}
        for pin in b.COMPILED.values():
            raw=(b.ROOT/pin['source']).read_bytes()
            values[pin['source']]=raw.replace(b'\r\n',b'\n') if pin['source_normalization']!='IDENTITY' else raw
        bindings={}
        with patch.object(b,'immutable_revision',return_value='a'*40),patch.object(b,'blob',side_effect=lambda revision,name:values[name]):
            revision,payloads=b.payloads('a'*40,source_bindings=bindings)
        self.assertEqual(revision,'a'*40)
        self.assertEqual(set(payloads),set(b.PAYLOADS))
        self.assertEqual(set(bindings),{pin['source'] for pin in b.COMPILED.values()})
        for pin in b.COMPILED.values():
            self.assertEqual(bindings[pin['source']]['git_blob']['sha256'],pin['source_git_sha256'])
            self.assertEqual(bindings[pin['source']]['compiler_input']['sha256'],pin['source_sha256'])

    def test_projection_preserves_unknown_top_and_row_fields_and_recounts(self):
        original=manifest({'scripts/vscripts/a.lua':b'old','resource/a.txt':b'text'})
        original['files'][1]['future_row']={'retained':True}
        original['content_sha256']=b.sha(b.pack.runtime.manifest_payload(original))
        before=copy.deepcopy(original)
        result,changed=b.projected(original,{'scripts/vscripts/a.lua':b'changed','scripts/vscripts/new.lua':b'new'})
        self.assertEqual(set(changed),{'scripts/vscripts/a.lua','scripts/vscripts/new.lua'})
        self.assertEqual(result['future_metadata'],original['future_metadata'])
        self.assertEqual(result['files'][1]['future_row'],{'retained':True})
        self.assertEqual(result['by_directory'],{'resource':1,'scripts':2})
        self.assertEqual(original,before)
        b.pack.runtime.validate_manifest(result)

    def test_projection_rejects_unsafe_or_case_colliding_paths(self):
        original=manifest({'resource/a.txt':b'a'})
        for name in ('../escape.lua','resource/A.txt'):
            with self.subTest(name=name),self.assertRaises(ValueError):b.projected(original,{name:b'b'})

    def test_source_alias_is_rejected_before_git_lookup(self):
        with patch.object(b.parent.parent,'revision',side_effect=AssertionError('git_lookup')) as resolve:
            for name in ('HEAD','dev','',None,'a'*39):
                with self.subTest(name=name),self.assertRaisesRegex(ValueError,'immutable40'):b.immutable_revision(name)
            resolve.assert_not_called()

    def test_exact_commit_is_still_resolved_and_checked(self):
        with patch.object(b.parent.parent,'revision',return_value='a'*40):self.assertEqual(b.immutable_revision('a'*40),'a'*40)
        with patch.object(b.parent.parent,'revision',return_value='b'*40):
            with self.assertRaisesRegex(ValueError,'identity differs'):b.immutable_revision('a'*40)

    def test_review_requires_sha_and_does_not_accept_signed_payload_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'plan.json';value=dict(status='PLAN_ONLY_NOT_SIGNED',dry_run=True,signature_valid=False)
            digest=save(path,value)
            self.assertEqual(b.reviewed_plan(path,digest),value)
            with self.assertRaisesRegex(ValueError,'SHA'):b.reviewed_plan(path,'0'*64)
            value['payload_changed']=False;digest=save(path,value)
            with self.assertRaisesRegex(ValueError,'unsigned plan'):b.reviewed_plan(path,digest)

    def test_wrong_plan_sha_never_enters_plan_or_key_operation(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'plan.json';save(path,{})
            with (patch.object(b,'plan',side_effect=AssertionError('must_not_plan')) as plan,
                  patch.object(b.pack.protect_data,'sign_manifest',side_effect=AssertionError('must_not_sign')) as sign):
                with self.assertRaisesRegex(ValueError,'SHA'):b.build_signed('a'*40,path,'0'*64,Path(directory)/'nonexistent.pem')
                plan.assert_not_called();sign.assert_not_called()

    def test_unsigned_review_contains_all_twelve_and_no_signature_or_key_use(self):
        with tempfile.TemporaryDirectory() as directory:
            directory=Path(directory);target=directory/'new_unsigned'
            values={name:('synthetic:'+name).encode() for name in b.PAYLOADS}
            projected=manifest(values)
            actual=dict(status='PLAN_ONLY_NOT_SIGNED',dry_run=True,signature_valid=False,
                target_pins={name:b.checks(raw) for name,raw in values.items()},content_sha256=projected['content_sha256'])
            path=directory/'plan.json';digest=save(path,actual)
            def plan(_):return copy.deepcopy(actual),{},copy.deepcopy(projected),values,None,None
            with (patch.object(b,'UNSIGNED',target),patch.object(b,'plan',side_effect=plan),
                  patch.object(b.pack.protect_data,'sign_manifest',side_effect=AssertionError('must_not_sign')) as sign):
                result=b.prepare_unsigned('a'*40,path,digest)
                self.assertEqual(result['status'],'UNSIGNED_REVIEW_READY_NOT_PUBLISHABLE')
                self.assertTrue(result['dry_run']);self.assertFalse(result['signature_valid'])
                self.assertNotIn('payload_changed',result)
                self.assertFalse((target/b.pack.handoff.SIGNATURE).exists())
                self.assertEqual(b.inc.all_files(target),set(b.PAYLOADS)|{b.pack.handoff.MANIFEST,'_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json'})
                sign.assert_not_called()
                with self.assertRaisesRegex(ValueError,'New unsigned'):b.prepare_unsigned('a'*40,path,digest)

    def test_frozen_parent_import_does_not_replace_this_builder_alias(self):
        self.assertIs(__import__('build_release'),b)
        self.assertIs(b.parent_checks.build,b.parent)
        self.assertEqual(b.parent_checks.build.SEQUENCE,2026103102)

    def test_validator_by_path_does_not_bind_an_unrelated_builder(self):
        wrong=Mock(__file__='D:/unrelated/build_release.py')
        with patch.dict(sys.modules,{'build_release':wrong}):
            checks=b.module('isolated_1101_readonly_checks',Path(__file__).with_name('release_checks.py'))
            self.assertEqual(checks.b.SEQUENCE,2026110101)
            self.assertEqual(checks.b.ROOT,b.ROOT)
            self.assertIs(sys.modules['build_release'],wrong)


if __name__=='__main__':unittest.main()
