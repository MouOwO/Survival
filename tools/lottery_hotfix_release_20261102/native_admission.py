"""Read-only lottery visual admission; no SDK, gameplay action or live query.

Default execution is a static plan. Explicit admission authenticates one signed
four-resource package and a finite ordinary-client evidence set. It neither
inherits Boss/FPS gates nor treats synthetic consumer tests as player draws.
"""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import importlib.util
import json
import re
import struct
import subprocess
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SEQUENCE=2026110202
POOLS=('map','cultivation','dragon_knight','summer')
KIND='LOTTERY_HOTFIX_ORDINARY_VISUAL_REVIEW'
SCOPE='LOTTERY_PRESENTATION_ONLY_NO_TRANSACTION'
POLICY='DATA_VOLUMES_USED_INDEX_AUTHENTICATED_NOT_OPEN'
REVIEW_FLAGS=('normal_oauth_approved','no_synthetic_profile','no_draw_purchase_claim_redeem',
    'no_runtime_script_injection','no_crash_or_hang','normal_exit_without_force',
    'keeper_held_continuously_reviewed')


def need(ok,message):
    if not ok:raise ValueError(message)


def sha(raw):return hashlib.sha256(raw).hexdigest()


def timestamp(value):
    need(isinstance(value,str),'Timezone-aware timestamp required')
    result=datetime.fromisoformat(value.replace('Z','+00:00'))
    need(result.tzinfo is not None,'Timezone-aware timestamp required')
    return result


def same_process(left,right):
    return (type(left.get('pid'))is int and left['pid']>0 and left['pid']==right.get('pid')
        and timestamp(left['created_utc'])==timestamp(right['created_utc'])
        and type(left.get('native_created_filetime'))is int
        and left['native_created_filetime']==right.get('native_created_filetime'))


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def environment():
    # Lazy: importing this module or printing the plan does not load a package,
    # inspect a process, contact Steam, or read any signing/authentication key.
    checks=module('lottery0202_native_checks',HERE/'release_checks.py')
    ops=module('lottery0202_native_rehearsal',HERE/'rehearsal.py')
    return checks,checks.b,ops


class Evidence:
    """Index each bounded evidence object once; rehash once at final admission.

    At most128 files/384MiB total; JSON8MiB, native log64MiB, PNG20MiB.
    O(total evidence bytes+file count), no timer, UI bridge or online request.
    """
    def __init__(self,b,ops):self.b,self.ops=b,ops;self.files={};self.decoded={};self.bytes=0
    def file(self,ref,origin):
        need(isinstance(ref,dict) and isinstance(ref.get('path'),str)
            and re.fullmatch('[a-f0-9]{64}',ref.get('sha256','')),'Evidence path/SHA required')
        path=Path(ref['path']);path=path if path.is_absolute()else origin.parent/path
        path=self.b.pack.handoff.regular_path(path)
        need(any(self.b.pack.runtime.within(path,root)for root in (self.b.ROOT/'output',self.ops.p.STORE)),
            'Evidence outside fixed private roots')
        size=path.stat().st_size;need(size<=64*1024*1024,'Evidence file exceeds64MiB')
        if path not in self.files:
            need(len(self.files)<128 and self.bytes+size<=384*1024*1024,'Evidence budget exceeded')
            need(self.b.pack.runtime.digest(path)==ref['sha256'],'Evidence SHA mismatch')
            self.files[path]=ref['sha256'];self.bytes+=size
        else:need(self.files[path]==ref['sha256'],'Contradictory evidence references')
        return path
    def document(self,ref,origin):
        path=self.file(ref,origin);need(path.stat().st_size<=8*1024*1024,'JSON exceeds8MiB')
        if path not in self.decoded:
            def pairs(items):
                result={}
                for key,value in items:
                    need(key not in result,'Duplicate evidence JSON key');result[key]=value
                return result
            self.decoded[path]=json.loads(path.read_bytes(),object_pairs_hook=pairs)
        return self.decoded[path],path
    def unchanged(self):
        for path,digest in self.files.items():
            need(self.b.pack.runtime.digest(path)==digest,'Evidence changed during admission')


