"""Explicit reviewed production-rehearsal admission and original-item update.

No arguments: static plan. --preflight authenticates local evidence only, zero
SDK. --apply additionally performs the reviewed SDK update after every gate.
No signing, installation, game input, ACF write or fabricated closure approval.
"""
from pathlib import Path
from datetime import datetime,timedelta,timezone
import argparse
import hashlib
import importlib.util
import json
import math
import re
import struct
import subprocess
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


c=module('portrait1103_publish_checks',HERE/'release_checks.py')
b,need=c.b,c.b.need
ops=module('portrait1103_publish_rehearsal_ops',HERE/'rehearsal_v03.py')
legacy=module('portrait1103_private_evidence_utilities',HERE.parent/'arcade_portrait_release_20261031/publish.py')
# Only this private module's pure helpers use the new candidate. Never call its
# development native_acceptance/apply or fill its disabled closure constant.
legacy.b=b
sdk=legacy.sdk
timestamp,number,same_process=legacy.timestamp,legacy.number,legacy.same_process
KIND='LOCAL_SIGNED_CANDIDATE_PRODUCTION_REVIEW'
STATUS='ROOT_REVIEWED_TESTED_PATHS_PASS'
SCOPE='SAME_SIGNED_CANDIDATE_OBSERVED_FOR_TESTED_PATHS'
CASES={'bane_5','wave_equipped','hero_builder_switch','bane_5_after_eviction'}
REQUIRED_REVIEW={'production_entry_roster_oauth_reviewed','normal_oauth_approved','no_synthetic_profile',
    'no_business_claim_buy_redeem','no_runtime_script_injection','no_crash_or_hang',
    'normal_exit_without_force','keeper_held_continuously_reviewed','no_observer_hashing_during_etw'}


class Evidence(legacy.Evidence):
    def file(self,ref,origin):
        need(isinstance(ref,dict) and isinstance(ref.get('path'),str)
             and re.fullmatch(r'[a-f0-9]{64}',ref.get('sha256','')) is not None,'Evidence path and exact SHA required')
        path=Path(ref['path']);path=path if path.is_absolute() else origin.parent/path
        path=b.pack.handoff.regular_path(path)
        need(any(b.pack.runtime.within(path,root) for root in (b.ROOT/'output',ops.p.STORE)),
            'Evidence must stay in private output or the fixed rehearsal store')
        need(path.stat().st_size<=512*1024*1024,'Bounded evidence file required')
        if path not in self.files:
            need(b.pack.runtime.digest(path)==ref['sha256'],'Evidence SHA mismatch');self.files[path]=ref['sha256']
        else:need(self.files[path]==ref['sha256'],'Contradictory evidence references')
        return path


def screenshot(ref,process,reader,origin):
    path=reader.file(ref['png'],origin);meta,_=reader.document(ref['metadata'],origin)
    with path.open('rb') as stream:header=stream.read(24)
    need(header[:8]==b'\x89PNG\r\n\x1a\n' and header[12:16]==b'IHDR','Actual native PNG required')
    width,height=struct.unpack('>II',header[16:24])
    need(width>=640 and height>=360 and meta.get('schema_version')==1
         and meta.get('helper')=='capture_arcade_readonly.ps1' and meta.get('capture_valid') is True
         and meta.get('ordinary_client_verified') is True and meta.get('png_bytes')==path.stat().st_size
         and timestamp(meta['process_created_utc'])==timestamp(process['created_utc']), 'Strict ordinary-client capture required')
    need(timestamp(process['created_utc'])<=timestamp(meta['started_utc'])<=timestamp(meta['ended_utc']), 'Capture time/creation mismatch')
    need(meta['before']['hwnd']==meta['after']['hwnd'],'Capture main HWND changed')
    for state in (meta['before'],meta['after']):
        need(state.get('pid')==process['pid'] and state.get('foreground') is True and state.get('visible') is True
             and state.get('iconic') is False and state.get('hung') is False
             and (state['client_width'],state['client_height'])==(width,height)
             and len(state['corner_owners'])==4
             and all(row.get('owned') is True and row.get('pid')==process['pid'] for row in state['corner_owners']),
             'Capture foreground/window/corner identity changed')
    return dict(started_utc=meta['started_utc'],ended_utc=meta['ended_utc'],width=width,height=height,
        hwnd=meta['before']['hwnd'],png_sha256=ref['png']['sha256'])


