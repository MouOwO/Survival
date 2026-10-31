"""Read-only scoped-development review; publication currently fail-closed.

Production rejects offline logic. Independent signed startup plus twelve-input
development functional/ETW evidence cannot prove full production gameplay.
--apply additionally needs a root-reviewed immutable dependency-closure report;
none is approved. Nothing here signs, installs or starts Dota.
"""
from pathlib import Path
from datetime import datetime,timedelta,timezone
import argparse
import csv
import hashlib
import importlib.util
import json
import math
import re
import struct
import sys

sys.dont_write_bytecode=True
_checks_path=Path(__file__).with_name('release_checks.py').resolve()
_checks_name='portrait1101_adapter_release_checks'
_checks=sys.modules.get(_checks_name)
if not getattr(_checks,'__file__',None) or Path(_checks.__file__).resolve()!=_checks_path:
    _spec=importlib.util.spec_from_file_location(_checks_name,_checks_path)
    _checks=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_checks)
    sys.modules[_checks_name]=_checks
b,validated_package=_checks.b,_checks.validated_package
import steam_workshop_upload as sdk

NATIVE_KIND='DEVELOPMENT_SCOPED_EQUIVALENCE'
FRAME_KIND='NATIVE_OFFLINE_ETW_ACCEPTANCE'
D_CHECKS={'unowned_hidden_and_rejected','owned_cast_succeeds','shared_cooldown_10s',
    'failed_cast_no_new_cd_and_refund','builder_d_unaffected'}
PORTRAIT_CASES={'bane_5','wave_equipped','hero_builder_switch','bane_5_after_eviction'}
MIN_SECONDS,MIN_FRAMES,MIN_MEAN_FPS,MAX_P95_MS=30,120,90,16.7
SUCCESS_STATUS='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
STARTUP_MARKERS={'signed_addon','server_activated','initialized','layout_ready','no_script_error'}
# No broader dependency-closure equivalence has been reviewed. A data-supplied
# boolean must never turn a development fixture into production admission.
# Any future pin requires a separate root review of the exact immutable report.
APPROVED_CLOSURE_REVIEW_SHA=None


def number(value):
    b.need(type(value) in (int,float) and math.isfinite(value),'Finite numeric evidence required')
    return float(value)


def timestamp(value):
    result=datetime.fromisoformat(value.replace('Z','+00:00'))
    b.need(result.tzinfo is not None,'Timezone-aware evidence timestamp required')
    return result


def same_process(left,right):
    return (type(left.get('pid')) is int and type(right.get('pid')) is int and left['pid']>0 and left['pid']==right['pid']
        and timestamp(left['created_utc'])==timestamp(right['created_utc']))


class Evidence:
    """One indexed pass over frozen local evidence, never a live UI operation."""
    def __init__(self,root=None):
        self.root=(root or b.ROOT/'output').resolve()
        self.files={};self.decoded={}

    def file(self,ref,origin):
        b.need(isinstance(ref,dict) and isinstance(ref.get('path'),str)
            and re.fullmatch(r'[a-f0-9]{64}',ref.get('sha256','')) is not None,'Evidence path/SHA required')
        path=Path(ref['path'])
        if not path.is_absolute():path=origin.parent/path
        path=b.pack.handoff.regular_path(path)
        b.need(b.pack.runtime.within(path,self.root),'Evidence must remain beneath the private output root')
        b.need(path.stat().st_size<=512*1024*1024,'Evidence exceeds one-file512MiB budget')
        if path not in self.files:
            b.need(b.pack.runtime.digest(path)==ref['sha256'],'Evidence hash differs')
            self.files[path]=ref['sha256']
        else:b.need(self.files[path]==ref['sha256'],'Contradictory evidence references')
        return path

    def raw(self,ref,origin):
        path=self.file(ref,origin)
        b.need(path.stat().st_size<=8*1024*1024,'Structured evidence exceeds8MiB budget')
        return path.read_bytes(),path

    def document(self,ref,origin):
        path=self.file(ref,origin)
        if path not in self.decoded:
            raw,_=self.raw(ref,origin);self.decoded[path]=json.loads(raw)
        return self.decoded[path],path

    def unchanged(self):
        for path,digest in self.files.items():b.need(b.pack.runtime.digest(path)==digest,'Evidence changed during admission')