def screenshot(ref,process,reader,origin):
    path=reader.file(ref['png'],origin);meta,_=reader.document(ref['metadata'],origin)
    need(path.stat().st_size<=20*1024*1024,'PNG exceeds20MiB')
    with path.open('rb')as stream:head=stream.read(24)
    need(head[:8]==b'\x89PNG\r\n\x1a\n' and head[12:16]==b'IHDR','Actual native PNG required')
    width,height=struct.unpack('>II',head[16:24])
    need(width>=640 and height>=360 and width*height<=4000000,'Bounded native image dimensions required')
    need(meta.get('schema_version')==1 and meta.get('helper')=='capture_arcade_readonly.ps1'
        and meta.get('capture_valid')is True and meta.get('ordinary_client_verified')is True
        and meta.get('png_bytes')==path.stat().st_size
        and timestamp(meta['process_created_utc'])==timestamp(process['created_utc']),
        'Strict ordinary screenshot metadata required')
    need(timestamp(process['created_utc'])<=timestamp(meta['started_utc'])<=timestamp(meta['ended_utc']),
        'Screenshot predates process')
    need(meta['before']['hwnd']==meta['after']['hwnd'],'Screenshot HWND changed')
    for state in (meta['before'],meta['after']):
        need(state.get('pid')==process['pid'] and type(state.get('hwnd'))is int and state['hwnd']>0
            and state.get('foreground')is True and state.get('visible')is True
            and state.get('iconic')is False and state.get('hung')is False
            and (state['client_width'],state['client_height'])==(width,height)
            and len(state['corner_owners'])==4
            and all(row.get('owned')is True and row.get('pid')==process['pid']for row in state['corner_owners']),
            'Screenshot lost ordinary native window identity')
    return dict(start=timestamp(meta['started_utc']),end=timestamp(meta['ended_utc']),
        hwnd=meta['before']['hwnd'],width=width,height=height,sha256=ref['png']['sha256'])


