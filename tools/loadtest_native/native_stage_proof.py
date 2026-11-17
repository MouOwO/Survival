"""Source-bound completed-count and signed-activity proof for native stages.
Derived from the reviewed v16 proof; original SLA/SQL decisions stay separate.
No per-request instrumentation. Final verification is two bounded O(S) source
passes and O(K) signed observations, K<=4000, never a periodic player scan.
"""
from __future__ import annotations
import csv,hashlib,json,math,re,sys
from pathlib import Path
from datetime import datetime,timezone
from native_status import SignedStatusReader,final_http_metrics,summarize_status
PROJECT=Path()

def configure(lab):
    global PROJECT
    PROJECT=Path(lab)/'operator'
    for path in (PROJECT,Path(lab)/'runtime'):
        if str(path) not in sys.path:sys.path.insert(0,str(path))
    import native_status
    native_status.PROJECT=PROJECT

def need(value,code):
    if not value:raise ValueError(code)

def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()

def read_public_json(path):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size<=8*1024*1024,'public_configuration_invalid')
    value=json.loads(path.read_bytes())
    need(type(value)is dict,'public_configuration_invalid')
    return value

_OPERATOR_NAMES = ('__init__', 'business_experiments', 'checkpoint_experiments', 'cli', 'database_experiments',
    'experiments', 'frontend_experiments', 'guard', 'identity', 'leaderboard_experiments', 'lottery_cache_experiments', 'locustfile', 'monitor',
    'principal_experiments', 'profile_context_experiments', 'process_runtime', 'progress', 'runtime', 'smoke', 'snapshot', 'status',
    'wire_client', 'workload', 'workload_profiles')

SOURCE_BINDINGS = tuple(('tools/loadtest_lab/'+name+'.py',
                        'operator/loadtest_lab/'+name+'.py') for name in _OPERATOR_NAMES) + (
    ('server/player_web_auth/business_wire.py', 'runtime/player_web_auth/business_wire.py'),
    ('server/player_web_auth/business_wire_schema.json', 'runtime/player_web_auth/business_wire_schema.json'),
)

def source_lf(raw):
    need(type(raw)is bytes,'source_bytes_required')
    result=raw.replace(b'\r\n',b'\n')
    need(b'\r'not in result,'source_line_endings_invalid')
    return result

def bindings_for(cfg):
    result = SOURCE_BINDINGS + ((('tools/loadtest_lab/mature_fixture.py',
                                'operator/loadtest_lab/mature_fixture.py'),)
                              if 'mature_fixture' in cfg else ())
    if 'checkpoint_lifecycle' in cfg:
        result += (('server/fishing_api_overrides/checkpoint_lifecycle.sql','database/20_checkpoint_lifecycle.sql'),)
    if type(cfg.get('profile_context')) is dict and cfg['profile_context'].get('id') == 'idle-v1':
        result += (('server/fishing_api_overrides/profile_context_patch.py','operator/principal_experiments/profile_context_patch.py'),
                   ('server/fishing_api_overrides/profile_context.sql','operator/principal_experiments/profile_context.sql'),
                   ('server/fishing_api_overrides/profile_context.sql','database/21_profile_context.sql'))
    if cfg.get('frontend_experiment',{}).get('id')=='hot-wal-reserved-v1':
        need(cfg['sources'].get('operator/frontend_experiments/sqlite_reserved_rate_patch.py')=='a40ea4760631f0b5cb911cbb2f574e6f488f4f092a5db97c281ca8464c4b234c','reserved_operator_binding_required')
        result += (('server/player_web_auth_overrides/sqlite_reserved_rate_patch.py','operator/frontend_experiments/sqlite_reserved_rate_patch.py'),('server/player_web_auth/rate_reservations.py','runtime/player_web_auth/rate_reservations.py'))
    if 'runtime/player_web_auth/response_pool.py' in cfg.get('sources',{}):
        result += (('server/player_web_auth/response_pool.py','runtime/player_web_auth/response_pool.py'),)
    if 'operator/loadtest_lab/rpc_process_pool.py'in cfg.get('sources',{}):
        result += (('tools/loadtest_lab/rpc_process_pool.py','operator/loadtest_lab/rpc_process_pool.py'),)
    if 'lottery_static_cache'in cfg:
        result += (('server/fishing_api_overrides/lottery_revision_cache.py','operator/runtime_experiments/lottery_revision_cache.py'),)
    return result

