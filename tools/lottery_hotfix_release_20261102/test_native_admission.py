"""Synthetic evidence contracts only: no native pixels/SDK/DB/network or install.

Temporary miniature files live outside both addon trees. Cryptographic package
authentication and final VPK validation are explicit mocks, not claimed passed.
The complete admission function and evidence/lifetime validators execute.
"""
from pathlib import Path
from datetime import datetime,timezone
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import Mock,patch
import copy
import hashlib
import importlib.util
import io
import json
import struct
import subprocess
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('lottery0202_native_contract',HERE/'native_admission.py')
x=importlib.util.module_from_spec(spec);spec.loader.exec_module(x)
sha=lambda raw:hashlib.sha256(raw).hexdigest()
# Fixture times may exceed59 seconds.
def utc(second):
    return datetime.fromtimestamp(datetime(2026,11,2,tzinfo=timezone.utc).timestamp()+second,timezone.utc).isoformat()
def ticks(value):return int((x.timestamp(value).timestamp()+11644473600)*10000000)


class Fixture:
    def __init__(self,root):
        self.root=Path(root).resolve();self.output=self.root/'output';self.output.mkdir()
        self.store=self.root/'store';self.directory=self.store/'trial';self.directory.mkdir(parents=True)
        (self.directory/'inspections').mkdir();self.install=self.root/'installed';self.install.mkdir()
        names=['3824360109.vpk',*['3824360109_%03d.vpk'%i for i in range(4)]]
        self.original=[dict(name=name,bytes=3,sha256=sha(('old '+name).encode()))for name in names]
        candidate=[dict(name=name,bytes=5,sha256=sha(('new '+name).encode()))for name in names]
        self.sources={'game':'c'*40,'content':'d'*40};self.pins={'synthetic_operator':'e'*64}
        self.report_sha='a'*64;self.content='b'*64
        payloads=('panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c',
            'panorama/styles/custom_game/lottery_cinematic_v1.vcss_c',
            'scripts/vscripts/ui/production_ui_service.lua','scripts/vscripts/ui/ui_request_router.lua')
        self.package=dict(source_revision=self.sources['game'],source_revisions=self.sources,
            content_sha256=self.content,files=6917,protected_modules_preserved=184,
            changed_runtime_paths=sorted(payloads),package_files=candidate,release_sequence=x.SEQUENCE)
        parent_reviews={'scripts/vscripts/synthetic_review_%02d.lua'%i:{'sha256':sha(str(i).encode())}for i in range(17)}
        parent_reviews[payloads[3]]={'sha256':'1'*64}
        target_pins={name:{'sha256':sha(('candidate '+name).encode())}for name in payloads}
        reviews=copy.deepcopy(parent_reviews)
        reviews.update({name:target_pins[name]for name in payloads[2:]})
        compiled={payloads[0]:{'source':'panorama/src/scripts/custom_game/lottery_cinematic_v1.js'},
            payloads[1]:{'source':'panorama/src/styles/custom_game/lottery_cinematic_v1.css'}}
        self.package.update(target_pins=target_pins,trusted_review_pins=reviews,
            source_artifact_pins={pin['source']:{'sha256':sha(pin['source'].encode())}for pin in compiled.values()})
        self.manifest={'content_sha256':self.content};self.signed={'signature_valid':True,'release_sequence':x.SEQUENCE}
        self.process=dict(schema=1,kind='SYNTHETIC_REHEARSAL_PROTOCOL',pid=1234,created_utc=utc(1),
            native_created_filetime=ticks(utc(1))+7,started_utc=utc(0),
            executable=str(self.root/'dota2.exe'),workshop_id='3824360109',tools=False,
            offline_logic_requested=False,owned_launch=True,launch_route='lobby',direct_entry_requested=False,
            port=29061,package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revision=self.sources['game'],source_revisions=self.sources,code_pins=self.pins,
            log_file=str(self.directory/'engine.log'),log_origin='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT',
            keeper=dict(pid=4321,created_utc=utc(0),native_created_filetime=ticks(utc(0))),
            file_hold_mode='GENERIC_READ_FILE_SHARE_READ_ONLY',held_files=[dict(name=name,path=str(self.install/name),
                bytes=5,volume_serial=1,file_index=i+1)for i,name in enumerate(names)])
        def arguments(log,route):
            return ['-steam','-console','-vconport','29061','-condebug','-con_logfile',str(log),
                '+sv_cheats','0','+survival_archive_http_enabled','1']+(
                ['+dota_launch_custom_game','3824360109','ws4_entry']if route=='direct'else [])
        self.process['argv']=arguments(Path(self.process['log_file']),'lobby')
        self.process['command_line_sha256']=sha(subprocess.list2cmdline(
            [self.process['executable'],*self.process['argv']]).encode())
        runtime=SimpleNamespace(within=lambda path,root:path.resolve().is_relative_to(Path(root).resolve()),
            digest=lambda path:sha(Path(path).read_bytes()))
        self.b=SimpleNamespace(ROOT=self.root,ITEM='3824360109',SEQUENCE=x.SEQUENCE,PAYLOADS=payloads,COMPILED=compiled,
            BASE_CONTENT='f'*64,pack=SimpleNamespace(handoff=SimpleNamespace(regular_path=lambda path:Path(path).resolve()),runtime=runtime),
            baseline=Mock(return_value=({'package_files':self.original},'SYNTHETIC_OLD_MANIFEST')),
            BASE_REPORT=self.root/'authenticated_parent_report.json',
            load=Mock(return_value={'trusted_review_pins':parent_reviews}),
            base_trusted_review=lambda report:report['trusted_review_pins'])
        self.ops=SimpleNamespace(p=SimpleNamespace(STORE=self.store,INSTALLED=self.install,NAMES=tuple(names),
            EXE=Path(self.process['executable']),PORT=29061,KIND=self.process['kind'],utc_ticks=ticks,
            require_rows=Mock(),full_vpk=Mock()),LAUNCH_ROUTES=('direct','lobby'),arguments=arguments,
            source_binding=Mock(),own_code_pins=lambda:self.pins,expected_log_path=lambda directory:directory/'engine.log')
        self.checks=SimpleNamespace(validated_package=Mock(return_value=(self.package,self.manifest,self.signed)))
        transaction=dict(schema=1,kind=self.process['kind'],transaction_id='trial',installed=str(self.install),
            release_sequence=x.SEQUENCE,package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revision=self.sources['game'],source_revisions=self.sources,code_pins=self.pins,
            candidate_files=candidate,original_files=self.original)
        refs=dict(transaction=self.save(self.directory/'transaction.json',transaction),
            process=self.save(self.directory/'process.json',self.process),inspections=[])
        for label,second in [('before',3),('after',90)]:
            inspection=dict(process=self.process,package_report_sha256=self.report_sha,
                source_revisions=self.sources,content_sha256=self.content,candidate_files=candidate,
                held_files=self.process['held_files'],keeper=self.process['keeper'],observed_utc=utc(second),
                file_use=[dict(name=name,owned_keeper_uses_file=True,owned_dota_uses_file=i>0)for i,name in enumerate(names)],
                index_owned_dota_use_observed=False,all_five_open_verified=False,
                all_five_owned_dota_file_uses_observed=False,external_signed_manifest_binding=True,
                external_signed_resources_verified=6917,external_protected_modules_verified=184)
            refs['inspections'].append(self.save(self.directory/'inspections'/(label+'.json'),inspection))
        refs['close_intent']=self.save(self.directory/'close_intent.json',dict(self.process,
            status='ONE_OWNED_WM_CLOSE_INTENT',console_connections=0))
        refs['close_requested']=self.save(self.directory/'close_requested.json',dict(self.process,
            status='WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED',queued=True,force_stop=False,
            console_connections=0,observed_utc=utc(91)))
        refs['hold_end']=self.save(self.directory/'hold_end.json',dict(self.process,
            status='OWNED_DOTA_EXITED_HOLDS_COMPLETED',end_no_dota_verified=None,
            end_no_dota_check_deferred_to_restore=True,ended_utc=utc(92),process_lifetime=dict(
                pid=1234,executable=self.process['executable'],created_filetime=self.process['native_created_filetime'],
                exit_observed=True,executable_verified_while_alive=True,
                exit_identity_method='SAME_RETAINED_HANDLE_GETPROCESSTIMES',
                exit_filetime=self.process['native_created_filetime']+910000000)))
        refs['restored']=self.save(self.directory/'restored.json',dict(
            status='ORIGINAL0104_FIVE_FILES_FULLY_RESTORED',original_files=self.original,
            original_content_sha256=self.b.BASE_CONTENT,acf_written=False,canonical_journal_written=False,
            backups_preserved=True,observed_utc=utc(93)))
        self.log='[WS4-NATIVE-HANDOFF-01]\n[Survival][INFO][Addon] initialized\n'
        cases={}
        for i,pool in enumerate(x.POOLS):
            self.log+='[LOTTERY_CINEMATIC] stage=preview pool='+pool+'\n'
            self.log+='[LOTTERY_CINEMATIC] stage=fallback pool='+pool+' reason=native_error preview=true\n'
            self.log+='[LOTTERY_CINEMATIC] stage=complete pool='+pool+' preview=true\n'
            captures={role:self.screen(pool+'_'+role,4+i*15+j*2)for j,role in enumerate(
                ('window_before','animation_a','animation_b','window_after'))}
            cases[pool]=dict(mode='NO_CONSUMPTION_PREVIEW',pool=pool,presentation='fallback',fallback_reason='native_error',
                observed_ticket_pool='map',tickets_before=0,tickets_after=0,captures=captures,visual_review=dict(
                    theme_matches_pool=True,animation_progressed=True,returned_to_lottery_window=True,
                    no_movie_error_visible_after_fallback=True,no_draw_inputs=True,
                    reviewed_png_sha256=[ref['png']['sha256']for ref in captures.values()]))
        refs['engine_log_final']=self.raw(Path(self.process['log_file']),self.log.encode())
        self.review=dict(schema=1,kind=x.KIND,scope=x.SCOPE,synthetic=False,release_sequence=x.SEQUENCE,
            package_report_sha256=self.report_sha,source_revisions=self.sources,content_sha256=self.content,
            runtime_paths=sorted(payloads),native_file_use_policy=x.POLICY,tools=False,offline_logic_test=False,
            cheats=False,http_enabled=True,real_player_transaction_performed=False,
            root_review={key:True for key in x.REVIEW_FLAGS},process=self.process,
            rehearsal=refs,lottery_previews=cases,reviewed_utc=utc(94))
        self.request=dict(report_sha256=self.report_sha,source_revisions=self.sources,
            native_process_generation=copy.deepcopy(self.process))
        self.update()

    def raw(self,path,raw):
        Path(path).write_bytes(raw);return {'path':str(path),'sha256':sha(raw)}
    def save(self,path,value):return self.raw(path,json.dumps(value,sort_keys=True).encode())
    def update(self):
        ref=self.save(self.output/'review.json',self.review)
        self.request.update(production_evidence_path=ref['path'],production_evidence_sha256=ref['sha256'])
    def change_receipt(self,name,mutate):
        ref=self.review['rehearsal'][name];value=json.loads(Path(ref['path']).read_bytes());mutate(value)
        self.review['rehearsal'][name]=self.save(Path(ref['path']),value)
    def replace_log(self,text):
        self.review['rehearsal']['engine_log_final']=self.raw(Path(self.process['log_file']),text.encode())
    def screen(self,name,second):
        # Deliberately synthetic PNG header; no claim of codec/native rendering.
        png=self.raw(self.output/(name+'.png'),b'\x89PNG\r\n\x1a\n'+b'\0'*4+b'IHDR'+struct.pack('>II',1600,900)+name.encode())
        state=dict(pid=1234,hwnd=100,foreground=True,visible=True,iconic=False,hung=False,
            client_width=1600,client_height=900,corner_owners=[dict(owned=True,pid=1234)for _ in range(4)])
        meta=dict(schema_version=1,helper='capture_arcade_readonly.ps1',capture_valid=True,
            ordinary_client_verified=True,png_bytes=Path(png['path']).stat().st_size,
            process_created_utc=utc(1),started_utc=utc(second),ended_utc=utc(second+.1),
            before=state,after=state)
        return {'png':png,'metadata':self.save(self.output/(name+'.json'),meta)}
    def validate(self):
        self.update()
        with patch.object(x,'environment',return_value=(self.checks,self.b,self.ops)):
            return x.validate_native_release(self.request,self.package,self.manifest,self.signed)