def bind_candidate(document,package,package_sha,kind):
    b.need(document.get('schema')==1 and document.get('kind')==kind and document.get('synthetic') is False
        and document.get('release_sequence')==b.SEQUENCE and document.get('content_sha256')==package['content_sha256']
        and document.get('package_report_sha256')==package_sha and document.get('online_fps_verified') is False,
        'Real evidence must bind this exact candidate; online FPS remains unverified')


def runtime_inputs(rows,package,reader,origin):
    b.need(isinstance(rows,list) and len(rows)==12,'Exactly12 frozen native runtime inputs required')
    seen=set();result={}
    for item in rows:
        name=item['runtime_path'];b.need(name in package['target_pins'] and name not in seen,'Unexpected/duplicate native runtime input')
        seen.add(name);raw,_=reader.raw(item['raw'],origin)
        normalization=item['normalization']
        if normalization=='EXACT':normalized=raw
        else:
            b.need(normalization=='RUNTIME_CRLF_TO_GIT_LF_ONLY' and name.endswith(('.lua','.txt'))
                and b'\r\n' in raw,'Only explicitly declared runtime text CRLF-to-Git-LF is allowed')
            normalized=raw.replace(b'\r\n',b'\n')
            b.need(b'\r' not in normalized,'Mixed/lone CR native source is not equivalent')
        b.need(b.checks(normalized)==package['target_pins'][name],'Native loaded-source snapshot differs from signed payload')
        result[name]={'raw_sha256':item['raw']['sha256'],'candidate_sha256':b.sha(normalized),'normalization':normalization}
    b.need(seen==set(package['target_pins']),'Missing scoped native input')
    return result


def screenshot(screen,process,reader,origin):
    path=reader.file(screen['png'],origin);metadata,_=reader.document(screen['metadata'],origin)
    with path.open('rb') as stream:header=stream.read(24)
    b.need(header[:8]==b'\x89PNG\r\n\x1a\n' and header[12:16]==b'IHDR','Native screenshot must be a PNG')
    width,height=struct.unpack('>II',header[16:24])
    b.need(width>=640 and height>=360 and metadata.get('schema_version')==1
        and metadata.get('helper')=='capture_live_ui_readonly.ps1' and metadata.get('capture_valid') is True
        and metadata.get('survival_tools_verified') is True
        and metadata.get('png_bytes')==path.stat().st_size
        and timestamp(metadata['process_created_utc'])==timestamp(process['created_utc']),'Strict Tools screenshot identity required')
    windows=[metadata[name] for name in ('before','after')]
    b.need(timestamp(process['created_utc'])<=timestamp(metadata['started_utc'])<=timestamp(metadata['ended_utc']),
        'Native screenshot predates its process or has inverted timestamps')
    b.need(windows[0]['hwnd']==windows[1]['hwnd'],'Screenshot HWND changed')
    for window in windows:
        b.need(window['pid']==process['pid'] and window.get('foreground') is True and window.get('visible') is True
            and window.get('iconic') is False and window.get('hung') is False
            and (window['client_width'],window['client_height'])==(width,height)
            and len(window['corner_owners'])==4
            and all(row['owned'] is True and row['pid']==process['pid'] for row in window['corner_owners']),
            'Native screenshot window/corner ownership changed')
    return {'started_utc':metadata['started_utc'],'ended_utc':metadata['ended_utc'],'width':width,'height':height,
        'png_sha256':screen['png']['sha256']}