def validate_all_prepared_sources(lab,cfg):
    """Two O(S) bounded local passes per stage, never part of 5s sampling.

    The explicitly declared approved consumers do not replace proof of every actual exported
    public runtime/operator/config/schema source in this manifest. Private
    client/controller, role passwords, compose/env and pgdata are excluded.
    """
    lab=Path(lab).resolve();sources=cfg.get('sources')
    need(type(sources)is dict and 1<=len(sources)<=300,'prepared_source_budget_invalid')
    need(cfg.get('run_id')and type(cfg.get('run_id'))is str and re.fullmatch('[a-f0-9]{32}',cfg['run_id']),'prepared_source_run_invalid')
    config_path=lab/'lab.json';disk=read_public_json(config_path)
    need(canonical(disk)==canonical(cfg),'prepared_manifest_changed')
    records=[];total=0
    for name,expected in sources.items():
        need(type(name)is str and '\\'not in name and ':'not in name and all(part not in('','.','..')for part in name.split('/')),'prepared_source_relative_path_invalid')
        need(name=='run_lab.py'or name=='database/10_schema.sql'or name=='database/20_checkpoint_lifecycle.sql' and cfg.get('checkpoint_lifecycle',{}).get('id')=='lifecycle-v1'or name=='database/21_profile_context.sql' and type(cfg.get('profile_context'))is dict and cfg['profile_context'].get('id')=='idle-v1'or name.startswith(('runtime/','operator/','addon/')),'prepared_source_public_path_required')
        need(type(expected)is str and re.fullmatch('[a-f0-9]{64}',expected),'prepared_source_digest_invalid')
        path=lab/name
        need(path.resolve().is_relative_to(lab)and path.is_file()and not path.is_symlink()and path.stat().st_size<=8*1024*1024,'prepared_source_file_invalid')
        raw=path.read_bytes();total+=len(raw)
        need(len(raw)<=8*1024*1024 and total<=64*1024*1024,'prepared_source_bytes_budget')
        actual=hashlib.sha256(raw).hexdigest();need(actual==expected,'prepared_source_physical_changed')
        records.append({'prepared_target':name,'manifest_sha256':expected,'actual_raw_sha256':actual,'bytes':len(raw)})
    return {'kind':'ALL_DECLARED_PUBLIC_PREPARED_SOURCES_REVERIFIED','run_id':cfg['run_id'],
            'manifest_canonical_sha256':hashlib.sha256(canonical(cfg)).hexdigest(),
            'lab_json_raw_sha256':hashlib.sha256(config_path.read_bytes()).hexdigest(),
            'source_count':len(records),'total_bytes':total,'records':records,
            'private_files_read':False,'scope':'all declared public files, not undeclared pgdata/env/client/roles or a whole repository'}

