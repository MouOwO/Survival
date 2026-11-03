"""Read-only 30s Tools ETW capture; never launches/closes Dota or changes settings.

Only the fixed prepared Dev family and its owned port29069 are admitted. Two
unique PresentMon sessions (v1/v2) run alongside the existing 1Hz focus observer.
This is developer diagnostics, not ordinary signed-client/FPS acceptance.
"""
from __future__ import annotations
import argparse
import concurrent.futures
import csv
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import struct
import sys
import threading
import time
import uuid

ROOT=Path(__file__).resolve().parents[1]
STORE=Path('D:/Survival_本地排演/network50_dev_20261103')
COLLECTOR=ROOT/'output/four_client_perf_20261012/bin/PresentMon-2.6.0-x64.exe'
COLLECTOR_SHA='b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af'
PORT=29069
CREATE_NO_WINDOW=getattr(subprocess,'CREATE_NO_WINDOW',0)

def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/file)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

focus=module('network50_focus','observe_live_perf_focus.py')
v1=module('network50_v1','analyze_presentmon_capture.py')
compiler=module('network50_compiled_blocks','compile_network50_ui.py')

def need(value,reason):
    if not value:raise ValueError(reason)

def sha(path):
    with Path(path).open('rb')as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def save(path,value):
    with Path(path).open('x',encoding='utf-8')as stream:json.dump(value,stream,ensure_ascii=False,indent=2,allow_nan=False);stream.write('\n')

def ps(script):
    shell=shutil.which('pwsh.exe');need(shell,'powershell7_required_for_inherited_module_environment')
    script="$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false);"+script
    done=subprocess.run([shell,'-NoProfile','-NonInteractive','-Command',script],capture_output=True,
                        encoding='utf-8',errors='replace',check=True,timeout=6,creationflags=CREATE_NO_WINDOW)
    return json.loads(done.stdout or 'null')

def collector_identity():
    need(COLLECTOR.is_file()and COLLECTOR.stat().st_size==980320 and sha(COLLECTOR)==COLLECTOR_SHA,'exact_intel_collector_required')
    literal=str(COLLECTOR).replace("'","''")
    result=ps("$s=Get-AuthenticodeSignature -LiteralPath '"+literal+"';[ordered]@{status=[string]$s.Status;signer=$s.SignerCertificate.Subject;thumbprint=$s.SignerCertificate.Thumbprint}|ConvertTo-Json -Compress")
    need(result.get('status')=='Valid'and 'O=Intel Corporation' in result.get('signer',''),'valid_intel_signature_required')
    return dict(result,path=str(COLLECTOR),bytes=980320,sha256=COLLECTOR_SHA)

def command_from_log(path):
    with Path(path).open('rb')as stream:
        stream.seek(max(0,Path(path).stat().st_size-512*1024));text=stream.read().decode('utf-8',errors='replace')
    matches=re.findall(r'\[NETWORK50_UI_DIAGNOSTIC\] ready command=(network50_inspect_[0-9]{10,16}_[0-9]{1,6})\b',text)
    need(matches,'tools_inspect_ready_command_missing')
    return matches[-1]


