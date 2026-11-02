"""Synthetic source/projection tests; no signing, package build or native action."""
from pathlib import Path
from types import SimpleNamespace
import copy
import importlib.util
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('lottery_hotfix_test_builder',HERE/'build_release.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)


class BuildTests(unittest.TestCase):
    def test_static_does_not_read_parent_git_key_or_create_outputs(self):
        with patch.object(b,'baseline',side_effect=AssertionError('No baseline')),\
             patch.object(b,'immutable_revision',side_effect=AssertionError('No Git')),\
             patch.object(Path,'mkdir',side_effect=AssertionError('No writes')):
            value=b.static_plan()
        self.assertEqual((value['payload_count'],value['proposed_file_count'],value['files_written']),(4,6917,0))
        self.assertTrue(value['unpublished0201_preserved'])

    def test_scope_is_four_existing_ui_resources_and_no_0201_payload(self):
        self.assertEqual(len(b.PAYLOADS),4)
        self.assertEqual(b.ADDED_RUNTIME_PATHS,())
        self.assertTrue(all('lottery_cinematic_v1' in n for n in b.PAYLOADS[:2]))
        self.assertEqual(set(b.PAYLOADS[2:]),set(b.TRAINING_SOURCE_PINS))
        self.assertFalse(any('portrait' in n or 'challenge' in n for n in b.PAYLOADS))

    def test_two_compiler_proofs_are_ready_and_css_uses_styles_mirror(self):
        b.compiled_pins_ready()
        self.assertEqual(len(b.COMPILED),2)
        self.assertEqual(b.COMPILED[b.PAYLOADS[1]]['content_source'],
                         'panorama/styles/custom_game/lottery_cinematic_v1.css')

    def test_missing_compiler_proof_blocks_before_git_blob_or_key_use(self):
        pins=copy.deepcopy(b.COMPILED);pins[b.PAYLOADS[0]]['compiled_sha256']=None
        with patch.object(b,'COMPILED',pins),patch.object(b,'immutable_revision',return_value='a'*40),\
             patch.object(b,'blob',side_effect=AssertionError('No blob read')):
            with self.assertRaisesRegex(ValueError,'PENDING_OFFICIAL_COMPILER_PROOF'):
                b.payloads('a'*40)

    def test_compiler_input_normalization_is_exact_and_wrong_git_rejected(self):
        raw=b'x\ny\n';compiler=raw.replace(b'\n',b'\r\n')
        pin=dict(source='test.js',source_git_sha256=b.sha(raw),source_sha256=b.sha(compiler),
                 source_normalization='GIT_LF_TO_COMPILER_CRLF_ONLY',compiled_sha256='a'*64)
        self.assertEqual(b.compiled_source_pin(pin,raw)['compiler_input']['sha256'],b.sha(compiler))
        with self.assertRaises(ValueError):b.compiled_source_pin(pin,raw+b' ')

    def test_projector_preserves_unknown_parent_rows_fields_and_original_input(self):
        names=[*b.PAYLOADS,'scripts/vscripts/systems/shared_challenge_boss_registry.lua']
        old={'files':[dict(path=n,**b.checks(b'old'),unknown='retained') for n in names],
             'file_count':len(names),'bytes':3*len(names),'custom_parent':'retained'}
        before=copy.deepcopy(old);values={n:b'new' for n in b.PAYLOADS}
        with patch.object(b.pack.runtime,'manifest_payload',side_effect=lambda m:b.pack.runtime.canonical_bytes(m)),\
             patch.object(b.pack.runtime,'validate_manifest',return_value=True):
            after,changed=b.projected(old,values)
        self.assertEqual(old,before);self.assertEqual(set(changed),set(b.PAYLOADS))
        self.assertEqual(after['custom_parent'],'retained')
        self.assertTrue(all(row['unknown']=='retained' for row in after['files']))
        sentinel=names[-1]
        self.assertEqual(next(row for row in after['files'] if row['path']==sentinel),before['files'][-1])

    def test_parent_admission_six_rows_cannot_change(self):
        rows=[dict(path=n,sha256='a'*64,bytes=1) for n in b.ADMISSION_PATHS]
        old={'files':rows};new=copy.deepcopy(old)
        self.assertEqual(set(b.preserved_admission(old,new)),set(b.ADMISSION_PATHS))
        new['files'][0]['sha256']='b'*64
        with self.assertRaises(ValueError):b.preserved_admission(old,new)

    def test_training_reviews_add_only_two_and_reject_drift(self):
        values={n:('source-'+n).encode() for n in b.ADDITIONAL_SOURCE_REVIEWS}
        pins={n:b.sha(v) for n,v in values.items()}
        parent={f'parent{i}':b.checks(b'original') for i in range(18)}
        with patch.object(b,'base_trusted_review',return_value=parent),patch.object(b,'TRAINING_SOURCE_PINS',pins):
            self.assertEqual(len(b.trusted_review({},values)),20)
            values[next(iter(values))]=b'changed'
            with self.assertRaises(ValueError):b.trusted_review({},values)

    def test_operator_aux_and_external_paths_preserve_frozen0201(self):
        self.assertIn('tools/lottery_hotfix_release_20261102/ledger.py',b.AUXILIARY_INPUTS)
        self.assertIn('tools/portrait_resolution_release_20261102/build_release.py',b.AUXILIARY_INPUTS)
        self.assertTrue(all('shared_boss_portrait_v08' in str(p) for p in b.FROZEN_V08_OUTPUTS))
        self.assertTrue(all(p!=b.VIEW for p in b.FROZEN_V08_OUTPUTS))


class LedgerTests(unittest.TestCase):
    def fixture(self):
        game,content='a'*40,'b'*40
        a=b'new';old=b'old';source=b'x\n';boss=b'unpublished0201'
        row=lambda value:dict(kind='blob',mode='100644',oid=b.sha(value))
        game_tree={n:row(a) for n in b.PAYLOADS}
        for pin in b.COMPILED.values():game_tree[pin['source']]=row(source)
        game_tree['scripts/vscripts/systems/boss.lua']=row(boss)
        mirrors={p['content_source']:row(source) for p in b.COMPILED.values()}
        inventory={'game':copy.deepcopy(game_tree),'content':copy.deepcopy(mirrors)}
        snapshot=dict(source_inventory=inventory,source_anchors={'game':'c'*40,'content':'d'*40},
            deferred_sources={},resource_origins={n:dict(kind='FROZEN_SIGNED_RESOURCE') for n in b.PAYLOADS},
            source_gap_audit_sha256='1'*64,binary_gap_audit_sha256='2'*64,
            resource_origins_sha256='3'*64,parent_manifest_sha256='4'*64)
        values={n:a for n in b.PAYLOADS}
        sources={p['source']:{} for p in b.COMPILED.values()}
        compiled={n:{**p,'source_git_sha256':b.sha(source)} for n,p in b.COMPILED.items()}
        parent={'content_sha256':'5'*64,'files':[dict(path=n,**b.checks(old)) for n in b.PAYLOADS]}
        trees={'game':game_tree,'content':mirrors}
        def git_tree(root,commit):return trees['game' if Path(root)==b.ROOT else 'content']
        def blob(root,commit,name):return boss if name.endswith('/boss.lua') else source
        fake=SimpleNamespace(**b.__dict__);fake.COMPILED=compiled
        fake.git_export=SimpleNamespace(git_tree=git_tree);fake.blob_at=blob
        return fake,game,content,parent,values,sources,snapshot,trees

    def audit(self,items):
        fake,game,content,parent,values,sources,snapshot,trees=items
        with patch.object(b.ledger,'load_baseline',return_value=snapshot),\
             patch.object(b.ledger,'deferred0201',return_value={'game':{'scripts/vscripts/systems/boss.lua'},'content':set()}),\
             patch.object(fake.pack.runtime,'digest',return_value='4'*64):
            return b.ledger.audit(fake,game,content,parent,values,sources)

    def test_real_ledger_explicitly_defers_not_publishes0201_and_binds_css(self):
        items=self.fixture();result=self.audit(items)
        self.assertEqual(len(result['changed_runtime_paths']),4)
        self.assertFalse(result['full_head_publication_claimed'])
        self.assertEqual(len(result['deferred_unpublished0201_sources']),1)
        self.assertEqual(items[5][items[0].COMPILED[b.PAYLOADS[1]]['source']]['content_mirror']['path'],
                         'panorama/styles/custom_game/lottery_cinematic_v1.css')

    def test_real_ledger_refuses_unreviewed_other_runtime_drift(self):
        items=self.fixture();items[7]['game']['scripts/vscripts/unknown.lua']=dict(kind='blob',mode='100644',oid='x')
        with self.assertRaisesRegex(ValueError,'NEW_UNREVIEWED_RUNTIME_SOURCE_DRIFT'):self.audit(items)

    def test_real_ledger_refuses_admitted_symlink_mode(self):
        items=self.fixture();items[7]['game'][b.PAYLOADS[0]]['mode']='120000'
        with self.assertRaisesRegex(ValueError,'invalid_source_file_mode'):self.audit(items)

    def test_real_ledger_refuses_changed_deferred0201_bytes(self):
        items=self.fixture();fake=items[0]
        original=fake.blob_at
        fake.blob_at=lambda root,commit,name:(b'new-unreviewed' if commit==items[1] and name.endswith('/boss.lua') else original(root,commit,name))
        with self.assertRaisesRegex(ValueError,'changed_unpublished0201_source'):self.audit(items)


if __name__=='__main__':unittest.main()