def bind_review(review,package,package_sha):
    ops.require_source_revision()
    need(review.get('schema')==1 and review.get('kind')==KIND and review.get('status')==STATUS
         and review.get('scope')==SCOPE and review.get('synthetic') is False
         and review.get('release_sequence')==b.SEQUENCE and review.get('content_sha256')==package['content_sha256']
         and review.get('package_report_sha256')==package_sha and review.get('source_revision')==ops.RUNTIME_SOURCE_REVISION
         and package['source_revision']==ops.RUNTIME_SOURCE_REVISION
         and review.get('runtime_paths')==sorted(b.PAYLOADS), 'Actual reviewed production candidate14 evidence required')
    need(review.get('tools') is False and review.get('offline_logic_test') is False and review.get('cheats') is False
         and review.get('http_enabled') is True and review.get('official_download') is False
         and review.get('all_gameplay_paths_verified') is False,'Rehearsal is ordinary production, not development or official download')
    need(all(review.get('root_review',{}).get(key) is True for key in REQUIRED_REVIEW),'Root must review actual production/exit/observer limits')


def reject_fatal_network_diagnostics(text):
    # These exact diagnostic families accompanied the real cold-start snapshot
    # disconnect. A root no-crash boolean cannot override the actual log.
    need(re.search(r'NETWORK_DISCONNECT_SNAPSHOTERROR|Failed\s+to\s+serialize\s+(?:CUserMsg_)?CustomGameEvent|SendData[^\r\n]*reliable\s+data\s+too\s+big',
        text,re.I) is None,'Fatal network snapshot or reliable CustomGameEvent serialization diagnostic; candidate must not publish')