def critical_resource_binding(base,row,index):
    """Read current Tools output against immutable copied author, not a new manifest.

    Tools can change REDI/RERL/compiler metadata on legitimate on-demand compile.
    Only JS with byte-exact DATA matching its copied CRLF author is admitted;
    map bytes and author bytes must still match the untouched launch manifest.
    """
    relative=row['relative'];path=base/'game'/relative
    actual=path.read_bytes();actual_sha=hashlib.sha256(actual).hexdigest()
    result={'path':relative,'sha256':actual_sha,'prelaunch_sha256':row['sha256'],
            'actual_postcompile_sha256':actual_sha,'tools_recompiled':actual_sha!=row['sha256']}
    if not relative.endswith('.vjs_c'):
        need(actual_sha==row['sha256'],'critical_runtime_drift:'+relative)
        result['binding_kind']='EXACT_PRELAUNCH_BYTES'
        return result
    author_relative=relative[:-6]+'.js'
    source_row=index.get(('content',author_relative))
    need(source_row is not None,'immutable_copied_author_missing:'+relative)
    author=(base/'content'/author_relative).read_bytes()
    author_sha=hashlib.sha256(author).hexdigest()
    need(author_sha==source_row['sha256'],'immutable_copied_author_drift:'+author_relative)
    lf=author.replace(b'\r\n',b'\n')
    need(b'\r'not in lf and lf.replace(b'\n',b'\r\n')==author,'copied_compiler_crlf_author_required:'+author_relative)
    data=compiler.blocks(actual).get(b'DATA')
    offset,count=struct.unpack_from('<II',actual,8);start=8+offset
    need(sum(actual[start+n*12:start+n*12+4]==b'DATA'for n in range(count))==1,'unique_compiled_data_block_required')
    need(data==author,'actual_js_data_differs_from_immutable_author:'+relative)
    result.update(binding_kind='TOOLS_CURRENT_DATA_EQUALS_IMMUTABLE_COPIED_AUTHOR_NOT_SIGNED_ACCEPTANCE',
                  author_relative=author_relative,author_sha256=author_sha,
                  compiled_data_sha256=hashlib.sha256(data).hexdigest(),compiled_data_equals_copied_author=True)
    return result

def bindings(run):
    need(re.fullmatch(r'run[0-9]{2}',run)is not None,'fixed_dev_run_required')
    base=STORE/run
    raw=(base/'process.json').read_bytes();process=json.loads(raw)
    prepared_raw=(base/'prepared.json').read_bytes();prepared=json.loads(prepared_raw)
    manifest_raw=(base/'files.manifest.json').read_bytes();manifest=json.loads(manifest_raw)
    digest=hashlib.sha256(manifest_raw).hexdigest()
    need(digest==prepared['manifest_sha256']==process['snapshot_manifest_sha256'],'dev_manifest_binding_mismatch')
    need(Path(prepared['external_root']).resolve()==base.resolve(),'fixed_external_dev_root_required')
    argv=prepared['suggested_argv'];need(argv.count('-addon')==1 and '-tools'in argv,'tools_addon_source_required')
    alias=argv[argv.index('-addon')+1];need(re.fullmatch(r'svt_network50_dev(?:_[a-z0-9_]+)?',alias)is not None,'owned_dev_alias_required')
    mounts=prepared['mounts'];need(len(mounts)==2,'both_dev_mounts_required')
    for row in mounts:
        mount,target=Path(row['path']),Path(row['target'])
        need(mount.name==alias and mount.is_junction()and mount.resolve()==target.resolve()
             and target.resolve()in{(base/'game').resolve(),(base/'content').resolve()},'dev_mount_identity_drift')
    expected_log=ROOT/'output/network50_dev_20261103'/run/'engine.log'
    need(Path(process['log']).resolve()==expected_log.resolve(),'fixed_engine_log_required')
    pid=process['pid'];need(type(pid)is int and pid>0 and isinstance(process.get('created'),str),'owned_process_generation_required')
    critical=[]
    selected={'panorama/scripts/custom_game/common/network50_diagnostics.vjs_c',
              'panorama/scripts/custom_game/common/compact_ui_runtime.vjs_c',
              'panorama/scripts/custom_game/common/ui_static_catalog.vjs_c','maps/template_map.vpk'}
    index={(row['area'],row['relative']):row for row in manifest['files']}
    need(len(index)==len(manifest['files']),'unique_immutable_manifest_paths_required')
    for row in manifest['files']:
        if row['area']=='game'and row['relative']in selected:
            critical.append(critical_resource_binding(base,row,index))
    need({r['path']for r in critical}==selected,'diagnostic_runtime_closure_missing')
    return dict(run=run,pid=pid,created=process['created'],alias=alias,manifest_sha256=digest,
                process_receipt_sha256=hashlib.sha256(raw).hexdigest(),prepared_sha256=hashlib.sha256(prepared_raw).hexdigest(),
                critical=critical,log=str(expected_log),command=command_from_log(expected_log),exe=str(Path(argv[0]).resolve()))