def validate_prepared_sources(lab,cfg,head,git_lf):
    # HEAD-clean alone is insufficient: every actual consumer must also match
    # the same frozen source bytes exported into this specific lab manifest.
    need(type(head)is str and re.fullmatch('[a-f0-9]{40}',head),'operator_commit_invalid')
    need(type(git_lf)is dict and set(git_lf)=={name for name,_ in bindings_for(cfg)},'prepared_consumer_source_set_invalid')
    need(type(cfg.get('sources'))is dict,'prepared_consumer_manifest_sources_invalid')
    revision=cfg.get('csv_source_revision')
    need(type(revision)is str and re.fullmatch('[a-f0-9]{40}',revision),'prepared_consumer_revision_invalid')
    lab=Path(lab).resolve();rows=[]
    full_export=validate_all_prepared_sources(lab,cfg)
    for name,target in bindings_for(cfg):
        expected=cfg['sources'].get(target);actual=git_lf[name]
        need(type(expected)is str and re.fullmatch('[a-f0-9]{64}',expected)
             and type(actual)is str and re.fullmatch('[a-f0-9]{64}',actual),'prepared_consumer_digest_invalid')
        need(actual==expected,'prepared_consumer_git_manifest_mismatch')
        path=lab/target
        need(path.resolve().is_relative_to(lab) and path.is_file() and not path.is_symlink()
             and path.stat().st_size<=8*1024*1024,'prepared_consumer_export_invalid')
        raw=path.read_bytes();export_sha=hashlib.sha256(raw).hexdigest()
        need(export_sha==expected and hashlib.sha256(source_lf(raw)).hexdigest()==actual,
             'prepared_consumer_export_changed')
        rows.append({'source':name,'prepared_target':target,'git_blob_lf_sha256':actual,
                     'manifest_sha256':expected,'prepared_export_raw_sha256':export_sha})
    return {'kind':'ACTUAL_CONSUMERS_MATCH_PREPARED_LAB_SOURCES','operator_commit':head,
            'prepared_source_revision':revision,'source_count':len(rows),
            'normalization':'CRLF_to_LF_only; bare_CR_refused',
            'all_git_lf_match_manifest_and_export':True,'sources':rows,'full_export':full_export,
            'scope':'approved main consumer links (a source may feed multiple targets) and all declared public exports; no private-file or whole-repository equivalence claim'}

def parse_final_html(path):
    need(path.is_file() and path.stat().st_size<=64*1024*1024,'final_html_missing_or_oversize')
    text=path.read_text(encoding='utf-8')
    matches=list(re.finditer(r'window\.templateArgs\s*=\s*',text))
    need(bool(matches),'final_html_statistics_missing')
    value,_=json.JSONDecoder().raw_decode(text[matches[-1].end():].lstrip())
    rows=value.get('requests_statistics',[])
    totals=[row for row in rows if type(row)is dict and row.get('name')=='Aggregated' and not row.get('method')]
    need(len(totals)==1,'final_html_aggregate_ambiguous')
    total=totals[0]
    need(type(total.get('num_requests'))is int and type(total.get('num_failures'))is int,'final_html_counts_invalid')
    p95=total.get('response_time_percentile_0.95')
    if not isinstance(p95,(int,float)) or isinstance(p95,bool):
        candidates=[row for row in value.get('response_time_statistics',[])if row.get('name')=='Aggregated' and not row.get('method')]
        p95=candidates[0].get('0.95')if len(candidates)==1 else None
    if type(p95)not in(int,float) or not math.isfinite(p95):p95=None
    start,end=value.get('start_time'),value.get('end_time')
    need(type(start)is str and type(end)is str,'final_html_actual_window_missing')
    begin,finish=datetime.fromisoformat(start.replace('Z','+00:00')),datetime.fromisoformat(end.replace('Z','+00:00'))
    need(begin.tzinfo is not None and finish.tzinfo is not None and finish>begin,'final_html_actual_window_invalid')
    return {'requests':total['num_requests'],'failures':total['num_failures'],'p95_ms':p95,'p95_status':'available'if p95 is not None else'missing','p50_ms':total.get('median_response_time'),'mean_ms':total.get('avg_response_time'),'max_ms':total.get('max_response_time'),'average_rps':total.get('total_rps'),'duration':value.get('duration'),'source':'final_locust_html_not_periodic_csv','statistics_window':{'start_utc':begin.astimezone(timezone.utc).isoformat(),'end_utc':finish.astimezone(timezone.utc).isoformat(),'seconds':(finish-begin).total_seconds(),'scope':'entire final event report (HTTP, ASSERT and optional WORKFLOW), including setup ramp and finalization; not pure steady'}}

def periodic_csv_count(path):
    if not path.is_file():return None
    with path.open(encoding='utf-8-sig',newline='')as stream:
        rows=[row for row in csv.DictReader(stream)if row.get('Name')=='Aggregated']
    if not rows:return None
    try:return int(rows[-1]['Request Count'])
    except(ValueError,KeyError):return None

