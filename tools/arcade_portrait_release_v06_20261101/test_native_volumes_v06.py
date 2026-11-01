"""Synthetic/mocked v06 evidence regression. Zero SDK/GUI/real-native actions."""
from pathlib import Path
from contextlib import ExitStack,redirect_stdout
from unittest.mock import patch
import copy
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest

HERE=Path(__file__).resolve().parent

def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

x=module('v06_isolated_under_test',HERE/'publish_native_volumes_v06.py')
base=module('v06_synthetic_fixture_only',HERE/'test_publish.py');base.x=x


def synthetic_map():
    return {name:dict(archive=3 if i in (0,1) else 0,archive_name=x.b.ITEM+'_%03d.vpk'%(3 if i in (0,1) else 0),
        offset=i,bytes=1,payload_sha256='c'*64) for i,name in enumerate(x.b.PAYLOADS)}


class EvidenceCase:
    def __init__(self,root):
        self.f=base.Fixture(root);f=self.f
        f.process['started_utc']=base.utc(0)
        f.review['native_file_use_policy']=x.POLICY
        f.edit(f.review['rehearsal']['process'],started_utc=base.utc(0))
        for ref in f.review['rehearsal']['inspections']:
            f.edit(ref,index_owned_dota_use_observed=False,all_five_open_verified=False,
                all_five_owned_dota_file_uses_observed=False,external_signed_manifest_binding=True,
                external_signed_resources_verified=6918,external_protected_modules_verified=184,
                file_use=[dict(name=name,owned_dota_uses_file=(i>0),owned_keeper_uses_file=True)
                    for i,name in enumerate(x.ops.p.NAMES)])
        anchor=json.dumps(dict(binding='shared_main',sharedMainReason='native_portrait_identity_matches',
            mainRejection=None,entity=653,expectedDisplayUnit=653,nativePortraitUnit=653))
        log=(b'[WS4-NATIVE-HANDOFF-01]\n[Survival][INFO][Addon] initialized\n'+
            ('[SURVIVAL_PORTRAIT] QUERY_ANCHOR '+anchor+'\n').encode()+
            ('[SURVIVAL_MONSTER_PORTRAIT] READY asset= '+x.BANE+' map= portraits/synthetic ms= 97 components= 4\n').encode()+
            ('[SURVIVAL_PORTRAIT] SCENE_SET unit= SYNTHETIC asset= '+x.BANE+' item_def= none\n').encode()+
            b'[SURVIVAL_PORTRAIT] SHOW mode= monster_scene unit= SYNTHETIC\n')
        ref=f.review['rehearsal']['engine_log_final'];ref.update(f.raw(Path(ref['path']),log))