def lifecycle(review,origin,report,report_sha,reader,b,ops):
    refs=review['rehearsal'];transaction,path=reader.document(refs['transaction'],origin)
    process,process_path=reader.document(refs['process'],origin);directory=path.parent
    need(path.name=='transaction.json' and directory.parent==ops.p.STORE
        and process_path==directory/'process.json','Exact rehearsal transaction path required')
    sources=report['source_revisions'];pins=ops.own_code_pins()
    need(transaction.get('schema')==1 and transaction.get('kind')==ops.p.KIND
        and transaction.get('transaction_id')==directory.name and transaction.get('installed')==str(ops.p.INSTALLED)
        and transaction.get('release_sequence')==SEQUENCE and transaction.get('package_report_sha256')==report_sha
        and transaction.get('source_revision')==sources['game'] and transaction.get('source_revisions')==sources
        and transaction.get('content_sha256')==report['content_sha256']
        and transaction.get('candidate_files')==report['package_files'] and transaction.get('code_pins')==pins,
        'Signed candidate or operation lineage differs')
    need(process.get('kind')==ops.p.KIND and process.get('schema')==1
        and process.get('package_report_sha256')==report_sha and process.get('source_revisions')==sources
        and process.get('source_revision')==sources['game'] and process.get('code_pins')==pins
        and process.get('content_sha256')==report['content_sha256'] and process.get('workshop_id')==b.ITEM
        and process.get('tools')is False and process.get('offline_logic_requested')is False
        and process.get('owned_launch')is True and process.get('launch_route')in ops.LAUNCH_ROUTES
        and process.get('direct_entry_requested')is(process['launch_route']=='direct')
        and process.get('argv')==ops.arguments(Path(process['log_file']),process['launch_route'])
        and process.get('port')==ops.p.PORT and process.get('log_file')==str(ops.expected_log_path(directory))
        and process.get('log_origin')=='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT',
        'Fresh owned ordinary-client launch and native log required; manual/Tools refused')
    need(Path(process['executable']).resolve()==ops.p.EXE.resolve()
        and process['command_line_sha256']==sha(subprocess.list2cmdline([str(ops.p.EXE),*process['argv']]).encode())
        and type(process.get('native_created_filetime'))is int
        and process['native_created_filetime']//10==ops.p.utc_ticks(process['created_utc'])//10
        and timestamp(process['started_utc'])<=timestamp(process['created_utc'])
        and same_process(review['process'],process),'Actual PID/full-argv/native creation differs')
    names=list(ops.p.NAMES);held=process.get('held_files',[])
    need(len(held)==5 and [row['name']for row in held]==names
        and [row['path']for row in held]==[str(ops.p.INSTALLED/name)for name in names]
        and [row['bytes']for row in held]==[row['bytes']for row in report['package_files']]
        and len({(row['volume_serial'],row['file_index'])for row in held})==5
        and process.get('file_hold_mode')=='GENERIC_READ_FILE_SHARE_READ_ONLY'
        and not(directory/'hold_failed.json').exists(),'Continuous signed five-file identity holds required')
    observations=[]
    need(len(refs['inspections'])==2,'Exactly before/after native observations required')
    for ref in refs['inspections']:
        value,where=reader.document(ref,origin);rows=value.get('file_use',[])
        need(where.parent==directory/'inspections' and same_process(value['process'],process)
            and value.get('package_report_sha256')==report_sha and value.get('source_revisions')==sources
            and value.get('content_sha256')==report['content_sha256']
            and value.get('candidate_files')==report['package_files'] and value.get('held_files')==held
            and value.get('keeper')==process.get('keeper') and len(rows)==5
            and [row.get('name')for row in rows]==names
            and all(row.get('owned_keeper_uses_file')is True for row in rows)
            and all(row.get('owned_dota_uses_file')is True for row in rows[1:])
            and type(rows[0].get('owned_dota_uses_file'))is bool
            and value.get('index_owned_dota_use_observed')is rows[0]['owned_dota_uses_file']
            and value.get('external_signed_manifest_binding')is True
            and value.get('external_signed_resources_verified')==6917
            and value.get('external_protected_modules_verified')==184,'Actual same-process signed data-volume use required')
        all_open=all(row['owned_dota_uses_file']and row['owned_keeper_uses_file']for row in rows)
        need(value.get('all_five_open_verified')is all_open
            and value.get('all_five_owned_dota_file_uses_observed')is all_open,'Raw index-use observations must remain unchanged')
        observations.append(timestamp(value['observed_utc']))
    documents={}
    for name in ('close_intent','close_requested','hold_end','restored'):
        value,where=reader.document(refs[name],origin)
        need(where==directory/(name+'.json'),'Exact lifecycle receipt path required');documents[name]=value
    intent,close,end,restored=(documents[name]for name in ('close_intent','close_requested','hold_end','restored'))
    need(intent.get('status')=='ONE_OWNED_WM_CLOSE_INTENT' and same_process(intent,process)
        and intent.get('code_pins')==pins and intent.get('console_connections')==0
        and close.get('status')=='WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED' and same_process(close,process)
        and close.get('queued')is True and close.get('force_stop')is False and close.get('console_connections')==0,
        'Normal owned close request required, distinct from exit')
    life=end.get('process_lifetime',{})
    need(end.get('status')=='OWNED_DOTA_EXITED_HOLDS_COMPLETED' and same_process(end,process)
        and end.get('held_files')==held and end.get('end_no_dota_verified')is None
        and end.get('end_no_dota_check_deferred_to_restore')is True
        and life.get('pid')==process['pid'] and Path(life.get('executable','')).resolve()==ops.p.EXE.resolve()
        and life.get('exit_observed')is True and life.get('executable_verified_while_alive')is True
        and life.get('exit_identity_method')=='SAME_RETAINED_HANDLE_GETPROCESSTIMES'
        and life.get('created_filetime')==process['native_created_filetime']
        and type(life.get('exit_filetime'))is int and life['exit_filetime']>life['created_filetime'],
        'Same retained native handle exit required, not PID absence')
    baseline,old=b.baseline(full=False,require_current_journal=False)
    need(restored.get('status')=='ORIGINAL0104_FIVE_FILES_FULLY_RESTORED'
        and restored.get('original_files')==transaction.get('original_files')==baseline['package_files']
        and restored.get('original_content_sha256')==b.BASE_CONTENT and restored.get('acf_written')is False
        and restored.get('canonical_journal_written')is False and restored.get('backups_preserved')is True,
        'Official0104 exact five-file restoration required')
    need(timestamp(process['created_utc'])<=observations[0]<observations[1]
        <=timestamp(close['observed_utc'])<=timestamp(end['ended_utc'])<=timestamp(restored['observed_utc'])
        <=timestamp(review['reviewed_utc']),'Inspection/exit/restore/final review chronology invalid')
    log=reader.file(refs['engine_log_final'],origin)
    need(log==ops.expected_log_path(directory),'Exact native launch log required')
    text=log.read_text(encoding='utf8',errors='replace')
    need('[WS4-NATIVE-HANDOFF-01]'in text and '[Survival][INFO][Addon] initialized'in text,
        'Actual ordinary original-item handoff and addon startup required')
    need(re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:|'
        r'NETWORK_DISCONNECT_SNAPSHOTERROR|Failed\s+to\s+serialize\s+(?:CUserMsg_)?CustomGameEvent|'
        r'SendData[^\r\n]*reliable\s+data\s+too\s+big|VPK directory corrupt',text,re.I)is None,
        'Native script/network/package fatal diagnostic rejects admission')
    return process,observations,text