def native_acceptance(document,origin,package,package_sha,reader):
    bind_candidate(document,package,package_sha,NATIVE_KIND)
    b.need(document.get('status')=='PASS_SCOPED_DEVELOPMENT_FUNCTIONAL_ONLY',
        'Only explicitly scoped development equivalence is supported; production rejects offline logic')
    startup,_=reader.document(document['signed_startup'],origin)
    b.need(startup.get('status')=='PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY'
        and startup.get('release_sequence')==b.SEQUENCE and startup.get('content_sha256')==package['content_sha256']
        and startup.get('signed_resources_verified')==6918 and startup.get('protected_modules_verified')==184
        and startup.get('cheats') is False and startup.get('normal_default_verified') is True
        and set(startup.get('markers',{}))==STARTUP_MARKERS
        and all(startup['markers'][key] is True for key in STARTUP_MARKERS),
        'Fresh same-content signed startup with cheats=false required')
    reader.file(document['signed_startup_log'],origin)
    b.need(startup['engine_log_sha256']==document['signed_startup_log']['sha256'],'Signed startup log is not bound')
    query,_=reader.document(document['signed_startup_query'],origin)
    output=query.get('raw_output','')
    b.need(startup.get('native_query_sha256')==document['signed_startup_query']['sha256']
        and query.get('marker_received') is True and query.get('script_injection') is False
        and same_process(query,startup['native_process'])
        and query.get('addon')==startup['native_process']['addon']==b.NATIVE_ADDON
        and query.get('raw_output_sha256')==b.sha(output.encode())
        and re.search(r'(?m)^sv_cheats\s*=\s*false\s*$',output)
        and re.search(r'(?m)^survival_archive_http_enabled\s*=\s*1\s*$',output),
        'Signed startup requires actual same-process native cheats/HTTP query')
    process=document['process']
    b.need(type(process.get('pid')) is int and process['pid']>0
        and timestamp(process['created_utc'])>timestamp(document['input_freeze_utc']), 'Fresh functional process after source freeze required')
    inputs=runtime_inputs(document['runtime_inputs'],package,reader,origin)
    equivalent=document['equivalence']
    b.need(equivalent.get('comparison_basis')=='EXACT_SIGNED_TWELVE_RUNTIME_INPUTS_ONLY'
        and equivalent.get('source_revision')==package['source_revision']
        and equivalent.get('full_package_gameplay_verified') is False
        and equivalent.get('broader_dependency_closure_verified') is False
        and equivalent.get('production_entry')=={'addon':b.NATIVE_ADDON,'release_channel':'production',
            'web_auth_enabled':True,'archive_http_enabled':1,'offline_logic_test':False,'cheats':False}
        and equivalent.get('development_entry')=={'addon':'survival','release_channel':'development',
            'web_auth_enabled':False,'archive_http_enabled':0,'offline_logic_test':True,'cheats':True},
        'Explicit production/development entry differences and limited twelve-input equivalence required')
    transport,_=reader.document(document['native_transport'],origin)
    b.need(same_process(transport['process'],process) and transport.get('expected_output_received') is True
        and isinstance(transport.get('raw_output'),str),'Actual native console capture/identity required')
    matches=[]
    for line in transport['raw_output'].splitlines():
        marker='[ARCADE_1101_NATIVE_PROOF] '
        if marker in line:matches.append(json.loads(line.split(marker,1)[1]))
    b.need(len(matches)==1,'One real native behavior marker required')
    trace=matches[0]
    b.need(same_process(trace['process'],process) and trace.get('tools') is True
        and trace.get('offline_logic') is True and trace.get('storage')=='session_memory'
        and trace.get('gameplay_ready') is True and trace.get('in_progress') is True and trace.get('paused') is False
        and trace.get('cloud_writes')==0 and trace.get('real_account_operations')==0
        and trace.get('release_channel')=='development' and trace.get('addon')=='survival'
        and trace.get('web_auth_enabled') is False
        and type(trace.get('cheats')) is bool,'Real isolated development GAME_IN_PROGRESS trace required; Tools cheats may be true')
    b.need(D_CHECKS<=trace.get('d_checks',{}).keys() and all(trace['d_checks'][key] is True for key in D_CHECKS),
        'Actual native D ownership/cooldown/refund/builder checks required')
    portraits=document['portraits']
    b.need(set(portraits)==PORTRAIT_CASES,'Bane5/wave/hero-builder/eviction-return native cases required')
    captures={}
    for name,case in portraits.items():
        b.need(case.get('visual_reviewed') is True and case.get('native_ui') is True
            and case.get('no_stale_portrait') is True and case.get('captures'),'Actual reviewed native screenshots required')
        captures[name]=[screenshot(screen,process,reader,origin) for screen in case['captures']]
        b.need(all(timestamp(left['ended_utc'])<=timestamp(right['started_utc'])
            for left,right in zip(captures[name],captures[name][1:])),'Native screenshot sequence must be chronological')
        if name!='hero_builder_switch':
            b.need(case.get('wearables_visible') is True and case.get('background_visible') is True
                and case.get('no_base_model_flash') is True and len(case['captures'])>=3
                and case.get('reviewed_frame_count')==len(case['captures'])
                and len({screen['png']['sha256'] for screen in case['captures']})==len(case['captures']),
                'Reviewed accessory/background/selection sequence required')
        else:b.need(case.get('hero_and_builder_correct') is True and case.get('no_stale_qwer') is True,'Hero/builder switching and QWER proof required')
    returned=portraits['bane_5_after_eviction']
    visited=returned.get('visited_other_scene_keys',[])
    b.need(len(visited)==len(set(visited))>=5 and all(isinstance(value,str) and value for value in visited)
        and portraits['bane_5']['scene_key']==returned.get('returned_scene_key')
        and returned['returned_scene_key'] not in visited,'Visit >4 other scenes and return to Bane5 required')
    intermediate=returned.get('visited_scenes',{})
    b.need(set(intermediate)==set(visited) and all(value.get('visual_reviewed') is True for value in intermediate.values()),
        'Actual reviewed screenshots for each intermediate scene required')
    visits=[screenshot(intermediate[key]['capture'],process,reader,origin) for key in visited]
    b.need(len({visit['png_sha256'] for visit in visits})==len(visits),'Intermediate scenes must have distinct actual screenshots')
    sequence=[captures['bane_5'][-1],*visits,captures['bane_5_after_eviction'][0]]
    b.need(all(timestamp(left['ended_utc'])<=timestamp(right['started_utc']) for left,right in zip(sequence,sequence[1:])),
        'Bane initial/other scenes/return must follow actual capture time order')
    return {'process':process,'runtime_inputs':inputs,'signed_startup_sha256':document['signed_startup']['sha256'],
        'scope':'DEVELOPMENT_SCOPED_EQUIVALENCE','full_package_gameplay_verified':False}


