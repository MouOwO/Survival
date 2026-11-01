"""Read-only ordinary-production acceptance for the scoped seventeen-resource candidate.

Default/--plan is pure. validate_native_release authenticates evidence only.
There is no signing, installation, input, SDK initialization or upload entrypoint.
Logic tests, native pixels, cross-PC observation and FPS remain distinct evidence.
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


c=module('shared_boss0201_publish_checks',HERE/'release_checks.py')
b,need=c.b,c.b.need
ops=module('shared_boss0201_publish_rehearsal_ops',HERE/'rehearsal.py')
legacy=module('shared_boss0201_private_evidence_utilities',b.ROOT/'tools/arcade_portrait_release_20261031/publish.py')
# Only this private module's pure helpers use the new candidate. Never call its
# development native_acceptance/apply or fill its disabled closure constant.
legacy.b=b
timestamp,number,same_process=legacy.timestamp,legacy.number,legacy.same_process
KIND='LOCAL_SIGNED_CANDIDATE_PRODUCTION_REVIEW'
STATUS='ROOT_REVIEWED_TESTED_PATHS_PASS'
SCOPE='SAME_SIGNED_CANDIDATE_OBSERVED_FOR_TESTED_PATHS'
POLICY='DATA_VOLUMES_USED_INDEX_AUTHENTICATED_NOT_OPEN'
CASES={'bane_5','qop_commandment_09','wave_equipped','hero_builder_switch','bane_5_after_eviction'}
REQUIRED_REVIEW={'production_entry_roster_oauth_reviewed','normal_oauth_approved','no_synthetic_profile',
    'no_business_claim_buy_redeem','no_runtime_script_injection','no_crash_or_hang',
    'normal_exit_without_force','keeper_held_continuously_reviewed','no_observer_hashing_during_etw'}

# Read-only GDI+ codec validation is used only at explicit native preflight.
# JSON stdin carries file paths; no user text is interpolated as PowerShell.
IMAGE_DECODE_PS=r'''$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Drawing
$paths=@([Console]::In.ReadToEnd()|ConvertFrom-Json);if($paths.Count -lt 1 -or $paths.Count -gt 8){throw 'Bounded images required'}
$out=@();foreach($p in $paths){$s=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{$im=[Drawing.Image]::FromStream($s,$true,$true);try{
if($im.Width -lt 1 -or $im.Height -lt 1 -or [long]$im.Width*$im.Height -gt 2000000){throw 'Image pixel budget exceeded'}
$kind=if($im.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Png.Guid){'PNG'}elseif($im.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Jpeg.Guid){'JPEG'}else{throw 'Native PNG/JPEG required'}
if($im.PropertyIdList -contains 274 -and $im.GetPropertyItem(274).Value[0] -ne 1){throw 'Rotated EXIF image refused'}
$bmp=[Drawing.Bitmap]::new($im);try{$rect=[Drawing.Rectangle]::new(0,0,$bmp.Width,$bmp.Height)
$bits=$bmp.LockBits($rect,[Drawing.Imaging.ImageLockMode]::ReadOnly,$bmp.PixelFormat)
try{if($bits.Scan0 -eq [IntPtr]::Zero -or [long][Math]::Abs($bits.Stride)*$bmp.Height -gt 10000000){throw 'Decoded raster budget invalid'}}finally{$bmp.UnlockBits($bits)}
$out+=@{width=$bmp.Width;height=$bmp.Height;format=$kind;decoded=$true}
}finally{$bmp.Dispose()}}finally{$im.Dispose()}}finally{$s.Dispose()}}
ConvertTo-Json -InputObject $out -Compress'''


def peer_image_header(path):
    # Reject large raster headers before asking the native codec to decompress.
    with path.open('rb') as stream:raw=stream.read(65536)
    if raw[:8]==b'\x89PNG\r\n\x1a\n' and len(raw)>=24 and raw[12:16]==b'IHDR':
        width,height=struct.unpack('>II',raw[16:24])
    else:
        need(raw[:2]==b'\xff\xd8','Native PNG/JPEG peer pixels required')
        offset=2;width=height=None
        while offset+4<=len(raw):
            need(raw[offset]==255,'Invalid bounded JPEG marker')
            while offset<len(raw) and raw[offset]==255:offset+=1
            need(offset+3<=len(raw),'Truncated bounded JPEG header')
            marker=raw[offset];offset+=1
            need(marker not in {0,0xd8,0xd9,0xda},'Missing JPEG frame before image stream')
            size=struct.unpack('>H',raw[offset:offset+2])[0]
            need(size>=2 and offset+size<=len(raw),'Bounded JPEG header segment exceeds limit')
            if marker in {0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf}:
                need(size>=8,'Invalid JPEG frame dimensions')
                height,width=struct.unpack('>HH',raw[offset+3:offset+7]);break
            offset+=size
        need(width is not None and height is not None,'JPEG frame unavailable within64KiB header budget')
    need(0<width<=2000 and 0<height<=1200 and width*height<=2000000,'Peer image raster budget exceeded')
    return width,height


def decode_peer_images(paths):
    need(1<=len(paths)<=8,'Bounded peer image list required')
    headers=[peer_image_header(path) for path in paths]
    completed=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',IMAGE_DECODE_PS],
        input=json.dumps([str(path) for path in paths]).encode('utf8'),capture_output=True,timeout=20,
        creationflags=ops.p.HIDDEN)
    need(completed.returncode==0 and len(completed.stdout)<=8192,'Actual native PNG/JPEG decoding failed')
    values=json.loads(completed.stdout.decode('utf-8-sig'))
    need(isinstance(values,list) and len(values)==len(paths) and all(row.get('decoded') is True
        and type(row.get('width')) is int and type(row.get('height')) is int
        and row.get('format') in {'PNG','JPEG'} for row in values),'Complete bounded decoded dimensions required')
    need(all((row['width'],row['height'])==header for row,header in zip(values,headers)),
        'Actual codec dimensions differ from bounded native image header')
    return values


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
    sources=ops.require_source_revision()
    need(review.get('schema')==1 and review.get('kind')==KIND and review.get('status')==STATUS
         and review.get('scope')==SCOPE and review.get('synthetic') is False
         and review.get('release_sequence')==b.SEQUENCE and review.get('content_sha256')==package['content_sha256']
         and review.get('package_report_sha256')==package_sha and review.get('source_revision')==sources['game']
         and review.get('source_revisions')==sources and package['source_revisions']==sources
         and review.get('runtime_paths')==sorted(b.PAYLOADS), 'Actual reviewed production candidate17 evidence required')
    need(review.get('native_file_use_policy')==POLICY,'Corrected native file-use policy must be reviewed')
    need(review.get('tools') is False and review.get('offline_logic_test') is False and review.get('cheats') is False
         and review.get('http_enabled') is True and review.get('official_download') is False
         and review.get('all_gameplay_paths_verified') is False,'Rehearsal is ordinary production, not development or official download')
    need(all(review.get('root_review',{}).get(key) is True for key in REQUIRED_REVIEW),'Root must review actual production/exit/observer limits')


def reject_fatal_network_diagnostics(text):
    # These exact diagnostic families accompanied the real cold-start snapshot
    # disconnect. A root no-crash boolean cannot override the actual log.
    need(re.search(r'NETWORK_DISCONNECT_SNAPSHOTERROR|Failed\s+to\s+serialize\s+(?:CUserMsg_)?CustomGameEvent|SendData[^\r\n]*reliable\s+data\s+too\s+big',
        text,re.I) is None,'Fatal network snapshot or reliable CustomGameEvent serialization diagnostic; candidate must not publish')


def scope_map(package):
    # Full c.validated_package(full=True) has already authenticated all five
    # VPKs. Read/hash the small directory index once to bind this lookup too.
    path=b.OUTPUT/(b.ITEM+'.vpk')
    expected=package['package_files'][0]
    need(expected['name']==b.ITEM+'.vpk' and path.stat().st_size==expected['bytes']
        and b.pack.runtime.digest(path)==expected['sha256'],'Signed index hash/size changed')
    entries=b.inc.read_entries(path);index={row['path']:row for row in entries}
    need(len(index)==len(entries),'Duplicate signed-index paths')
    need(package['changed_runtime_paths']==sorted(b.PAYLOADS) and len(b.PAYLOADS)==17,'Exact seventeen-path payload scope required')
    result={}
    for name in b.PAYLOADS:
        row=index.get(name);pin=package['target_pins'][name]
        need(row is not None and row.get('archive') in range(4) and row.get('bytes')==pin['bytes'],
            'Every tested payload must have an authenticated data-archive mapping')
        result[name]={'archive':row['archive'],'archive_name':b.ITEM+'_%03d.vpk'%row['archive'],
            'offset':row['offset'],'bytes':row['bytes'],'payload_sha256':pin['sha256']}
    need({row['archive'] for row in result.values()}=={0,3},'Reviewed seventeen payloads must occupy archives0 and3')
    return result


def native_data_volume_use(value,process,package,mapping):
    names=list(ops.p.NAMES);rows=value.get('file_use',[])
    need(isinstance(rows,list) and len(rows)==5 and [row.get('name') for row in rows]==names,
        'Exact five RM resource rows required; missing/unknown/duplicate row')
    need(type(process.get('native_created_filetime')) is int
        and process['native_created_filetime']//10==ops.p.utc_ticks(process['created_utc'])//10,
        'Same owned native process FILETIME required')
    if 'native_created_filetime' in value.get('process',{}):
        need(value['process']['native_created_filetime']==process['native_created_filetime'],'Inspection native process FILETIME changed')
    need(timestamp(process['created_utc'])>=timestamp(process['started_utc']),
        'Fresh owned process must be created after its recorded launch start')
    held=process['held_files']
    need(value.get('held_files')==held and len(held)==5
        and len({(row['volume_serial'],row['file_index']) for row in held})==5
        and [row['name'] for row in held]==names
        and all(row['bytes']==expected['bytes'] for row,expected in zip(held,package['package_files'])),
        'All five locked FileIDs and signed sizes must remain unchanged')
    need(all(type(row.get('owned_keeper_uses_file')) is bool and row['owned_keeper_uses_file'] is True
        and type(row.get('owned_dota_uses_file')) is bool for row in rows),
        'Keeper must own all five resources with explicit unchanged observations')
    need(all(row['owned_dota_uses_file'] is True for row in rows[1:]),
        'All four data volumes must be used by the same owned Dota generation')
    need(value.get('index_owned_dota_use_observed') is rows[0]['owned_dota_uses_file'],
        'Raw index observation must remain unchanged and consistent')
    observed_all=all(row['owned_dota_uses_file'] and row['owned_keeper_uses_file'] for row in rows)
    need(value.get('all_five_open_verified') is observed_all
        and value.get('all_five_owned_dota_file_uses_observed') is observed_all,
        'Raw all-five-open observations must not be rewritten')
    need(value.get('external_signed_manifest_binding') is True
        and value.get('external_signed_resources_verified')==6919
        and value.get('external_protected_modules_verified')==184,
        'Full signed inventory authentication binding required')
    used={row['name'] for row in rows[1:]}
    need(all(row['archive_name'] in used for row in mapping.values()),'A tested payload archive is not an owned native resource')
    # The frozen inspection's file_use_result compares RM PID AND the complete
    # native100ns creation time from process.json. It did not export raw RM
    # process lists. Do not invent them or claim that such raw lists were saved.
    return dict(observed_utc=value['observed_utc'],
        pid=process['pid'],native_created_filetime=process['native_created_filetime'],
        exact_generation_source='FROZEN_INSPECTION_FILE_USE_RESULT_PID_AND_NATIVE_FILETIME',
        raw_rm_pid_lists_saved=False,data_volumes=[row['name'] for row in rows[1:]],
        keeper_all_five=True,index_owned_dota_use_observed=rows[0]['owned_dota_uses_file'],
        all_five_open_verified=value['all_five_open_verified'],held_files=held)


def unique_log_fingerprint(review,origin,reader):
    path=reader.file(review['rehearsal']['engine_log_final'],origin)
    text=path.read_text(encoding='utf8',errors='replace')
    anchors=[]
    for line in text.splitlines():
        prefix='[SURVIVAL_PORTRAIT] QUERY_ANCHOR '
        if prefix not in line:continue
        try:row=json.loads(line.split(prefix,1)[1])
        except ValueError:continue
        if (row.get('binding')=='shared_main' and row.get('sharedMainReason')=='native_portrait_identity_matches'
            and row.get('mainRejection') is None and type(row.get('entity')) is int
            and row['entity']==row.get('expectedDisplayUnit')==row.get('nativePortraitUnit')):anchors.append(row['entity'])
    need(bool(anchors),'Unique current shared_main native identity fingerprint required')
    ready=re.search(r'\[SURVIVAL_MONSTER_PORTRAIT\] READY asset=\s*'+re.escape(BANE)
        +r'\s+map=\s*[A-Za-z0-9_./-]+\s+ms=\s*\d+\s+components=\s*4\b',text)
    selected=re.search(r'\[SURVIVAL_PORTRAIT\] SCENE_SET[^\r\n]*\basset=\s*'+re.escape(BANE)+r'\b',text)
    need(ready is not None and selected is not None and re.search(
        r'\[SURVIVAL_PORTRAIT\] SHOW mode=\s*monster_scene\b',text[selected.end():]) is not None,
        'Unique Bane four-component READY, SCENE_SET and subsequent SHOW required')
    return dict(shared_main_entities=sorted(set(anchors)),bane_ready_components=4,
        bane_scene_set=True,subsequent_monster_scene_show=True,raw_log_exported=False)


def rehearsal_acceptance(review,origin,package,package_sha,reader):
    sources=ops.require_source_revision()
    refs=review['rehearsal']
    transaction,transaction_path=reader.document(refs['transaction'],origin)
    process,process_path=reader.document(refs['process'],origin)
    directory=transaction_path.parent
    need(process_path==directory/'process.json' and directory.parent==ops.p.STORE
         and transaction_path.name=='transaction.json','Exact external rehearsal transaction required')
    need(transaction.get('schema')==1 and transaction.get('kind')==ops.p.KIND
         and transaction.get('transaction_id')==directory.name and transaction.get('installed')==str(ops.p.INSTALLED)
         and transaction.get('release_sequence')==b.SEQUENCE and transaction.get('source_revision')==sources['game']
         and transaction.get('source_revisions')==sources
         and transaction.get('package_report_sha256')==package_sha
         and transaction.get('content_sha256')==package['content_sha256']
         and transaction.get('candidate_files')==package['package_files']
         and transaction.get('code_pins')==ops.own_code_pins(),'Rehearsal transaction package/operation code differs')
    need(process.get('schema')==1 and process.get('kind')==ops.p.KIND
         and process.get('package_report_sha256')==package_sha and process.get('content_sha256')==package['content_sha256']
         and process.get('source_revision')==sources['game'] and process.get('source_revisions')==sources
         and process.get('code_pins')==transaction['code_pins'] and process.get('tools') is False
         and process.get('offline_logic_requested') is False and process.get('port')==ops.p.PORT
         and process.get('workshop_id')==b.ITEM and type(process.get('native_created_filetime')) is int
         and process.get('launch_route') in ops.LAUNCH_ROUTES
         and process.get('owned_launch') is True
         and process.get('direct_entry_requested') is (process['launch_route']=='direct')
         and process.get('argv')==ops.arguments(Path(process['log_file']),process['launch_route'])
         and process['log_file']==str(ops.expected_log_path(directory))
         and process.get('log_origin')=='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT','Ordinary original-item process receipt differs')
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
         and review['process'].get('native_created_filetime')==process['native_created_filetime']
         and review['process'].get('source_revisions')==sources,'Review native process generation mismatch')
    inspections=[];volume_observations=[];mapping=scope_map(package)
    need(len(refs['inspections'])>=2,'Before/after real native file inspections required')
    for ref in refs['inspections']:
        value,path=reader.document(ref,origin)
        need(path.parent==directory/'inspections' and same_process(value['process'],process)
             and value.get('package_report_sha256')==package_sha and value.get('content_sha256')==package['content_sha256']
             and value.get('source_revision')==sources['game'] and value.get('source_revisions')==sources and value.get('candidate_files')==package['package_files']
             and value.get('keeper')==process.get('keeper')
             and value.get('held_files')==process['held_files']
             and value.get('all_gameplay_paths_verified') is False
             , 'Authenticated signed index and native data volumes required')
        volume_observations.append(native_data_volume_use(value,process,package,mapping))
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
         and ended.get('end_no_dota_verified') is None
         and ended.get('end_no_dota_check_deferred_to_restore') is True
         and ended['process_lifetime'].get('pid')==process['pid']
         and Path(ended['process_lifetime'].get('executable','')).resolve()==ops.p.EXE.resolve()
         and ended['process_lifetime'].get('exit_observed') is True
         and ended['process_lifetime'].get('executable_verified_while_alive') is True
         and ended['process_lifetime'].get('exit_identity_method')=='SAME_RETAINED_HANDLE_GETPROCESSTIMES'
         and type(ended['process_lifetime'].get('exit_filetime')) is int
         and ended['process_lifetime']['exit_filetime']>ended['process_lifetime']['created_filetime'] and ended.get('held_files')==process['held_files']
         and ended['process_lifetime']['created_filetime']==process['native_created_filetime'], 'Actual same-handle process exit required')
    baseline,_=b.baseline(full=False,require_current_journal=False)
    need(restored.get('status')=='ORIGINAL0104_FIVE_FILES_FULLY_RESTORED'
         and restored.get('original_files')==baseline['package_files'] and transaction.get('original_files')==baseline['package_files']
         and restored.get('original_content_sha256')==b.BASE_CONTENT and restored.get('acf_written') is False
         and restored.get('canonical_journal_written') is False and restored.get('backups_preserved') is True,
         'Original0104 full restoration receipt required')
    need(timestamp(process['started_utc'])<=inspections[0]<inspections[-1]
         <=timestamp(close['observed_utc'])<=timestamp(ended['ended_utc'])<=timestamp(restored['observed_utc']),
         'Production inspect/close/exit/restore chronology invalid')
    log=reader.file(refs['engine_log_final'],origin)
    need(log==ops.expected_log_path(directory) and log.stat().st_size<=64*1024*1024,'Exact bounded ordinary engine log required')
    text=log.read_text(encoding='utf8',errors='replace')
    need('[WS4-NATIVE-HANDOFF-01]' in text and '[Survival][INFO][Addon] initialized' in text
         and re.search(r'Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:',text,re.I) is None,
         'Actual ordinary entry/gameplay startup without script error required')
    reject_fatal_network_diagnostics(text)
    return dict(process=process,first=inspections[0],last=inspections[-1],restore=restored,known_network_fatal_absent=True,
        volume_observations=volume_observations,payload_archive_mapping=mapping,engine_text=text)


def portraits_acceptance(review,origin,process,reader):
    cases=review['portraits'];need(set(cases)==CASES,'Bane5/QOP09/wave/hero-builder/eviction-return cases required')
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
    need(cases['qop_commandment_09'].get('unit_name')=='npc_survival_named_ten_sin_09'
         and cases['qop_commandment_09'].get('scene_key')=='monster_boss_ten_sin_09_eminence_ristul',
         'Actual Reverence QOP arcana scene identity required')
    wave=cases['wave_equipped'];hero=cases['hero_builder_switch']
    need(type(wave.get('wave_number')) is int and wave['wave_number']>=7
         and type(wave.get('castle_level')) is int and wave['castle_level']>=4
         and wave.get('native_progression_reviewed') is True,
         'Actual wave7-or-later/castle4 progression screenshots must be reviewed')
    need(hero.get('free_hero_used') is True,'Actual free hero and builder switch required')
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


def peer_resolution_acceptance(review,origin,process,package,reader,local_shots,engine_text):
    proof=review.get('peer_portrait_resolution')
    need(isinstance(proof,dict),'Actual peer900/1000 resolution evidence is mandatory')
    need(proof.get('kind')=='PEER_PLAYER1_NATIVE_PORTRAIT_RESOLUTION_AB_REVIEW'
        and proof.get('package_report_sha256')==review['package_report_sha256']
        and proof.get('content_sha256')==package['content_sha256']
        and proof.get('source_revisions')==package['source_revisions']
        and proof.get('peer_player_slot')==1 and proof.get('peer_kernel_identity_claimed') is False
        and same_process(proof['host_process_generation'],process)
        and proof['host_process_generation'].get('native_created_filetime')==process['native_created_filetime'],
        'Actual candidate-bound peer1 resolution review and same host generation required')
    need(re.search(r'\[WS4-NATIVE-HANDOFF-01\] status=handoff_queued players=2 expected=2(?:\s|$)',engine_text),
        'Actual same-process native two-human handoff log required')
    session,session_path=reader.document(proof['session_review'],origin)
    need(session.get('kind')=='NATIVE_LOCALHOST_TWO_HUMAN_SESSION_REVIEW'
        and session.get('package_report_sha256')==review['package_report_sha256']
        and same_process(session['host_process_generation'],process)
        and session['host_process_generation'].get('native_created_filetime')==process['native_created_filetime']
        and session.get('native_status_human_players')==2 and session.get('local_host_ui_reviewed') is True
        and session.get('same_server_session_reviewed') is True
        and isinstance(session.get('server_session_label'),str) and 3<=len(session['server_session_label'])<=100,
        'Actual native Local Host and two-human status review required')
    session_shots=[screenshot(session[name],process,reader,session_path) for name in ('lobby_capture','status_capture')]
    need(timestamp(session_shots[0]['ended_utc'])<=timestamp(session_shots[1]['started_utc']),
        'Real lobby setup must precede actual same-session native status')
    local=[]
    comparisons=proof['local_comparisons']
    need(set(comparisons)=={'alchemist_rest','high_resolution_boss'},'Two local native comparison portraits required')
    for name,row in comparisons.items():
        need(row.get('root_reviewed') is True and row.get('wearables_complete') is True
            and row.get('background_visible') is True and row.get('no_stale_qwer') is True,
            'Actual local comparison portrait review required')
        shot=screenshot(row['capture'],process,reader,origin)
        need((shot['width'],shot['height'])==(1600,900),'Local900 native comparison required')
        local.append(shot)
    peer=proof['peer_captures']
    need(isinstance(peer,list) and len(peer)==3,'Peer Alchemist900/1000 pair plus QOP-or-Bane1000 required')
    allowed_high={'qop_commandment_09','bane_5'}
    high=[row for row in peer if row.get('case') in allowed_high]
    need(len(high)==1 and comparisons['high_resolution_boss'].get('case')==high[0]['case'],
        'Same local/peer QOP-or-Bane high-resolution comparison required')
    need(comparisons['alchemist_rest'].get('case')=='alchemist_rest','Alchemist Rest local comparison required')
    keys={(row.get('case'),row.get('client_width'),row.get('client_height')) for row in peer}
    need(keys=={('alchemist_rest',1600,900),('alchemist_rest',1600,1000),(high[0]['case'],1600,1000)},
        'Actual peer1 Alchemist Rest A/B and second1000 portrait matrix required')
    local_hashes={shot['png_sha256'] for shot in [*local_shots,*session_shots,*local]}
    paths=[];hashes=[]
    for row in peer:
        need(row.get('origin') in {'USER_PROVIDED_STEAM_F12','USER_PROVIDED_NATIVE_SCREENSHOT'}
            and row.get('provided_by')=='PEER_PLAYER_1' and row.get('player_slot')==1
            and row.get('kernel_metadata_available') is False and 'metadata' not in row
            and row.get('uncropped_full_client') is True and row.get('root_reviewed') is True
            and all(row.get(key) is True for key in ('wearables_complete','background_visible','no_stale_qwer','same_unit_label_reviewed')),
            'Peer images need honest human source and actual complete portrait review, not local capture metadata')
        ref=row['image'];path=reader.file(ref,origin)
        need(path.stat().st_size<=20*1024*1024 and ref['sha256'] not in local_hashes,
            'Root-only screenshot cannot substitute for peer pixels')
        paths.append(path);hashes.append(ref['sha256'])
    need(len(set(hashes))==3,'Three distinct actual peer screenshots required')
    decoded=decode_peer_images(paths)
    for row,size in zip(peer,decoded):
        need((size['width'],size['height'])==(row['client_width'],row['client_height']),
            'Actual decoded peer dimensions differ from claimed900/1000')
    confirm,confirm_path=reader.document(proof['user_confirmation'],origin)
    need(confirm.get('kind')=='USER_PEER1_SAME_SESSION_PORTRAIT_RESOLUTION_CONFIRMATION'
        and confirm.get('source_kind')=='USER_MESSAGE' and confirm.get('peer_player_slot')==1
        and confirm.get('package_report_sha256')==review['package_report_sha256']
        and confirm.get('content_sha256')==package['content_sha256']
        and confirm.get('source_revisions')==package['source_revisions']
        and same_process(confirm['host_process_generation'],process)
        and confirm['host_process_generation'].get('native_created_filetime')==process['native_created_filetime']
        and confirm.get('server_session_label')==session['server_session_label']
        and confirm.get('user_confirmed') is True and confirm.get('same_server_session_confirmed') is True
        and confirm.get('local_host_confirmed') is True and confirm.get('both_resolution_images_from_peer_pc') is True
        and confirm.get('same_alchemist_unit_confirmed') is True
        and confirm.get('image_sha256s')==sorted(hashes)
        and isinstance(confirm.get('confirmation_text'),str) and 5<=len(confirm['confirmation_text'])<=4000
        and timestamp(process['created_utc'])<=timestamp(confirm['observed_utc'])<=timestamp(review['reviewed_utc']),
        'Real user peer900/1000 same-session confirmation with exact image refs required')
    # Main-menu lobby setup can predate custom-package RM use; it is identity-
    # bound setup evidence, not a tested portrait. Every gameplay comparison,
    # native status, old portrait case and ETW still lies inside the RM window.
    return [session_shots[1],*local],dict(peer_player_slot=1,peer_images=3,
        peer_resolutions=[[1600,900],[1600,1000]],same_host_generation_reviewed=True,
        peer_origin_human_attested=True,peer_kernel_identity_verified=False,
        image_dimensions_actually_decoded=True,local_native900_comparisons=2,
        lobby_setup_same_process_verified=True,lobby_setup_not_claimed_as_gameplay_file_use=True,
        peer_image_time_human_attested=True,peer_fps_measured=False)


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


LOGIC_TEST='scripts/vscripts/tests/test_shared_challenge_bosses.lua'
LOGIC_MARKER='SHARED_CHALLENGE_BOSSES_PASS:'
LUA=Path('C:/Program Files/lua/bin/lua5.1.exe')
BANE='monster_boss_rebirth_05_lucid_torment'
QOP='monster_boss_ten_sin_09_eminence_ristul'


def scene_lifecycle_acceptance(text,review):
    # Actual successful native loads support the finite observed matrix. They
    # do not assert that DeleteAsync has completed or GPU residency is <=4.
    ready=list(re.finditer(r'\[SURVIVAL_MONSTER_PORTRAIT\] READY asset=([a-zA-Z0-9_]+) map=([^ ]+) ms=(\d+) components=(\d+)',text))
    bane=[row for row in ready if row[1]==BANE and int(row[4])==4]
    qop=[row for row in ready if row[1]==QOP and int(row[4])==5]
    need(len(bane)>=2 and qop,'Native Bane cold return and five-component QOP READY required')
    visits=review['portraits']['bane_5_after_eviction']['visited_other_scenes']
    required={row['scene_key'] for row in visits}
    need(any(required <= {row[1] for row in ready if a.end()<row.start()<z.start()}
        for a,z in zip(bane,bane[1:])), 'Five other native scene READY entries must precede cold Bane rebuild')
    for key in (BANE,QOP,*required):
        need(re.search(r'\[SURVIVAL_PORTRAIT\] SCENE_SET [^\r\n]*asset='+re.escape(key)+r'(?: |$)',text) is not None,
            'Native selected scene evidence missing: '+key)
    return dict(bane_ready_ms=[int(row[3]) for row in bane],qop_ready_ms=[int(row[3]) for row in qop],
        native_gpu_residency_verified=False,finite_scene_matrix_only=True)


def shared_boss_acceptance(review,origin,process,package,reader):
    proof=review['shared_bosses']
    logic,path=reader.document(proof['logic_test'],origin)
    sources=package['source_revisions']
    need(logic.get('kind')=='SAME_COMMIT_REAL_SHARED_BOSS_SERVICE_SYNTHETIC_ENGINE_TEST'
        and logic.get('source_revisions')==sources and logic.get('package_report_sha256')==review['package_report_sha256']
        and logic.get('exit_code')==0 and logic.get('real_service_and_registry') is True
        and logic.get('native_engine') is False and logic.get('db_or_player_write') is False
        and logic.get('published_dependency_equivalence_claimed') is False,
        'Same-commit real service/registry test receipt required, separate from native gameplay')
    stdout=reader.file(logic['stdout'],path).read_text(encoding='utf8')
    need(stdout.startswith(LOGIC_MARKER) and '296 private mobs' in stdout
        and 'personal drops' in stdout and 'old callbacks and reset' in stdout,'Actual full domain test output required')
    need(logic.get('test_path')==LOGIC_TEST and re.fullmatch('[a-f0-9]{64}',logic.get('test_sha256','')),
        'Exact immutable Lua test source required')
    need(b.sha(b.blob_at(b.ROOT,sources['game'],LOGIC_TEST))==logic['test_sha256'],
        'Lua test must come from candidate game commit')
    need(logic.get('runner_sha256')==b.sha(Path(__file__).read_bytes())
        and logic.get('lua_executable_sha256')==b.sha(LUA.read_bytes()),'Exact reviewed logic-test runner and Lua executable required')
    rows={row['path']:row for row in b.inc.metadata(b.VIEW)[0]['files']}
    modules=logic.get('loaded_modules')
    need(isinstance(modules,dict) and set(b.BOSS_SOURCE_PINS)<=set(modules),'All three genuine boss modules must execute')
    for name,pin in modules.items():
        need(re.fullmatch(r'scripts/vscripts/[A-Za-z0-9_/]+\.lua',name) is not None,
            'Bounded immutable Lua module path required')
        need(b.sha(b.blob_at(b.ROOT,sources['game'],name))==pin,'Test module source differs from same immutable commit')
    need(all(modules[name]==b.BOSS_SOURCE_PINS[name]==rows[name]['sha256'] for name in b.BOSS_SOURCE_PINS),
        'Tested boss modules must be byte-identical to signed production candidate')
    native=proof['native_observation']
    need(native.get('reviewed') is True and native.get('same_server_session_confirmed') is True
        and native.get('shared_body_count')==1 and native.get('respawn_delay_seconds')==1
        and native.get('eligible_personal_progress_preserved') is True
        and native.get('no_unentered_player_reward') is True
        and native.get('slot_key') in {
            'encounter_challenge_11:boss_ten_sin_09:challenge_11_stage_09_spawn',
            'encounter_challenge_05:challenge_05_boss:challenge_05_room'},
        'Native shared-body/respawn/personal-eligibility observation required')
    captures=[screenshot(ref,process,reader,origin) for ref in native['captures']]
    need(len(captures)>=3 and all(timestamp(a['ended_utc'])<=timestamp(z['started_utc']) for a,z in zip(captures,captures[1:])),
        'Native shared-boss before/death/respawn captures required')
    confirm,confirm_path=reader.document(proof['cross_pc_confirmation'],origin)
    need(confirm.get('kind')=='USER_CROSS_PC_SHARED_BOSS_CONFIRMATION'
        and confirm.get('package_report_sha256')==review['package_report_sha256']
        and confirm.get('content_sha256')==package['content_sha256']
        and confirm.get('source_revisions')==sources and confirm.get('user_confirmed') is True
        and isinstance(confirm.get('confirmation_text'),str) and 5<=len(confirm['confirmation_text'])<=4000
        and isinstance(confirm.get('player_slots'),list) and len(set(confirm['player_slots']))>=2
        and all(type(slot) is int and 0<=slot<=3 for slot in confirm['player_slots'])
        and confirm.get('same_server_session_confirmed') is True
        and confirm.get('slot_key')==native.get('slot_key') and isinstance(native.get('slot_key'),str)
        and confirm.get('single_shared_body_observed') is True,
        'Actual second-PC user confirmation is required; local logic tests cannot substitute')
    need(timestamp(process['created_utc'])<=timestamp(confirm['observed_utc'])<=timestamp(review['reviewed_utc']),
        'Cross-PC confirmation must belong to this candidate review window')
    return captures,dict(logic_test_pass=True,native_observed=True,user_cross_pc_confirmed=True,
        real_db_reward_delivery_verified=False,all_challenge_paths_verified=False)


def validate_native_release(request,report,manifest,signed):
    # Authenticate authority locally rather than trusting objects or a caller's
    # READY flag. The public validator separately binds plan/journal lineage.
    expected=request.get('report_sha256')
    actual,actual_manifest,actual_signed=c.validated_package(expected,full=True)
    need(actual==report and actual_manifest==manifest and actual_signed==signed,
        'Passed package objects differ from authenticated candidate')
    need(signed.get('signature_valid') is True and signed.get('release_sequence')==b.SEQUENCE==2026110201,
        'Exact signed seventeen-resource production package required')
    ops.source_binding(report,expected)
    need(request.get('source_revisions')==report['source_revisions'],'Request source cursors differ')
    reader=Evidence();ref=request['native_review']
    review,origin=reader.document(ref,b.ROOT/'output/native_review_origin.json')
    bind_review(review,report,expected)
    need(same_process(request['native_process_generation'],review['process'])
        and request['native_process_generation'].get('native_created_filetime')==review['process'].get('native_created_filetime'),
        'Request native process generation differs')
    native=rehearsal_acceptance(review,origin,report,expected,reader)
    screens=portraits_acceptance(review,origin,native['process'],reader)
    fingerprint=unique_log_fingerprint(review,origin,reader)
    lifecycle=scene_lifecycle_acceptance(native['engine_text'],review)
    stats,etw_screens=frames_acceptance(review['frames'],origin,native['process'],reader)
    boss_screens,boss=shared_boss_acceptance(review,origin,native['process'],report,reader)
    screens+=etw_screens+boss_screens
    resolution_screens,resolution=peer_resolution_acceptance(review,origin,native['process'],report,reader,screens,native['engine_text'])
    screens+=resolution_screens
    need(native['first']<=min(timestamp(shot['started_utc']) for shot in screens)
        and max(timestamp(shot['ended_utc']) for shot in screens)<=native['last'],
        'Native file-use inspections must bracket every tested pixel and ETW')
    baseline,old=b.baseline(full=True,require_current_journal=False)
    ops.p.require_rows(ops.p.INSTALLED,baseline['package_files']);ops.p.full_vpk(ops.p.INSTALLED,old)
    need(timestamp(review['reviewed_utc'])>=timestamp(native['restore']['observed_utc']),
        'Final root review must follow verified original0104 restoration')
    reader.unchanged()
    return dict(ordinary_production_acceptance=True,content_sha256=manifest['content_sha256'],
        mean_fps=stats['mean_fps'],p95_ms=stats['p95_ms'],frame_statistics=stats,
        release_sequence=b.SEQUENCE,source_revisions=report['source_revisions'],
        native_review_sha256=ref['sha256'],process_generation=dict(request['native_process_generation']),
        portraits_finite_cases=sorted(CASES),scene_lifecycle=lifecycle,native_fingerprint=fingerprint,shared_bosses=boss,
        peer_portrait_resolution=resolution,
        original0104_fully_restored=True,native_data_volumes_observed=4,
        native_file_use_policy=POLICY,payload_archive_mapping=native['payload_archive_mapping'],
        native_volume_observations=native['volume_observations'],
        index_open_not_required=True,raw_receipts_modified=False,
        all_gameplay_paths_verified=False,official_download=False,post_upload_arcade_verified=False,
        sdk_initialized=False,updates_submitted=0)


def run_logic_tests(report_sha,label):
    # Explicit offline host-only domain test. Export immutable Lua sources once;
    # only actually loaded module pins are evidence. No Dota/VM/Steam is touched.
    package,manifest,signed=c.validated_package(report_sha,full=False)
    ops.source_binding(package,report_sha);label=ops.p.safe_id(label)
    folder=b.ROOT/'output/portrait_resolution_logic_20261102'/label
    need(not folder.exists(),'Logic-test output must be NEW')
    tree=b.git_export.git_tree(b.ROOT,package['source_revisions']['game'])
    selected={name:row for name,row in tree.items() if name.startswith('scripts/vscripts/') and name.endswith('.lua')}
    need(LOGIC_TEST in selected and sum(row['bytes'] for row in selected.values())<=64*1024*1024,
        'Bounded same-commit Lua source export required')
    need(all(row['kind']=='blob' and row['mode'] in ('100644','100755') for row in selected.values()),
        'Lua test inputs must be regular immutable blobs')
    folder.mkdir(parents=True,exist_ok=False)
    # Explicit one-time O(N+B) export, one Git process and <=1MiB buffer.
    # It is not a timer or client callback; stable admission does not export.
    with b.git_export.GitBatch(b.ROOT) as stream:
        for name,row in selected.items():
            stream.process.stdin.write(row['oid'].encode()+b'\n');stream.process.stdin.flush()
            header=stream.process.stdout.readline(256).split()
            need(len(header)==3 and header[0].decode()==row['oid'] and header[1]==b'blob'
                and int(header[2])==row['bytes'],'Immutable test source batch identity changed')
            target=folder/name;target.parent.mkdir(parents=True,exist_ok=True)
            remaining=row['bytes']
            with target.open('xb') as output:
                while remaining:
                    chunk=stream.process.stdout.read(min(1024*1024,remaining));need(chunk,'Truncated immutable Lua test source')
                    output.write(chunk);remaining-=len(chunk)
            need(stream.process.stdout.read(1)==b'\n','Immutable source batch delimiter missing')
    bootstrap='local loaded={}\nlocal original=require\nfunction require(name)\n  if not package.loaded[name] then loaded[name]=true end\n  return original(name)\nend\ndofile("scripts/vscripts/tests/test_shared_challenge_bosses.lua")\nlocal names={};for name in pairs(loaded) do names[#names+1]=name end;table.sort(names)\nfor _,name in ipairs(names) do print("LOADED_SHARED_BOSS_MODULE:"..name) end\n'
    boot=folder/'run.lua';boot.write_text(bootstrap,encoding='utf8',newline='\n')
    completed=subprocess.run([str(LUA),str(boot)],cwd=folder,capture_output=True,timeout=60)
    stdout=completed.stdout.decode('utf8','strict');stderr=completed.stderr.decode('utf8','replace')
    need(completed.returncode==0 and not stderr and stdout.startswith(LOGIC_MARKER),'Actual Lua domain test failed')
    stdout_path=folder/'stdout.txt';stdout_path.write_bytes(completed.stdout)
    loaded=re.findall(r'^LOADED_SHARED_BOSS_MODULE:([A-Za-z0-9_/]+)$',stdout,re.M)
    modules={'scripts/vscripts/'+name+'.lua':b.sha((folder/('scripts/vscripts/'+name+'.lua')).read_bytes()) for name in loaded}
    need(set(b.BOSS_SOURCE_PINS)<=set(modules),'All three real boss modules must execute')
    receipt=dict(schema=1,kind='SAME_COMMIT_REAL_SHARED_BOSS_SERVICE_SYNTHETIC_ENGINE_TEST',
        source_revisions=package['source_revisions'],package_report_sha256=report_sha,
        runner_sha256=b.sha(Path(__file__).read_bytes()),test_path=LOGIC_TEST,
        test_sha256=b.sha((folder/LOGIC_TEST).read_bytes()),loaded_modules=modules,
        stdout=dict(path=str(stdout_path),sha256=b.sha(completed.stdout)),exit_code=0,
        lua_executable_sha256=b.sha(LUA.read_bytes()),real_service_and_registry=True,
        native_engine=False,db_or_player_write=False,published_dependency_equivalence_claimed=False,
        source_export='SAME_COMMIT_HOST_TEST_INPUTS_NOT_FULL_HEAD_PUBLICATION')
    path=folder/'receipt.json';ops.p.write_new(path,receipt)
    return dict(path=str(path),sha256=b.sha(path.read_bytes()),native_gameplay_verified=False,fps_measured=False)


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logic-test',action='store_true');parser.add_argument('--report-sha256');parser.add_argument('--label')
    args=parser.parse_args(argv)
    if not args.logic_test:
        need(not args.report_sha256 and not args.label,'Static plan takes no action inputs')
        result=dict(status='STATIC_SHARED_BOSS_NATIVE_POLICY_PLAN_NO_EFFECTS',sdk_initialized=False,
            files_written=0,os_queries=0,clients_started=0,ready_for_upload=False,
            required_portrait_cases=sorted(CASES),minimum_mean_fps=90,maximum_p95_ms=16.7,
            shared_boss_native_and_cross_pc_required=True)
    else:
        need(args.report_sha256 and args.label,'Exact signed report and NEW logic label required')
        result=run_logic_tests(args.report_sha256,args.label)
    print(json.dumps(result,ensure_ascii=True));return 0


if __name__=='__main__':raise SystemExit(main())
