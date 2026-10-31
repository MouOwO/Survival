"""Synthetic local admission tests. Zero native input, SDK init or network.

All proof files below are deliberately synthetic temporary fixtures. Passing
these tests never creates a production proof or establishes native/FPS success.
"""
from contextlib import ExitStack,nullcontext,redirect_stdout
from datetime import datetime,timezone
from pathlib import Path
from unittest.mock import Mock,patch
import copy
import importlib.util
import io
import json
import struct
import sys
import tempfile
import unittest

DIRECTORY=Path(__file__).resolve().parent
sys.path.insert(0,str(DIRECTORY))
_spec=importlib.util.spec_from_file_location('portrait1101_test_publish',DIRECTORY/'publish.py')
p=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(p)
_spec=importlib.util.spec_from_file_location('portrait1101_test_download',DIRECTORY/'verify_download.py')
d=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(d)


class PublicationAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='portrait_admission_synthetic_')
        self.addCleanup(self.temporary.cleanup)
        protocol_names=('ITEM','SEQUENCE','FILE_COUNT','CONTENT','CANDIDATE','TRUSTED','VPK','REPORT','STATE','OUTPUT',
            'MINIMUM_REMOTE_UPDATED','local_inputs')
        saved={name:getattr(d.protocol,name) for name in protocol_names}
        self.addCleanup(lambda:[setattr(d.protocol,name,value) for name,value in saved.items()])
        self.root=Path(self.temporary.name).resolve();self.counter=0
        self.process={'pid':30000,'created_utc':'2026-11-01T00:00:01Z'}
        self.package={'content_sha256':'a'*64,'release_sequence':p.b.SEQUENCE,'source_revision':'a'*40,'vpk_sha256':'b'*64,
            'package_files':[{'name':name,'bytes':index+1,'sha256':('b' if index==0 else str(index))*64}
                for index,name in enumerate([p.b.ITEM+'.vpk',*(p.b.ITEM+f'_{n:03}.vpk' for n in range(4))])],
            'target_pins':{}}
        self.manifest={'content_sha256':self.package['content_sha256']}
        self.package_sha='c'*64;self.inputs=[]
        for name in p.b.PAYLOADS:
            raw=('synthetic fixture '+name+'\n').encode();ref=self.file(raw)
            self.inputs.append({'runtime_path':name,'raw':ref,'normalization':'EXACT'})
            self.package['target_pins'][name]=p.b.checks(raw)
        self.journal={'owner':p.sdk.OWNER,'app_id':p.sdk.APP,'workshop_id':p.b.ITEM,
            'visibility_requested':3,'uploaded':True,'legal_agreement_required':False,'status':p.SUCCESS_STATUS,
            **{key:copy.deepcopy(self.package[key]) for key in ('release_sequence','content_sha256','vpk_sha256','package_files')},
            'vpk_bytes':1}
        self.journal_path=self.root/'journal.json';self.write(self.journal_path,self.journal)
        self.base=self.root/'base';self.base.mkdir()
        ids=['1','2','3','4']
        self.listing_path=self.base/'listing.json'
        self.write(self.listing_path,{'workshop_id':p.b.ITEM,'visibility_requested':'unlisted',
            'tester_steamids64':ids,'cover':'synthetic.jpg'})
        startup={'status':'PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY','release_sequence':p.b.SEQUENCE,
            'content_sha256':self.package['content_sha256'],'signed_resources_verified':6918,
            'protected_modules_verified':184,'cheats':False,'normal_default_verified':True,
            'markers':{name:True for name in p.STARTUP_MARKERS}}
        log=self.file(b'SYNTHETIC signed startup log, not native proof')
        startup['engine_log_sha256']=log['sha256']
        startup['native_process']={'pid':29000,'addon':p.b.NATIVE_ADDON,'created_utc':'2026-11-01T00:00:00Z'}
        query_output='sv_cheats = false\nsurvival_archive_http_enabled = 1\n'
        startup_query=self.json(dict(pid=29000,addon=p.b.NATIVE_ADDON,created_utc='2026-11-01T00:00:00Z',
            marker_received=True,script_injection=False,
            raw_output=query_output,raw_output_sha256=p.b.sha(query_output.encode())))
        startup['native_query_sha256']=startup_query['sha256']
        trace=dict(process=self.process,tools=True,offline_logic=True,storage='session_memory',
            gameplay_ready=True,in_progress=True,paused=False,cloud_writes=0,real_account_operations=0,cheats=True,
            release_channel='development',addon='survival',web_auth_enabled=False,
            d_checks={key:True for key in p.D_CHECKS})
        self.native=self.outer(p.NATIVE_KIND,'PASS_SCOPED_DEVELOPMENT_FUNCTIONAL_ONLY')
        self.native['equivalence']=dict(comparison_basis='EXACT_SIGNED_TWELVE_RUNTIME_INPUTS_ONLY',
            source_revision=self.package['source_revision'],full_package_gameplay_verified=False,
            broader_dependency_closure_verified=False,
            production_entry=dict(addon=p.b.NATIVE_ADDON,release_channel='production',web_auth_enabled=True,
                archive_http_enabled=1,offline_logic_test=False,cheats=False),
            development_entry=dict(addon='survival',release_channel='development',web_auth_enabled=False,
                archive_http_enabled=0,offline_logic_test=True,cheats=True))
        self.native.update(signed_startup=self.json(startup),signed_startup_log=log,signed_startup_query=startup_query,
            input_freeze_utc='2026-11-01T00:00:00Z',process=self.process,runtime_inputs=self.inputs,
            native_transport=self.transport('[ARCADE_1101_NATIVE_PROOF] ',trace),portraits={})
        for name in p.PORTRAIT_CASES:
            count=1 if name=='hero_builder_switch' else 3
            start=13 if name=='bane_5_after_eviction' else 5
            self.native['portraits'][name]=dict(visual_reviewed=True,native_ui=True,no_stale_portrait=True,
                captures=[self.screen(start+index) for index in range(count)],wearables_visible=True,
                background_visible=True,no_base_model_flash=True,reviewed_frame_count=count,
                hero_and_builder_correct=True,no_stale_qwer=True)
        self.native['portraits']['bane_5']['scene_key']='bane5'
        self.native['portraits']['bane_5_after_eviction'].update(returned_scene_key='bane5',
            visited_other_scene_keys=['s1','s2','s3','s4','s5'],
            visited_scenes={key:dict(visual_reviewed=True,capture=self.screen(8+index))
                for index,key in enumerate(['s1','s2','s3','s4','s5'])})
        self.frames=self.outer(p.FRAME_KIND,'PASS_NATIVE_OFFLINE_ETW')
        csv_ref=self.csv()
        self.frames.update(process=self.process,runtime_inputs=copy.deepcopy(self.inputs),
            capture=self.json(dict(pid=self.process['pid'],seconds=30,delay=3,started_utc=self.utc(17),wall_seconds=35,
                tools=True,read_only_etw=True,
                script_injection=False,account_operations=0,frame_csv_sha256=csv_ref['sha256'])),
            collector_identity=self.json(dict(pid=self.process['pid'],created_utc=self.process['created_utc'],
                tools=True,signature='Valid',signer='CN=Intel Corporation, O=Intel Corporation')),
            frames_csv=csv_ref)
        window={'pid':self.process['pid'],'hwnd':23,'title':'Dota 2','visible':True,'iconic':False,
            'client_rect_valid':True,'client_width':800,'client_height':600}
        self.frames['focus']=self.json(dict(target_pid=self.process['pid'],requested_seconds=30,delay_seconds=3,
            target_hwnd=23,target_window=window,all_game_foreground=True,validation={'valid':True},
            observation_start_monotonic_seconds=100,observation_end_monotonic_seconds=130,
            observation_start_unix_seconds=self.time(20),observation_end_unix_seconds=self.time(50),
            samples=[dict(seconds=index,foreground_pid=self.process['pid'],foreground_hwnd=23,
                game_foreground=True,foreground_iconic=False,target_window_valid=True,window_candidate_count=1,
                target_client_width=800,target_client_height=600) for index in range(30)]))
        self.frames['screens']={'before':self.screen(10),'after':self.screen(51)}
        self.frames['visual_review']=dict(performed=True,before_game_in_progress=True,after_game_in_progress=True,
            timer_advanced=True,**{name+'_png_sha256':screen['png']['sha256'] for name,screen in self.frames['screens'].items()})
        for side,seconds,game_time in [('before',15,100),('after',55,140)]:
            self.frames['gameplay_'+side]=self.transport('[ARCADE_1101_GAMEPLAY_SAMPLE] ',dict(process=self.process,
                in_progress=True,paused=False,gameplay_ready=True,host_timescale=1,game_time=game_time,utc=self.utc(seconds)))
        self.native_path=self.root/'functional.json';self.frames_path=self.root/'frameproof.json'
        self.reader_type=p.Evidence
        self.stack=ExitStack();self.addCleanup(self.stack.close)
        for owner,name,value in [(p.b,'JOURNAL',self.journal_path),(p.b.parent,'REPORT',self.base),
                (p.b,'VIEW',self.root/'view'),(p.b,'REPORT',self.root/'release')]:
            self.stack.enter_context(patch.object(owner,name,value))
        self.stack.enter_context(patch.object(p,'Evidence',side_effect=lambda:self.reader_type(self.root)))
        self.package_validator=self.stack.enter_context(patch.object(p,'validated_package',return_value=(self.package,self.manifest,{})))
        self.stack.enter_context(patch.object(p.b.pack.handoff,'configured_ids',return_value=ids))
        self.steam=self.stack.enter_context(patch.object(p.sdk,'Steam',side_effect=AssertionError('No SDK init in isolated tests')))
        self.publisher=self.stack.enter_context(patch.object(p.sdk,'publish',side_effect=AssertionError('No network publication in tests')))
        self.sdk_validation=self.stack.enter_context(patch.object(p.sdk,'validate_upload',side_effect=AssertionError('No SDK operation in preflight')))

    def file(self,raw):
        self.counter+=1;path=self.root/f'fixture_{self.counter}'
        path.write_bytes(raw);return {'path':str(path),'sha256':p.b.sha(raw)}

    def json(self,value):return self.file(json.dumps(value).encode())

    def write(self,path,value):
        raw=json.dumps(value).encode();path.write_bytes(raw);return p.b.sha(raw)

    def load(self,ref):return json.loads(Path(ref['path']).read_bytes())

    def outer(self,kind,status):
        return dict(schema=1,kind=kind,status=status,synthetic=False,release_sequence=p.b.SEQUENCE,
            content_sha256=self.package['content_sha256'],package_report_sha256=self.package_sha,online_fps_verified=False)

    def time(self,seconds):return datetime(2026,11,1,tzinfo=timezone.utc).timestamp()+seconds

    def utc(self,seconds):return datetime.fromtimestamp(self.time(seconds),timezone.utc).isoformat()

    def transport(self,marker,payload):
        return self.json({'process':self.process,'expected_output_received':True,'raw_output':marker+json.dumps(payload)+'\n'})

    def screen(self,seconds):
        # Deliberately synthetic PNG-shaped bytes: test fixtures, never accepted
        # by any real operator as native screenshots or exported as receipts.
        png=self.file(b'\x89PNG\r\n\x1a\n'+struct.pack('>I',13)+b'IHDR'+struct.pack('>II',800,600)+str(self.counter).encode())
        window=dict(pid=self.process['pid'],hwnd=23,foreground=True,visible=True,iconic=False,hung=False,
            client_width=800,client_height=600,corner_owners=[{'owned':True,'pid':self.process['pid']} for _ in range(4)])
        return {'png':png,'metadata':self.json(dict(schema_version=1,helper='capture_live_ui_readonly.ps1',
            png_bytes=Path(png['path']).stat().st_size,capture_valid=True,survival_tools_verified=True,
            process_created_utc=self.process['created_utc'],started_utc=self.utc(seconds),ended_utc=self.utc(seconds+.1),
            before=window,after=window))}

    def csv(self,*,pid=30000,frames=3000,duration=10,chain='0x123',offset=3000):
        lines=['ProcessID,SwapChainAddress,CPUStartTime,FrameTime']
        lines.extend(f'{pid},{chain},{offset+index*duration},{duration}' for index in range(frames+1))
        return self.file(('\n'.join(lines)+'\n').encode())

    def run_preflight(self):
        native_sha=self.write(self.native_path,self.native);frames_sha=self.write(self.frames_path,self.frames)
        return p.preflight(self.package_sha,self.native_path,native_sha,self.frames_path,frames_sha)

    def test_default_preflight_full_local_checks_and_zero_sdk_or_writes(self):
        self.write(self.native_path,self.native);self.write(self.frames_path,self.frames)
        before={path:path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        with redirect_stdout(io.StringIO()) as output:
            code=p.main(['--report-sha256',self.package_sha,'--native-proof',str(self.native_path),
                '--native-proof-sha256',p.b.sha(self.native_path.read_bytes()),'--frame-proof',str(self.frames_path),
                '--frame-proof-sha256',p.b.sha(self.frames_path.read_bytes())])
        result=json.loads(output.getvalue());self.assertEqual(code,2)
        self.assertEqual(result['status'],'SCOPED_DEVELOPMENT_REVIEW_ONLY_BLOCKED_FOR_PUBLICATION')
        self.assertFalse(result['full_package_gameplay_verified']);self.assertFalse(result['production_functional_admission'])
        self.assertFalse(result['online_fps_verified']);self.assertFalse(result['steam_initialized'])
        self.assertAlmostEqual(result['offline_etw']['mean_fps'],100)
        self.package_validator.assert_called_once_with(self.package_sha,full=True)
        self.steam.assert_not_called();self.publisher.assert_not_called();self.sdk_validation.assert_not_called()
        self.assertEqual(before,{path:path.read_bytes() for path in self.root.rglob('*') if path.is_file()})

    def test_functional_cheats_true_allowed_but_signed_startup_true_rejected(self):
        self.assertEqual(self.run_preflight()['summary']['updates_submitted'],0)
        startup=self.load(self.native['signed_startup']);startup['cheats']=True
        self.native['signed_startup']=self.json(startup)
        with self.assertRaisesRegex(ValueError,'signed startup'):self.run_preflight()

    def test_missing_startup_marker_rejected(self):
        startup=self.load(self.native['signed_startup']);startup['markers'].pop('initialized')
        self.native['signed_startup']=self.json(startup)
        with self.assertRaisesRegex(ValueError,'signed startup'):self.run_preflight()

    def test_signed_startup_must_include_real_bound_native_cvar_query(self):
        query=self.load(self.native['signed_startup_query'])
        query['raw_output']='sv_cheats = true\nsurvival_archive_http_enabled = 1\n'
        query['raw_output_sha256']=p.b.sha(query['raw_output'].encode())
        self.native['signed_startup_query']=self.json(query)
        startup=self.load(self.native['signed_startup']);startup['native_query_sha256']=self.native['signed_startup_query']['sha256']
        self.native['signed_startup']=self.json(startup)
        with self.assertRaisesRegex(ValueError,'actual same-process native'):self.run_preflight()

    def test_signed_startup_query_old_generation_same_pid_rejected(self):
        query=self.load(self.native['signed_startup_query']);query['created_utc']='2026-10-31T00:00:00Z'
        self.native['signed_startup_query']=self.json(query)
        startup=self.load(self.native['signed_startup']);startup['native_query_sha256']=self.native['signed_startup_query']['sha256']
        self.native['signed_startup']=self.json(startup)
        with self.assertRaisesRegex(ValueError,'actual same-process native'):self.run_preflight()

    def test_synthetic_or_other_candidate_or_online_claim_rejected(self):
        for key,value in [('synthetic',True),('content_sha256','d'*64),('online_fps_verified',True)]:
            with self.subTest(key=key):
                old=self.native[key];self.native[key]=value
                with self.assertRaisesRegex(ValueError,'Real evidence'):self.run_preflight()
                self.native[key]=old

    def test_old_game_setup_cloud_writes_and_missing_d_check_rejected(self):
        original=self.native['native_transport'];transport=self.load(original)
        trace=json.loads(transport['raw_output'].split('] ',1)[1])
        for key,value in [('in_progress',False),('cloud_writes',1),('storage','cloud')]:
            with self.subTest(key=key):
                bad=copy.deepcopy(trace);bad[key]=value
                self.native['native_transport']=self.transport('[ARCADE_1101_NATIVE_PROOF] ',bad)
                with self.assertRaisesRegex(ValueError,'development GAME_IN_PROGRESS'):self.run_preflight()
        bad=copy.deepcopy(trace);bad['d_checks']['owned_cast_succeeds']=False
        self.native['native_transport']=self.transport('[ARCADE_1101_NATIVE_PROOF] ',bad)
        with self.assertRaisesRegex(ValueError,'D ownership'):self.run_preflight()

    def test_frame_process_generation_and_input_freeze_rejected(self):
        self.frames['process']=dict(self.process,created_utc='2026-11-01T00:00:02Z')
        with self.assertRaisesRegex(ValueError,'generation'):self.run_preflight()
        self.frames['process']=self.process;self.native['input_freeze_utc']='2026-11-01T00:00:02Z'
        with self.assertRaisesRegex(ValueError,'source freeze'):self.run_preflight()

    def test_twelve_inputs_strict_paths_no_duplicates_or_unbound_differences(self):
        original=copy.deepcopy(self.native['runtime_inputs'])
        for bad in [original[:-1],original[:-1]+[original[0]],
                [dict(original[0],raw=self.file(b'different')), *original[1:]]]:
            self.native['runtime_inputs']=bad
            with self.assertRaises(ValueError):self.run_preflight()

    def test_only_explicit_crlf_lf_text_binding_allowed(self):
        index=1;name=self.inputs[index]['runtime_path'];self.assertTrue(name.endswith('.lua'))
        raw=Path(self.inputs[index]['raw']['path']).read_bytes().replace(b'\n',b'\r\n')
        row=dict(self.inputs[index],raw=self.file(raw),normalization='RUNTIME_CRLF_TO_GIT_LF_ONLY')
        self.native['runtime_inputs'][index]=row;self.frames['runtime_inputs'][index]=copy.deepcopy(row)
        self.run_preflight()
        row['normalization']='STRIP_WHITESPACE'
        with self.assertRaisesRegex(ValueError,'Only explicitly'):self.run_preflight()

    def test_missing_bane_wave_or_eviction_return_rejected(self):
        for name in ['bane_5','wave_equipped','hero_builder_switch','bane_5_after_eviction']:
            case=self.native['portraits'].pop(name)
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,'native cases'):self.run_preflight()
            self.native['portraits'][name]=case
        self.native['portraits']['bane_5_after_eviction']['visited_other_scene_keys']=['s1','s2','s3','s4']
        with self.assertRaisesRegex(ValueError,'Visit >4'):self.run_preflight()

    def test_sparse_or_repeated_capture_not_three_frame_review(self):
        case=self.native['portraits']['bane_5'];case['captures']=case['captures'][:1]
        with self.assertRaisesRegex(ValueError,'selection sequence'):self.run_preflight()
        case['captures']*=3
        with self.assertRaises(ValueError):self.run_preflight()

    def test_intermediate_scene_list_needs_actual_reviewed_screens(self):
        self.native['portraits']['bane_5_after_eviction']['visited_scenes'].pop('s3')
        with self.assertRaisesRegex(ValueError,'each intermediate scene'):self.run_preflight()

    def test_intermediate_scene_capture_time_order_required(self):
        returned=self.native['portraits']['bane_5_after_eviction']
        returned['visited_other_scene_keys'].reverse()
        with self.assertRaisesRegex(ValueError,'actual capture time order'):self.run_preflight()

    def test_stale_qwer_and_hidden_wearables_rejected(self):
        self.native['portraits']['hero_builder_switch']['no_stale_qwer']=False
        with self.assertRaisesRegex(ValueError,'QWER'):self.run_preflight()
        self.native['portraits']['hero_builder_switch']['no_stale_qwer']=True
        self.native['portraits']['bane_5']['wearables_visible']=False
        with self.assertRaisesRegex(ValueError,'selection sequence'):self.run_preflight()

    def test_no_actual_screenshot_or_wrong_foreground_rejected(self):
        screen=self.frames['screens']['after'];meta=self.load(screen['metadata']);meta['after']['foreground']=False
        screen['metadata']=self.json(meta)
        with self.assertRaisesRegex(ValueError,'ownership'):self.run_preflight()

    def test_focus_self_report_does_not_override_foreign_sample(self):
        focus=self.load(self.frames['focus']);focus['samples'][10]['foreground_pid']=5
        self.frames['focus']=self.json(focus)
        with self.assertRaisesRegex(ValueError,'foreground/visibility'):self.run_preflight()

    def test_old_capture_cannot_borrow_new_focus_screens_same_pid(self):
        capture=self.load(self.frames['capture']);capture.update(started_utc=self.utc(2),delay=3,wall_seconds=34)
        self.frames['capture']=self.json(capture)
        with self.assertRaisesRegex(ValueError,'this actual capture'):self.run_preflight()

    def test_csv_old_start_offsets_cannot_borrow_current_capture_window(self):
        ref=self.csv(offset=18000);self.frames['frames_csv']=ref
        capture=self.load(self.frames['capture']);capture['frame_csv_sha256']=ref['sha256'];self.frames['capture']=self.json(capture)
        with self.assertRaisesRegex(ValueError,'CPUStartTime must align'):self.run_preflight()

    def test_game_timer_not_advanced_despite_json_visual_review_rejected(self):
        sample=dict(process=self.process,in_progress=True,paused=False,gameplay_ready=True,host_timescale=1,
            game_time=100,utc=self.utc(55))
        self.frames['gameplay_after']=self.transport('[ARCADE_1101_GAMEPLAY_SAMPLE] ',sample)
        with self.assertRaisesRegex(ValueError,'timer did not advance'):self.run_preflight()

    def test_foreign_pid_multi_chain_and_short_csv_rejected(self):
        for ref in [self.csv(pid=42),self.csv(frames=119),self.file(b'ProcessID,FrameTime\n30000,10\n')]:
            self.frames['frames_csv']=ref
            capture=self.load(self.frames['capture']);capture['frame_csv_sha256']=ref['sha256'];self.frames['capture']=self.json(capture)
            with self.assertRaises(ValueError):self.run_preflight()
        ref=self.csv();path=Path(ref['path']);raw=path.read_bytes().replace(b'30000,0x123,3010,',b'30000,0x456,3010,',1)
        path.write_bytes(raw);ref['sha256']=p.b.sha(raw);self.frames['frames_csv']=ref
        capture=self.load(self.frames['capture']);capture['frame_csv_sha256']=ref['sha256'];self.frames['capture']=self.json(capture)
        with self.assertRaisesRegex(ValueError,'swapchain'):self.run_preflight()

    def test_real_frame_count_duration_and_gate_are_recomputed(self):
        accepted=p.frame_statistics(Path(self.frames['frames_csv']['path']),self.process['pid'])
        self.assertEqual(accepted['accepted_frames'],3000);self.assertEqual(accepted['p95_ms'],10)
        for bad in [dict(accepted,accepted_frames=119),dict(accepted,interval_sum_seconds=10),
                dict(accepted,mean_fps=89.99),dict(accepted,p95_ms=16.71)]:
            with self.assertRaises(ValueError):p.performance_gate(bad)
        # A60s CSV cannot borrow a30s foreground observation even at100FPS.
        ref=self.csv(frames=6000);self.frames['frames_csv']=ref
        capture=self.load(self.frames['capture']);capture['frame_csv_sha256']=ref['sha256'];self.frames['capture']=self.json(capture)
        with self.assertRaisesRegex(ValueError,'same requested observation'):self.run_preflight()

    def test_hash_change_and_evidence_escape_rejected(self):
        reader=self.reader_type(self.root);ref=self.file(b'original');reader.file(ref,self.native_path)
        Path(ref['path']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError,'changed during admission'):reader.unchanged()
        reader=self.reader_type(self.root/'other');self.assertRaises(ValueError,reader.file,ref,self.native_path)

    def test_unknown_pending_and_same_sequence_other_vpk_preserved(self):
        original=copy.deepcopy(self.journal)
        for key,value in [('status','SUBMIT_REQUEST_PENDING'),('status','UNKNOWN'),('uploaded',False),
                ('vpk_sha256','e'*64),('workshop_id','123'),('visibility_requested',2)]:
            state=dict(original);state[key]=value;self.write(self.journal_path,state)
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.run_preflight()
            self.assertEqual(json.loads(self.journal_path.read_bytes()),state)

    def test_parent_journal_binds_frozen_parent_volume_inventory(self):
        base=self.root/'parent_package.json';digest=self.write(base,self.package)
        state=dict(self.journal,release_sequence=p.b.BASE_SEQUENCE,content_sha256=p.b.BASE_CONTENT)
        with patch.object(p.b,'BASE_REPORT',base),patch.object(p.b,'BASE_REPORT_SHA',digest):
            p.journal_admission(state,self.package)
            state['package_files']=copy.deepcopy(state['package_files']);state['package_files'][2]['sha256']='e'*64
            with self.assertRaisesRegex(ValueError,'frozen3102'):p.journal_admission(state,self.package)

    def test_scoped_development_cannot_self_report_full_package_or_production_entry(self):
        self.native['equivalence']['full_package_gameplay_verified']=True
        with self.assertRaisesRegex(ValueError,'limited twelve-input'):self.run_preflight()
        self.native['equivalence']['full_package_gameplay_verified']=False
        self.native['equivalence']['development_entry']['release_channel']='production'
        with self.assertRaisesRegex(ValueError,'limited twelve-input'):self.run_preflight()

    def test_apply_hard_blocked_without_root_reviewed_dependency_closure(self):
        context=self.run_preflight();context['native_document']['broader_dependency_closure_review']={'sha256':'f'*64}
        before={path:path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        with self.assertRaisesRegex(ValueError,'PRODUCTION_ADMISSION_BLOCKED'):p.apply(context)
        self.assertEqual(before,{path:path.read_bytes() for path in self.root.rglob('*') if path.is_file()})
        self.steam.assert_not_called();self.publisher.assert_not_called();self.sdk_validation.assert_not_called()

    def test_download_success_requires_current_exact_package_and_no_pending(self):
        self.assertTrue(d.successful_same_release(self.journal,self.package,self.manifest))
        for key,value in [('status','SUBMIT_REQUEST_PENDING'),('release_sequence',p.b.BASE_SEQUENCE),
                ('content_sha256','d'*64),('vpk_bytes',100),('visibility_requested',2),('package_files',[])]:
            with self.subTest(key=key):self.assertFalse(d.successful_same_release(dict(self.journal,**{key:value}),self.package,self.manifest))

    def test_download_defaults_to_frozen_local_protocol_without_sdk(self):
        parent={'observed_utc':'2026-10-31T14:08:37.921875+00:00'};record=self.root/'parent_record.json'
        digest=self.write(record,parent);protocol_main=Mock(return_value=0)
        with patch.object(d,'validated_package',return_value=(self.package,self.manifest,{})),\
                patch.object(d.b,'BASE_RECORD',record),patch.object(d.b,'BASE_RECORD_SHA',digest),\
                patch.object(d.b,'scene_maps',side_effect=nullcontext),\
                patch.object(d.b.inc,'trusted_source',side_effect=lambda path:nullcontext()),\
                patch.object(d.protocol,'main',protocol_main):
            self.assertEqual(d.main(['--report-sha256',self.package_sha]),0)
        protocol_main.assert_called_once_with([])
        self.assertIs(d.protocol.local_inputs,d.local_inputs);self.assertEqual(d.protocol.FILE_COUNT,6918)
        self.assertEqual(d.protocol.STATE,self.journal_path)
        self.steam.assert_not_called();self.publisher.assert_not_called()

    def test_download_real_local_snapshot_wrapper_uses184_and_current_manifest_only(self):
        for path,value in [(p.b.REPORT/'package.json',self.package),
                (p.b.VIEW/d.api.pack.handoff.MANIFEST,self.manifest),(p.b.VIEW/d.api.pack.handoff.SIGNATURE,{})]:
            path.parent.mkdir(parents=True,exist_ok=True);self.write(path,value)
        self.journal['previous_release']={'steam_manifest':'1234567'}
        self.write(self.journal_path,self.journal)
        with patch.object(d,'REPORT_SHA',self.package_sha),\
                patch.object(d,'validated_package',return_value=(self.package,self.manifest,{})):
            result=d.local_inputs(True)
            self.assertTrue(result['success']);self.assertIsNone(result['expected_manifest'])
            self.assertEqual(result['protected_modules'],184)
            self.assertEqual(result['total'],15)
            bad=dict(self.journal,status='SUBMIT_REQUEST_PENDING')
            self.write(self.journal_path,bad)
            with self.assertRaisesRegex(ValueError,'pending publication'):d.local_inputs(False)
            self.assertEqual(self.load({'path':str(self.journal_path)}),bad)
        self.steam.assert_not_called();self.publisher.assert_not_called()

    def test_actual_frozen_protocol_default_is_local_and_zero_sdk(self):
        inputs={'total':15,'success':False,'expected_manifest':None}
        emitted=[]
        with patch.object(d.protocol,'local_inputs',return_value=inputs),\
                patch.object(d.protocol.shutil,'disk_usage',return_value=Mock(free=2*1024**3)),\
                patch.object(d.protocol,'RefreshSteam',side_effect=AssertionError('No Steam init')),\
                patch.object(d.protocol.api,'emit',side_effect=emitted.append):
            self.assertEqual(d.protocol.main([]),0)
        self.assertEqual(len(emitted),1);self.assertFalse(emitted[0]['steam_initialized'])
        self.assertEqual(emitted[0]['files_written'],0)

    def test_future_apply_is_original_item_only_and_new_receipts_not_fake_native(self):
        context=self.run_preflight();facts={key:copy.deepcopy(self.package[key]) for key in
            ('content_sha256','release_sequence','vpk_sha256','package_files')}
        updates=Mock(return_value={'status':'SYNTHETIC_MOCK_NOT_A_REAL_UPLOAD'})
        with patch.object(p,'require_closure_review'),patch.object(p.b,'scene_maps',side_effect=nullcontext),\
                patch.object(p.b.inc,'trusted_source',side_effect=lambda path:nullcontext()),\
                patch.object(p.sdk,'publication_lock',side_effect=lambda path:nullcontext()),\
                patch.object(p.sdk,'validate_upload',return_value=(context['listing'],self.root/'cover',facts)),\
                patch.object(p.sdk,'Steam',side_effect=lambda:nullcontext('mock SDK object')),\
                patch.object(p.sdk,'publish',updates),patch.object(p.sdk,'emit'):
            self.assertEqual(p.apply(context),0)
        self.assertEqual(updates.call_count,1)
        self.assertEqual(updates.call_args.kwargs,{'apply':True,'update_existing':True})
        self.assertEqual(updates.call_args.args[1]['workshop_id'],p.b.ITEM)
        self.assertEqual(self.load({'path':str(self.journal_path)}),self.journal)

    def test_apply_rejects_journal_change_before_any_sdk_initialization(self):
        context=self.run_preflight();self.write(self.journal_path,dict(self.journal,status='SUBMIT_REQUEST_PENDING'))
        facts={key:self.package[key] for key in ('content_sha256','release_sequence','vpk_sha256','package_files')}
        with patch.object(p,'require_closure_review'),patch.object(p.b,'scene_maps',side_effect=nullcontext),\
                patch.object(p.b.inc,'trusted_source',side_effect=lambda path:nullcontext()),\
                patch.object(p.sdk,'publication_lock',side_effect=lambda path:nullcontext()),\
                patch.object(p.sdk,'validate_upload',return_value=(context['listing'],self.root/'cover',facts)):
            with self.assertRaisesRegex(ValueError,'Journal changed'):p.apply(context)
        self.steam.assert_not_called();self.publisher.assert_not_called()

    def test_frozen_protocol_retains_callback_and_actual184_receipt_contract(self):
        raw=d.PROTOCOL.read_bytes().replace(b'\r\n',b'\n')
        self.assertEqual(p.b.sha(raw),d.PROTOCOL_SHA)
        self.assertIn(b'refresh_subscription_once()',raw)
        self.assertIn(b'self.dispatch.download(',raw)
        self.assertIn(b'protected_modules_verified=inputs["protected_modules"]',raw)
        self.assertIn(b'protected_modules_verified=180',raw) # Unchanged legacy terminal summary.


if __name__=='__main__':unittest.main()