def require_closure_review(context):
    """Conservative explicit release gate, currently disabled until root review."""
    pin=APPROVED_CLOSURE_REVIEW_SHA
    b.need(isinstance(pin,str) and re.fullmatch(r'[a-f0-9]{64}',pin) is not None,
        'PRODUCTION_ADMISSION_BLOCKED: broader dependency-closure equivalence has no root-reviewed immutable SHA')
    ref=context['native_document'].get('broader_dependency_closure_review',{})
    b.need(ref.get('sha256')==pin,'Root-reviewed closure report required; self-reported PASS is insufficient')
    review,_=context['reader'].document(ref,context['native_origin'])
    b.need(review.get('kind')=='PRODUCTION_DEVELOPMENT_DEPENDENCY_CLOSURE_EQUIVALENCE'
        and review.get('release_sequence')==b.SEQUENCE
        and review.get('content_sha256')==context['package']['content_sha256']
        and review.get('package_report_sha256')==context['package_report_sha256']
        and review.get('source_revision')==context['package']['source_revision']
        and review.get('full_dependency_closure_verified') is True,
        'Audited closure must bind this exact immutable production/development pair')


def frame_statistics(path,pid):
    b.need(path.stat().st_size<=64*1024*1024,'ETW CSV exceeds64MiB budget')
    times=[];chain=None;previous=None;first_time=None;raw_rows=0
    with path.open(encoding='utf-8-sig',newline='') as stream:
        rows=csv.DictReader(stream)
        b.need({'ProcessID','SwapChainAddress','CPUStartTime','FrameTime'}<=set(rows.fieldnames or []),'PresentMon v2 columns required')
        for row in rows:
            b.need(int(row['ProcessID'])==pid,'Foreign process in frame CSV')
            b.need(row['SwapChainAddress'] and (chain is None or chain==row['SwapChainAddress']),'Exactly one ETW swapchain required')
            chain=row['SwapChainAddress'];start=float(row['CPUStartTime']);duration=float(row['FrameTime'])
            b.need(math.isfinite(start) and math.isfinite(duration) and start>=0 and duration>=0,'Invalid native frame interval')
            b.need(previous is None or start>previous,'Frame times must be monotonic')
            previous=start;raw_rows+=1
            if raw_rows==1:continue # Same conservative first-row policy as the existing collector.
            b.need(duration>0 and len(times)<200000,'Positive bounded ETW frames required')
            if first_time is None:first_time=start
            times.append(duration)
    b.need(len(times)>=MIN_FRAMES,'At least120 accepted ETW frames required')
    ordered=sorted(times);position=(len(ordered)-1)*.95;index=math.floor(position)
    p95=ordered[index]+(ordered[min(index+1,len(ordered)-1)]-ordered[index])*(position-index)
    return {'raw_frames':raw_rows,'accepted_frames':len(times),'discarded_first_row':1,
        'mean_fps':1000*len(times)/math.fsum(times),'p95_ms':p95,
        'interval_sum_seconds':math.fsum(times)/1000,'cpu_span_seconds':(previous-first_time+times[-1])/1000,
        'first_cpu_start_ms':first_time,'last_cpu_end_ms':previous+times[-1]}


