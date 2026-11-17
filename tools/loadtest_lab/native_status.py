"""Bounded signed status observations over a tunnel already owned by the driver.

No SSH/process creation or production writes. load_client owns private client
configuration reading; authenticated request contents and controller never leave
this object's private state. Each probe is one bounded HTTP GET and fixed-map
verification O(1); only final local JSONL analysis is O(number of probes).
Server-ready means marked identities remain valid, not individual heartbeats.
"""
from __future__ import annotations
import datetime,hashlib,http.client,json,math,os,secrets,time
from pathlib import Path

PROJECT = Path()
PHASES=frozenset(('before_locust_start','periodic','pre_planned_stop','after_locust_exit','before_tunnel_close_on_abort'))
INTERVAL_SECONDS=5
MAX_RESPONSE=16*1024
MAX_RECORDS=4000
HTTP_METHODS=frozenset(('GET','POST','HEAD','PUT','PATCH','DELETE','OPTIONS'))

def need(value,code):
    if not value:raise ValueError(code)
def _canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode()
def _utc(value):return datetime.datetime.fromtimestamp(value,datetime.timezone.utc).isoformat()
def _timestamp(value):
    parsed=datetime.datetime.fromisoformat(value.replace('Z','+00:00'));need(parsed.tzinfo is not None,'status_window_timezone_required');return parsed.timestamp()
def _number(value):return type(value)in(int,float) and math.isfinite(value) and value>=0