def live_identity(binding):
    pid=binding['pid']
    data=ps("$p=Get-CimInstance Win32_Process -Filter 'ProcessId="+str(pid)+"';$l=@(Get-NetTCPConnection -State Listen -LocalPort 29069 -ErrorAction SilentlyContinue);[ordered]@{pid=if($p){[int]$p.ProcessId}else{0};created=if($p){$p.CreationDate.ToUniversalTime().ToString('o')}else{''};exe=if($p){$p.ExecutablePath}else{''};command=if($p){$p.CommandLine}else{''};listeners=@($l|ForEach-Object{[ordered]@{pid=[int]$_.OwningProcess;address=$_.LocalAddress}})}|ConvertTo-Json -Compress -Depth 4")
    need(data.get('pid')==pid and data.get('created')==binding['created'],'process_generation_changed')
    need(os.path.normcase(str(Path(data.get('exe','')).resolve()))==os.path.normcase(binding['exe']),'dota_executable_mismatch')
    # Match the exact standalone addon token, never a substring of another lab.
    command=data.get('command','')
    need(re.search(r'(?:^|\s)-tools(?:\s|$)',command)and re.search(r'(?:^|\s)-addon\s+"?'+re.escape(binding['alias'])+r'"?(?:\s|$)',command),'live_tools_alias_mismatch')
    listeners=data.get('listeners',[])
    need(listeners and all(row.get('pid')==pid and row.get('address')in('127.0.0.1','0.0.0.0','::','::1')for row in listeners),'owned_loopback_vconsole_port_required')
    return {'pid':pid,'created':data['created'],'tools':True,'alias':binding['alias'],'port':PORT,'port_owner_pid':pid}

def public_sample(value):
    need(isinstance(value,dict),'inspect_sample_required')
    wave=value.get('wave');wire=value.get('wire')
    result={key:value.get(key)for key in('active','tools','game_time','paused')}
    result['wave']={key:wave.get(key)for key in('status','current','alive','defeated')}if isinstance(wave,dict)else None
    result['wire']={'ready':wire.get('ready'),'views':wire.get('views'),'counters':{}}if isinstance(wire,dict)else None
    if result['wire']is not None:
        counters=wire.get('counters')or{}
        for key in('received','sent','stale','rejected','hello_requests','hello_commits','view_commits','resyncs','controls','intents'):
            number=counters.get(key)
            if type(number)is int and number>=0:result['wire']['counters'][key]=number
    return result

def gameplay_validation(before,after,seconds=30):
    reasons=[]
    allowed={'countdown','spawning','all_waves_spawned','archive_challenges','archive_challenges_pending','fishing','dev_mode','dev_spawn'}
    for label,sample in(('before',before),('after',after)):
        if sample.get('active')is not True or sample.get('tools')is not True:reasons.append(label+'_inactive_or_not_tools')
        if sample.get('paused')is not False:reasons.append(label+'_paused_or_unknown')
        wave=sample.get('wave')or{}
        if wave.get('status')not in allowed or wave.get('defeated')in(True,1):reasons.append(label+'_not_live_gameplay_or_victory_defeat')
        if not sample.get('wire')or sample['wire'].get('ready')is not True:reasons.append(label+'_compact_not_ready')
    a,b=before.get('game_time'),after.get('game_time')
    delta=b-a if type(a)in(int,float)and type(b)in(int,float)and math.isfinite(a)and math.isfinite(b)else None
    if delta is None or not seconds-1.5<=delta<=seconds+3:reasons.append('game_clock_pause_speed_or_coverage_mismatch')
    return {'valid':not reasons,'invalid_reasons':reasons,'game_clock_seconds':delta,
            'limit':'Two endpoint samples and clock progress cannot rule out every transient pause, overlay or scene change; review the bracketing screenshots separately.'}

