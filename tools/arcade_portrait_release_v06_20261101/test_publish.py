"""Synthetic temporary evidence only. No real package, SDK, game or network."""
from contextlib import ExitStack,nullcontext,redirect_stdout
from pathlib import Path
from unittest.mock import Mock,patch
from datetime import datetime,timedelta,timezone
import copy
import hashlib
import importlib.util
import io
import json
import struct
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('isolated_production_publish_v03',HERE/'publish.py')
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
        self.package=dict(source_revision=x.ops.RUNTIME_SOURCE_REVISION,content_sha256=self.content,
            package_files=candidate,vpk_sha256=candidate[0]['sha256'],release_sequence=x.b.SEQUENCE)
        self.process=dict(schema=1,kind=x.ops.p.KIND,pid=1234,created_utc=utc(0),native_created_filetime=x.ops.p.utc_ticks(utc(0))+7,
            executable=str(x.ops.p.EXE),command_line_sha256='c'*64,package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revision=x.ops.RUNTIME_SOURCE_REVISION,code_pins=self.codes,tools=False,offline_logic_requested=False,
            port=x.ops.p.PORT,workshop_id=x.b.ITEM,log_file=str(x.ops.expected_log_path(self.directory)),log_origin='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT',started_utc=utc(1),
            keeper=dict(pid=4321,created_utc=utc(0),native_created_filetime=x.ops.p.utc_ticks(utc(0))+3),
            file_hold_mode='GENERIC_READ_FILE_SHARE_READ_ONLY',held_files=[dict(name=n,path=str(self.install/n),bytes=candidate[i]['bytes'],volume_serial=1,file_index=i+1) for i,n in enumerate(x.ops.p.NAMES)])
        self.process['argv']=x.ops.p.arguments(Path(self.process['log_file']))
        self.process['command_line_sha256']=sha(x.subprocess.list2cmdline([str(x.ops.p.EXE),*self.process['argv']]).encode())
        transaction=dict(schema=1,kind=x.ops.p.KIND,transaction_id='trial',installed=str(self.install),release_sequence=x.b.SEQUENCE,
            package_report_sha256=self.report_sha,content_sha256=self.content,
            source_revision=x.ops.RUNTIME_SOURCE_REVISION,candidate_files=candidate,code_pins=self.codes,original_files=self.original)
        refs=dict(transaction=self.save(self.directory/'transaction.json',transaction),process=self.save(self.directory/'process.json',self.process))
        refs['inspections']=[]
        for label,time in [('before',2),('after',47)]:
            inspection=dict(process=self.process,package_report_sha256=self.report_sha,content_sha256=self.content,
                source_revision=x.ops.RUNTIME_SOURCE_REVISION,candidate_files=candidate,held_files=self.process['held_files'],
                keeper=self.process['keeper'],
                index_owned_dota_use_observed=True,all_gameplay_paths_verified=False,observed_utc=utc(time),
                file_use=[dict(name=x.b.ITEM+'.vpk',owned_dota_uses_file=True,owned_keeper_uses_file=True)])
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
        for name,times in [('bane_5',[3,4,5]),('bane_5_after_eviction',[11,12,13]),('wave_equipped',[14,15,16]),('hero_builder_switch',[17,18,19])]:
            portraits[name]=dict(reviewed=True,native_ui=True,no_stale_qwer=True,wearables_visible=True,background_visible=True,
                no_base_model_flash=True,hero_and_builder_correct=True,scene_key='bane' if name.startswith('bane') else name,
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
            content_sha256=self.content,package_report_sha256=self.report_sha,source_revision=x.ops.RUNTIME_SOURCE_REVISION,
            runtime_paths=sorted(x.b.PAYLOADS),tools=False,offline_logic_test=False,cheats=False,http_enabled=True,
            official_download=False,all_gameplay_paths_verified=False,root_review={k:True for k in x.REQUIRED_REVIEW},
            process=self.process,rehearsal=refs,portraits=portraits,frames=frame)
        self.review_path=self.out/'root_review.json'
        self.base_report=self.out/'base_package.json';self.save(self.base_report,dict(package_files=self.original,vpk_sha256=self.original[0]['sha256']))
        self.journal=self.out/'journal.json';self.state=dict(uploaded=True,status=x.legacy.SUCCESS_STATUS,owner=x.sdk.OWNER,app_id=x.sdk.APP,
            workshop_id=x.b.ITEM,visibility_requested=3,legal_agreement_required=False,release_sequence=x.b.BASE_SEQUENCE,
            content_sha256=x.b.BASE_CONTENT,package_files=self.original,vpk_sha256=self.original[0]['sha256'],vpk_bytes=self.original[0]['bytes'],
            previous_release={'synthetic_original_history':True},release_history=[{}]*20)
        self.save(self.journal,self.state)
        self.package['canonical_journal_sha256']=sha(self.journal.read_bytes())
        self.listing_dir=self.root/'base_listing';self.listing_dir.mkdir();self.save(self.listing_dir/'listing.json',dict(workshop_id=x.b.ITEM,
            visibility_requested='unlisted',tester_steamids64=['1','2','3','4','5'],cover='cover.png'))
        self.report_dir=self.root/'new_report';self.report_dir.mkdir()

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
        return x.preflight(self.report_sha,self.review_path,ref['sha256'])
    def patches(self):
        return [patch.object(x.b,'ROOT',self.root),patch.object(x.ops.p,'STORE',self.store),
            patch.object(x.ops.p,'INSTALLED',self.install),patch.object(x.ops,'own_code_pins',return_value=self.codes),
            patch.object(x.c,'validated_package',return_value=(self.package,dict(content_sha256=self.content),{})),
            patch.object(x.b,'baseline',return_value=(dict(package_files=self.original),{})),patch.object(x.ops.p,'full_vpk'),
            patch.object(x.b,'BASE_REPORT',self.base_report),patch.object(x.b,'BASE_REPORT_SHA',sha(self.base_report.read_bytes())),
            patch.object(x.b,'JOURNAL',self.journal),patch.object(x.b.five,'REPORT',self.listing_dir),patch.object(x.b,'REPORT',self.report_dir),
            patch.object(x.b.five,'parsed_ids',return_value=['1','2','3','4','5'])]


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.source=patch.object(x.ops,'RUNTIME_SOURCE_REVISION','c'*40)
        self.source.start();self.addCleanup(self.source.stop)
        self.log_route=patch.object(x.ops,'expected_log_path',side_effect=lambda folder:Path(folder)/'engine.log')
        self.log_route.start();self.addCleanup(self.log_route.stop)

    def test_default_static_plan_no_package_sdk_or_writes(self):
        with patch.object(x.c,'validated_package',side_effect=AssertionError('No package')),patch.object(x.sdk,'Steam') as sdk,redirect_stdout(io.StringIO()) as out:
            x.main([])
        sdk.assert_not_called();self.assertEqual(json.loads(out.getvalue())['updates_submitted'],0)

    def test_development_synthetic_wrong_source_or_scope_cannot_admit(self):
        package=dict(source_revision=x.ops.RUNTIME_SOURCE_REVISION,content_sha256='a'*64)
        review=dict(schema=1,kind=x.KIND,status=x.STATUS,scope=x.SCOPE,synthetic=False,release_sequence=x.b.SEQUENCE,
            content_sha256='a'*64,package_report_sha256='b'*64,source_revision=x.ops.RUNTIME_SOURCE_REVISION,runtime_paths=sorted(x.b.PAYLOADS),
            tools=False,offline_logic_test=False,cheats=False,http_enabled=True,official_download=False,all_gameplay_paths_verified=False,
            root_review={k:True for k in x.REQUIRED_REVIEW})
        for key,value in [('kind','DEVELOPMENT_SCOPED_EQUIVALENCE'),('synthetic',True),('tools',True),('source_revision','f'*40),('all_gameplay_paths_verified',True),('runtime_paths',sorted(x.b.PAYLOADS)[:-1])]:
            with self.subTest(key=key),self.assertRaises(ValueError):x.bind_review(dict(review,**{key:value}),package,'b'*64)

    def test_full_synthetic_production_preflight_passes_without_sdk_or_journal_mutation(self):
        with tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
            f=Fixture(temporary)
            for item in f.patches():stack.enter_context(item)
            sdk=stack.enter_context(patch.object(x.sdk,'Steam'));before=f.journal.read_bytes()
            result=f.run()
            self.assertTrue(result['summary']['ready_for_authorized_original_item_update'])
            self.assertFalse(result['summary']['post_upload_arcade_verified']);sdk.assert_not_called()
            self.assertEqual(before,f.journal.read_bytes());self.assertEqual(len(json.loads(before)['release_history']),20)

    def test_wrong_index_use_force_exit_restore_or_old_etw_is_rejected(self):
        for mode in ('no_index','force','bad_restore','old_etw','pending','changed_installed','hold_failed',
                     'tools_capture','slow_fps','speedup_timer','foreign_capture_window','different_capture_hwnd','cleared_history'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
                f=Fixture(temporary)
                for item in f.patches():stack.enter_context(item)
                sdk=stack.enter_context(patch.object(x.sdk,'Steam'))
                if mode=='no_index':f.edit(f.review['rehearsal']['inspections'][0],index_owned_dota_use_observed=False)
                if mode=='force':f.edit(f.review['rehearsal']['close_requested'],force_stop=True)
                if mode=='bad_restore':f.edit(f.review['rehearsal']['restored'],status='NOT_RESTORED')
                if mode=='old_etw':f.edit(f.review['frames']['capture'],started_utc=utc(3))
                if mode=='pending':f.save(f.journal,dict(f.state,status='SUBMIT_PENDING_UNKNOWN'))
                if mode=='cleared_history':f.save(f.journal,dict(f.state,release_history=[]))
                if mode=='changed_installed':(f.install/x.ops.p.NAMES[0]).write_bytes(b'FOREIGN')
                if mode=='hold_failed':(f.directory/'hold_failed.json').write_bytes(b'{}')
                if mode=='tools_capture':f.edit(f.review['frames']['capture'],tools=True)
                if mode=='slow_fps':
                    ref=f.review['frames']['frames_csv'];path=Path(ref['path'])
                    ref.update(f.raw(path,path.read_bytes().replace(b',10\n',b',20\n')))
                    f.edit(f.review['frames']['capture'],frame_csv_sha256=ref['sha256'])
                if mode=='speedup_timer':f.review['frames']['visual_review']['gameplay_timer_advanced_seconds']=68
                if mode=='foreign_capture_window':
                    ref=f.review['frames']['screens']['before']['metadata'];meta=json.loads(Path(ref['path']).read_bytes())
                    meta['before']['pid']=9999;ref.update(f.save(Path(ref['path']),meta))
                if mode=='different_capture_hwnd':
                    ref=f.review['frames']['screens']['before']['metadata'];meta=json.loads(Path(ref['path']).read_bytes())
                    meta['before']['hwnd']=meta['after']['hwnd']=101;ref.update(f.save(Path(ref['path']),meta))
                with self.assertRaises((ValueError,AssertionError)):f.run()
                sdk.assert_not_called()

    def test_apply_revalidates_before_any_mutation_or_sdk(self):
        context=dict(package_report_sha256='a'*64,review_path=Path('notreal'),review_sha256='b'*64)
        with patch.object(x,'preflight',side_effect=ValueError('changed evidence')),patch.object(x.b.inc,'write_new') as write,patch.object(x.sdk,'Steam') as sdk:
            with self.assertRaises(ValueError):x.apply(context)
        write.assert_not_called();sdk.assert_not_called()

    def test_already_submitted_does_not_repeat_sdk_update(self):
        context=dict(package_report_sha256='a'*64,review_path=Path('notreal'),review_sha256='b'*64,journal_sha256='c'*64)
        fresh=dict(journal_sha256='c'*64,summary={'already_submitted':True})
        with patch.object(x,'preflight',return_value=fresh),patch.object(x.b.inc,'write_new') as write,patch.object(x.sdk,'Steam') as sdk:
            with self.assertRaisesRegex(ValueError,'already submitted'):x.apply(context)
        write.assert_not_called();sdk.assert_not_called()

    def test_reviewed_apply_routes_only_existing_item_and_same_canonical_journal(self):
        with tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
            f=Fixture(temporary)
            for item in f.patches():stack.enter_context(item)
            context=f.run()
            stack.enter_context(patch.object(x.b,'scene_maps',side_effect=lambda:nullcontext()))
            stack.enter_context(patch.object(x.b.inc,'trusted_source',side_effect=lambda ignored:nullcontext()))
            stack.enter_context(patch.object(x.sdk,'publication_lock',side_effect=lambda ignored:nullcontext()))
            steam=stack.enter_context(patch.object(x.sdk,'Steam'))
            publish=stack.enter_context(patch.object(x.sdk,'publish',return_value={'synthetic_mock_only':True}))
            stack.enter_context(patch.object(x.sdk,'emit'))
            stack.enter_context(patch.object(x.sdk,'validate_upload',return_value=(context['listing'],Path('synthetic_cover'),f.package)))
            x.apply(context)
            steam.assert_called_once();publish.assert_called_once()
            self.assertEqual(publish.call_args.args[5],f.journal)
            self.assertTrue(publish.call_args.kwargs['update_existing']);self.assertTrue(publish.call_args.kwargs['apply'])
            self.assertEqual(len(json.loads(f.journal.read_bytes())['release_history']),20)


    def test_actual_snapshot_and_custom_event_fatal_logs_refuse_whole_preflight(self):
        diagnostics=(b'NETWORK_DISCONNECT_SNAPSHOTERROR',b'Failed to serialize CustomGameEvent',
            b'Failed to serialize CUserMsg_CustomGameEvent [148]',
            b'SendData reliable data too big (7628 bytes)',b'SendData: reliable data too big')
        for diagnostic in diagnostics:
            with self.subTest(diagnostic=diagnostic),tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
                f=Fixture(temporary)
                for item in f.patches():stack.enter_context(item)
                sdk=stack.enter_context(patch.object(x.sdk,'Steam'))
                ref=f.review['rehearsal']['engine_log_final'];path=Path(ref['path'])
                ref.update(f.raw(path,path.read_bytes()+b'\n'+diagnostic+b'\n'))
                before=f.journal.read_bytes()
                with self.assertRaisesRegex(ValueError,'Fatal network snapshot'):f.run()
                self.assertEqual(f.journal.read_bytes(),before);sdk.assert_not_called()

    def test_missing_runtime_pin_refuses_before_package_or_sdk(self):
        with patch.object(x.ops,'RUNTIME_SOURCE_REVISION',None),patch.object(x.c,'validated_package') as auth,patch.object(x.sdk,'Steam') as sdk:
            with self.assertRaisesRegex(ValueError,'PENDING_IMMUTABLE_V06'):x.preflight('a'*64,Path('fake'),'b'*64)
        auth.assert_not_called();sdk.assert_not_called()


    def test_v04_exit_proof_and_direct_native_log_origin_cannot_be_downgraded(self):
        for mode in ('legacy_log','no_exit','zero_exit','wrong_exit_exe','wrong_exit_pid','old_no_dota_flag'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
                f=Fixture(temporary)
                for item in f.patches():stack.enter_context(item)
                sdk=stack.enter_context(patch.object(x.sdk,'Steam'))
                if mode=='legacy_log':f.edit(f.review['rehearsal']['process'],log_origin='COPIED_EXTERNAL_LOG')
                else:
                    ref=f.review['rehearsal']['hold_end'];value=json.loads(Path(ref['path']).read_bytes())
                    if mode=='no_exit':value['process_lifetime']['exit_observed']=False
                    if mode=='zero_exit':value['process_lifetime']['exit_filetime']=0
                    if mode=='wrong_exit_exe':value['process_lifetime']['executable']=str(Path(x.ops.p.EXE).parent/'foreign.exe')
                    if mode=='wrong_exit_pid':value['process_lifetime']['pid']=9999
                    if mode=='old_no_dota_flag':value['end_no_dota_verified']=True
                    ref.update(f.save(Path(ref['path']),value))
                with self.assertRaises(ValueError):f.run()
                sdk.assert_not_called()


    def test_parent_four_account_listing_or_nineteen_history_cannot_replace0104(self):
        for mode in ('four_accounts','old_history','old_restore'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
                f=Fixture(temporary)
                for item in f.patches():stack.enter_context(item)
                sdk=stack.enter_context(patch.object(x.sdk,'Steam'))
                if mode=='four_accounts':
                    path=f.listing_dir/'listing.json';value=json.loads(path.read_bytes())
                    value['tester_steamids64']=value['tester_steamids64'][:4];f.save(path,value)
                if mode=='old_history':f.save(f.journal,dict(f.state,release_history=[{}]*19))
                if mode=='old_restore':f.edit(f.review['rehearsal']['restored'],status='ORIGINAL3102_FIVE_FILES_FULLY_RESTORED')
                with self.assertRaises(ValueError):f.run()
                sdk.assert_not_called()


if __name__=='__main__':unittest.main()