class SignedStatusReader:
    __slots__=('_cfg','_controller','_manifest','_decode','_stream','_transport','_clock','_monotonic','_requests','_success','_failure','_last','_clock_anchor','_clock_ok')
    def __init__(self,client_path,expected_cfg,output_path,*,transport=None,clock=time.time,monotonic=time.monotonic):
        import sys
        if str(PROJECT)not in sys.path:sys.path.insert(0,str(PROJECT))
        from loadtest_lab.guard import load_client
        from loadtest_lab.status import decode_status
        cfg,controller=load_client(client_path)
        need(_canonical(cfg)==_canonical(expected_cfg),'status_client_manifest_mismatch')
        self._cfg,self._controller=cfg,controller
        self._manifest=hashlib.sha256(_canonical(cfg)).hexdigest();self._decode=decode_status
        self._transport=transport or self._request;self._clock,self._monotonic=clock,monotonic
        self._requests=self._success=self._failure=0;self._last=None;self._clock_anchor=None;self._clock_ok=True
        self._stream=Path(output_path).open('x',encoding='utf8');Path(output_path).chmod(0o600)
    def __repr__(self):return 'SignedStatusReader()'
    @staticmethod
    def _request(path,headers):
        connection=http.client.HTTPConnection('127.0.0.1',29567,timeout=5)
        try:
            connection.request('GET',path,headers=headers)
            response=connection.getresponse();raw=response.read(MAX_RESPONSE+1)
            need(len(raw)<=MAX_RESPONSE,'status_response_budget_exceeded')
            return response.status,raw
        finally:connection.close()
    def observe(self,phase):
        need(phase in PHASES,'status_phase_invalid');need(self._requests<MAX_RECORDS,'status_probe_budget_exceeded')
        self._requests+=1;nonce=secrets.token_hex(16)
        before_wall,before_mono=self._clock(),self._monotonic()
        if self._clock_anchor is None:self._clock_anchor=(before_wall,before_mono)
        row={'kind':'VERIFIED_SYNTHETIC_STATUS_OBSERVATION','index':self._requests,'phase':phase,
             'run_id':self._cfg['run_id'],'manifest_sha256':self._manifest,
             'request_started_utc':_utc(before_wall),'request_started_monotonic':before_mono,'requested_nonce':nonce,
             'http_status':None,'response_body_bytes':0,'proof_valid':False,'proof':None,'error':None}
        try:
            status,raw=self._transport('/_loadtest/status?nonce='+nonce,
                {'Authorization':'Bearer '+self._controller,'Accept':'application/json','Connection':'close'})
            row['http_status']=status if type(status)is int and 100<=status<=599 else None
            need(type(raw)is bytes and len(raw)<=MAX_RESPONSE,'status_response_budget_exceeded')
            row['response_body_bytes']=len(raw);need(status==200,'status_http_non_200')
            self._decode(raw,self._cfg['run_id'],self._manifest,self._controller,nonce,
                         active_budget=self._cfg['active'],account_budget=self._cfg['accounts'])
            row['proof']=json.loads(raw);row['proof_valid']=True;self._success+=1
        except Exception as error:
            import re
            code=str(error) if isinstance(error,ValueError) and re.fullmatch('[a-z0-9_]{1,100}',str(error)) else 'status_transport_or_verification_failed'
            row['error']=code;self._failure+=1
        after_mono,after_wall=self._monotonic(),self._clock()
        anchor_wall,anchor_mono=self._clock_anchor
        self._clock_ok=self._clock_ok and abs((after_wall-before_wall)-(after_mono-before_mono))<=1 and after_mono>=before_mono and abs((after_wall-anchor_wall)-(after_mono-anchor_mono))<=1
        row.update(request_finished_utc=_utc(after_wall),request_finished_monotonic=after_mono,
                   elapsed_ms=round(max(0,after_mono-before_mono)*1000,3),
                   local_clock_consistent=self._clock_ok)
        self._stream.write(json.dumps(row,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n');self._stream.flush()
        self._last=row
        return row
    def close(self):
        if not self._stream.closed:self._stream.flush();os.fsync(self._stream.fileno());self._stream.close()
    def counts(self):return {'requests':self._requests,'verified':self._success,'failed':self._failure,'scope':'extra driver control GETs; excluded from all Locust business/wire counts'}


def final_http_metrics(final,window):
    """One final reconciliation; no assertion events are counted as HTTP."""
    rows=final.get('routes');need(type(rows)is list and len(rows)<=1000,'status_final_route_budget_invalid')
    total=failed=http=http_failed=asserts=assert_failed=other=0
    for row in rows:
        need(type(row)is dict and type(row.get('requests'))is int and type(row.get('failures'))is int
             and 0<=row['failures']<=row['requests'],'status_final_route_counts_invalid')
        n,f=row['requests'],row['failures'];total+=n;failed+=f
        if row.get('method')in HTTP_METHODS:http+=n;http_failed+=f
        elif row.get('method')=='ASSERT':asserts+=n;assert_failed+=f
        else:other+=n
    need(total==final.get('requests') and failed==final.get('failures'),'status_final_event_total_mismatch')
    wire=final.get('business_wire',{});counters=wire.get('counters',{})
    need(wire.get('collection_complete')is True and counters.get('requests')==counters.get('responses')==http,'status_final_wire_http_mismatch')
    start,end=_timestamp(window['start_utc']),_timestamp(window['end_utc']);need(end>start,'status_http_window_invalid')
    return {'window_source':'final Locust HTML reported start_time/end_time','start_utc':window['start_utc'],'end_utc':window['end_utc'],'window_seconds':end-start,
            'http_requests':http,'http_failures':http_failed,'local_assert_events':asserts,'local_assert_failures':assert_failed,'other_non_http_events':other,
            'http_rps_over_reported_window':http/(end-start),'includes_setup_ramp_and_finalization':True,'pure_steady_request_statistics_available':False,
            'extra_driver_status_control_gets_included':False,'wire_collection_complete':True}


def summarize_status(path,cfg,users,window=None,*,client_path):
    """One O(K) local pass, K<=4000. Ready proof is never a player heartbeat.

    For one verified probe with server current duration D and client request
    wall interval [a,b], [b-D,a] is a conservative continuous marked-ready
    interval under equal monotonic clock rates and no local wall-clock change.
    It is intersected with the actual final request-report window. We never
    extend beyond a successful observation or stitch a failed observation.
    """
    path=Path(path);need(path.is_file() and not path.is_symlink() and path.stat().st_size<=16*1024*1024,'status_observation_file_invalid')
    import sys
    if str(PROJECT)not in sys.path:sys.path.insert(0,str(PROJECT))
    from loadtest_lab.guard import load_client
    from loadtest_lab.status import verify_status
    client_cfg,controller=load_client(client_path)
    need(_canonical(client_cfg)==_canonical(cfg),'status_summary_client_binding_mismatch')
    manifest=hashlib.sha256(_canonical(cfg)).hexdigest()
    requests=verified=failed=phases_pre=phases_after=clock_invalid=0;last_index=0;peak_ready=0;best_seconds=0.;best=None;max_server_current=0.;max_rtt=0.;phase_counts={name:0 for name in sorted(PHASES)};run_remaining_before=None
    start=end=None
    if window is not None:start,end=_timestamp(window['start_utc']),_timestamp(window['end_utc']);need(end>start,'status_summary_window_invalid')
    for line in path.open(encoding='utf8'):
        need(len(line.encode('utf8'))<=32768 and requests<MAX_RECORDS,'status_observation_budget_exceeded')
        row=json.loads(line);requests+=1
        need(row.get('kind')=='VERIFIED_SYNTHETIC_STATUS_OBSERVATION' and row.get('index')==last_index+1
             and row.get('run_id')==cfg['run_id'] and row.get('manifest_sha256')==manifest and row.get('phase')in PHASES,'status_observation_binding_invalid')
        last_index=row['index'];phase_counts[row['phase']]+=1
        clock_invalid+=int(row.get('local_clock_consistent')is not True)
        if not row.get('proof_valid'):failed+=1;continue
        proof=row.get('proof');need(type(proof)is dict and proof.get('run_id')==cfg['run_id'] and proof.get('manifest_sha256')==manifest,'status_derived_proof_binding_invalid')
        stats=verify_status(proof,cfg['run_id'],manifest,controller,row.get('requested_nonce'),active_budget=cfg['active'],account_budget=cfg['accounts'])
        verified+=1;peak_ready=max(peak_ready,stats['effective_ready'])
        max_rtt=max(max_rtt,row['elapsed_ms']);max_server_current=max(max_server_current,stats['target_ready_current_seconds'])
        if row['phase']=='before_locust_start':run_remaining_before=stats['business_remaining_seconds']
        if row['phase']=='pre_planned_stop':phases_pre+=1
        if row['phase']=='after_locust_exit':phases_after+=1
        target=(users==cfg['active'] and stats['ready_valid']is True and stats['effective_ready']==users
                and stats['target_ready_since_seconds']is not None and row.get('local_clock_consistent')is True)
        if target and start is not None:
            a,b=_timestamp(row['request_started_utc']),_timestamp(row['request_finished_utc'])
            left=max(start,b-stats['target_ready_current_seconds']);right=min(end,a)
            seconds=max(0,right-left)
            if seconds>best_seconds:
                best_seconds=seconds;best={'probe_index':row['index'],'phase':row['phase'],'lower_bound_start_utc':_utc(left),'lower_bound_end_utc':_utc(right),'server_target_ready_since_seconds':stats['target_ready_since_seconds'],'server_current_ready_seconds_at_probe':stats['target_ready_current_seconds']}
    return {'kind':'SIGNED_STATUS_DRIVER_OBSERVATION_SUMMARY','run_id':cfg['run_id'],'manifest_sha256':manifest,'source':str(path),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'requests':requests,'verified':verified,'failed':failed,'phase_counts':phase_counts,'pre_planned_stop_verified':phases_pre>0,'after_locust_exit_verified':phases_after>0,
            'collection_complete':requests>0 and failed==0 and clock_invalid==0 and phases_pre>0 and phases_after>0,'local_clock_invalid_probes':clock_invalid,'observed_business_remaining_before_locust_seconds':run_remaining_before,
            'max_effective_marked_ready':peak_ready,'max_server_continuous_marked_ready_seconds_at_probe':max_server_current,'target_equals_configured_active_budget':users==cfg['active'],
            'stage_marked_ready_overlap_lower_bound_seconds':best_seconds if window is not None else None,'best_overlap_proof':best,'max_status_rtt_ms':max_rtt,
            'observation_interval_seconds':INTERVAL_SECONDS,'fresh_nonce_and_signature_verified_on_receipt':True,'signatures_reverified_during_final_summary':True,'extra_status_requests_counted_separately_from_locust':True,
            'ready_scope':'valid server-marked synthetic identities; no per-player heartbeat or proof of per-user business progress',
            'overlap_clock_assumption':'equal server/client monotonic rates; client wall/monotonic consistency checked across all probes; subtract full request RTT and clip to final HTML window',
            'failed_observations_are_not_extended_or_stitched':True,'capacity_certified':False}