def v2_statistics(path,pid):
    groups={};foreign=0
    with Path(path).open(encoding='utf-8-sig',newline='')as stream:
        reader=csv.DictReader(stream);need({'ProcessID','SwapChainAddress','CPUStartTime','FrameTime'}<=set(reader.fieldnames or[]),'v2_native_columns_required')
        for row in reader:
            need(None not in row and all(v is not None for v in row.values()),'v2_malformed_row')
            if int(row['ProcessID'])!=pid:foreign+=1;continue
            key=row['SwapChainAddress'];need(key,'v2_swapchain_required')
            start,duration=float(row['CPUStartTime']),float(row['FrameTime'])
            need(math.isfinite(start)and math.isfinite(duration)and start>=0 and duration>=0,'v2_nonfinite_frame')
            group=groups.setdefault(key,{'starts':[],'intervals':[]})
            need(not group['starts']or start>group['starts'][-1],'v2_nonmonotonic_time')
            group['starts'].append(start)
            if len(group['starts'])>1:need(duration>0,'v2_nonpositive_frame');group['intervals'].append(duration)
            need(len(group['starts'])<=200000,'bounded_native_csv_required')
    need(not foreign,'v2_foreign_pid')
    need(len(groups)==1,'v2_single_swapchain_required')
    chain,group=next(iter(groups.items()));values=group['intervals'];need(values,'v2_zero_samples')
    ordered=sorted(values);at=(len(values)-1)*.95;lo=math.floor(at);p95=ordered[lo]+(ordered[min(lo+1,len(values)-1)]-ordered[lo])*(at-lo)
    return {'swapchain':chain,'accepted_frames':len(values),'mean_fps':1000*len(values)/math.fsum(values),'p95_ms':p95,
            'interval_sum_seconds':math.fsum(values)/1000,'cpu_span_seconds':(group['starts'][-1]-group['starts'][0])/1000,'first_row_excluded':True}

class Readback:
    def __init__(self,command):
        self.child=subprocess.Popen(['node',str(ROOT/'tools/network50_perf_vconsole.cjs'),command],cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,encoding='utf-8',creationflags=CREATE_NO_WINDOW)
        self.lines=queue.Queue()
        def pump():
            for line in self.child.stdout:self.lines.put(line)
        threading.Thread(target=pump,daemon=True).start()
        try:need(self.receive(6).get('ready')is True,'persistent_readback_not_ready')
        except Exception:
            self.close();raise
    def receive(self,seconds):
        try:return json.loads(self.lines.get(timeout=seconds))
        except queue.Empty:raise ValueError('bounded_readback_timeout')from None
    def inspect(self):
        nonce=uuid.uuid4().hex
        self.child.stdin.write(json.dumps({'op':'inspect','nonce':nonce})+'\n');self.child.stdin.flush()
        reply=self.receive(4);need(reply.get('nonce')==nonce,'fresh_inspect_nonce_mismatch')
        return {'nonce':nonce,'sample':public_sample(reply.get('sample')),'utc':datetime.now(timezone.utc).isoformat()}
    def close(self):
        if self.child.poll()is None:
            try:self.child.stdin.write('{"op":"close"}\n');self.child.stdin.flush();self.child.wait(timeout=2)
            except (OSError,subprocess.TimeoutExpired):self.child.terminate()