def rehearsal_acceptance(review,origin,package,package_sha,reader):
    refs=review['rehearsal']
    transaction,transaction_path=reader.document(refs['transaction'],origin)
    process,process_path=reader.document(refs['process'],origin)
    directory=transaction_path.parent
    need(process_path==directory/'process.json' and directory.parent==ops.p.STORE
         and transaction_path.name=='transaction.json','Exact external rehearsal transaction required')
    need(transaction.get('schema')==1 and transaction.get('kind')==ops.p.KIND
         and transaction.get('transaction_id')==directory.name and transaction.get('installed')==str(ops.p.INSTALLED)
         and transaction.get('release_sequence')==b.SEQUENCE and transaction.get('source_revision')==ops.RUNTIME_SOURCE_REVISION
         and transaction.get('package_report_sha256')==package_sha
         and transaction.get('content_sha256')==package['content_sha256']
         and transaction.get('candidate_files')==package['package_files']
         and transaction.get('code_pins')==ops.own_code_pins(),'Rehearsal transaction package/operation code differs')
    need(process.get('schema')==1 and process.get('kind')==ops.p.KIND
         and process.get('package_report_sha256')==package_sha and process.get('content_sha256')==package['content_sha256']
         and process.get('source_revision')==ops.RUNTIME_SOURCE_REVISION
         and process.get('code_pins')==transaction['code_pins'] and process.get('tools') is False
         and process.get('offline_logic_requested') is False and process.get('port')==ops.p.PORT
         and process.get('workshop_id')==b.ITEM and type(process.get('native_created_filetime')) is int
         and process.get('argv')==ops.p.arguments(Path(process['log_file']))
         and process['log_file']==str(directory/'engine.log'),'Ordinary original-item process receipt differs')
    need(Path(process['executable']).resolve()==ops.p.EXE.resolve()
         and process['command_line_sha256']==b.sha(subprocess.list2cmdline([str(ops.p.EXE),*process['argv']]).encode())
         and process['native_created_filetime']//10==ops.p.utc_ticks(process['created_utc'])//10,
         'Actual executable/full-argv/native creation binding differs')
    need(len(process.get('held_files',[]))==5 and len({(row['volume_serial'],row['file_index']) for row in process['held_files']})==5
         and [row['name'] for row in process['held_files']]==list(ops.p.NAMES)
         and [row['path'] for row in process['held_files']]==[str(ops.p.INSTALLED/name) for name in ops.p.NAMES]
         and [row['bytes'] for row in process['held_files']]==[row['bytes'] for row in package['package_files']]
         and process.get('file_hold_mode')=='GENERIC_READ_FILE_SHARE_READ_ONLY'
         and not (directory/'hold_failed.json').exists(),'Continuous five read-only file holds required')
    need(same_process(review['process'],process)
         and review['process'].get('native_created_filetime')==process['native_created_filetime'],'Review native process generation mismatch')
    inspections=[]
    need(len(refs['inspections'])>=2,'Before/after real native file inspections required')
    for ref in refs['inspections']:
        value,path=reader.document(ref,origin)
        need(path.parent==directory/'inspections' and same_process(value['process'],process)
             and value.get('package_report_sha256')==package_sha and value.get('content_sha256')==package['content_sha256']
             and value.get('source_revision')==ops.RUNTIME_SOURCE_REVISION and value.get('candidate_files')==package['package_files']
             and value.get('keeper')==process.get('keeper')
             and value.get('held_files')==process['held_files'] and value.get('index_owned_dota_use_observed') is True
             and value.get('all_gameplay_paths_verified') is False
             and any(row.get('name')==b.ITEM+'.vpk' and row.get('owned_dota_uses_file') is True
                 and row.get('owned_keeper_uses_file') is True for row in value.get('file_use',[])), 'Owned Dota/keeper candidate index observation required')
        inspections.append(timestamp(value['observed_utc']))
    need(all(a<b_ for a,b_ in zip(inspections,inspections[1:])), 'Inspection chronology invalid')
    intent,intent_path=reader.document(refs['close_intent'],origin)
    close,close_path=reader.document(refs['close_requested'],origin)
    ended,end_path=reader.document(refs['hold_end'],origin)
    restored,restore_path=reader.document(refs['restored'],origin)
    need((intent_path,close_path,end_path,restore_path)==tuple(directory/name for name in
        ('close_intent.json','close_requested.json','hold_end.json','restored.json')),'Exact close/exit/restore receipt paths required')
    need(intent.get('status')=='ONE_OWNED_WM_CLOSE_INTENT' and same_process(intent,process)
         and intent.get('code_pins')==transaction['code_pins'] and intent.get('console_connections')==0
         and intent.get('native_created_filetime')==process['native_created_filetime']
         and close.get('status')=='WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED' and close.get('queued') is True
         and close.get('force_stop') is False and close.get('console_connections')==0 and same_process(close,process),
         'Normal owned WM_CLOSE request required; request is not exit')
    need(ended.get('status')=='OWNED_DOTA_EXITED_HOLDS_COMPLETED' and same_process(ended,process)
         and ended.get('end_no_dota_verified') is True and ended.get('held_files')==process['held_files']
         and ended['process_lifetime']['created_filetime']==process['native_created_filetime'], 'Actual same-handle process exit required')
    baseline,_=b.baseline(full=False,require_current_journal=False)
    need(restored.get('status')=='ORIGINAL3102_FIVE_FILES_FULLY_RESTORED'
         and restored.get('original_files')==baseline['package_files'] and transaction.get('original_files')==baseline['package_files']
         and restored.get('original_content_sha256')==b.BASE_CONTENT and restored.get('acf_written') is False
         and restored.get('canonical_journal_written') is False and restored.get('backups_preserved') is True,
         'Original3102 full restoration receipt required')
    need(timestamp(process['started_utc'])<=inspections[0]<inspections[-1]
         <=timestamp(close['observed_utc'])<=timestamp(ended['ended_utc'])<=timestamp(restored['observed_utc']),
         'Production inspect/close/exit/restore chronology invalid')
    log=reader.file(refs['engine_log_final'],origin)
    need(log==directory/'engine.log' and log.stat().st_size<=64*1024*1024,'Exact bounded ordinary engine log required')
    text=log.read_text(encoding='utf8',errors='replace')
    need('[WS4-NATIVE-HANDOFF-01]' in text and '[Survival][INFO][Addon] initialized' in text
         and re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:',text,re.I) is None,
         'Actual ordinary entry/gameplay startup without script error required')
    reject_fatal_network_diagnostics(text)
    return dict(process=process,first=inspections[0],last=inspections[-1],restore=restored,known_network_fatal_absent=True)


