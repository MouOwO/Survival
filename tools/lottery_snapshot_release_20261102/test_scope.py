"""Pure fixtures for five-scope thin reuse; no keys/build/native/SDK actions."""
from pathlib import Path
from types import ModuleType
import copy
import hashlib
import importlib.util
import tempfile
import unittest
from unittest.mock import Mock,patch

HERE=Path(__file__).resolve().parent
def module(name):
    s=importlib.util.spec_from_file_location('test_snapshot0203_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
outer=module('build_release');b=outer.impl
ops=module('rehearsal');download=module('verify_download');checks=module('release_checks')


class ScopeTests(unittest.TestCase):
    def test_default_is_five_static_without_git_parent_key_or_writes(self):
        with patch.object(b,'baseline',side_effect=AssertionError('No parent IO')),\
             patch.object(b,'blob',side_effect=AssertionError('No Git')),\
             patch.object(Path,'mkdir',side_effect=AssertionError('No writes')):
            p=b.static_plan()
        self.assertEqual((p['payload_count'],p['trusted_review_count'],p['files_written']),(5,20,0))
        self.assertEqual((p['training_source_reviews'],p['archive_wire_source_reviews']),(2,1))

    def test_scope_promotes_only_reviewed_archive_from_frozen0202(self):
        self.assertEqual(b.PAYLOADS[-1],b.ARCHIVE)
        self.assertEqual(len(b.PAYLOADS),5)
        self.assertEqual(b.ARCHIVE_SOURCE_SHA256,'6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4')
        self.assertEqual(len(b.COMPILED),2)
        self.assertEqual(b.ADDED_RUNTIME_PATHS,())
        self.assertEqual(set(b.ADDITIONAL_SOURCE_REVIEWS),set(b.SOURCE_REVIEW_PINS))

    def test_all_old0202_outputs_are_explicitly_preserved(self):
        self.assertEqual(len(b.FROZEN_V09_OUTPUTS),5)
        self.assertTrue(all('lottery_hotfix_v09' in str(p) for p in b.FROZEN_V09_OUTPUTS))
        self.assertTrue(all(b.VIEW!=p for p in b.FROZEN_V09_OUTPUTS))

    def test_parent18_projection_replaces_router_and_adds_two_new_sources(self):
        router=next(iter(b.REPLACED_PARENT_REVIEWS))
        parent={f'parent{i}':b.checks(b'original') for i in range(17)}
        parent[router]=b.checks(b'old-router')
        original=copy.deepcopy(parent)
        values={n:('new '+n).encode() for n in b.ADDITIONAL_SOURCE_REVIEWS}
        pins={n:b.sha(v) for n,v in values.items()}
        with patch.object(b,'base_trusted_review',return_value=parent),patch.object(b,'SOURCE_REVIEW_PINS',pins):
            result=b.trusted_review({},values)
            self.assertEqual(len(result),20)
            self.assertEqual(set(result)-set(parent),set(b.NEW_SOURCE_REVIEWS))
            self.assertEqual(sum(result[n]==p for n,p in parent.items()),17)
            values[b.ARCHIVE]=b'wrong-wire'
            with self.assertRaises(ValueError):b.trusted_review({},values)
        self.assertEqual(parent,original)

    def test_training_roles_do_not_absorb_archive_wire_review(self):
        values={n:('new '+n).encode() for n in b.ADDITIONAL_SOURCE_REVIEWS}
        result=b.training_review('a'*40,values)
        self.assertEqual(set(result),set(b.TRAINING_SOURCE_PINS))
        self.assertNotIn(b.ARCHIVE,result)
        with self.assertRaises(ValueError):b.archive_review('a'*40,values)

    def test_ledger_removes_only_archive_from_deferred_domain(self):
        old={'game':{b.ARCHIVE,*{f'game{i}' for i in range(19)}},'content':{f'content{i}' for i in range(3)}}
        with patch.object(b.ledger,'_parent_deferred',return_value=old):
            result=b.ledger.deferred0201(b)
        self.assertEqual((len(result['game']),len(result['content'])),(19,3))
        self.assertNotIn(b.ARCHIVE,result['game']);self.assertIn(b.ARCHIVE,old['game'])

    def test_ledger_wrapper_requires_exact_five_and22_remaining_deferrals(self):
        value=dict(changed_runtime_paths=list(b.PAYLOADS),deferred_unpublished0201_sources={str(i):{} for i in range(22)})
        with patch.object(b.ledger,'_parent_audit',return_value=value):
            result=b.ledger.audit(b,None)
        self.assertEqual(result['promoted0201_source']['path'],b.ARCHIVE)
        value['deferred_unpublished0201_sources']['extra']={}
        with patch.object(b.ledger,'_parent_audit',return_value=value):
            with self.assertRaises(ValueError):b.ledger.audit(b,None)

    def test_frozen_dependency_hash_rejected_before_module_execution(self):
        with tempfile.TemporaryDirectory(prefix='synthetic-snapshot-adapter-') as directory:
            p=Path(directory)/'probe.py';p.write_bytes(b'raise AssertionError("must not execute")\n')
            with patch.object(outer.a,'PARENT',Path(directory)):
                with self.assertRaisesRegex(ValueError,'Frozen0202 dependency changed'):
                    outer.a.frozen('probe','0'*64)

    def test_function_transform_requires_exact_once_match(self):
        m=ModuleType('synthetic');m.__file__='synthetic.py';m._frozen_source='def f():\n    return "x"+"x"\n'
        with self.assertRaisesRegex(ValueError,'adaptation differs'):
            outer.a.function(m,'f',[("x","y")])

    def test_ops_are_new_ordinary_process_and_same_handle_close_globals(self):
        p=ops.static_plan();self.assertEqual((p['port'],p['release_sequence'],p['scoped_runtime_paths']),(29064,2026110203,5))
        self.assertIn('lottery_snapshot_v10',p['external_store'])
        argv=ops.arguments(Path('D:/test/engine.log'),'direct')
        self.assertIn('29064',argv);self.assertNotIn('29062',argv);self.assertNotIn('-tools',argv)
        self.assertIs(ops.impl.v4.r.own_code_pins,ops.own_code_pins)
        self.assertIs(ops.impl.p.package_auth,ops.impl.package_auth)

    def test_download_contract_is_five20_and_no_sdk(self):
        download.require_family_identity();p=download.static_plan()
        self.assertEqual((p['release_sequence'],p['runtime_files'],p['scoped_runtime_paths'],p['trusted_reviews']),
                         (2026110203,6917,5,20))
        self.assertEqual(p['downloads_requested'],0);self.assertFalse(p['steam_initialized'])

    def test_checks_add_archive_wire_proof_after_full_parent_authentication(self):
        c=checks.impl;values={b.ARCHIVE:b'fixture'};wire={'fixture':'wire'}
        report=dict(source_revision='a'*40,archive_source_review=wire,trusted_review_pins={str(i):{} for i in range(20)},training_ui_source_review={'router':{},'production':{}})
        with patch.object(checks,'_parent_validate',return_value=(report,{},{})),\
             patch.object(c.b,'payloads',return_value=('a'*40,values)),\
             patch.object(c.b,'archive_review',return_value=wire):
            self.assertEqual(checks.validated_package('b'*64)[0],report)
            report['archive_source_review']={'wrong':'proof'}
            with self.assertRaises(ValueError):checks.validated_package('b'*64)


if __name__=='__main__':unittest.main()