def performance_gate(statistics):
    b.need(statistics['accepted_frames']>=MIN_FRAMES and statistics['interval_sum_seconds']>=MIN_SECONDS-1.5
        and statistics['cpu_span_seconds']>=MIN_SECONDS-1.5,'ETW needs real30s frame coverage')
    b.need(statistics['mean_fps']>=MIN_MEAN_FPS and statistics['p95_ms']<=MAX_P95_MS,
        'Engineering gate failed: offline mean must be>=90FPS and P95<=16.7ms; do not relax without review')


def gameplay_sample(ref,process,reader,origin):
    transport,_=reader.document(ref,origin)
    b.need(same_process(transport['process'],process) and transport.get('expected_output_received') is True,
        'Native gameplay sample process mismatch')
    matches=[]
    for line in transport['raw_output'].splitlines():
        marker='[ARCADE_1101_GAMEPLAY_SAMPLE] '
        if marker in line:matches.append(json.loads(line.split(marker,1)[1]))
    b.need(len(matches)==1,'Real gameplay sample marker required')
    sample=matches[0]
    b.need(same_process(sample['process'],process) and sample.get('in_progress') is True
        and sample.get('paused') is False and sample.get('gameplay_ready') is True
        and sample.get('host_timescale')==1,'Screen/sample must be real unpaused GAME_IN_PROGRESS')
    number(sample['game_time']);timestamp(sample['utc'])
    return sample