def portraits_acceptance(review,origin,process,reader):
    cases=review['portraits'];need(set(cases)==CASES,'Bane5/wave/hero-builder/eviction-return cases required')
    times=[];by_case={}
    for name,case in cases.items():
        need(case.get('reviewed') is True and case.get('native_ui') is True and case.get('no_stale_qwer') is True,
            'Root-reviewed actual native portrait required')
        shots=[screenshot(ref,process,reader,origin) for ref in case['captures']]
        need(len(shots)>=3 and len({shot['png_sha256'] for shot in shots})==len(shots),'Distinct real selection frames required')
        need(all(timestamp(a['ended_utc'])<=timestamp(z['started_utc']) for a,z in zip(shots,shots[1:])),'Selection captures out of order')
        if name!='hero_builder_switch':
            need(all(case.get(key) is True for key in ('wearables_visible','background_visible','no_base_model_flash')),'Accessories/background/flash review missing')
        else:need(case.get('hero_and_builder_correct') is True,'Hero/builder switching review missing')
        by_case[name]=shots;times.extend(shots)
    returned=cases['bane_5_after_eviction'];visits=returned['visited_other_scenes']
    need(len(visits)>=5 and len({row['scene_key'] for row in visits})==len(visits)
         and returned['scene_key']==cases['bane_5']['scene_key']
         and returned['scene_key'] not in {row['scene_key'] for row in visits},'>4 different scenes then same Bane return required')
    visited=[]
    for row in visits:
        need(row.get('reviewed') is True,'Intermediate scene must be reviewed')
        shot=screenshot(row['capture'],process,reader,origin);visited.append(shot);times.append(shot)
    sequence=[by_case['bane_5'][-1],*visited,by_case['bane_5_after_eviction'][0]]
    need(all(timestamp(a['ended_utc'])<=timestamp(z['started_utc']) for a,z in zip(sequence,sequence[1:])), 'Bane visit/return ordering required')
    return times


def frames_acceptance(frame,origin,process,reader):
    capture,_=reader.document(frame['capture'],origin);identity,_=reader.document(frame['collector_identity'],origin)
    need(capture.get('pid')==process['pid'] and capture.get('tools') is False and capture.get('read_only_etw') is True
         and capture.get('script_injection') is False and capture.get('account_operations')==0,'Ordinary read-only ETW required')
    seconds,delay,wall=map(number,(capture['seconds'],capture['delay'],capture['wall_seconds']))
    start=timestamp(capture['started_utc'])
    need(30<=seconds<=600 and 0<=delay<=60 and seconds+delay-1.25<=wall<=seconds+delay+120
         and timestamp(process['created_utc'])<start,'Actual ETW start/delay/duration required')
    need(same_process(identity,process) and identity.get('tools') is False and identity.get('signature')=='Valid'
         and 'O=Intel Corporation' in identity.get('signer',''),'Signed native collector identity required')
    csv=reader.file(frame['frames_csv'],origin)
    need(capture['frame_csv_sha256']==frame['frames_csv']['sha256'],'Capture/CSV mismatch')
    stats=legacy.frame_statistics(csv,process['pid'])
    need(stats['accepted_frames']>=120 and stats['mean_fps']>=90 and stats['p95_ms']<=16.7,
         'Ordinary rehearsal engineering threshold requires >=90FPS and P95<=16.7ms')
    need(all(abs(stats[key]-seconds)<=1.5 for key in ('interval_sum_seconds','cpu_span_seconds'))
         and abs(stats['interval_sum_seconds']-stats['cpu_span_seconds'])<=max(.05,seconds*.002),
         'ETW actual frame duration/interval consistency mismatch')
    focus,_=reader.document(frame['focus'],origin);samples=focus['samples'];window=focus['target_window']
    need(focus.get('target_pid')==process['pid'] and focus.get('all_game_foreground') is True
         and focus.get('validation',{}).get('valid') is True and focus['requested_seconds']==seconds
         and focus['delay_seconds']==delay and len(samples)>=math.ceil(seconds)-1
         and type(focus.get('target_hwnd')) is int and focus['target_hwnd']>0
         and window.get('pid')==process['pid'] and window.get('hwnd')==focus.get('target_hwnd')
         and window.get('title')=='Dota 2' and window.get('visible') is True and window.get('iconic') is False
         and window.get('client_rect_valid') is True,
         'Same ordinary native window focus evidence required')
    for row in samples:
        need(row.get('foreground_pid')==process['pid'] and row.get('foreground_hwnd')==focus['target_hwnd']
             and row.get('game_foreground') is True and row.get('foreground_iconic') is False
             and row.get('target_window_valid') is True and row.get('window_candidate_count')==1
             and row.get('target_client_width')==window['client_width'] and row.get('target_client_height')==window['client_height'],
             'Ordinary ETW lost focus/window identity')
    duration=number(focus['observation_end_monotonic_seconds'])-number(focus['observation_start_monotonic_seconds'])
    moments=[number(row['seconds']) for row in samples]
    gaps=[moments[0],*[z-a for a,z in zip(moments,moments[1:])],duration-moments[-1]]
    need(duration>=seconds-1.25 and all(a<z for a,z in zip(moments,moments[1:])) and min(gaps)>=0 and max(gaps)<=1.75,
         'Focus monotonic sample gaps invalid')
    first=datetime.fromtimestamp(number(focus['observation_start_unix_seconds']),timezone.utc)
    last=datetime.fromtimestamp(number(focus['observation_end_unix_seconds']),timezone.utc)
    need(abs((last-first).total_seconds()-duration)<=.5
         and abs((first-start).total_seconds()-delay)<=1.25
         and abs((start+timedelta(milliseconds=stats['first_cpu_start_ms'])-first).total_seconds())<=1.25
         and abs((start+timedelta(milliseconds=stats['last_cpu_end_ms'])-last).total_seconds())<=1.25,'ETW/foreground windows differ')
    screens={name:screenshot(frame['screens'][name],process,reader,origin) for name in ('before','after')}
    visual=frame['visual_review']
    need(all(visual.get(key) is True for key in ('performed','before_game_in_progress','after_game_in_progress','timer_advanced'))
         and visual.get('before_paused') is False and visual.get('after_paused') is False
         and number(visual['gameplay_timer_advanced_seconds'])>=seconds-1.5
         and all(visual[name+'_png_sha256']==screens[name]['png_sha256'] for name in screens), 'Root-reviewed real advancing gameplay screens required')
    need(timestamp(screens['before']['ended_utc'])<=start<first<last<=timestamp(screens['after']['started_utc'])
         and timestamp(screens['after']['ended_utc'])<=start+timedelta(seconds=wall), 'Screens must bracket actual ETW capture')
    visible_span=(timestamp(screens['after']['started_utc'])-timestamp(screens['before']['ended_utc'])).total_seconds()
    need(abs(number(visual['gameplay_timer_advanced_seconds'])-visible_span)<=2,
         'Visible gameplay timer must advance at normal speed across the actual bracketing screens')
    need(all((shot['width'],shot['height'])==(window['client_width'],window['client_height'])
         and shot['hwnd']==focus['target_hwnd'] for shot in screens.values()), 'Screen/focus main HWND or dimensions differ')
    return stats,list(screens.values())