def lottery_cases(review,origin,process,bounds,text,reader):
    cases=review['lottery_previews'];need(set(cases)==set(POOLS),'Exactly four pool previews required')
    shots=[];error_cases=0;balance_pools={}
    for pool in POOLS:
        case=cases[pool];need(case.get('mode')=='NO_CONSUMPTION_PREVIEW' and case.get('pool')==pool,
            'Native preview only; do not spend tickets or manufacture a production ACK')
        visual=case['visual_review']
        need(all(visual.get(key)is True for key in ('theme_matches_pool','animation_progressed',
            'returned_to_lottery_window','no_movie_error_visible_after_fallback','no_draw_inputs')),
            'Root must review actual animation pixels and return window')
        # Preview may leave the ordinary window on map while showing another
        # theme. State which visible balance was actually read; do not invent
        # a target-pool balance or require spending to unlock its tab.
        need(case.get('observed_ticket_pool')in POOLS,'Explicit visible balance pool required')
        balance_pools[pool]=case['observed_ticket_pool']
        need(type(case.get('tickets_before'))is int and 0<=case['tickets_before']<=2147483647
            and type(case.get('tickets_after'))is int and case['tickets_before']==case['tickets_after'],
            'Visible ticket balance must remain unchanged')
        roles=('window_before','animation_a','animation_b','window_after')
        need(set(case['captures'])==set(roles),'Before/two dynamic frames/return captures required')
        current=[screenshot(case['captures'][role],process,reader,origin)for role in roles]
        need(visual.get('reviewed_png_sha256')==[shot['sha256']for shot in current],
            'Pixel review must bind exact four captures')
        # Returning to the same unchanged window may legitimately reproduce
        # its exact pixels. Only the two animation frames must visibly differ.
        need(current[1]['sha256']!=current[2]['sha256']
            and all(shot['sha256']not in {current[0]['sha256'],current[3]['sha256']}for shot in current[1:3])
            and all(a['end']<z['start']for a,z in zip(current,current[1:])),
            'Distinct chronological native animation frames required')
        start='[LOTTERY_CINEMATIC] stage=preview pool='+pool
        finish='[LOTTERY_CINEMATIC] stage=complete pool='+pool+' preview=true'
        left=text.find(start);right=text.find(finish,left+len(start))
        need(left>=0 and right>left,'Pool-specific native preview/completion log sequence required')
        segment=text[left:right]
        if case.get('presentation')=='fallback':
            reason=case.get('fallback_reason')
            need(reason in ('native_error','sync_error','circuit_open'), 'Native fallback reason required')
            need('[LOTTERY_CINEMATIC] stage=fallback pool='+pool+' reason='+reason in segment,
                'Pool-specific native fallback log required')
            if reason in ('native_error','sync_error'):error_cases+=1
        else:need(case.get('presentation')=='movie','Unknown preview presentation')
        shots+=current
    need(error_cases>=1,'At least one real decoder-error-to-theme fallback must be observed')
    need(len({(shot['hwnd'],shot['width'],shot['height'])for shot in shots})==1,
        'All visual cases must use the same native window')
    need(bounds[0]<=min(shot['start']for shot in shots) and max(shot['end']for shot in shots)<=bounds[1],
        'Native data-volume observations must bracket every preview capture')
    need(re.search(r'\[SURVIVAL_LOTTERY_UI\]\s+(?:stage=result_received|result_count=)',text)is None,
        'Native visual window must not contain real draw ACK/results')
    return {'pools':list(POOLS),'native_error_fallback_cases':error_cases,'native_screens':len(shots),
        'unique_pngs':len({shot['sha256']for shot in shots}),'observed_ticket_pools':balance_pools,
        'ticket_balances_unchanged':True,'real_draw_ack_required':False,'consumer_ack_test_is_native':False}


