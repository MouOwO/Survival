"""Draft composed-controller safety and actual Python/Lua probe, no remote I/O."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from unittest.mock import Mock,patch

HERE=Path(__file__).resolve().parent
ROOT=next(p for p in HERE.parents if(p/'scripts/vscripts').is_dir()and(p/'tools').is_dir())
sys.path.insert(0,str(ROOT/'server/tests'))
import test_ws4_compact_deploy_safety as previous_safety
import test_ws4_compact_drain_gate as previous_gate
spec=importlib.util.spec_from_file_location('daily_controller_under_test',HERE/'deploy.py')
deploy=importlib.util.module_from_spec(spec);spec.loader.exec_module(deploy)
probe=deploy.load('daily_probe_under_test',HERE/'probe.py')


class Safety(previous_safety.DeploymentSafety):
    def setUp(self):
        with patch.object(previous_safety,'deploy',deploy):super().setUp()
        self.env['WIRE_TARGET']=deploy.WIRE_TARGET
        self.target_unit=self.env['unit_pair']()[1]
        self.unit.write_bytes(self.target_unit)
        (self.records/'candidate-addon.env').write_bytes(self.env['addon_environment']())

    def probe(self):
        value=dict(ok=True,status='ACTUAL_WS4_PREPARED_DAILY_REFS_V2_PARITY_PASS',
                   binding=self.env['control_binding'](self.original),rpc_calls=0,database_writes=0,
                   real_player_data_used=False,legacy_unchanged=True,real_lua_vectors=18,malformed_vectors=4,
                   changed_files=[deploy.WIRE_TARGET],bundle_unchanged=True)
        (self.records/'probe.json').write_text(json.dumps(value));return value

    def test_receipt_failure_preserves_explicit_recovered_state(self):
        self.env['save']=Mock(side_effect=OSError('private path'))
        result=self.env['record_recovery'](self.recover())
        self.assertFalse(result['ok']);self.assertFalse(result['receipt_persisted'])
        self.assertEqual(result['status'],'OWN_WS4_DAILY_REFS_V2_ROLLED_BACK')
        self.assertEqual(self.unit.read_bytes(),self.original_unit)

    def test_independent_addon_path_and_unchanged_config_metadata(self):
        manifest=self.env['candidate_manifest'](self.original)
        self.assertEqual(manifest['archive_bundle'],deploy.BUNDLE)
        self.assertFalse(manifest['database_schema_or_config_changed'])
        self.assertTrue(manifest['addon_bytes_unchanged'])
        self.assertEqual((self.records/'candidate-addon.env').read_text(),'SURVIVAL_ADDON_ROOT='+str(self.new/'addon')+'\n')
        self.assertEqual(self.target_unit.count(b'EnvironmentFile='),1)

    def test_probe_rejects_no_v2_or_additional_runtime_change(self):
        for key,value in (('real_lua_vectors',4),('malformed_vectors',0),('legacy_unchanged',False)):
            record=self.probe();record[key]=value
            (self.records/'probe.json').write_text(json.dumps(record))
            self.assert_rejected(self.env['validate_probe'],'daily_wire_probe_missing',self.original)
        record=self.probe();record['changed_files'].append('other.py')
        (self.records/'probe.json').write_text(json.dumps(record))
        self.assert_rejected(self.env['validate_probe'],'daily_probe_scope_changed',self.original)

    def test_candidate_environment_drift_does_not_block_exact_rollback(self):
        self.candidate();(self.records/'candidate-addon.env').write_text('SURVIVAL_ADDON_ROOT=/wrong\n')
        self.assert_rejected(self.env['validate_candidate'],'candidate_addon_environment_changed',self.original)
        self.assertTrue(self.recover()['ok'])


class Controllers(previous_gate.ControllerTests):
    def setUp(self):
        with patch.object(previous_gate,'deploy',deploy):super().setUp()


class Activation(previous_gate.ActivationTests):
    def setUp(self):
        with patch.object(previous_gate,'deploy',deploy):super().setUp()


class FrozenGate(previous_gate.GateTests):pass
class FrozenWatchdog(previous_gate.WatchdogTests):pass


class SourceAndProbe(unittest.TestCase):
    def test_linux_default_matches_verified_server_executable(self):
        # The real server has /usr/bin/lua. Windows tests pass a separate
        # executable explicitly, so they must not mask a broken Linux default.
        self.assertEqual(probe.run.__defaults__, ('/usr/bin/lua',))

    def test_source_preserves_exact_v1_logic(self):
        parent=deploy.git_blob(deploy.PARENT_SOURCE,deploy.WIRE_SOURCE)
        current=(ROOT/deploy.WIRE_SOURCE).read_bytes().replace(b'\r\n',b'\n')
        deploy.validate_wire_source(parent,current)
        with self.assertRaisesRegex(RuntimeError,'legacy_v1_logic_changed'):
            deploy.validate_wire_source(parent,current.replace(b"capabilities.get(CAPABILITY) is not True",b"capabilities.get(CAPABILITY) is not False",1))

    def test_plan_only_and_unpromoted_source_inputs_blocked(self):
        self.assertEqual(deploy.plan()['remote_actions'],0)
        self.assertEqual(deploy.plan()['changed_runtime_files'],[deploy.WIRE_TARGET])
        draft=ROOT/'output/synthetic-unpromoted-daily-refs/deploy.py'
        with patch.object(deploy,'__file__',str(draft)),patch.object(deploy,'git_blob')as read_git:
            with self.assertRaisesRegex(RuntimeError,'promote_reviewed_operator'):
                deploy.source_inputs('a'*40,'b'*40)
            read_git.assert_not_called()
        tree=ast.parse(deploy.REMOTE)
        check=next(n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name=='verify_config_admission')
        code=ast.unparse(check)
        self.assertNotIn('subprocess',code);self.assertNotIn('psql',code);self.assertIn('daily_bundle_bytes_changed',code)

    def test_real_python_real_lua_probe_only_changed_wire(self):
        with tempfile.TemporaryDirectory()as folder:
            old=Path(folder)/'old';new=Path(folder)/'new'
            for root in (old,new):(root/'backend/archive_backend').mkdir(parents=True)
            (old/deploy.WIRE_TARGET).write_bytes(deploy.git_blob(deploy.PARENT_SOURCE,deploy.WIRE_SOURCE))
            (new/deploy.WIRE_TARGET).write_bytes((ROOT/deploy.WIRE_SOURCE).read_bytes())
            for name in ('__init__.py','bundle.py','daily_limits.py','config_compatibility.py'):
                shutil.copyfile(ROOT/'server/archive_backend'/name,new/'backend/archive_backend'/name)
            shutil.copytree(ROOT/'server/bundles'/deploy.BUNDLE,new/'addon/server/bundles'/deploy.BUNDLE)
            result=probe.run(old,new,deploy.BUNDLE,(ROOT/deploy.DECODER).read_text(encoding='utf8'),
                             (ROOT/deploy.VECTOR).read_text(encoding='utf8'),'C:/Program Files/lua/bin/lua5.1.exe')
            self.assertTrue(result['ok']);self.assertEqual(result['real_lua_vectors'],18)
            self.assertEqual(result['rpc_calls'],0);self.assertEqual(result['database_writes'],0)
            self.assertTrue(all(row['v2_bytes']<row['v1_bytes']for row in result['sizes']))


if __name__=='__main__':unittest.main(verbosity=1)
