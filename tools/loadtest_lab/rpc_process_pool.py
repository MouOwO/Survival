"""Opt-in isolated RPC processes;original driver/SQL/commit,never replay.

Startup O(W*S),W in(3,6,12) immutable workers;each RPC O(payload bytes+fixed stages),
no account scans or authority cache. At most24 in-flight calls;queue-start
wait<=2s and original HTTP absolute deadline includes IPC. Driver pools have
a total of16 configured connections and32 waiter slots;serial workers use
W actual connections. Snapshot visits W fixed records,not players.
Parent-death/pidfd shutdown is shared with the proven pure-worker lifecycle.
"""
from __future__ import annotations
from pathlib import Path
import hashlib,json,os,re,threading,time

_CLIENT=None


def _publish(path,value):
    with Path(path).open('x',encoding='utf8')as f:json.dump(value,f,separators=(',',':'))


def _gate(path,deadline):
    while not Path(path).is_file():
        if time.monotonic()>=deadline:raise RuntimeError('rpc_control_gate_deadline')
        time.sleep(.02)


def _boot(root,dsn,options,allocations):
    global _CLIENT
    from fishing_api.postgres import PostgresRpcClient
    import fishing_api.postgres as driver
    pid=os.getpid();allocation=allocations[pid]
    if _CLIENT is not None:raise RuntimeError('rpc_worker_already_initialized')
    _CLIENT=PostgresRpcClient(dsn,**options,**allocation)
    _CLIENT.ready()
    value={'pid':pid,'driver_sha256':hashlib.sha256(Path(driver.__file__).read_bytes()).hexdigest(),
           'pool':_CLIENT.pool_stats(),'allocation':allocation}
    _publish(Path(root)/(str(pid)+'.ready.json'),value)
    _gate(Path(root)/'ready.gate',time.monotonic()+12)
    return value


def _job(function,payload,request_until,queue_until,enqueued,observe):
    from fishing_api._bounded_pool import request_deadline
    from fishing_api.postgres import DatabaseError
    from archive_backend import _checkpoint_observation as observation
    began=time.monotonic();trace=observation.Trace('/v1/online-time/checkpoint')if observe else None
    token=observation._ACTIVE.set(trace)if trace is not None else None
    try:
        if began>=request_until:raise DatabaseError('database_timeout')
        if began>=queue_until:raise DatabaseError('database_busy')
        if _CLIENT is None:raise DatabaseError()
        with request_deadline(request_until):result=_CLIENT.ready()if function is None else _CLIENT.rpc(function,payload)
        ok=True
    except DatabaseError as error:
        ok=False;result={'code':error.code,'status':error.status}
    except Exception:
        ok=False;result={'code':'database_unavailable','status':503}
    finally:
        if token is not None:observation._ACTIVE.reset(token)
    return {'pid':os.getpid(),'ok':ok,'result':result,'pool':_CLIENT.pool_stats(),
            'stages':{}if trace is None else trace.stages,
            'queue_ms':max(0,(began-enqueued)*1000)}


def _finish(root):
    if _CLIENT is None:raise RuntimeError('rpc_worker_not_initialized')
    _CLIENT.close();value={'pid':os.getpid(),'pool':_CLIENT.pool_stats()}
    _publish(Path(root)/(str(os.getpid())+'.closed.json'),value)
    _gate(Path(root)/'closed.gate',time.monotonic()+10)
    return value


def validate_profile(cfg):
    value=cfg.get('rpc_process_pool')
    if value is None:return None
    workers=value.get('workers')if type(value)is dict else None
    if (type(workers)is not int or workers not in(3,6,12)or value!={'id':'driver-process'+str(workers)+'-v1','workers':workers,'max_pending':24,'queue_seconds':2}
        or cfg.get('purpose')!='capacity'or cfg.get('process_topology')!='split-v1'
        or cfg.get('process_observation')!='pid-v1'or cfg.get('db_concurrency')!=16
        or cfg.get('database_pool_limits')!={'connections':16,'waiting':32,'wait_seconds':2.0}
        or 'operator/loadtest_lab/rpc_process_pool.py'not in cfg.get('sources',{})
        or 'runtime/player_web_auth/response_pool.py'not in cfg.get('sources',{})):
        raise ValueError('rpc_process_profile_invalid')
    return value