def preflight(package_sha,review_path,review_sha):
    ops.require_source_revision()
    package,manifest,signed=c.validated_package(package_sha,full=True)
    need(package['source_revision']==ops.RUNTIME_SOURCE_REVISION and len(package['package_files'])==5,'Exact immutable v03 signed package required')
    reader=Evidence();review,origin=reader.document(dict(path=str(review_path.resolve()),sha256=review_sha),review_path)
    bind_review(review,package,package_sha)
    native=rehearsal_acceptance(review,origin,package,package_sha,reader)
    screens=portraits_acceptance(review,origin,native['process'],reader)
    stats,etw_screens=frames_acceptance(review['frames'],origin,native['process'],reader);screens+=etw_screens
    need(native['first']<=min(timestamp(shot['started_utc']) for shot in screens)
         and max(timestamp(shot['ended_utc']) for shot in screens)<=native['last'], 'Native inspections must bracket tested pixels/ETW')
    # Recheck the actual installed baseline after restoration, not just a flag.
    baseline,old=b.baseline(full=True,require_current_journal=False)
    ops.p.require_rows(ops.p.INSTALLED,baseline['package_files']);ops.p.full_vpk(ops.p.INSTALLED,old)
    state_raw=b.JOURNAL.read_bytes();state=json.loads(state_raw);legacy.journal_admission(state,package)
    if state['release_sequence']==b.BASE_SEQUENCE:
        need(b.sha(state_raw)==package['canonical_journal_sha256']
             and len(state.get('release_history',[]))==19 and isinstance(state.get('previous_release'),dict),
             'Exact original3102 canonical journal and all19 history entries must be preserved')
    else:
        need(len(state.get('release_history',[]))>=19,'Already-submitted journal lost history; reconcile separately')
    already_submitted=state['release_sequence']==b.SEQUENCE
    listing_path=b.parent.REPORT/'listing.json';listing=b.load(listing_path)
    need(listing['workshop_id']==b.ITEM and listing['visibility_requested']=='unlisted'
         and sorted(listing['tester_steamids64'])==sorted(b.pack.handoff.configured_ids(b.VIEW))
         and len(listing['tester_steamids64'])==4,'Original Unlisted four-account listing required')
    listing=dict(listing);listing['cover']=str((listing_path.parent/listing['cover']).resolve())
    listing.update(runtime_content_sha256=manifest['content_sha256'],release_sequence=b.SEQUENCE,release_revision=b.REVISION,
        vpk_sha256=package['vpk_sha256'],runtime_files=6918,package_files=package['package_files'],
        package_bytes=sum(row['bytes'] for row in package['package_files']))
    reader.unchanged()
    return dict(reader=reader,review_path=review_path,review_sha256=review_sha,package=package,listing=listing,
        package_report_sha256=package_sha,journal_sha256=b.sha(state_raw),summary=dict(status='LOCAL_V03_PRODUCTION_REHEARSAL_PREFLIGHT_PASS',
        scope=SCOPE,release_sequence=b.SEQUENCE,content_sha256=package['content_sha256'],runtime_source_revision=ops.RUNTIME_SOURCE_REVISION,
        files=6918,protected_modules=184,local_ordinary_etw=stats,restored3102_verified=True,known_network_fatal_absent=True,
        all_gameplay_paths_verified=False,official_download=False,post_upload_arcade_verified=False,
        already_submitted=already_submitted,ready_for_authorized_original_item_update=not already_submitted,
        steam_initialized=False,updates_submitted=0))