COMPACT_KEYS=frozenset(('rooms_opened','rooms_closed','room_startup_catalog_attempts','room_startup_catalog','room_startup_catalog_failed','room_periodic_catalog_attempts','room_periodic_catalog','room_periodic_catalog_failed','catalog_hits','catalog_misses','room_failures','local_view_intents','legacy_snapshot_attempts','rooms_remaining'))

WORKLOAD_COUNTER_KEYS=frozenset(('checkpoint_attempts','checkpoint_completed','checkpoint_failed','grants_validated','grant_responses','grant_followup_attempts','grant_followup_completed','grant_followup_failed','finalization_attempts','finalization_completed','finalization_failed'))

HTTP_METHODS=frozenset(('GET','POST','HEAD','PUT','PATCH','DELETE','OPTIONS'))

def compact_final_count_checks(final,cfg,users=None):
    c=final.get('compact_client');routes=final.get('routes',[])
    users=cfg.get('active')if users is None else users
    valid=(type(c)is dict and set(c)==COMPACT_KEYS and all(type(v)is int and 0<=v<=10**12 for v in c.values())and type(users)is int and 1<=users<=4000 and type(routes)is list and all(type(r)is dict and type(r.get('requests'))is int and r['requests']>=0 for r in routes))
    keys=('compact_report_shape','compact_attempts_settled','compact_http_catalog_reconciled','compact_snapshot_HTTP_absent','compact_rooms_complete','compact_business_errors_zero','compact_local_intents_observed')
    if not valid:return dict.fromkeys(keys,False)
    catalog=sum(r['requests']for r in routes if r.get('method')in HTTP_METHODS and 'lottery/catalog'in str(r.get('name','')))
    snapshot=sum(r['requests']for r in routes if r.get('method')in HTTP_METHODS and 'lottery/snapshot'in str(r.get('name','')))
    return {'compact_report_shape':True,
        'compact_attempts_settled':c['room_startup_catalog_attempts']==c['room_startup_catalog']+c['room_startup_catalog_failed']and c['room_periodic_catalog_attempts']==c['room_periodic_catalog']+c['room_periodic_catalog_failed']and c['catalog_hits']==c['room_startup_catalog']+c['room_periodic_catalog']and c['room_failures']==c['room_startup_catalog_failed']+c['room_periodic_catalog_failed']and c['catalog_misses']<=c['room_failures'],
        'compact_http_catalog_reconciled':catalog==c['room_startup_catalog_attempts']+c['room_periodic_catalog_attempts'],
        'compact_snapshot_HTTP_absent':snapshot==0 and c['legacy_snapshot_attempts']==0,
        'compact_rooms_complete':c['rooms_opened']==c['rooms_closed']==c['room_startup_catalog']==(users+3)//4 and c['rooms_remaining']==0,
        'compact_business_errors_zero':c['room_failures']==c['catalog_misses']==c['room_startup_catalog_failed']==c['room_periodic_catalog_failed']==0,
        'compact_local_intents_observed':users<=2 or c['local_view_intents']>0}

def full_workload_count_checks(final):
    c=final.get('run_state',{}).get('workload_counters');rows=final.get('workflow_statistics');valid=(type(c)is dict and set(c)==WORKLOAD_COUNTER_KEYS and all(type(v)is int and 0<=v<=10**12 for v in c.values())and type(rows)is list and len(rows)==4 and all(type(r)is dict and type(r.get('requests'))is int and type(r.get('failures'))is int and 0<=r['failures']<=r['requests']for r in rows))
    keys=('workload_counters_complete','workload_counters_settled','workload_workflow_counts_reconciled','grant_followups_not_skipped')
    if not valid:return dict.fromkeys(keys,False)
    flow={r.get('name'):r for r in rows};expected={'checkpoint_setup','checkpoint_periodic','checkpoint_final','finalization'}
    if set(flow)!=expected:return dict.fromkeys(keys,False)
    attempted=sum(flow[k]['requests']for k in expected if k!='finalization');failed=sum(flow[k]['failures']for k in expected if k!='finalization')
    return {'workload_counters_complete':True,
        'workload_counters_settled':c['checkpoint_attempts']==c['checkpoint_completed']+c['checkpoint_failed']and c['grant_followup_attempts']==c['grant_followup_completed']+c['grant_followup_failed']and c['finalization_attempts']==c['finalization_completed']+c['finalization_failed'],
        'workload_workflow_counts_reconciled':(c['checkpoint_attempts'],c['checkpoint_failed'],c['finalization_attempts'],c['finalization_failed'])==(attempted,failed,flow['finalization']['requests'],flow['finalization']['failures']),
        'grant_followups_not_skipped':c['grant_responses']==c['grant_followup_attempts']==c['grant_followup_completed']and c['grant_followup_failed']==0 and c['grant_responses']<=c['grants_validated']<=128*c['checkpoint_attempts']}