def trusted_review_lineage(report,b):
    # The authenticated original18 already review ui_request_router. Replacing
    # that reviewed source does not add a twentieth review; only the production
    # presentation service is new. Authenticate the old18 before deriving19.
    router='scripts/vscripts/ui/ui_request_router.lua'
    added='scripts/vscripts/ui/production_ui_service.lua'
    parent=b.base_trusted_review(b.load(b.BASE_REPORT))
    reviewed=report.get('trusted_review_pins',{})
    need(len(parent)==18 and router in parent and added not in parent,
        'Authenticated original18 router review required')
    need(len(reviewed)==19 and set(reviewed)==set(parent)|{added}
        and set(reviewed).intersection(b.PAYLOADS)=={router,added}
        and all(reviewed[name]==pin for name,pin in parent.items()if name!=router)
        and all(reviewed[name]==report['target_pins'][name]for name in (router,added)),
        'Original17 unchanged, one controlled router replacement and one new service review required')
    need(set(b.COMPILED)==set(b.PAYLOADS[:2]) and len(b.COMPILED)==2
        and set(report.get('source_artifact_pins',{}))=={pin['source']for pin in b.COMPILED.values()},
        'Exactly the two compiled JS/CSS bindings required')
    return dict(parent_count=18,unchanged_parent_count=17,final_count=19,
        replaced_parent_paths=[router],added_paths=[added])


def validate_native_release(request,report,manifest,signed):
    checks,b,ops=environment();expected=request.get('report_sha256')
    actual,actual_manifest,actual_signed=checks.validated_package(expected,full=True)
    need((actual,actual_manifest,actual_signed)==(report,manifest,signed),'Authenticated package objects differ')
    need(signed.get('signature_valid')is True and signed.get('release_sequence')==b.SEQUENCE==SEQUENCE
        and report.get('files')==6917 and report.get('protected_modules_preserved')==184
        and len(b.PAYLOADS)==4 and report.get('changed_runtime_paths')==sorted(b.PAYLOADS),
        'Exact signed0202 four-resource candidate required')
    trusted=trusted_review_lineage(report,b)
    ops.source_binding(report,expected)
    need(request.get('source_revisions')==report['source_revisions'],'Request source pair differs')
    ref={'path':request.get('production_evidence_path'),'sha256':request.get('production_evidence_sha256')}
    reader=Evidence(b,ops);review,origin=reader.document(ref,b.ROOT/'output/native_review_origin.json')
    need(review.get('schema')==1 and review.get('kind')==KIND and review.get('scope')==SCOPE
        and review.get('synthetic')is False and review.get('release_sequence')==SEQUENCE
        and review.get('package_report_sha256')==expected and review.get('source_revisions')==report['source_revisions']
        and review.get('content_sha256')==manifest['content_sha256']==report['content_sha256']
        and review.get('runtime_paths')==sorted(b.PAYLOADS) and review.get('native_file_use_policy')==POLICY,
        'Exact signed ordinary visual review required; READY is not evidence')
    need(review.get('tools')is False and review.get('offline_logic_test')is False
        and review.get('cheats')is False and review.get('http_enabled')is True
        and review.get('real_player_transaction_performed')is False
        and all(review.get('root_review',{}).get(key)is True for key in REVIEW_FLAGS),
        'Ordinary authenticated no-consumption scope required')
    need(same_process(request['native_process_generation'],review['process']), 'Request native generation differs')
    process,bounds,text=lifecycle(review,origin,report,expected,reader,b,ops)
    visual=lottery_cases(review,origin,process,bounds,text,reader)
    baseline,old=b.baseline(full=True,require_current_journal=False)
    ops.p.require_rows(ops.p.INSTALLED,baseline['package_files']);ops.p.full_vpk(ops.p.INSTALLED,old)
    reader.unchanged()
    return dict(ordinary_production_acceptance=True,scope=SCOPE,release_sequence=SEQUENCE,
        content_sha256=manifest['content_sha256'],source_revisions=report['source_revisions'],
        production_evidence_sha256=ref['sha256'],native_process_generation=request['native_process_generation'],
        lottery_previews=visual,trusted_review_lineage=trusted,
        original0104_fully_restored=True,native_file_use_policy=POLICY,
        all_gameplay_paths_verified=False,training_tips_native_tested=False,real_player_transaction_performed=False,
        native_fps_measured=False,official_download=False,post_upload_arcade_verified=False,
        sdk_initialized=False,updates_submitted=0)


def main(argv=None):
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    print(json.dumps({'status':'STATIC_LOTTERY_NATIVE_EVIDENCE_PLAN','release_sequence':SEQUENCE,
        'scope':SCOPE,'pools':POOLS,'native_actions':0,'sdk_initialized':False,'ready_for_upload':False}))
    return 0


if __name__=='__main__':raise SystemExit(main())