def apply(context):
    # Rebuild the complete admission immediately before any mutation/SDK use.
    fresh=preflight(context['package_report_sha256'],context['review_path'],context['review_sha256'])
    need(fresh['journal_sha256']==context['journal_sha256'],'Canonical journal changed; preserve it and re-review')
    need(not fresh['summary']['already_submitted'],'This release is already submitted; verify official download instead of reapplying')
    target=b.REPORT/'listing.json';raw=(json.dumps(fresh['listing'],ensure_ascii=False,indent=2)+'\n').encode()
    if target.exists():need(target.read_bytes()==raw,'Different derived listing exists')
    else:b.inc.write_new(target,raw)
    with b.scene_maps(),b.inc.trusted_source(b.TRUSTED):
        listing,cover,facts=sdk.validate_upload(b.VIEW,b.OUTPUT/(b.ITEM+'.vpk'),target,b.REPORT/'package.json')
        with sdk.publication_lock(b.JOURNAL):
            need(b.pack.runtime.digest(b.JOURNAL)==fresh['journal_sha256'],'Journal changed before SDK; do not clear pending')
            c.validated_package(fresh['package_report_sha256'])
            need(all(facts[key]==fresh['package'][key] for key in ('content_sha256','release_sequence','vpk_sha256','package_files')), 'SDK package facts differ')
            legacy.journal_admission(b.load(b.JOURNAL),fresh['package']);fresh['reader'].unchanged()
            with sdk.Steam() as steam:
                sdk.emit(sdk.publish(steam,listing,cover,b.OUTPUT/(b.ITEM+'.vpk'),facts,b.JOURNAL,apply=True,update_existing=True))
    return 0


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group();modes.add_argument('--preflight',action='store_true');modes.add_argument('--apply',action='store_true')
    parser.add_argument('--report-sha256');parser.add_argument('--review',type=Path);parser.add_argument('--reviewed-evidence-sha256')
    args=parser.parse_args(argv)
    if not args.preflight and not args.apply:
        need(not any((args.report_sha256,args.review,args.reviewed_evidence_sha256)),'Static plan takes no action inputs')
        print(json.dumps(dict(status='STATIC_V03_PUBLICATION_PLAN_NO_EFFECTS',sdk_initialized=False,updates_submitted=0,
            required_review_kind=KIND,scope=SCOPE,ready_for_upload=False)));return 0
    need(args.review is not None and args.report_sha256 and args.reviewed_evidence_sha256,'Exact signed report and root-reviewed evidence path/SHA required')
    context=preflight(args.report_sha256,args.review,args.reviewed_evidence_sha256)
    if args.apply:return apply(context)
    print(json.dumps(context['summary']));return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        reason=str(error)
        safe_reason=reason if isinstance(error,(ValueError,KeyError)) and re.fullmatch(r"[A-Za-z0-9_ .,:;/<>=()'\-]{1,240}",reason) else 'External validation failed; inspect locally'
        print(json.dumps(dict(status='REFUSED_V03_PRESERVE_CANONICAL_JOURNAL',error_type=type(error).__name__,reason=safe_reason,updates_submitted=0)))
        raise SystemExit(2)
