"""Run an immutable exported business workload natively on an isolated Linux host.

Two O(S) public source passes; steady monitoring reads only the known child PID
and one bounded signed status request per5s, O(1) with respect to actors.
The existing workload maintains its own indexed O(log N) activity deadlines.
Loopback mode includes generator resources in host;peer mode measures them separately.
Peer mode has one pinned,restricted,owned Linux SSH forward;no production endpoint.
"""
from __future__ import annotations
import argparse,hashlib,json,os,re,signal,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
import psutil
import native_stage_proof as proof
from native_status import SignedStatusReader,final_http_metrics,summarize_status

ROOT=Path('/srv/survival-loadtest')
TOOL_NAMES=('native_stage.py','native_stage_proof.py','native_status.py')
STOP_SECONDS=45

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save(path,value):
    with Path(path).open('x',encoding='utf-8')as f:json.dump(value,f,indent=2)
    Path(path).chmod(0o600)
def code(exc):
    v=str(exc)
    return v if isinstance(exc,ValueError)and re.fullmatch('[a-z0-9_]{1,100}',v)else type(exc).__name__
def owned_sample(proc,handle,created,started,final=False,forward=None,decoder=None):
    row={'elapsed_seconds':round(time.monotonic()-started,3),'processes':[],'worker_discovery_status':'ACTUAL_WORKER_IDENTIFIED','actual_locust_worker_observed':False,'generator_measurement_status':'ACTUAL_WORKER_NOT_OBSERVED'}
    alive=proc.poll()is None
    value={'role':'locust_worker','pid':proc.pid,'running':alive}
    if alive:
        proof.need(handle.create_time()==created,'owned_child_identity_changed')
        value.update(cpu_percent_one_core_scale=handle.cpu_percent(None),rss_bytes=handle.memory_info().rss)
        row.update(actual_locust_worker_observed=True,generator_measurement_status='ACTUAL_WORKER_OBSERVED')
    row['processes']=[value]
    if forward is not None:row['processes'].append(forward.sample())
    if decoder is not None:row['processes'].extend(decoder.sample())
    if final:row['final']=True
    return row