def frame_acceptance(document,origin,package,package_sha,native,reader):
    bind_candidate(document,package,package_sha,FRAME_KIND)
    b.need(document.get('status')=='PASS_NATIVE_OFFLINE_ETW' and same_process(document['process'],native['process']),
        'ETW must belong to the functional process generation')
    b.need(runtime_inputs(document['runtime_inputs'],package,reader,origin)==native['runtime_inputs'], 'ETW/native runtime snapshots differ')
    capture,_=reader.document(document['capture'],origin);identity,_=reader.document(document['collector_identity'],origin)
    process=native['process'];pid=process['pid'];seconds=number(capture['seconds'])
    delay=number(capture['delay']);wall=number(capture['wall_seconds']);capture_start=timestamp(capture['started_utc'])
    b.need(0<=delay<=60 and seconds+delay-1.25<=wall<=seconds+delay+120
        and timestamp(process['created_utc'])<capture_start,'Actual bounded capture start/delay/wall clock required')
    capture_end=capture_start+timedelta(seconds=wall)
    b.need(MIN_SECONDS<=seconds<=600 and capture.get('pid')==pid and capture.get('tools') is True
        and capture.get('read_only_etw') is True and capture.get('script_injection') is False
        and capture.get('account_operations')==0,'Read-only offline ETW capture >=30s required')
    b.need(identity.get('pid')==pid and timestamp(identity['created_utc'])==timestamp(process['created_utc'])
        and identity.get('tools') is True and identity.get('signature')=='Valid'
        and 'O=Intel Corporation' in identity.get('signer',''),'Actual signed PresentMon collector identity required')
    csv_path=reader.file(document['frames_csv'],origin)
    b.need(capture['frame_csv_sha256']==document['frames_csv']['sha256'],'Capture/CSV hash mismatch')
    focus,_=reader.document(document['focus'],origin);samples=focus.get('samples',[])
    b.need(focus.get('target_pid')==pid and focus.get('all_game_foreground') is True
        and focus.get('requested_seconds')==seconds and focus.get('delay_seconds')==delay
        and type(focus.get('target_hwnd')) is int
        and focus['target_hwnd']>0 and focus.get('validation',{}).get('valid') is True
        and len(samples)>=math.ceil(seconds)-1,'Real foreground coverage required')
    window=focus['target_window']
    b.need(window.get('pid')==pid and window.get('hwnd')==focus['target_hwnd'] and window.get('title')=='Dota 2'
        and window.get('visible') is True and window.get('iconic') is False and window.get('client_rect_valid') is True,
        'Actual focus target window required')
    for sample in samples:
        b.need(sample.get('foreground_pid')==pid and sample.get('foreground_hwnd')==focus['target_hwnd']
            and sample.get('game_foreground') is True and sample.get('foreground_iconic') is False
            and sample.get('target_window_valid') is True and sample.get('window_candidate_count')==1
            and sample.get('target_client_width')==window['client_width']
            and sample.get('target_client_height')==window['client_height'],
            'ETW foreground/visibility changed')
    duration=number(focus['observation_end_monotonic_seconds'])-number(focus['observation_start_monotonic_seconds'])
    times=[number(row['seconds']) for row in samples]
    gaps=[times[0],*[right-left for left,right in zip(times,times[1:])],duration-times[-1]]
    b.need(duration>=seconds-1.25 and all(right>left for left,right in zip(times,times[1:]))
        and min(gaps)>=0 and max(gaps)<=1.75,'Foreground sample timestamps/gaps invalid')
    screens={name:screenshot(document['screens'][name],process,reader,origin) for name in ('before','after')}
    b.need(all((screen['width'],screen['height'])==(window['client_width'],window['client_height'])
        for screen in screens.values()),'Screenshot/focus window dimensions differ')
    visual=document['visual_review']
    b.need(visual.get('performed') is True and visual.get('before_game_in_progress') is True
        and visual.get('after_game_in_progress') is True and visual.get('timer_advanced') is True
        and all(visual[name+'_png_sha256']==screens[name]['png_sha256'] for name in screens),
        'Actual before/after gameplay screens must be reviewed')
    before=gameplay_sample(document['gameplay_before'],process,reader,origin)
    after=gameplay_sample(document['gameplay_after'],process,reader,origin)
    b.need(number(after['game_time'])-number(before['game_time'])>=seconds-1.5,'Native gameplay timer did not advance through ETW')
    focus_start=datetime.fromtimestamp(number(focus['observation_start_unix_seconds']),timezone.utc)
    focus_end=datetime.fromtimestamp(number(focus['observation_end_unix_seconds']),timezone.utc)
    b.need(abs((focus_end-focus_start).total_seconds()-duration)<=.5,'Focus wall/monotonic clocks differ')
    b.need(timestamp(screens['before']['ended_utc'])<=focus_start<focus_end<=timestamp(screens['after']['started_utc'])
        and timestamp(before['utc'])<=focus_start and timestamp(after['utc'])>=focus_end,'Screens/gameplay samples must bracket real ETW focus observations')
    b.need(timestamp(screens['before']['ended_utc'])<=capture_start<focus_start<focus_end
        <=timestamp(screens['after']['ended_utc'])<=capture_end
        and abs((focus_start-capture_start).total_seconds()-delay)<=1.25,
        'Screens/focus must belong to this actual capture start/delay/wall window')
    statistics=frame_statistics(csv_path,pid);performance_gate(statistics)
    b.need(all(abs(statistics[key]-seconds)<=1.5 for key in ('interval_sum_seconds','cpu_span_seconds'))
        and abs(statistics['interval_sum_seconds']-statistics['cpu_span_seconds'])<=max(.05,seconds*.002),
        'ETW timestamps/intervals must cover the same requested observation')
    approximate_first=capture_start+timedelta(milliseconds=statistics['first_cpu_start_ms'])
    approximate_end=capture_start+timedelta(milliseconds=statistics['last_cpu_end_ms'])
    b.need(abs((approximate_first-focus_start).total_seconds())<=1.25
        and abs((approximate_end-focus_end).total_seconds())<=1.25,
        'Raw ETW CPUStartTime must align with this same capture/focus observation')
    statistics.update(scope='CONTROLLED_OFFLINE_TOOLS_ONLY',online_opening_fps_verified=False,
        continuous_focus_proven=False,clock_alignment_tolerance_seconds=1.25,
        absolute_etw_wall_clock_alignment_certified=False,
        focus_limit='1Hz samples plus reviewed bracketing screens; capture-spawn timing bounded to1.25s, not continuous pause/focus proof')
    return statistics


