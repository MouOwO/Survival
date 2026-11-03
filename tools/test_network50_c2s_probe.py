"""Pure source checks; no LAB creation, compiler run, Dota process or SDK."""
from pathlib import Path
import importlib.util,subprocess,unittest,xml.etree.ElementTree as ET
from unittest import mock

SPEC=importlib.util.spec_from_file_location('n50_addon_probe',Path(__file__).with_name('network50_native_addon_probe_20261103.py'))
probe=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(probe)

class C2SProbeTests(unittest.TestCase):
    def test_measured_run_has_fresh_log_all_sizes_and_valid_sources(self):
        with mock.patch.dict(probe.__dict__,{},clear=False):
            probe.measured_c2s_namespace()
            plan=probe.c2s_plan()
            self.assertIn('run06',plan['log'])
            self.assertEqual(plan['launch_argv'][plan['launch_argv'].index('+net_showmsg')+1],'1')
            checked=subprocess.run(['node','--check','-'],input=probe.C2S_JS.encode(),capture_output=True)
            self.assertEqual(checked.returncode,0,checked.stderr)
            checked=subprocess.run(['C:/Program Files/lua/bin/lua5.1.exe','-e','assert(loadstring(io.read("*a")))'],input=probe.C2S_LUA.encode(),capture_output=True)
            self.assertEqual(checked.returncode,0,checked.stderr)
            self.assertIn('[0,1,8,16,24,32]',probe.C2S_JS)

    def test_plan_does_not_launch_or_prepare(self):
        with mock.patch.object(probe.subprocess,'run',side_effect=AssertionError('no subprocess')),mock.patch.object(probe.subprocess,'Popen',side_effect=AssertionError('no process')):
            plan=probe.c2s_plan()
        self.assertTrue(plan['native_proof_pending']);self.assertTrue(plan['actor_source_proof_pending'])
        self.assertEqual(plan['value_ascii_bytes'],24);self.assertEqual(plan['launch_argv'][plan['launch_argv'].index('+net_restrict_showmsg_socket')+1],'server')
        self.assertEqual(Path(plan['external_lab']).parent.name,'run04')

    def test_minimal_sources_parse_without_game_execution(self):
        for text in (probe.C2S_MANIFEST,probe.C2S_XML):ET.fromstring(text)
        checked=subprocess.run(['node','--check','-'],input=probe.C2S_JS.encode(),capture_output=True)
        self.assertEqual(checked.returncode,0,checked.stderr)
        checked=subprocess.run(['C:/Program Files/lua/bin/lua5.1.exe','-e','assert(loadstring(io.read("*a")))'],input=probe.C2S_LUA.encode(),capture_output=True)
        self.assertEqual(checked.returncode,0,checked.stderr)
        self.assertIn('GameEvents.SendCustomGameEventToServer("cw",{d:"A".repeat(24)})',probe.C2S_JS)
        self.assertNotIn('require(',probe.C2S_LUA);self.assertNotIn('steamid',probe.C2S_LUA.lower())

    def test_existing_client_blocks_all_mount_and_file_mutations(self):
        with mock.patch.object(probe.p,'clients',return_value=[{'pid':1}]),mock.patch.object(probe,'_fresh_c2s_paths',side_effect=AssertionError('no paths')):
            with self.assertRaisesRegex(ValueError,'existing_dota_client_preserved'):
                probe.prepare_c2s()

if __name__=='__main__':unittest.main()