def complete_final_counts(final, html, cfg, users=None):
    wire=final.get('business_wire',{})
    counters=wire.get('counters',{})
    state=final.get('run_state',{})
    cleanup=state.get('counters',{})
    routes=final.get('routes',[])
    valid_routes=type(routes)is list and all(type(row)is dict and type(row.get('requests'))is int and row['requests']>=0 for row in routes)
    http=sum(row['requests'] for row in routes if row.get('method')in('GET','POST','HEAD','PUT','PATCH','DELETE','OPTIONS')) if valid_routes else None
    all_events=sum(row['requests'] for row in routes) if valid_routes else None
    names=('cleanup_attempts','cleanup_completed','cleanup_failed','cleanup_interrupted')
    valid_cleanup=all(type(cleanup.get(name))is int and cleanup[name]>=0 for name in names)
    checks = {'route_totals_match_final':valid_routes and all_events==final.get('requests')==html.get('requests'),
            'wire_http_counts_settled':type(http)is int and counters.get('requests')==counters.get('responses')==http,
            'cleanup_outcomes_settled':valid_cleanup and cleanup['cleanup_attempts']==sum(cleanup[name] for name in names[1:]),
            'run_state_collection_complete':state.get('collection_complete')is True}
    mode=cfg.get('client_workload','legacy-v1')
    checks['client_workload_bound']=mode in ('legacy-v1','client-v2','client-v3')and final.get('client_workload','legacy-v1')==mode
    if mode in ('client-v2','client-v3'):
        workflow = final.get('workflow_statistics')
        expected = {'checkpoint_setup', 'checkpoint_periodic', 'checkpoint_final', 'finalization'}
        valid = (type(workflow) is list and len(workflow) == 4
            and {row.get('name') for row in workflow if type(row) is dict} == expected
            and all(type(row) is dict and type(row.get('requests')) is int
                    and type(row.get('failures')) is int
                    and 0 <= row['failures'] <= row['requests'] for row in workflow))
        route_workflow = {row['name']: (row['requests'], row.get('failures'))
                          for row in routes if row.get('method') == 'WORKFLOW'} if valid_routes else {}
        checks.update(client_workload_bound=final.get('client_workload') == mode,
            http_totals_match_final=final.get('http_requests') == http,
            workflow_collection_complete=final.get('workflow_statistics_complete') is True,
            workflow_routes_match=valid and set(route_workflow) <= expected
                and len(route_workflow) == sum(row.get('method') == 'WORKFLOW' for row in routes)
                and all(route_workflow.get(row['name'], (0, 0)) == (row['requests'], row['failures'])
                        for row in workflow),
            known_event_methods_only=valid_routes and all(row.get('method') in
                ('GET','POST','HEAD','PUT','PATCH','DELETE','OPTIONS','ASSERT','WORKFLOW') for row in routes))
    if mode in ('client-v2','client-v3'):checks.update(full_workload_count_checks(final))
    if mode=='client-v3':checks.update(compact_final_count_checks(final,cfg,users))
    if (cfg.get('client_recovery') or {}).get('retry_setup_control') == 1:
        if str(PROJECT) not in sys.path: sys.path.insert(0, str(PROJECT))
        from loadtest_lab.workload import recovery_route_count_checks
        reconciled = recovery_route_count_checks(final, cfg, users)
        checks['recovery_route_ledger_valid'] = reconciled.get('route_ledger_valid') is True
        checks['compact_http_catalog_reconciled'] = reconciled.get('catalog_logical_reconciled') is True
    return checks