class RpcProcesses:
    def __init__(self,root,dsn,*,workers=3,connect_timeout,statement_timeout_ms,lock_timeout_ms):
        from player_web_auth.response_pool import ResponseEncoderPool
        if type(workers)is not int or workers not in(3,6,12):raise ValueError('rpc_worker_budget_invalid')
        self._workers=workers
        self._root=Path(root)/'rpc_process_controls';self._root.mkdir(mode=0o700)
        self._lock=threading.RLock();self._closed=False;self._closing=False
        self._stats={};self._calls=self._errors=self._used=self._queue_rejected=0
        self._boot_records=[];self._terminal=None
        self._lifecycle=ResponseEncoderPool(workers=workers,pending=workers*8)
        # Warmup has completed;all later RPC jobs share the same24-slot bound.
        self._lifecycle._maximum=24;self._lifecycle._slots=threading.BoundedSemaphore(24)
        self._pids=sorted(r['pid']for r in self._lifecycle.snapshot()['worker_identities'])
        self._allocations={pid:{'max_concurrency':16//workers+int(index<16%workers),
                               'pool_max_waiters':32//workers+int(index<32%workers),'pool_wait_timeout':2}
                           for index,pid in enumerate(self._pids)}
        options={'connect_timeout':connect_timeout,'statement_timeout_ms':statement_timeout_ms,
                 'lock_timeout_ms':lock_timeout_ms}
        futures=[self._lifecycle._executor.submit(_boot,str(self._root),dsn,options,self._allocations)for _ in self._pids]
        try:
            self._wait_files('ready.json',time.monotonic()+12)
            _publish(self._root/'ready.gate',{'released':True})
            records=[f.result(timeout=3)for f in futures]
            if {r['pid']for r in records}!=set(self._pids):raise RuntimeError('rpc_boot_worker_set_mismatch')
            from fishing_api import postgres as driver
            expected=hashlib.sha256(Path(driver.__file__).read_bytes()).hexdigest()
            if any(r['driver_sha256']!=expected or r['allocation']!=self._allocations[r['pid']]for r in records):
                raise RuntimeError('rpc_driver_source_or_budget_mismatch')
            self._stats={r['pid']:r['pool']for r in records};self._boot_records=records
        except BaseException:
            if not(self._root/'ready.gate').exists():_publish(self._root/'ready.gate',{'released_on_failure':True})
            self._lifecycle.close();raise

    def _wait_files(self,suffix,deadline):
        for pid in self._pids:
            path=self._root/(str(pid)+'.'+suffix)
            while not path.is_file():
                if time.monotonic()>=deadline:raise RuntimeError('rpc_owned_worker_control_deadline')
                time.sleep(.02)

    @staticmethod
    def _merge_stages(trace,stages,queue_ms):
        if trace is None:return
        # Fixed stage map only;child SQL timings are actual nested measurements.
        for name,value in stages.items():
            if name=='rpc':continue
            old=trace.stages.get(name,[0,0]);trace.stages[name]=[min(65535,old[0]+value[0]),round(min(86400000,old[1]+value[1]),3)]
        old=trace.stages.get('db_pool_wait',[0,0]);trace.stages['db_pool_wait']=[min(65535,old[0]+1),round(min(86400000,old[1]+queue_ms),3)]

    def rpc(self,function,payload):
        from concurrent.futures import TimeoutError
        from fishing_api.postgres import DatabaseError
        from fishing_api._bounded_pool import remaining_budget
        from archive_backend import _checkpoint_observation as observation
        from archive_backend.http_request_timing import rpc_span
        began=time.monotonic();remaining=remaining_budget();until=began+(20 if remaining is None else remaining)
        queue_until=min(until,began+2);pool=self._lifecycle;future=None
        if not pool._slots.acquire(timeout=max(0,queue_until-time.monotonic())):
            with self._lock:self._queue_rejected+=1
            raise DatabaseError('database_busy')
        trace=observation._ACTIVE.get()
        try:
            with self._lock:
                if self._closing or self._closed:raise DatabaseError('database_unavailable')
                self._calls+=1
            with pool._lock:
                if pool._closed:raise DatabaseError('database_unavailable')
                future=pool._executor.submit(_job,function,payload,until,queue_until,began,trace is not None)
                pool._pending[id(future)]=future;pool._counts['submitted']+=1
                pool._counts['peak_pending']=max(pool._counts['peak_pending'],len(pool._pending))
            future.add_done_callback(pool._finished)
            with rpc_span(function):value=future.result(timeout=max(.001,until-time.monotonic()))
            if type(value)is not dict or value.get('pid')not in self._pids or type(value.get('ok'))is not bool:
                raise DatabaseError()
            with self._lock:self._stats[value['pid']]=value['pool'];self._used+=1
            self._merge_stages(trace,value['stages'],value['queue_ms'])
            if not value['ok']:
                error=value['result'];code=error.get('code');status=error.get('status')
                if not(type(code)is str and re.fullmatch('[a-z][a-z0-9_]{0,63}',code)and type(status)is int and 400<=status<=599):raise DatabaseError()
                raise DatabaseError(code,status)
            return value['result']
        except BaseException as error:
            if future is None:pool._slots.release()
            else:future.cancel() # Only unstarted calls can cancel;no RPC is ever replayed.
            with self._lock:self._errors+=1
            if not isinstance(error,Exception):raise
            if isinstance(error,DatabaseError):raise
            raise DatabaseError('database_timeout'if isinstance(error,TimeoutError)else'database_unavailable')from None

    def ready(self):
        # A fresh original SELECT/role check;startup success is not cached readiness.
        return self.rpc(None,{})is True

    def pool_stats(self):
        with self._lock:rows=list(self._stats.values())
        if len(rows)!=self._workers:raise RuntimeError('rpc_pool_statistics_not_complete')
        keys=set(rows[0])
        if any(set(row)!=keys for row in rows):raise RuntimeError('rpc_pool_statistics_shape_changed')
        result={}
        for key in keys:
            values=[row[key]for row in rows]
            result[key]=(all(values)if key=='closed'else 2.0 if key=='wait_timeout'else sum(values))
        return result

    def snapshot(self):
        with self._lock:return {'kind':'ISOLATED_ORIGINAL_DRIVER_PROCESS_POOL_V1','workers':self._workers,'max_pending':24,
            'configured_connection_allocations':[self._allocations[pid]for pid in self._pids],
            'original_driver_boot_records':self._boot_records,'calls':self._calls,'results_used':self._used,
            'errors':self._errors,'queue_rejected_before_dispatch':self._queue_rejected,
            'RPC_replays':0,'closed':self._closed,'closing':self._closing,
            'worker_lifecycle':self._lifecycle.snapshot(),
            'pool_snapshot_scope':'last parent-collected original-driver snapshot for each fixed worker;exact at ready and drained close;not live per-connection telemetry'}

    def close(self):
        with self._lock:
            if self._closed:return
            self._closing=True
        pool=self._lifecycle;deadline=time.monotonic()+7
        try:
            if pool.snapshot()['pending']!=0:raise RuntimeError('rpc_calls_not_drained')
            futures=[pool._executor.submit(_finish,str(self._root))for _ in self._pids]
            self._wait_files('closed.json',deadline)
            _publish(self._root/'closed.gate',{'released':True})
            records=[f.result(timeout=max(.01,deadline-time.monotonic()))for f in futures]
            if {r['pid']for r in records}!=set(self._pids):raise RuntimeError('rpc_close_worker_set_mismatch')
            with self._lock:self._stats={r['pid']:r['pool']for r in records}
            if any(not r['pool']['closed']or any(r['pool'][k]for k in('total','waiting','in_use','connecting','closing','quarantined'))for r in records):
                raise RuntimeError('rpc_original_pools_not_closed')
        finally:
            if not(self._root/'closed.gate').exists():_publish(self._root/'closed.gate',{'released_on_failure':True})
            pool.close(deadline=deadline)
        state=pool.snapshot()
        if state['pending']or state['forced_workers']or not state['manager_joined']or len(state['worker_exit_confirmed'])!=self._workers or not all(state['worker_exit_confirmed']):
            raise RuntimeError('rpc_owned_workers_not_closed')
        with self._lock:self._closed=True