def capture(run,label):
    need(re.fullmatch(r'[a-z0-9_]{1,32}',label)is not None,'safe_capture_label_required')
    collector=collector_identity();binding=bindings(run);identity_before=live_identity(binding)
    preflight=focus.observe(binding['pid'],1,0)
    need(preflight['validation']['valid']and preflight['all_game_foreground'],'game_must_already_be_foreground_no_focus_stealing')
    unique=uuid.uuid4().hex;out=ROOT/'output/network50_perf_20261103'/run/(label+'_'+unique)
    out.mkdir(parents=True,exist_ok=False)
    save(out/'binding.json',binding);save(out/'collector.json',collector);save(out/'focus_preflight.json',preflight)
    readback=None;children=[];report={'kind':'TOOLS_READ_ONLY_ETW_DIAGNOSTIC_NOT_ORDINARY_ACCEPTANCE','valid':False,'seconds':30,'transactions':0,'game_settings_changed':False,'dota_started_or_closed':False,'ordinary_acceptance':False,'output':str(out),'invalid_reasons':[]}
    try:
        readback=Readback(binding['command']);before=readback.inspect();save(out/'inspect_before.json',before)
        need(gameplay_validation(before['sample'],before['sample'],0)['valid'],'before_capture_not_active_unpaused_gameplay')
        started=datetime.now(timezone.utc).isoformat();wall=time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=1)as pool:
            observation=pool.submit(focus.observe,binding['pid'],30,0)
            for version in(1,2):
                argv=[str(COLLECTOR),'--process_id',str(binding['pid']),'--output_file',str(out/f'frames_v{version}.csv'),f'--v{version}_metrics','--timed','30','--terminate_after_timed','--terminate_on_proc_exit','--no_console_stats','--session_name','N50_'+unique+'_v'+str(version)]
                log=(out/f'collector_v{version}.log').open('xb')
                child=subprocess.Popen(argv,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=CREATE_NO_WINDOW);children.append((child,log,argv))
            for child,log,_ in children:
                child.wait(timeout=max(.1,38-(time.perf_counter()-wall)));log.close();need(child.returncode==0,'collector_nonzero_exit')
            observed=observation.result(timeout=2)
        elapsed=time.perf_counter()-wall;save(out/'focus.json',observed)
        after=readback.inspect();save(out/'inspect_after.json',after)
        identity_after=live_identity(binding);need(bindings(run)==binding,'immutable_dev_binding_changed_during_capture')
        first=v1.analyze(out/'frames_v1.csv',binding['pid']);save(out/'statistics_v1.json',first)
        second=v2_statistics(out/'frames_v2.csv',binding['pid']);save(out/'statistics_v2.json',second)
        validation=gameplay_validation(before['sample'],after['sample'])
        reasons=list(validation['invalid_reasons'])
        if not observed['validation']['valid']:reasons.extend(observed['validation']['invalid_reasons'])
        primary=first.get('primary')
        if first['selection']['group_count']!=1 or not primary:reasons.append('v1_single_nonzero_swapchain_required')
        elif primary['accepted_interval_count']<120 or primary['accepted_interval_sum_seconds']<28.5 or primary['timestamp_span_seconds']<28.5:reasons.append('v1_30second_coverage_required')
        if second['accepted_frames']<120 or second['interval_sum_seconds']<28.5 or second['cpu_span_seconds']<28.5:reasons.append('v2_30second_coverage_required')
        if not 29<=elapsed<=38:reasons.append('bounded_capture_wall_duration_mismatch')
        report.update(valid=not reasons,invalid_reasons=sorted(set(reasons)),started_utc=started,wall_seconds=elapsed,
            process_before=identity_before,process_after=identity_after,gameplay=validation,focus=observed['validation'],
            frames_v1_sha256=sha(out/'frames_v1.csv'),frames_v2_sha256=sha(out/'frames_v2.csv'),statistics_v1=primary,statistics_v2=second,
            collector_argv=[argv for _,_,argv in children],engineering_gate=bool(not reasons and second['mean_fps']>=90 and second['p95_ms']<=16.7),
            limits=['1Hz foreground observations do not prove uninterrupted visibility between samples.','Endpoint state/clock probes do not prove every intermediate scene; bracketing screenshots require operator review.','Two simultaneous read-only ETW collectors add measurement overhead; compare captures using the same setup.','Present cadence is not displayed-frame cadence, server tick time or ordinary signed-client acceptance.'])
    except Exception as error:
        report['invalid_reasons'].append(str(error)if isinstance(error,ValueError)else type(error).__name__)
    finally:
        if readback:readback.close()
        for child,log,_ in children:
            if child.poll()is None:child.terminate();child.wait(timeout=3)
            if not log.closed:log.close()
        save(out/'capture.json',report)
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=('plan','capture'));parser.add_argument('--run',default='run05');parser.add_argument('--label',default='gameplay')
    args=parser.parse_args()
    if args.action=='plan':result={'status':'READ_ONLY_CAPTURE_PREPARED_NOT_RUN','collector':collector_identity(),'seconds':30,'versions':[1,2],'port':PORT,'processes_started':0,'transactions':0,'ordinary_acceptance':False}
    else:
        try:result=capture(args.run,args.label)
        except (ValueError,OSError,subprocess.SubprocessError)as error:
            result={'status':'CAPTURE_REFUSED_BEFORE_ETW','valid':False,'invalid_reasons':[str(error)if isinstance(error,ValueError)else type(error).__name__],
                    'transactions':0,'game_settings_changed':False,'dota_started_or_closed':False,'ordinary_acceptance':False}
    print(json.dumps(result,ensure_ascii=False,allow_nan=False))
if __name__=='__main__':main()
