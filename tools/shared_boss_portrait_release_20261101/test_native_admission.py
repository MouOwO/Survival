"""Temporary synthetic fixtures only; no native/SDK/network or installation."""
from contextlib import ExitStack,redirect_stdout
from pathlib import Path
from unittest.mock import patch,Mock
from datetime import datetime,timedelta,timezone
import copy,hashlib,importlib.util,io,json,struct,tempfile,unittest
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('isolated_shared_boss_native',HERE/'native_admission.py')
x=importlib.util.module_from_spec(spec);spec.loader.exec_module(x)
sha=lambda raw:hashlib.sha256(raw).hexdigest()
def utc(seconds):return (datetime(2026,11,1,tzinfo=timezone.utc)+timedelta(seconds=seconds)).isoformat()

class Fixture:
    def __init__(self,root):
        self.root=Path(root).resolve();self.out=self.root/'output';self.out.mkdir()
        self.store=self.root/'store';self.directory=self.store/'trial';self.directory.mkdir(parents=True)
        (self.directory/'inspections').mkdir();self.install=self.root/'installed';self.install.mkdir()
        self.report_sha='a'*64;self.content='b'*64;self.codes={'SYNTHETIC':'CODE_ONLY'}
        self.original=[];candidate=[]
        for name in x.ops.p.NAMES:
            old=('ORIGINAL '+name).encode();(self.install/name).write_bytes(old)
            self.original.append(dict(name=name,bytes=len(old),sha256=sha(old)))
            new=('CANDIDATE '+name).encode();candidate.append(dict(name=name,bytes=len(new),sha256=sha(new)))
        self.package=dict(files=6919,changed_runtime_paths=sorted(x.b.PAYLOADS),target_pins={name:{'bytes':1,'sha256':'e'*64}for name in x.b.PAYLOADS},source_revision='c'*40,source_revisions={'game':'c'*40,'content':'d'*40},content_sha256=self.content,
            package_files=candidate,vpk_sha256=candidate[0]['sha256'],release_sequence=x.b.SEQUENCE)
        self.process=dict(schema=1,kind=x.ops.p.KIND,pid=1234,created_utc=utc(0),native_created_filetime=x.ops.p.utc_ticks(utc(0))+7,
            executable=str(x.ops.p.EXE),command_line_sha256='c'*64,package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revision='c'*40,source_revisions={'game':'c'*40,'content':'d'*40},code_pins=self.codes,tools=False,offline_logic_requested=False,
            port=x.ops.p.PORT,workshop_id=x.b.ITEM,log_file=str(x.ops.expected_log_path(self.directory)),log_origin='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT',started_utc=utc(0),
            keeper=dict(pid=4321,created_utc=utc(0),native_created_filetime=x.ops.p.utc_ticks(utc(0))+3),
            file_hold_mode='GENERIC_READ_FILE_SHARE_READ_ONLY',held_files=[dict(name=n,path=str(self.install/n),bytes=candidate[i]['bytes'],volume_serial=1,file_index=i+1) for i,n in enumerate(x.ops.p.NAMES)])
        self.process['argv']=x.ops.p.arguments(Path(self.process['log_file']))
        self.process['command_line_sha256']=sha(x.subprocess.list2cmdline([str(x.ops.p.EXE),*self.process['argv']]).encode())
        transaction=dict(schema=1,kind=x.ops.p.KIND,transaction_id='trial',installed=str(self.install),release_sequence=x.b.SEQUENCE,
            package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revision='c'*40,source_revisions={'game':'c'*40,'content':'d'*40},candidate_files=candidate,code_pins=self.codes,original_files=self.original)
        refs=dict(transaction=self.save(self.directory/'transaction.json',transaction),process=self.save(self.directory/'process.json',self.process))
        refs['inspections']=[]
        for label,time in [('before',2),('after',47)]:
            inspection=dict(process=self.process,package_report_sha256=self.report_sha,content_sha256=self.content,
                source_revision='c'*40,source_revisions={'game':'c'*40,'content':'d'*40},candidate_files=candidate,held_files=self.process['held_files'],
                keeper=self.process['keeper'],
                index_owned_dota_use_observed=False,all_five_open_verified=False,all_five_owned_dota_file_uses_observed=False,external_signed_manifest_binding=True,external_signed_resources_verified=6919,external_protected_modules_verified=184,all_gameplay_paths_verified=False,observed_utc=utc(time),
                file_use=[dict(name=name,owned_dota_uses_file=i>0,owned_keeper_uses_file=True)for i,name in enumerate(x.ops.p.NAMES)])
            refs['inspections'].append(self.save(self.directory/'inspections'/(label+'.json'),inspection))
        refs['close_intent']=self.save(self.directory/'close_intent.json',dict(self.process,status='ONE_OWNED_WM_CLOSE_INTENT',console_connections=0))
        refs['close_requested']=self.save(self.directory/'close_requested.json',dict(self.process,status='WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED',
            queued=True,force_stop=False,console_connections=0,observed_utc=utc(48)))
        refs['hold_end']=self.save(self.directory/'hold_end.json',dict(self.process,status='OWNED_DOTA_EXITED_HOLDS_COMPLETED',
            end_no_dota_verified=None,end_no_dota_check_deferred_to_restore=True,process_lifetime=dict(pid=self.process['pid'],executable=str(x.ops.p.EXE),created_filetime=self.process['native_created_filetime'],exit_observed=True,executable_verified_while_alive=True,exit_identity_method='SAME_RETAINED_HANDLE_GETPROCESSTIMES',exit_filetime=self.process['native_created_filetime']+10000000),ended_utc=utc(50)))
        refs['restored']=self.save(self.directory/'restored.json',dict(status='ORIGINAL0104_FIVE_FILES_FULLY_RESTORED',
            original_files=self.original,original_content_sha256=x.b.BASE_CONTENT,acf_written=False,
            canonical_journal_written=False,backups_preserved=True,observed_utc=utc(51)))
        refs['engine_log_final']=self.raw(x.ops.expected_log_path(self.directory),b'[WS4-NATIVE-HANDOFF-01]\n[Survival][INFO][Addon] initialized\n')
        portraits={}
        for name,times in [('bane_5',[3,4,5]),('bane_5_after_eviction',[11,12,13]),('wave_equipped',[14,15,16]),('hero_builder_switch',[17,18,19]),('qop_commandment_09',[20,21,22])]:
            portraits[name]=dict(reviewed=True,native_ui=True,no_stale_qwer=True,wearables_visible=True,background_visible=True,
                no_base_model_flash=True,hero_and_builder_correct=True,scene_key=x.BANE if name.startswith('bane') else x.QOP if name=='qop_commandment_09' else name,unit_name='npc_survival_named_ten_sin_09' if name=='qop_commandment_09' else 'synthetic',
                captures=[self.screen(name+str(t),t) for t in times])
        portraits['bane_5_after_eviction']['visited_other_scenes']=[dict(scene_key='other'+str(i),reviewed=True,
            capture=self.screen('other'+str(i),6+i)) for i in range(5)]
        csv=('ProcessID,SwapChainAddress,CPUStartTime,FrameTime\n'+''.join('1234,chain,%d,10\n'%(3000+i*10) for i in range(3001))).encode()
        csvref=self.raw(self.out/'frames.csv',csv)
        frame=dict(capture=self.save(self.out/'capture.json',dict(pid=1234,tools=False,seconds=30,delay=3,wall_seconds=34,
            started_utc=utc(10),read_only_etw=True,script_injection=False,account_operations=0,frame_csv_sha256=csvref['sha256'])),
            collector_identity=self.save(self.out/'identity.json',dict(pid=1234,created_utc=utc(0),tools=False,signature='Valid',signer='O=Intel Corporation')),
            frames_csv=csvref,screens={'before':self.screen('fps_before',9),'after':self.screen('fps_after',43.1)})
        window=dict(pid=1234,hwnd=100,title='Dota 2',visible=True,iconic=False,client_rect_valid=True,client_width=1600,client_height=900)
        samples=[dict(seconds=i,foreground_pid=1234,foreground_hwnd=100,game_foreground=True,foreground_iconic=False,
            target_window_valid=True,window_candidate_count=1,target_client_width=1600,target_client_height=900) for i in range(31)]
        frame['focus']=self.save(self.out/'focus.json',dict(target_pid=1234,all_game_foreground=True,validation={'valid':True},
            requested_seconds=30,delay_seconds=3,target_hwnd=100,target_window=window,samples=samples,
            observation_start_monotonic_seconds=0,observation_end_monotonic_seconds=30,
            observation_start_unix_seconds=datetime.fromisoformat(utc(13)).timestamp(),observation_end_unix_seconds=datetime.fromisoformat(utc(43)).timestamp()))
        frame['visual_review']=dict(performed=True,before_game_in_progress=True,after_game_in_progress=True,timer_advanced=True,
            before_paused=False,after_paused=False,gameplay_timer_advanced_seconds=34,
            before_png_sha256=frame['screens']['before']['png']['sha256'],after_png_sha256=frame['screens']['after']['png']['sha256'])
        self.review=dict(schema=1,kind=x.KIND,status=x.STATUS,scope=x.SCOPE,synthetic=False,release_sequence=x.b.SEQUENCE,
            content_sha256=self.content,package_report_sha256=self.report_sha,source_revision='c'*40,source_revisions={'game':'c'*40,'content':'d'*40},
            runtime_paths=sorted(x.b.PAYLOADS),tools=False,offline_logic_test=False,cheats=False,http_enabled=True,
            official_download=False,all_gameplay_paths_verified=False,root_review={k:True for k in x.REQUIRED_REVIEW},
            process=self.process,rehearsal=refs,portraits=portraits,frames=frame)
        self.review.update(source_revisions=self.package['source_revisions'],native_file_use_policy=x.POLICY,reviewed_utc=utc(52))
        self.output=self.root/'candidate_output';self.output.mkdir()
        (self.output/(x.b.ITEM+'.vpk')).write_bytes(('CANDIDATE '+x.b.ITEM+'.vpk').encode())
        self.entries=[dict(path=name,archive=0 if i%2 else 3,bytes=1,offset=i)for i,name in enumerate(x.b.PAYLOADS)]
        self.boss_pins={name:sha(('synthetic boss '+name).encode()) for name in x.b.BOSS_SOURCE_PINS}
        self.module_bytes={name:('synthetic boss '+name).encode() for name in self.boss_pins}
        self.module_bytes[x.LOGIC_TEST]=b'synthetic immutable Lua domain harness'
        self.manifest=dict(content_sha256=self.content,files=[dict(path=name,sha256=pin)for name,pin in self.boss_pins.items()])
        self.signed=dict(signature_valid=True,release_sequence=x.b.SEQUENCE)
        log=['[WS4-NATIVE-HANDOFF-01]','[Survival][INFO][Addon] initialized',
            '[SURVIVAL_PORTRAIT] QUERY_ANCHOR '+json.dumps(dict(binding='shared_main',sharedMainReason='native_portrait_identity_matches',mainRejection=None,entity=42,expectedDisplayUnit=42,nativePortraitUnit=42))]
        for key,parts in [(x.BANE,4),*[("other"+str(i),1)for i in range(5)],(x.BANE,4),(x.QOP,5)]:
            log.extend(['[SURVIVAL_MONSTER_PORTRAIT] READY asset='+key+' map=portraits/synthetic ms=100 components='+str(parts),
                '[SURVIVAL_PORTRAIT] SCENE_SET unit=synthetic asset='+key+' item_def=', '[SURVIVAL_PORTRAIT] SHOW mode=monster_scene'])
        refs['engine_log_final'].update(self.raw(Path(refs['engine_log_final']['path']),('\n'.join(log)+'\n').encode()))
        stdout=self.raw(self.out/'logic_stdout.txt',b'SHARED_CHALLENGE_BOSSES_PASS: personal drops, 296 private mobs, old callbacks and reset\n')
        logic=dict(kind='SAME_COMMIT_REAL_SHARED_BOSS_SERVICE_SYNTHETIC_ENGINE_TEST',source_revisions=self.package['source_revisions'],
            package_report_sha256=self.report_sha,exit_code=0,real_service_and_registry=True,native_engine=False,db_or_player_write=False,
            published_dependency_equivalence_claimed=False,stdout=stdout,test_path=x.LOGIC_TEST,test_sha256=sha(self.module_bytes[x.LOGIC_TEST]),
            runner_sha256=sha(Path(x.__file__).read_bytes()),lua_executable_sha256=sha(x.LUA.read_bytes()),loaded_modules=self.boss_pins)
        confirmation=dict(kind='USER_CROSS_PC_SHARED_BOSS_CONFIRMATION',package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revisions=self.package['source_revisions'],user_confirmed=True,confirmation_text='Synthetic confirmation fixture only',player_slots=[0,1],
            same_server_session_confirmed=True,slot_key='encounter_challenge_11:boss_ten_sin_09:challenge_11_stage_09_spawn',single_shared_body_observed=True,observed_utc=utc(46))
        self.review['shared_bosses']=dict(logic_test=self.save(self.out/'logic_receipt.json',logic),
            native_observation=dict(reviewed=True,same_server_session_confirmed=True,shared_body_count=1,respawn_delay_seconds=1,
                eligible_personal_progress_preserved=True,no_unentered_player_reward=True,slot_key=confirmation['slot_key'],
                captures=[self.screen('boss'+str(t),t)for t in (44,45,46)]),
            cross_pc_confirmation=self.save(self.out/'cross_pc.json',confirmation))
        self.review_path=self.out/'root_review.json'
    def raw(self,path,data):path.write_bytes(data);return dict(path=str(path),sha256=sha(data))
    def save(self,path,data):return self.raw(path,(json.dumps(data)+'\n').encode())
    def edit(self,ref,**fields):
        path=Path(ref['path']);value=json.loads(path.read_bytes());value.update(fields);ref.update(self.save(path,value))
    def screen(self,label,time):
        png=self.raw(self.out/(label+'.png'),b'\x89PNG\r\n\x1a\n'+b'\0'*4+b'IHDR'+struct.pack('>II',1600,900)+label.encode())
        window=dict(pid=1234,hwnd=100,foreground=True,visible=True,iconic=False,hung=False,client_width=1600,client_height=900,
            corner_owners=[dict(owned=True,pid=1234)]*4)
        meta=dict(schema_version=1,helper='capture_arcade_readonly.ps1',capture_valid=True,ordinary_client_verified=True,
            png_bytes=Path(png['path']).stat().st_size,process_created_utc=utc(0),started_utc=utc(time),ended_utc=utc(time+.01),before=window,after=window)
        return dict(png=png,metadata=self.save(self.out/(label+'.json'),meta))
    def run(self):
        ref=self.save(self.review_path,self.review)
        request=dict(report_sha256=self.report_sha,source_revisions=self.package['source_revisions'],
            generation=7,native_process_generation=dict(self.process),native_review=ref)
        return x.validate_native_release(request,self.package,self.manifest,self.signed)
    def patches(self):
        return [patch.object(x.b,'ROOT',self.root),patch.object(x.ops.p,'STORE',self.store),
            patch.object(x.ops.p,'INSTALLED',self.install),patch.object(x.ops,'own_code_pins',return_value=self.codes),
            patch.object(x.c,'validated_package',return_value=(self.package,self.manifest,self.signed)),
            patch.object(x.b,'baseline',return_value=(dict(package_files=self.original),{})),patch.object(x.ops.p,'full_vpk'),
            patch.object(x.b,'OUTPUT',self.output),patch.object(x.b.inc,'read_entries',return_value=self.entries),
            patch.object(x.b.inc,'metadata',return_value=(self.manifest,{},{})),
            patch.object(x.b,'blob_at',side_effect=lambda root,rev,name:self.module_bytes[name]),
            patch.object(x.b,'BOSS_SOURCE_PINS',self.boss_pins)]

class NativeAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.context=patch.object(x.ops,'_SOURCE_CONTEXT',None);self.context.start();self.addCleanup(self.context.stop)
        self.route=patch.object(x.ops,'expected_log_path',side_effect=lambda folder:Path(folder)/'engine.log')
        self.route.start();self.addCleanup(self.route.stop)

    def fixture(self,stack,temp):
        f=Fixture(temp)
        for item in f.patches():stack.enter_context(item)
        stack.enter_context(patch.object(x.ops.p,'snapshot',side_effect=AssertionError('No OS query')))
        stack.enter_context(patch.object(x.subprocess,'run',side_effect=AssertionError('No process/SDK')))
        return f

    def test_static_default_no_auth_write_os_sdk_or_source_requirement(self):
        with patch.object(x.c,'validated_package',side_effect=AssertionError('No package')),\
                patch.object(x.ops.p,'write_new',side_effect=AssertionError('No write')),\
                patch.object(x.subprocess,'run',side_effect=AssertionError('No OS')),redirect_stdout(io.StringIO()) as out:x.main([])
        self.assertEqual(json.loads(out.getvalue())['files_written'],0)
        self.assertFalse(json.loads(out.getvalue())['sdk_initialized']);self.assertFalse(hasattr(x,'apply'))

    def test_full_isolated_admission_preserves_raw_index_false_and_publication_generation_int(self):
        with tempfile.TemporaryDirectory() as temp,ExitStack() as stack:
            f=self.fixture(stack,temp);before={ref['path']:Path(ref['path']).read_bytes() for ref in f.review['rehearsal']['inspections']}
            result=f.run()
            self.assertTrue(result['ordinary_production_acceptance']);self.assertEqual(result['native_data_volumes_observed'],4)
            self.assertTrue(result['index_open_not_required']);self.assertFalse(result['raw_receipts_modified'])
            self.assertEqual(result['portraits_finite_cases'],sorted(x.CASES));self.assertEqual(len(result['payload_archive_mapping']),17)
            self.assertEqual(result['mean_fps'],100);self.assertEqual(result['p95_ms'],10)
            self.assertTrue(result['shared_bosses']['user_cross_pc_confirmed'])
            self.assertFalse(result['shared_bosses']['real_db_reward_delivery_verified'])
            self.assertTrue(all(row['index_owned_dota_use_observed'] is False and row['all_five_open_verified'] is False for row in result['native_volume_observations']))
            self.assertEqual(before,{name:Path(name).read_bytes() for name in before})

    def test_data_use_native_generation_and_source_pair_cannot_be_borrowed(self):
        for mode in ('missing_volume','index_rewritten','volume_generation','wrong_content_source','late_launch','missing_signature_auth'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temp,ExitStack() as stack:
                f=self.fixture(stack,temp)
                ref=f.review['rehearsal']['inspections'][0];value=json.loads(Path(ref['path']).read_bytes())
                if mode=='missing_volume':value['file_use'][2]['owned_dota_uses_file']=False
                if mode=='index_rewritten':value['index_owned_dota_use_observed']=True
                if mode=='volume_generation':value['process']['native_created_filetime']+=1
                if mode=='wrong_content_source':value['source_revisions']['content']='f'*40
                if mode=='late_launch':f.edit(f.review['rehearsal']['process'],started_utc=utc(1))
                if mode=='missing_signature_auth':value['external_signed_resources_verified']=6918
                ref.update(f.save(Path(ref['path']),value))
                with self.assertRaises(ValueError):f.run()

    def test_new_qop_actual_scene_and_cold_return_native_readiness_required(self):
        for mode in ('qop_absent','qop_identity','qop_naked','no_cold_return','only_four_other_scenes','anchor_missing'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temp,ExitStack() as stack:
                f=self.fixture(stack,temp)
                if mode=='qop_absent':del f.review['portraits']['qop_commandment_09']
                if mode=='qop_identity':f.review['portraits']['qop_commandment_09']['unit_name']='wrong'
                if mode=='only_four_other_scenes':f.review['portraits']['bane_5_after_eviction']['visited_other_scenes'].pop()
                if mode in ('qop_naked','no_cold_return','anchor_missing'):
                    ref=f.review['rehearsal']['engine_log_final'];path=Path(ref['path']);raw=path.read_bytes()
                    if mode=='qop_naked':raw=raw.replace((x.QOP+' map=portraits/synthetic ms=100 components=5').encode(),(x.QOP+' map=portraits/synthetic ms=100 components=0').encode())
                    if mode=='no_cold_return':
                        needle=('[SURVIVAL_MONSTER_PORTRAIT] READY asset='+x.BANE).encode();pos=raw.rfind(needle);raw=raw[:pos]+raw[pos:].replace(needle,b'NO_SECOND_READY',1)
                    if mode=='anchor_missing':raw=raw.replace(b'native_portrait_identity_matches',b'missing_anchor')
                    ref.update(f.raw(path,raw))
                with self.assertRaises(ValueError):f.run()

    def test_shared_logic_is_not_native_or_cross_pc_and_must_match_candidate_bytes(self):
        for mode in ('no_confirmation','one_player','old_package_confirmation','logic_fake_ready','wrong_test_source','wrong_boss_module','no_respawn_pixels','unentered_reward'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temp,ExitStack() as stack:
                f=self.fixture(stack,temp);proof=f.review['shared_bosses']
                if mode=='no_confirmation':f.edit(proof['cross_pc_confirmation'],user_confirmed=False)
                if mode=='one_player':f.edit(proof['cross_pc_confirmation'],player_slots=[0])
                if mode=='old_package_confirmation':f.edit(proof['cross_pc_confirmation'],package_report_sha256='f'*64)
                if mode=='logic_fake_ready':f.edit(proof['logic_test'],kind='READY')
                if mode=='wrong_test_source':f.edit(proof['logic_test'],test_sha256='f'*64)
                if mode=='wrong_boss_module':
                    ref=proof['logic_test'];v=json.loads(Path(ref['path']).read_bytes());v['loaded_modules'][next(iter(f.boss_pins))]='f'*64;ref.update(f.save(Path(ref['path']),v))
                if mode=='no_respawn_pixels':proof['native_observation']['captures']=proof['native_observation']['captures'][:1]
                if mode=='unentered_reward':proof['native_observation']['no_unentered_player_reward']=False
                with self.assertRaises(ValueError):f.run()

    def test_fatal_snapshot_force_close_old_generation_and_failed_restore_refuse(self):
        for mode in ('serialize','snapshot','reliable','force','exit_generation','restore','tools','old_etw','slow_p95','missing_qwer_review'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temp,ExitStack() as stack:
                f=self.fixture(stack,temp)
                if mode in ('serialize','snapshot','reliable'):
                    raw={'serialize':b'Failed to serialize CUserMsg_CustomGameEvent [148]','snapshot':b'NETWORK_DISCONNECT_SNAPSHOTERROR','reliable':b'SendData reliable data too big'}[mode]
                    ref=f.review['rehearsal']['engine_log_final'];path=Path(ref['path']);ref.update(f.raw(path,path.read_bytes()+raw))
                if mode=='force':f.edit(f.review['rehearsal']['close_requested'],force_stop=True)
                if mode=='exit_generation':
                    ref=f.review['rehearsal']['hold_end'];v=json.loads(Path(ref['path']).read_bytes());v['process_lifetime']['created_filetime']+=1;ref.update(f.save(Path(ref['path']),v))
                if mode=='restore':f.edit(f.review['rehearsal']['restored'],status='INCOMPLETE')
                if mode=='tools':f.review['tools']=True
                if mode=='old_etw':f.edit(f.review['frames']['collector_identity'],created_utc=utc(-1))
                if mode=='slow_p95':
                    ref=f.review['frames']['frames_csv'];path=Path(ref['path']);raw=('ProcessID,SwapChainAddress,CPUStartTime,FrameTime\n'+''.join('1234,chain,%d,20\n'%(3000+i*20) for i in range(1501))).encode();ref.update(f.raw(path,raw));f.edit(f.review['frames']['capture'],frame_csv_sha256=ref['sha256'])
                if mode=='missing_qwer_review':f.review['portraits']['hero_builder_switch']['no_stale_qwer']=False
                with self.assertRaises(ValueError):f.run()

    def test_caller_package_objects_must_equal_real_validator_result(self):
        with patch.object(x.c,'validated_package',return_value=({'auth':'actual'},{},{})):
            with self.assertRaisesRegex(ValueError,'Passed package objects'):x.validate_native_release({'report_sha256':'a'*64},{},{},{})

if __name__=='__main__':unittest.main()