def journal_admission(state,package):
    b.need(state.get('owner')==sdk.OWNER and state.get('app_id')==sdk.APP
        and state.get('workshop_id')==b.ITEM and state.get('visibility_requested')==3
        and state.get('legal_agreement_required') is False,'Original owner/app/Unlisted journal required')
    b.need(state.get('uploaded') is True and state.get('status')==SUCCESS_STATUS,
        'Unknown/pending upload must be reconciled separately; never clear or retry it here')
    if state.get('release_sequence')==b.SEQUENCE:
        b.need(state.get('content_sha256')==package['content_sha256'] and state.get('vpk_sha256')==package['vpk_sha256']
            and state.get('package_files')==package['package_files']
            and state.get('vpk_bytes')==package['package_files'][0]['bytes'],'Different same-sequence publication exists')
    else:
        b.need(state.get('release_sequence')==b.BASE_SEQUENCE and state.get('content_sha256')==b.BASE_CONTENT,
            'Successful exact3102 parent or this identical release required')
        base=b.load(b.BASE_REPORT)
        b.need(b.pack.runtime.digest(b.BASE_REPORT)==b.BASE_REPORT_SHA
            and state.get('vpk_sha256')==base['vpk_sha256'] and state.get('package_files')==base['package_files']
            and state.get('vpk_bytes')==base['package_files'][0]['bytes'],
            'Successful parent journal package differs from frozen3102')