class NativeTests(unittest.TestCase):
    def test_whole_admission_positive_four_preview_only_cases_no_unrelated_gates(self):
        with tempfile.TemporaryDirectory(prefix='lottery-native-contract-')as temp:
            f=Fixture(temp);result=f.validate()
            self.assertTrue(result['ordinary_production_acceptance'])
            self.assertEqual(result['lottery_previews']['native_screens'],16)
            self.assertEqual(result['lottery_previews']['observed_ticket_pools'],{pool:'map'for pool in x.POOLS})
            self.assertFalse(result['native_fps_measured']);self.assertFalse(result['real_player_transaction_performed'])
            self.assertFalse(result['training_tips_native_tested']);self.assertEqual(result['updates_submitted'],0)
            self.assertEqual(result['trusted_review_lineage']['final_count'],19)
            self.assertEqual(result['trusted_review_lineage']['unchanged_parent_count'],17)
            f.ops.p.require_rows.assert_called_once_with(f.install,f.original)
            f.ops.p.full_vpk.assert_called_once();f.checks.validated_package.assert_called_once_with('a'*64,full=True)

    def test_whole_admission_rejects_false_candidates_and_missing_actual_evidence(self):
        changes={
            'old_sequence':lambda f:f.signed.update(release_sequence=2026110201),
            'old_resource_scope':lambda f:f.package.update(files=6919),
            'extra_twentieth_review':lambda f:f.package['trusted_review_pins'].update({'unknown.lua':{'sha256':'9'*64}}),
            'changed_old_review':lambda f:f.package['trusted_review_pins'].update({'scripts/vscripts/synthetic_review_00.lua':{'sha256':'9'*64}}),
            'missing_router_review':lambda f:f.package['trusted_review_pins'].pop(f.b.PAYLOADS[3]),
            'old_router_not_replaced':lambda f:f.package['trusted_review_pins'].update({f.b.PAYLOADS[3]:{'sha256':'1'*64}}),
            'unknown_compile_binding':lambda f:f.package['source_artifact_pins'].update({'third_compiled':{}}),
            'wrong_sources':lambda f:f.review.update(source_revisions={'game':'1'*40,'content':'d'*40}),
            'ready_only':lambda f:f.review.clear(),
            'tools':lambda f:f.review.update(tools=True),
            'synthetic_review':lambda f:f.review.update(synthetic=True),
            'missing_pool':lambda f:f.review['lottery_previews'].pop('summer'),
            'ticket_spend':lambda f:f.review['lottery_previews']['map'].update(tickets_after=1),
            'unspecified_visible_balance_pool':lambda f:f.review['lottery_previews']['summer'].pop('observed_ticket_pool'),
            'no_error_exercised':lambda f:[case.update(presentation='movie')for case in f.review['lottery_previews'].values()],
            'fake_ack_instead_of_preview':lambda f:f.review['lottery_previews']['map'].update(mode='PRODUCTION_ACK'),
            'missing_fallback_log':lambda f:f.replace_log(f.log.replace('stage=fallback','stage=other')),
            'draw_ack_seen':lambda f:f.replace_log(f.log+'[SURVIVAL_LOTTERY_UI] stage=result_received request=test\n'),
            'snapshot_disconnect':lambda f:f.replace_log(f.log+'NETWORK_DISCONNECT_SNAPSHOTERROR\n'),
            'script_error':lambda f:f.replace_log(f.log+'Script Runtime Error in module\n'),
            'missing_log':lambda f:f.review['rehearsal'].pop('engine_log_final'),
            'wrong_native_generation':lambda f:f.request['native_process_generation'].update(native_created_filetime=1),
            'manual_adopt':lambda f:f.change_receipt('process',lambda row:row.update(owned_launch=False)),
            'exit_only_pid_absent':lambda f:f.change_receipt('hold_end',lambda row:row['process_lifetime'].update(exit_identity_method='PID_NOT_FOUND')),
            'wrong_restore':lambda f:f.change_receipt('restored',lambda row:row.update(original_files=[])),
            'force_close':lambda f:f.change_receipt('close_requested',lambda row:row.update(force_stop=True)),
            'hold_failed':lambda f:(f.directory/'hold_failed.json').write_text('{}'),
        }
        for label,change in changes.items():
            with self.subTest(label=label),tempfile.TemporaryDirectory(prefix='lottery-native-contract-')as temp:
                f=Fixture(temp);change(f)
                with self.assertRaises((ValueError,KeyError,TypeError)):f.validate()

    def test_pixel_review_binds_frames_and_all_data_observations(self):
        for label,change in {
            'same_frames':lambda f:f.review['lottery_previews']['map']['captures'].update(
                animation_b=f.review['lottery_previews']['map']['captures']['animation_a']),
            'unreviewed_sha':lambda f:f.review['lottery_previews']['map']['visual_review'].update(reviewed_png_sha256=['0'*64]*4),
            'late_frame':lambda f:f.review['lottery_previews']['map']['captures'].update(window_after=f.screen('late',100)),
            'sha_tamper':lambda f:Path(f.review['lottery_previews']['map']['captures']['animation_a']['png']['path']).write_bytes(b'not original pixels'),
        }.items():
            with self.subTest(label=label),tempfile.TemporaryDirectory(prefix='lottery-native-contract-')as temp:
                f=Fixture(temp);change(f)
                with self.assertRaises(ValueError):f.validate()
        with tempfile.TemporaryDirectory(prefix='lottery-native-contract-')as temp:
            f=Fixture(temp);ref=f.review['rehearsal']['inspections'][0]
            value=json.loads(Path(ref['path']).read_bytes());value['file_use'][2]['owned_dota_uses_file']=False
            f.review['rehearsal']['inspections'][0]=f.save(Path(ref['path']),value)
            with self.assertRaisesRegex(ValueError,'data-volume'):f.validate()

    def test_default_is_static_without_loading_package_or_native_tools(self):
        with patch.object(x,'environment',side_effect=AssertionError('No package/native query')),\
                redirect_stdout(io.StringIO())as output:
            self.assertEqual(x.main([]),0)
        self.assertEqual(json.loads(output.getvalue())['native_actions'],0)


if __name__=='__main__':unittest.main()
