import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import hashlib
import struct
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('capture',Path(__file__).with_name('capture_network50_perf.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class CaptureTests(unittest.TestCase):
    def compiled_js(self,data,metadata=b'original'):
        # Real Valve block-table layout; metadata may change independently of DATA.
        raw=bytearray(16+24+len(metadata)+len(data))
        struct.pack_into('<II',raw,8,8,2)
        struct.pack_into('<4sII',raw,16,b'REDI',40-20,len(metadata))
        struct.pack_into('<4sII',raw,28,b'DATA',40+len(metadata)-32,len(data))
        raw[40:40+len(metadata)]=metadata;raw[40+len(metadata):]=data
        return bytes(raw)

    def resource_fixture(self,base,author=b'const value=1;\r\n'):
        relative='panorama/scripts/custom_game/common/compact_ui_runtime.vjs_c'
        authored=relative[:-6]+'.js'
        source=base/'content'/authored;source.parent.mkdir(parents=True);source.write_bytes(author)
        path=base/'game'/relative;path.parent.mkdir(parents=True)
        old=self.compiled_js(author);path.write_bytes(old)
        row={'area':'game','relative':relative,'sha256':hashlib.sha256(old).hexdigest()}
        index={('content',authored):{'area':'content','relative':authored,'sha256':hashlib.sha256(author).hexdigest()}}
        return path,source,row,index

    def test_tools_metadata_recompile_binds_actual_data_to_immutable_author(self):
        with tempfile.TemporaryDirectory()as temporary:
            base=Path(temporary);path,source,row,index=self.resource_fixture(base)
            manifest=base/'files.manifest.json';manifest.write_text(json.dumps([row,*index.values()]))
            original_manifest=manifest.read_bytes()
            path.write_bytes(self.compiled_js(source.read_bytes(),b'on-demand metadata changed'))
            result=m.critical_resource_binding(base,row,index)
            self.assertTrue(result['tools_recompiled']);self.assertEqual(result['prelaunch_sha256'],row['sha256'])
            self.assertEqual(result['actual_postcompile_sha256'],m.sha(path));self.assertTrue(result['compiled_data_equals_copied_author'])
            self.assertIn('NOT_SIGNED_ACCEPTANCE',result['binding_kind']);self.assertEqual(manifest.read_bytes(),original_manifest)
            self.assertEqual(result,m.critical_resource_binding(base,row,index))
            path.write_bytes(self.compiled_js(source.read_bytes(),b'changed again during capture'))
            self.assertNotEqual(result,m.critical_resource_binding(base,row,index),'actual postcompile hashes must stay stable through capture')

    def test_recompile_cannot_hide_changed_data_author_or_line_endings(self):
        with tempfile.TemporaryDirectory()as temporary:
            base=Path(temporary);path,source,row,index=self.resource_fixture(base)
            path.write_bytes(self.compiled_js(b'const evil=2;\r\n',b'legitimate-looking metadata'))
            with self.assertRaisesRegex(ValueError,'actual_js_data_differs'):m.critical_resource_binding(base,row,index)
            source.write_bytes(b'const different=3;\r\n')
            with self.assertRaisesRegex(ValueError,'immutable_copied_author_drift'):m.critical_resource_binding(base,row,index)
        with tempfile.TemporaryDirectory()as temporary:
            base=Path(temporary);_,_,row,index=self.resource_fixture(base,b'const value=1;\n')
            with self.assertRaisesRegex(ValueError,'crlf_author_required'):m.critical_resource_binding(base,row,index)

    def test_normal_map_never_uses_js_recompile_exception(self):
        with tempfile.TemporaryDirectory()as temporary:
            base=Path(temporary);path=base/'game/maps/template_map.vpk';path.parent.mkdir(parents=True);path.write_bytes(b'map')
            row={'relative':'maps/template_map.vpk','sha256':m.sha(path)}
            self.assertEqual(m.critical_resource_binding(base,row,{})['binding_kind'],'EXACT_PRELAUNCH_BYTES')
            path.write_bytes(b'changed map')
            with self.assertRaisesRegex(ValueError,'critical_runtime_drift'):m.critical_resource_binding(base,row,{})

    def test_run05_tools_helpers_are_explicitly_allowed_without_execution(self):
        for relative in('tools/network50_dev_native_20261103.py','tools/network50_dev_input.ps1'):
            self.assertIn("'run05'",(m.ROOT/relative).read_text(encoding='utf-8'))

    def sample(self,time=100,status='spawning'):
        return {'active':True,'tools':True,'game_time':time,'paused':False,'wave':{'status':status,'current':3,'alive':20,'defeated':False},'wire':{'ready':True,'views':4,'counters':{'sent':3}}}

    def test_only_public_diagnostic_fields_leave_capture(self):
        source=self.sample();source.update(account_id='private',session_id='private');source['wave']['account_id']='private';source['wire']['counters']['secret']='private'
        result=m.public_sample(source)
        self.assertNotIn('private',json.dumps(result));self.assertEqual(result['wire']['counters'],{'sent':3})

    def test_paused_victory_defeat_and_unknown_states_are_invalid(self):
        before=self.sample();self.assertTrue(m.gameplay_validation(before,self.sample(130))['valid'])
        for status in ('victory','defeat','cleared','waiting','dev_preloading','invented'):
            self.assertFalse(m.gameplay_validation(before,self.sample(130,status))['valid'])
        after=self.sample(130);after['paused']=True
        self.assertFalse(m.gameplay_validation(before,after)['valid'])
        after=self.sample(130);after['paused']=None
        self.assertFalse(m.gameplay_validation(before,after)['valid'])

    def test_clock_freeze_speed_change_and_missing_samples_fail(self):
        for time in (100,110,160,None,float('nan')):
            self.assertFalse(m.gameplay_validation(self.sample(),self.sample(time))['valid'])

    def csv(self,path,rows):
        with path.open('w',newline='',encoding='utf-8')as stream:
            writer=csv.DictWriter(stream,fieldnames=['ProcessID','SwapChainAddress','CPUStartTime','FrameTime']);writer.writeheader();writer.writerows(rows)

    def frames(self):
        return [{'ProcessID':99,'SwapChainAddress':'0xabc','CPUStartTime':n*100,'FrameTime':100}for n in range(301)]

    def test_true_v2_intervals_are_recomputed_not_report_claims(self):
        with tempfile.TemporaryDirectory()as temporary:
            path=Path(temporary)/'v2.csv';self.csv(path,self.frames());result=m.v2_statistics(path,99)
            self.assertEqual(result['accepted_frames'],300);self.assertEqual(result['mean_fps'],10);self.assertEqual(result['p95_ms'],100);self.assertEqual(result['cpu_span_seconds'],30)

    def test_zero_foreign_multiple_swapchains_and_bad_clock_rejected(self):
        with tempfile.TemporaryDirectory()as temporary:
            path=Path(temporary)/'v2.csv'
            cases=[[],[dict(self.frames()[0],ProcessID=100)],self.frames()+[dict(self.frames()[0],SwapChainAddress='0xdef')],self.frames()+[self.frames()[0]]]
            for rows in cases:
                self.csv(path,rows)
                with self.assertRaises(ValueError):m.v2_statistics(path,99)

    def test_ready_command_only_from_bounded_explicit_marker(self):
        with tempfile.TemporaryDirectory()as temporary:
            path=Path(temporary)/'engine.log';path.write_text('private account data\n[NETWORK50_UI_DIAGNOSTIC] ready command=network50_inspect_1700000000000_1\n',encoding='utf-8')
            self.assertEqual(m.command_from_log(path),'network50_inspect_1700000000000_1')
            path.write_text('network50_inspect_1700000000000_1\n',encoding='utf-8')
            with self.assertRaises(ValueError):m.command_from_log(path)

    def test_live_pid_creation_alias_and_port_are_all_required(self):
        binding={'pid':99,'created':'2026-11-03T00:00:00.0000000Z','alias':'svt_network50_dev','exe':str(Path('D:/game/dota2.exe').resolve())}
        good={'pid':99,'created':binding['created'],'exe':binding['exe'],'command':'dota2.exe -tools -addon svt_network50_dev','listeners':[{'pid':99,'address':'127.0.0.1'}]}
        with patch.object(m,'ps',return_value=good):
            result=m.live_identity(binding);self.assertNotIn('command',result);self.assertEqual(result['port_owner_pid'],99)
        cases=[dict(good,created='reused'),dict(good,pid=100),dict(good,command='dota2.exe -tools -addon svt_network50_dev_old'),dict(good,listeners=[{'pid':100,'address':'127.0.0.1'}]),dict(good,listeners=[])]
        for case in cases:
            with patch.object(m,'ps',return_value=case),self.assertRaises(ValueError):m.live_identity(binding)

    def test_node_bridge_cannot_send_arbitrary_console_or_nonce(self):
        code="const a=require('./tools/network50_perf_vconsole.cjs');let n=0;for(const c of ['quit','network50_inspect_1700000000000_1;quit','script_reload_code tests/x'])try{a.parseCommand(c)}catch(e){n++}for(const c of ['x','A'.repeat(32),'a'.repeat(32)+';quit'])try{a.parseNonce(c)}catch(e){n++}if(n!==6)throw Error('allowlist');console.log(a.parseCommand('network50_inspect_1700000000000_1'))"
        result=subprocess.run(['node','-e',code],cwd=m.ROOT,capture_output=True,text=True,check=True)
        self.assertEqual(result.stdout.strip(),'network50_inspect_1700000000000_1')

if __name__=='__main__':unittest.main()