def run(spec_path,spec_sha):
    proof.need(os.name=='posix'and Path('/proc').is_dir(),'linux_native_operator_required')
    spec_path=Path(spec_path).resolve();proof.need(spec_path.is_relative_to(ROOT)and sha(spec_path)==spec_sha,'native_spec_digest_invalid')
    spec=proof.read_public_json(spec_path);proof.need(type(spec.get('run_id'))is str and re.fullmatch('[a-f0-9]{32}',spec['run_id']),'native_run_id_invalid');lab=ROOT/spec['run_id'];proof.need(lab.resolve()==lab and lab.is_dir(),'native_lab_path_invalid')
    proof.configure(lab)
    from loadtest_lab.guard import load_client,canonical,verify_attestation
    cfg,controller=load_client(lab/'client.json');proof.need(cfg==proof.read_public_json(lab/'lab.json'),'client_manifest_changed')
    manifest=hashlib.sha256(canonical(cfg)).hexdigest()
    proof.need(manifest==spec['manifest_sha256']and cfg['csv_source_revision']==spec['source_commit'],'native_manifest_binding_invalid')
    proof.need(cfg.get('generator_transport')=={'id':'linux-loopback-v1','loopback_ports':[29567]},'native_loopback_profile_required')
    proof.need(cfg.get('actor_progress')=={'id':'active-business-v1','ttl_seconds':120}and cfg['active']==spec['users'],'native_full_business_target_required')
    peer=spec.get('execution_mode')=='linux-peer-ssh-v1'
    names=TOOL_NAMES+('peer_forward.py',)if peer else TOOL_NAMES
    decode=spec.get('client_decode_processes')==2
    if decode:names+=('decode_service.py',)
    proof.need(spec.get('execution_mode','linux-loopback-v1')in('linux-loopback-v1','linux-peer-ssh-v1'),'native_execution_mode_invalid')
    proof.need(set(spec['tools'])==set(names)and all(sha(spec_path.parent/name)==expected for name,expected in spec['tools'].items()),'native_tool_binding_changed')
    for port in (15432,18765,18767,18769):
        import socket
        with socket.socket()as sock:
            sock.settimeout(.15);proof.need(sock.connect_ex(('127.0.0.1',port))!=0,'production_service_on_native_host')
    duration=spec['duration'];required=spec['required_seconds'];spawn=spec['spawn_rate']
    proof.need(type(duration)is int and 60<=duration<=17910 and cfg['duration_seconds']>=duration+90,'native_lifetime_budget_invalid')
    proof.need(type(required)is int and required in(60,300,3600,14400)and duration>required+cfg['active']/spawn,'native_activity_budget_invalid')
    source_proof=proof.validate_prepared_sources(lab,cfg,spec['source_commit'],spec['git_consumer_lf_sha256'])
    stage=spec_path.parent/spec['stage_name'];proof.need(re.fullmatch(r'stage_[a-z0-9_]{8,100}',stage.name)and not stage.exists(),'fresh_native_stage_required');stage.mkdir(mode=0o700)
    python=Path(spec['locust_python']);proof.need(python==ROOT/'native_generator_20261117_01/venv/bin/python'and python.is_file(),'native_generator_interpreter_invalid')
    from importlib.metadata import version
    proof.need(version('locust')=='2.47.0'and version('gevent')=='26.9.0','native_dependency_version_mismatch')
    decoder=None;forward=None;reader=None;proc=handle=None;created=None;error=None;locust_code=None;final=html=None;checks={};status=activity=http=None;started=time.monotonic()
    discovery={'status':'LOCUST_NOT_STARTED','worker_pid':None,'snapshot_calls':0,'stable_snapshot_calls':0,'indexed_processes':[]}
    try:
        if peer:
            from peer_forward import PeerForward
            forward=PeerForward(spec_path,spec_sha,stage);forward.start()
        if decode:
            from decode_service import Decoder
            decoder=Decoder(spec_path,spec_sha,stage);decoder.start()
        reader=SignedStatusReader(lab/'client.json',cfg,stage/'signed_status_samples.jsonl')
        initial=reader.observe('before_locust_start');proof.need(initial['proof_valid']is True,'signed_status_initial_probe_failed')
        proof.need(initial['proof']['stats']['business_remaining_seconds']>=duration+90,'native_api_remaining_lifetime_insufficient')
        env=dict(os.environ);env.update(LOADTEST_CLIENT=str(lab/'client.json'),LOADTEST_REPORT_DIRECTORY=str(stage),PYTHONPATH=os.pathsep.join([str(lab/'operator'),str(lab/'runtime')]),PYTHONDONTWRITEBYTECODE='1',HTTP_PROXY='',HTTPS_PROXY='',ALL_PROXY='',NO_PROXY='127.0.0.1,localhost');env.pop('LOCUST_SKIP_MONKEY_PATCH',None)
        if decoder is not None:env.update(LOADTEST_DECODE_SOCKET=decoder.path,PYTHONPATH=env['PYTHONPATH']+os.pathsep+str(spec_path.parent))
        argv=[str(python),'-X','utf8','-B','-m','locust','-f',str(lab/'operator/loadtest_lab/locustfile.py'),'--headless','--host','http://127.0.0.1:29567','--users',str(cfg['active']),'--spawn-rate',str(spawn),'--run-time',str(duration)+'s','--stop-timeout',str(STOP_SECONDS),'--only-summary','--loglevel','INFO','--csv',str(stage/'locust'),'--html',str(stage/'locust.html')]
        with(stage/'locust_stdout.log').open('xb')as out:
            proc=subprocess.Popen(argv,cwd=lab,env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
        handle=psutil.Process(proc.pid);created=handle.create_time();proof.need(handle.cmdline()==argv,'native_child_command_mismatch');handle.cpu_percent(None)
        discovery.update(status='ACTUAL_WORKER_IDENTIFIED',launcher_pid=proc.pid,worker_pid=proc.pid,indexed_processes=[{'pid':proc.pid,'create_time':created,'depth':0}],indexed_process_count=1,launcher_and_worker_same_native_process=True)
        with(stage/'process_samples.jsonl').open('x',encoding='utf-8')as samples:
            samples.write(json.dumps(owned_sample(proc,handle,created,started,forward=forward,decoder=decoder))+chr(10));samples.flush()
            planned=time.monotonic()+duration;deadline=planned+STOP_SECONDS+45;next_sample=next_status=time.monotonic()+5;pre=False
            while proc.poll()is None:
                now=time.monotonic();proof.need(now<deadline,'native_stage_exceeded_deadline')
                if forward is not None:forward.require_alive()
                if decoder is not None:decoder.require_alive()
                if not pre and(now>=planned-5 or now>=next_status and proof.exit_probe_pre_stop_due(stage,cfg)):
                    reader.observe('pre_planned_stop');pre=True;next_status=time.monotonic()+5
                elif now>=next_status:
                    reader.observe('periodic');next_status=time.monotonic()+5
                if time.monotonic()>=next_sample:
                    samples.write(json.dumps(owned_sample(proc,handle,created,started,forward=forward,decoder=decoder))+chr(10));samples.flush();next_sample=time.monotonic()+5
                time.sleep(.2)
            locust_code=proc.returncode
    except BaseException as exc:error=code(exc)
    finally:
        if proc is not None and proc.poll()is None:
            try:
                proof.need(handle.create_time()==created,'owned_child_identity_changed');proc.send_signal(signal.SIGTERM);proc.wait(timeout=STOP_SECONDS+5)
            except Exception:
                error=error or'native_child_graceful_stop_failed'
                if proc.poll()is None:
                    proc.terminate()
                    try:proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=10)
        if proc is not None and handle is not None:
            with(stage/'process_samples.jsonl').open('a',encoding='utf-8')as samples:samples.write(json.dumps(owned_sample(proc,handle,created,started,final=True,forward=forward,decoder=decoder))+chr(10))
        if reader is not None:
            try:reader.observe('after_locust_exit')
            except Exception as exc:error=error or code(exc)
            finally:reader.close()
        if decoder is not None:
            try:decoder.close()
            except Exception as exc:error=error or code(exc)
        if forward is not None:
            try:forward.close()
            except Exception as exc:error=error or code(exc)
    try:
        files=list(stage.glob('locust_final_*_receipt.json'));proof.need(len(files)==1,'one_native_final_required');final=proof.read_public_json(files[0]);proof.need(final['run_id']==cfg['run_id']and final['manifest_sha256']==manifest and not final['reset_stats_requested'],'native_final_binding_invalid')
        html=proof.parse_final_html(stage/'locust.html');checks={'final_html_requests_match':html['requests']==final['requests'],'final_html_failures_match':html['failures']==final['failures'],'wire_collection_complete':final['business_wire']['collection_complete']is True};checks.update(proof.complete_final_counts(final,html,cfg,cfg['active']));proof.need(all(checks.values()),'final_statistics_mismatch')
    except Exception as exc:error=error or code(exc)
    if reader is not None:
        try:
            status=summarize_status(stage/'signed_status_samples.jsonl',cfg,cfg['active'],None if html is None else html['statistics_window'],client_path=lab/'client.json')
            proof.need(status['collection_complete'],'signed_status_collection_incomplete')
            if final is not None and html is not None:http=final_http_metrics(final,html['statistics_window'])
            proof.need(status['max_effective_marked_ready']==cfg['active'],'native_full_ready_not_observed')
        except Exception as exc:error=error or code(exc)
    try:
        proof.need(final is not None and html is not None and status is not None and discovery['worker_pid']is not None,'native_activity_evidence_missing')
        activity=proof.verify_actor_progress(stage,lab,cfg,final,discovery['worker_pid'],status,html['statistics_window']);checks['actor_progress_common_interval_sufficient']=activity['shared_activity']['common_seconds']>=required;proof.need(checks['actor_progress_common_interval_sufficient'],'actor_progress_common_interval_insufficient')
    except Exception as exc:error=error or code(exc)
    try:
        proof.need(proof.validate_prepared_sources(lab,cfg,spec['source_commit'],spec['git_consumer_lf_sha256'])==source_proof,'native_sources_changed_during_stage');proof.need(all(sha(spec_path.parent/name)==expected for name,expected in spec['tools'].items())and sha(spec_path)==spec_sha,'native_control_changed_during_stage')
    except Exception as exc:error=error or code(exc)
    if decode:
        try:
            off=final['client_decode_offload'];proof.need(off['calls']==off['worker_used']==final['business_wire']['counters']['responses']and off['fallback']==off['remote_errors']==off['HTTP_replays']==0,'native_decode_result_counts_invalid')
            end=decoder.terminal;proof.need(end['stats']['requests']==end['stats']['completed']==off['calls']and end['stats']['errors']==0 and end['lifecycle']['manager_joined']is True and all(x['exited']for x in end['lifecycle']['worker_exit_confirmed']),'native_decode_service_closure_invalid')
        except Exception as exc:error=error or code(exc)
    success=error is None and locust_code==0 and final is not None and final.get('failures')==0 and final.get('requests',0)>0
    r={'kind':'ISOLATED_CAPACITY_LINUX_PEER_NATIVE_STAGE_V1_RECEIPT'if peer else'ISOLATED_CAPACITY_LINUX_NATIVE_STAGE_V1_RECEIPT','artifact_root':str(stage),'source_root':str(lab),'status':'DIAGNOSTIC_STAGE_FINISHED'if success else'DIAGNOSTIC_STAGE_NOT_CONFIRMED','error':error,'run_id':cfg['run_id'],'operator_commit':spec['source_commit'],'source_sha256s':spec['source_sha256s'],'prepared_source_binding':source_proof,'source_origin':'controller Git-verified export plus native physical before/after source verification;no native Git checkout claimed','driver_source_sha256s':{str(spec_path.parent/n):h for n,h in spec['tools'].items()},'native_spec_sha256':spec_sha,'signed_status_summary':status,'actor_progress':activity,'required_active_seconds':required,'extra_status_control_counts':None if reader is None else reader.counts(),'http_request_statistics_window':http,'requested_users':cfg['active'],'requested_duration_seconds':duration,'spawn_rate':spawn,'api_declared_duration_seconds':cfg['duration_seconds'],'locust_exit_code':locust_code,'final_statistics':html,'final_count_checks':checks,'periodic_csv_requests':proof.periodic_csv_count(stage/'locust_stats.csv'),'periodic_csv_is_final':False,'final_locust_receipt_requests':None if final is None else final['requests'],'business_wire':None if final is None else final['business_wire'],'owned_process_discovery':discovery,'actual_generator_measurements_available':discovery['status']=='ACTUAL_WORKER_IDENTIFIED','monitor_interval_seconds':5,'generator_colocated_with_backend':not peer,'generator_CPU_and_memory_in_host_aggregates':not peer,'data_ssh_processes':int(peer),'peer_forward':None if forward is None else forward.receipt(),'client_decode_offload':None if final is None else final.get('client_decode_offload'),'decoder_processes':None if decoder is None else decoder.receipt(),'generator_host':'47.116.11.179'if peer else'47.111.16.128','backend_host':'47.111.16.128','scope':'Linux peer SSH loopback business capacity;generator and forwarding client measured separately from backend host;public Nginx/TLS,real Steam/payment excluded'if peer else'Linux loopback server business capacity;generator resource cost included;public Nginx/TLS/WAN,real Steam/payment excluded','capacity_certified':False,'owned_processes_remaining':([]if proc is None or proc.poll()is not None else['locust_worker'])+([]if forward is None or forward.closed()else['data_ssh_tunnel'])+([]if decoder is None or decoder.closed()else['decode_service'])}
    save(stage/'stage_receipt.json',r)
    print(json.dumps({'status':r['status'],'stage_directory':str(stage),'error':error,'locust_exit_code':locust_code,'common_seconds':None if activity is None else activity['shared_activity']['common_seconds']}),flush=True)
    return 0 if success else 2

def main():
    p=argparse.ArgumentParser();p.add_argument('--spec',required=True);p.add_argument('--spec-sha256',required=True);a=p.parse_args()
    try:return run(a.spec,a.spec_sha256)
    except Exception as exc:print(json.dumps({'status':'NATIVE_STAGE_NOT_STARTED','error':code(exc)}),flush=True);return 2
if __name__=='__main__':raise SystemExit(main())