def preflight(package_sha,native_path,native_sha,frames_path,frames_sha):
    reader=Evidence()
    native,origin=reader.document({'path':str(native_path.resolve()),'sha256':native_sha},native_path)
    frames,frame_origin=reader.document({'path':str(frames_path.resolve()),'sha256':frames_sha},frames_path)
    package,manifest,_=validated_package(package_sha,full=True)
    b.need(len(package['package_files'])==5,'Exactly five signed VPK volumes required')
    functional=native_acceptance(native,origin,package,package_sha,reader)
    statistics=frame_acceptance(frames,frame_origin,package,package_sha,functional,reader)
    journal_raw=b.JOURNAL.read_bytes();state=json.loads(journal_raw);journal_admission(state,package)
    listing_path=b.parent.REPORT/'listing.json'
    listing,_=reader.document({'path':str(listing_path),'sha256':b.pack.runtime.digest(listing_path)},listing_path)
    listing=dict(listing)
    b.need(listing['workshop_id']==b.ITEM and listing['visibility_requested']=='unlisted'
        and sorted(listing['tester_steamids64'])==sorted(b.pack.handoff.configured_ids(b.VIEW))
        and len(listing['tester_steamids64'])==4, 'Original four-account listing required')
    listing['cover']=str((listing_path.parent/listing['cover']).resolve())
    listing.update(runtime_content_sha256=manifest['content_sha256'],release_sequence=b.SEQUENCE,release_revision=b.REVISION,
        vpk_sha256=package['vpk_sha256'],runtime_files=6918,package_files=package['package_files'],
        package_bytes=sum(row['bytes'] for row in package['package_files']))
    reader.unchanged()
    summary={'status':'SCOPED_DEVELOPMENT_REVIEW_ONLY_BLOCKED_FOR_PUBLICATION','release_sequence':b.SEQUENCE,'workshop_id':b.ITEM,
        'files':6918,'protected_modules':184,'offline_etw':statistics,'online_fps_verified':False,
        'functional_scope':'DEVELOPMENT_SCOPED_EQUIVALENCE','full_package_gameplay_verified':False,
        'production_functional_admission':False,'ready_for_upload':False,
        'blocking_reason':'No broader dependency-closure equivalence has a root-reviewed immutable SHA',
        'updates_submitted':0,'steam_initialized':False}
    return {'reader':reader,'package':package,'listing':listing,'journal_sha256':b.sha(journal_raw),'summary':summary,
        'native_document':native,'native_origin':origin,
        'native_sha256':native_sha,'frames_sha256':frames_sha,'package_report_sha256':package_sha}


def apply(context):
    require_closure_review(context)
    target=b.REPORT/'listing.json';raw=(json.dumps(context['listing'],ensure_ascii=False,indent=2)+'\n').encode()
    if target.exists():b.need(target.read_bytes()==raw,'Listing changed after preflight')
    else:b.inc.write_new(target,raw)
    with b.scene_maps(),b.inc.trusted_source(b.TRUSTED):
        listing,cover,facts=sdk.validate_upload(b.VIEW,b.OUTPUT/(b.ITEM+'.vpk'),target,b.REPORT/'package.json')
        with sdk.publication_lock(b.JOURNAL):
            b.need(b.pack.runtime.digest(b.JOURNAL)==context['journal_sha256'],'Journal changed; rerun preflight')
            validated_package(context['package_report_sha256'])
            b.need(all(facts[key]==context['package'][key] for key in
                ('content_sha256','release_sequence','vpk_sha256','package_files')),'SDK facts differ from admitted candidate')
            journal_admission(b.load(b.JOURNAL),context['package']);context['reader'].unchanged()
            with sdk.Steam() as steam:
                sdk.emit(sdk.publish(steam,listing,cover,b.OUTPUT/(b.ITEM+'.vpk'),facts,b.JOURNAL,apply=True,update_existing=True))
    return 0


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group();modes.add_argument('--preflight',action='store_true');modes.add_argument('--apply',action='store_true')
    for name in ('report-sha256','native-proof-sha256','frame-proof-sha256'):parser.add_argument('--'+name,required=True)
    parser.add_argument('--native-proof',type=Path,required=True);parser.add_argument('--frame-proof',type=Path,required=True)
    args=parser.parse_args(argv)
    context=preflight(args.report_sha256,args.native_proof,args.native_proof_sha256,args.frame_proof,args.frame_proof_sha256)
    if args.apply:return apply(context)
    print(json.dumps(context['summary'],ensure_ascii=False));return 2


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'status':'REFUSED_PRESERVE_JOURNAL','error':str(error),'updates_submitted':0}));raise SystemExit(1)