def activity_overlap(proof, offsets, ready, window):
    """Conservative shared UTC interval; 2s margin at EACH client endpoint."""
    need(type(offsets) is list and 1 <= len(offsets) <= 5000
         and all(type(x) in (int, float) and math.isfinite(x) for x in offsets),
         'progress_clock_offsets_invalid')
    need(max(offsets) - min(offsets) <= 2, 'progress_wall_monotonic_drift')
    interval = ready.get('best_overlap_proof')
    if proof.get('best_start_monotonic') is None or interval is None:
        return {'verified': True, 'common_seconds': 0, 'start_utc': None, 'end_utc': None}
    stamp = lambda value: datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()
    left = max(proof['best_start_monotonic'] + max(offsets) + 2,
               stamp(interval['lower_bound_start_utc']), stamp(window['start_utc']))
    right = min(proof['best_end_monotonic'] + min(offsets) - 2,
                stamp(interval['lower_bound_end_utc']), stamp(window['end_utc']))
    return {'verified': True, 'common_seconds': max(0, right-left),
            'start_utc': datetime.fromtimestamp(left, timezone.utc).isoformat(),
            'end_utc': datetime.fromtimestamp(right, timezone.utc).isoformat(),
            'client_clock_endpoint_margin_seconds': 2,
            'scope': 'intersection of signed per-actor successful-business span, signed server-ready lower bound and actual final HTTP window'}

def verify_actor_progress(stage, lab, cfg, final, worker_pid, ready, window):
    if str(PROJECT) not in sys.path:
        sys.path.insert(0, str(PROJECT))
    from loadtest_lab.guard import load_client
    from loadtest_lab.progress import verify_progress
    actual, controller = load_client(lab/'client.json')
    need(canonical(actual) == canonical(cfg), 'progress_client_manifest_mismatch')
    summary = final.get('actor_progress')
    need(type(summary) is dict, 'actor_progress_final_summary_missing')
    path = stage/'client_progress.jsonl'
    proof = verify_progress(path, summary, run_id=cfg['run_id'],
        manifest_sha256=hashlib.sha256(canonical(cfg)).hexdigest(), stage_id=stage.name,
        worker_pid=worker_pid, controller=controller, target=cfg['active'])
    # verify_progress already enforced signed rows, bounded bytes/records and SHA.
    offsets = []
    for line in path.read_bytes().splitlines():
        row = json.loads(line)
        offsets.append(row['at_utc_epoch'] - row['snapshot']['at_monotonic'])
    need(ready.get('collection_complete') is True and ready.get('max_effective_marked_ready') == cfg['active'],
         'progress_server_ready_not_confirmed')
    return {**proof, 'observation_sha256': summary['sha256'],
            'shared_activity': activity_overlap(proof, offsets, ready, window)}

def exit_probe_pre_stop_due(stage,cfg):
    """O(1) <=16KiB timing hint; final signed full-proof verification is unchanged."""
    target=cfg.get('exit_probe_common_seconds')
    if target is None:return False
    p=stage/'client_progress.jsonl'
    try:
        with p.open('rb')as f:
            f.seek(0,2);size=f.tell();f.seek(max(0,size-16384));raw=f.read(16384)
        rows=raw.split(b'\n')
        if not raw.endswith(b'\n') or len(rows)<2:return False
        row=json.loads(rows[-2]);state=row['snapshot']
        return (row.get('run_id')==cfg['run_id']and row.get('stage_id')==stage.name
            and row.get('manifest_sha256')==hashlib.sha256(canonical(cfg)).hexdigest()
            and state.get('all_active')is True and state.get('frozen_at_monotonic')is None
            and type(state.get('best_seconds'))in(int,float)and state['best_seconds']>=target+5)
    except (OSError,ValueError,KeyError,TypeError):return False