class NativeVolumeTests(unittest.TestCase):
    def setUp(self):
        self.source=patch.object(x.ops,'RUNTIME_SOURCE_REVISION','c'*40)
        self.source.start();self.addCleanup(self.source.stop)
        self.route=patch.object(x.ops,'expected_log_path',side_effect=lambda folder:Path(folder)/'engine.log')
        self.route.start();self.addCleanup(self.route.stop)

    def fixture(self,temporary,stack):
        case=EvidenceCase(temporary);f=case.f
        for item in f.patches():stack.enter_context(item)
        stack.enter_context(patch.object(x,'scope_map',return_value=synthetic_map()))
        sdk=stack.enter_context(patch.object(x.sdk,'Steam',side_effect=AssertionError('No real SDK')))
        return f,sdk

    def test_default_is_static_no_package_or_sdk_or_write(self):
        with patch.object(x.c,'validated_package',side_effect=AssertionError('No package')),\
                patch.object(x.sdk,'Steam') as sdk,redirect_stdout(io.StringIO()) as out:
            self.assertEqual(x.main([]),0)
        sdk.assert_not_called();result=json.loads(out.getvalue());self.assertEqual(result['files_written'],0)
        self.assertFalse(result['ready_for_upload']);self.assertEqual(result['policy'],x.POLICY)

    def test_false_index_stays_false_and_full_preflight_requires_data_volume_policy(self):
        with tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
            f,sdk=self.fixture(temporary,stack)
            before={ref['path']:Path(ref['path']).read_bytes() for ref in f.review['rehearsal']['inspections']}
            journal=f.journal.read_bytes();result=f.run();proof=result['native_volume_evidence']
            self.assertEqual(proof['status'],x.POLICY);self.assertEqual(len(proof['mapping']),14)
            self.assertTrue(result['summary']['ready_for_authorized_original_item_update'])
            self.assertEqual(result['summary']['index_owned_dota_original_observations'],[False,False])
            self.assertEqual(result['summary']['all_five_open_original_observations'],[False,False])
            self.assertEqual(f.journal.read_bytes(),journal)
            self.assertTrue(all(Path(name).read_bytes()==raw for name,raw in before.items()))
            self.assertFalse(proof['raw_receipts_modified']);sdk.assert_not_called()

    def test_missing_volume_bad_ft_index_keeper_unknown_row_and_wrong_parent_refuse(self):
        for mode in ('missing_volume','unused_volume','bad_ft','index_keeper_false','unknown_row','duplicate_row',
                     'parent_wrong','bad_fileid','old_source','changed_index_flag','false_all_open','old_process',
                     'unreviewed_policy','missing_shared_main','missing_scene_set','missing_ready','missing_show'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
                f,sdk=self.fixture(temporary,stack)
                ref=f.review['rehearsal']['inspections'][0]
                value=json.loads(Path(ref['path']).read_bytes())
                if mode=='missing_volume':value['file_use'].pop()
                if mode=='unused_volume':value['file_use'][3]['owned_dota_uses_file']=False
                if mode=='bad_ft':value['process']['native_created_filetime']+=1
                if mode=='index_keeper_false':value['file_use'][0]['owned_keeper_uses_file']=False
                if mode=='unknown_row':value['file_use'][1]['name']='FOREIGN.vpk'
                if mode=='duplicate_row':value['file_use'][2]=dict(value['file_use'][1])
                if mode=='bad_fileid':value['held_files'][0]['file_index']+=99
                if mode=='old_source':value['source_revision']='f'*40
                if mode=='changed_index_flag':value['index_owned_dota_use_observed']=True
                if mode=='false_all_open':value['all_five_open_verified']=True
                if mode=='old_process':f.edit(f.review['rehearsal']['process'],started_utc=base.utc(1))
                if mode=='parent_wrong':f.save(f.journal,dict(f.state,release_sequence=2026103102))
                if mode=='unreviewed_policy':f.review.pop('native_file_use_policy')
                if mode.startswith('missing_') and mode!='missing_volume':
                    logref=f.review['rehearsal']['engine_log_final'];path=Path(logref['path']);raw=path.read_bytes()
                    key={'missing_shared_main':b'QUERY_ANCHOR','missing_scene_set':b'SCENE_SET',
                        'missing_ready':b'READY','missing_show':b'SHOW'}[mode]
                    raw=b'\n'.join(line for line in raw.splitlines() if key not in line)
                    logref.update(f.raw(path,raw))
                ref.update(f.save(Path(ref['path']),value))
                with self.assertRaises(ValueError):f.run()
                sdk.assert_not_called()

    def test_frozen_parent_index_rules_only_are_replaced_and_parent_bytes_remain(self):
        self.assertEqual(hashlib.sha256(x.PARENT.read_bytes()).hexdigest(),x.PARENT_SHA)
        self.assertEqual(x._original_source.count(x._old_a),1);self.assertEqual(x._original_source.count(x._old_b),1)
        expected=x._original_source.replace(x._old_a,x._new_a).replace(x._old_b,x._new_b).replace(
            'Owned Dota/keeper candidate index observation required','Authenticated signed index and complete native data-volume use required')
        self.assertEqual(x._adapted_source,expected)
        with patch.object(x,'PARENT_SHA','0'*64),self.assertRaisesRegex(ValueError,'Frozen1106'):x.require_parent()

    def test_actual_scope_map_checks_signed_index_hash_all14_entries_and_archives(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary);path=directory/(x.b.ITEM+'.vpk');path.write_bytes(b'SYNTHETIC INDEX')
            pin=dict(name=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            package=dict(package_files=[pin],changed_runtime_paths=sorted(x.b.PAYLOADS),
                target_pins={name:dict(bytes=1,sha256='a'*64) for name in x.b.PAYLOADS})
            entries=[dict(path=name,archive=3 if i in (0,1) else 0,offset=i,bytes=1) for i,name in enumerate(x.b.PAYLOADS)]
            with patch.object(x.b,'OUTPUT',directory),patch.object(x.b.inc,'read_entries',return_value=entries):
                self.assertEqual(len(x.scope_map(package)),14)
                for mode in ('wrong_hash','missing_entry','unknown_archive','wrong_bytes'):
                    changed=copy.deepcopy(package);rows=copy.deepcopy(entries)
                    if mode=='wrong_hash':changed['package_files'][0]['sha256']='f'*64
                    if mode=='missing_entry':rows.pop()
                    if mode=='unknown_archive':rows[0]['archive']=32767
                    if mode=='wrong_bytes':rows[0]['bytes']=2
                    with self.subTest(mode=mode),patch.object(x.b.inc,'read_entries',return_value=rows),self.assertRaises(ValueError):x.scope_map(changed)


if __name__=='__main__':unittest.main()
