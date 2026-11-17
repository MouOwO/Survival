"""Opt-in isolated two-process lab; never a production service entry.

One FE owns SQLite/identity/ready state. One fresh-exec BE owns PostgreSQL/Lua.
Business still uses the original loopback HTTP forward, with no per-request IPC.
Startup/file validation is O(S) once. Stable supervision uses a blocking waitid,
not process scans. Cleanup uses an unreaped owned session leader to prevent PGID
reuse; no child is reaped until any required group cleanup has completed.
"""
from __future__ import annotations
from pathlib import Path
import ctypes
import hashlib
import json
import math
import re
import os
import secrets
import signal
import subprocess
import sys
import threading
import time

from .guard import PORTS, canonical, dsn, load, marker_guard, need, production_host_guard, sha, write_new
from . import runtime as shared

CONTROL_BUDGET = 131072
STARTUP_SECONDS = 30
DRAIN_SECONDS = 45
FILES = ('process_parent_boot.json', 'backend_started_receipt.json',
         'backend_stop_request.json', 'backend_stopped_receipt.json', 'process_scope.json')


def validate_process_options(cfg):
    mode = cfg.get('process_topology')
    obs = cfg.get('process_observation')
    need(mode in (None, 'same-v1', 'split-v1'), 'lab_process_topology_invalid')
    need(obs in (None, 'pid-v1'), 'lab_process_observation_invalid')
    if mode == 'split-v1':
        need(obs == 'pid-v1' and cfg.get('backend_db_pool') == 'bounded-v2',
             'split_process_requires_pid_observation_and_bounded_pool')
    if mode is not None or obs is not None:
        need('operator/loadtest_lab/process_runtime.py' in cfg.get('sources', {}),
             'process_runtime_source_binding_required')
    validate_backend_pair(cfg)
    return mode


def _linux():
    need(sys.platform.startswith('linux') and hasattr(os, 'pidfd_open')
         and hasattr(signal, 'pidfd_send_signal') and hasattr(os, 'P_PIDFD')
         and hasattr(os, 'WNOWAIT'), 'linux_pidfd_waitid_required')


def _identity(pid, roles):
    from .monitor import capture_process_identity
    value = capture_process_identity(pid)
    need(set(value) == {'pid', 'starttime_ticks', 'boot_id_sha256', 'exe_sha256'},
         'process_identity_shape_changed')
    return {**value, 'roles': roles}


def publish(path, value):
    """Atomic no-overwrite publication in this private, same-filesystem lab."""
    raw = canonical(value)
    need(len(raw) <= CONTROL_BUDGET and not path.exists() and not path.is_symlink(),
         'process_control_publication_invalid')
    temp = path.parent / ('.' + path.name + '.' + secrets.token_hex(12) + '.pending')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(raw); f.flush(); os.fsync(f.fileno())
    os.link(temp, path)  # Fails rather than replacing an existing immutable result.
    temp.unlink()
    if hasattr(os, 'O_DIRECTORY'):
        fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(fd)
        finally: os.close(fd)


def _read(path):
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= CONTROL_BUDGET,
         'process_control_file_invalid')
    with path.open('rb') as stream:
        raw = stream.read(CONTROL_BUDGET + 1)
    need(len(raw) <= CONTROL_BUDGET, 'process_control_file_budget')
    def pairs(items):
        value = {}
        for key, item in items:
            need(key not in value, 'process_control_duplicate_key')
            value[key] = item
        return value
    def finite_float(text):
        value = float(text)
        need(math.isfinite(value), 'process_control_nonfinite')
        return value
    def constant(_):
        raise ValueError('process_control_nonfinite')
    value = json.loads(raw, object_pairs_hook=pairs, parse_float=finite_float,
                       parse_constant=constant)
    need(type(value) is dict, 'process_control_object_required')
    return value


def _bound(value, cfg, nonce, kind):
    need(value.get('kind') == kind and value.get('run_id') == cfg['run_id']
         and value.get('manifest_sha256') == sha(canonical(cfg))
         and value.get('startup_nonce') == nonce, 'process_control_binding_mismatch')
    return value


def publish_scope(root, cfg, processes):
    need(cfg.get('process_observation') == 'pid-v1', 'process_scope_not_selected')
    value = {'schema': 1, 'id': 'pid-v1', 'run_id': cfg['run_id'],
             'manifest_sha256': sha(canonical(cfg)), 'processes': processes,
             'postgres_container_name': 'survival-loadtest-' + cfg['run_id'][:12]}
    publish(root / 'process_scope.json', value)
    return value


def publish_same_scope(root, cfg):
    if cfg.get('process_observation') != 'pid-v1':
        return None
    return publish_scope(root, cfg, [_identity(os.getpid(), ['frontend', 'backend'])])


def _retire_original_pool(original):
    """The original builder performs real readiness/sync RPCs before returning.
    Close those startup connections before any distributed workers are opened.
    """
    original.close()
    stats=original.pool_stats()
    need(type(stats)is dict and stats.get('closed')is True
         and all(stats.get(k)==0 for k in ('total','waiting','in_use','connecting','closing','quarantined')),
         'original_bootstrap_pool_not_fully_closed')
    return stats


def _http64_server_class(original,cfg):
    """Explicit lab-only aggregate admission. Original server/defaults stay32.

    Initial metadata O(1); each accepted socket O(1),64 fixed active sockets,
    <=2s admission and unchanged50ms rejection. Once-only shutdown O(64).
    No account scan, database call, permission cache or request replay.
    """
    if cfg.get('_backend_pair_node'):
        class SharedPortBackend(original):
            allow_reuse_port=True
        return SharedPortBackend
    if cfg.get('http_concurrency')!=64:return original
    selected=any(row.get('id')=='http-admission-v8'for row in cfg.get('runtime_experiments',()))
    if not(selected and cfg.get('db_concurrency')==32 and cfg.get('database_resource_profile')=='db32-4cpu-4g-v1'and cfg.get('rpc_process_pool',{}).get('id')=='driver-process32-v1'):
        raise ValueError('http64_requires_explicit_reviewed_profile')
    from http.server import ThreadingHTTPServer
    class ExplicitHTTP64(original):
        def __init__(self,address,handler,*,max_concurrency=64,request_backlog=128,admission_wait_seconds=2):
            if address[0]not in('127.0.0.1','localhost','::1')or type(max_concurrency)is not int or max_concurrency!=64 or request_backlog!=128 or admission_wait_seconds!=2:
                raise ValueError('http64_fixed_loopback_admission_required')
            if address[0]=='::1':
                import socket
                self.address_family=socket.AF_INET6
            self._configure_admission(layer='backend',max_concurrency=64,request_backlog=128,admission_wait_seconds=2)
            self._worker_limit=64;self._workers=self._admission_slots
            ThreadingHTTPServer.__init__(self,address,handler)
    return ExplicitHTTP64


def _backend_setup(root, cfg, private, lua):
    """The original Settings/constructor/preflight calls, in a fresh process."""
    cfg=_node_cfg(cfg)
    sys.path.insert(0, str(root / 'runtime'))
    from fishing_api.config import Settings
    from fishing_api.server import build_application, make_handler, BoundedThreadingHTTPServer
    settings = Settings(host='127.0.0.1', port=PORTS['backend'], api_token=private['backend'],
        supabase_url='', supabase_key='', account_id_pepper=private['pepper'],
        reward_csv=root / 'addon/data/csv/玩家档案系统/star_blessing_reward_definitions.csv',
        rule_csv=root / 'addon/data/csv/玩家档案系统/fishing_system_rules.csv',
        gameplay_stats_csv=root / 'addon/data/csv/玩家档案系统/player_gameplay_stats.csv',
        request_timeout_seconds=20, database_backend='postgres', postgres_dsn=dsn(cfg, private),
        postgres_max_concurrency=min(16,cfg['db_concurrency']), http_max_concurrency=min(32,cfg['http_concurrency']),
        payment_mode='test', archive_http=True, addon_root=root / 'addon', archive_lua_path=lua)
    os.environ.pop('SURVIVAL_TEST_STEAM_IDS64', None)
    # This unused bootstrap client retains original per-client limits. Actual
    # DB32 uses32 separate original validated one-connection clients.
    options = {'pool_max_waiters': min(32,cfg['database_pool_limits']['waiting']),
               'pool_wait_timeout': cfg['database_pool_limits']['wait_seconds']}
    app = build_application(settings, **options)
    try:
        from .rpc_process_pool import validate_profile as rpc_profile, RpcProcesses
        if rpc_profile(cfg)is not None:
            original=app.rpc_client
            if cfg['rpc_process_pool']['workers']==32:
                _retire_original_pool(original)
            parallel=RpcProcesses(root,settings.postgres_dsn,workers=cfg['rpc_process_pool']['workers'],
                connect_timeout=settings.postgres_connect_timeout_seconds,
                statement_timeout_ms=settings.postgres_statement_timeout_ms,
                lock_timeout_ms=settings.postgres_lock_timeout_ms)
            try:
                original.close();need(original.pool_stats()['total']==0,'original_startup_pool_not_closed')
                app.rpc_client=parallel
            except BaseException:
                parallel.close();raise
        pool = shared.checked_database_pool_stats(app.rpc_client, cfg)
        from archive_backend.lottery_catalog import catalog_document
        catalog_document(app.archive.bundle, lua)
        warm = shared.warm_settlement_cache(root, cfg, app, lua)
        base = make_handler(app, client_timeout=settings.http_client_timeout_seconds,
                            request_deadline=settings.http_request_deadline_seconds)
        from .experiments import has_http_admission, http_admission_backlog, http_admission_wait
        options = ({'request_backlog': http_admission_backlog(cfg), 'admission_wait_seconds': 2.0}
                   if has_http_admission(cfg) else {})
        # Settings retains its original constructor/default-factory cap. The
        # explicit lab HTTP64 class below owns the actual independently audited
        # admission budget; application/SQL/permissions and original files stay unchanged.
        server_type = _http64_server_class(BoundedThreadingHTTPServer,cfg)
        server = server_type(('127.0.0.1', PORTS['backend']), base,
                    max_concurrency=cfg['http_concurrency'], **options)
        server.block_on_close = False
        return app, server, pool, warm
    except BaseException:
        app.rpc_client.close()
        raise


def _safe_error(errors, code):
    if code not in errors and len(errors) < 24:
        errors.append(code)


def _best_effort(errors, code, function, default=None):
    try:
        return function()
    except BaseException:
        _safe_error(errors, code)
        return default


def _kill_own_session(own_pid):
    """Only the already verified BE session leader calls this; never the FE."""
    try:
        if os.getpid() == own_pid and os.getpgrp() == own_pid and os.getsid(0) == own_pid:
            os.killpg(own_pid, signal.SIGKILL)
    finally:
        os._exit(2)


def _backend_watchdog(stop, complete, own_pid):
    # The stop event is also set in finally, including startup exceptions. No
    # account/thread/process scan, and no receipt/disk IO in this last resort.
    stop.wait()
    if not complete.wait(DRAIN_SECONDS + 3):
        _kill_own_session(own_pid)


def backend_worker(directory, *, lua_executable=None, backend_index=None):
    _linux()
    root, cfg, private = load(directory)
    need(validate_process_options(cfg) == 'split-v1', 'split_backend_mode_required')
    production_host_guard(cfg)
    pair=validate_backend_pair(cfg)
    need((type(backend_index)is int and backend_index in(0,1))if pair else backend_index is None,'backend_index_not_bound')
    limits_cfg=_node_cfg(cfg)
    boot = _read(root / 'process_parent_boot.json')
    nonce = boot.get('startup_nonce')
    need(type(nonce) is str and re.fullmatch('[a-f0-9]{32}', nonce), 'process_nonce_invalid')
    _bound(boot, cfg, nonce, 'ISOLATED_PROCESS_PARENT_BOOT')
    parent = boot['parent_identity']
    need(type(parent) is dict and parent.get('pid') == os.getppid(), 'backend_parent_mismatch')
    need(os.getpgrp() == os.getpid() and os.getsid(0) == os.getpid(), 'backend_owned_session_required')
    own_pid = os.getpid()
    own = _identity(own_pid, ['backend1'if backend_index==1 else'backend'])
    stop, complete = threading.Event(), threading.Event()
    prior = signal.signal(signal.SIGTERM, lambda *_: stop.set())
    threading.Thread(target=_backend_watchdog, args=(stop, complete, own_pid), daemon=True).start()
    app = server = None
    running = False
    errors = []
    control_error = None
    reason = 'parent_lost_or_lifetime_expired'
    frontend_quiescent = False
    common = {'run_id': cfg['run_id'], 'manifest_sha256': sha(canonical(cfg)),
              'startup_nonce': nonce, 'process_identity': own, 'process_group': own_pid}
    drain = {'drained': False, 'worker_slots_not_drained': limits_cfg['http_concurrency']}
    closed = False
    close_error = None
    stats = None
    terminal_written = False
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        need(libc.prctl(1, signal.SIGTERM, 0, 0, 0) == 0, 'parent_death_signal_unavailable')
        need(os.getppid() == parent['pid']
             and _identity(parent['pid'], ['frontend']) == parent, 'backend_parent_identity_changed')
        lua, lua_sha, lua_version = shared.resolve_lua(lua_executable)
        import psycopg
        with psycopg.connect(dsn(cfg, private, admin=True), connect_timeout=3) as conn:
            conn.execute('SET TRANSACTION READ ONLY'); marker_guard(conn, cfg, private, seeded=True)
        app, server, pool, warm = _backend_setup(root, cfg, private, lua)
        need(not stop.is_set() and os.getppid() == parent['pid'], 'parent_lost_during_backend_startup')
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start(); running = True
        publish(_node_path(root,'backend_started_receipt.json',backend_index), {**common,
            'kind': 'ISOLATED_BACKEND_PROCESS_STARTED', 'database_pool_started': pool,
            'rpc_process_pool_started': app.rpc_client.snapshot()if cfg.get('rpc_process_pool')else None,
            'actual_database_pool_limits_verified': True,
            'http_admission_started': shared.checked_http_admission_stats(server, 'backend', limits_cfg),
            'settlement_cache_warmup': warm, 'actual_catalog_preflight_passed': True,
            'lua_executable': lua, 'lua_sha256': lua_sha, 'lua_version': lua_version,
            'checkpoint_observation_started': shared.checkpoint_observation_stats(cfg)})
        started_at = boot.get('started_monotonic')
        need(type(started_at) in (int, float) and math.isfinite(started_at)
             and 0 <= started_at <= time.monotonic(), 'backend_boot_clock_invalid')
        remaining = max(0, started_at + cfg['duration_seconds'] + 90 - time.monotonic())
        stop.wait(remaining)
    except BaseException:
        _safe_error(errors, 'backend_run_not_completed')
    finally:
        stop.set()  # Arms the hard watchdog before any potentially blocking work.
        deadline = time.monotonic() + DRAIN_SECONDS
        request = root / 'backend_stop_request.json'
        try:
            if request.exists():
                req = _bound(_read(request), cfg, nonce, 'ISOLATED_BACKEND_STOP_REQUEST')
                supplied = req.get('deadline_monotonic')
                need(type(supplied) in (int, float) and math.isfinite(supplied)
                     and 0 <= supplied <= time.monotonic() + DRAIN_SECONDS + 1,
                     'backend_stop_deadline_invalid')
                need(type(req.get('frontend_drained')) is bool
                     and type(req.get('frontend_pending')) is int and req['frontend_pending'] >= 0,
                     'backend_frontend_quiescence_invalid')
                deadline = min(deadline, supplied)
                frontend_quiescent = req['frontend_drained'] and req['frontend_pending'] == 0
                reason = 'parent_requested'
            else:
                _safe_error(errors, 'backend_stop_request_missing')
        except BaseException:
            control_error = 'backend_stop_request_invalid'
            reason = 'invalid_stop_request_cleanup'
            _safe_error(errors, control_error)
        if running:
            _best_effort(errors, 'backend_listener_shutdown_failed', server.shutdown)
        if server is not None:
            drain = _best_effort(errors, 'backend_drain_failed', lambda:
                shared.drain_server_workers(server, '_workers', limits_cfg['http_concurrency'], deadline), drain)
            _best_effort(errors, 'backend_server_close_failed', server.server_close)
        else:
            # No backend listeners/app were constructed; this cannot certify a
            # normal run, but there are no worker slots to keep draining.
            drain = {'drained': True, 'worker_slots_not_drained': 0}
        if app is not None:
            if drain.get('drained') is True:
                try:
                    app.rpc_client.close()
                    stats = shared.checked_database_pool_stats(app.rpc_client, limits_cfg)
                    closed = (stats.get('closed') is True
                              and stats.get('total') == stats.get('waiting') == 0)
                except BaseException:
                    _safe_error(errors, 'database_pool_close_not_completed')
            else:
                stats = _best_effort(errors, 'database_pool_terminal_stats_failed', lambda:
                    shared.checked_database_pool_stats(app.rpc_client, limits_cfg))
            if not closed:
                close_error = 'database_pool_close_not_completed'
        if not frontend_quiescent:
            _safe_error(errors, 'frontend_quiescence_not_confirmed')
        if os.getppid() != parent['pid']:
            _safe_error(errors, 'backend_parent_lost')
        clean = (not errors and reason == 'parent_requested' and control_error is None
                 and frontend_quiescent and drain.get('drained') is True and closed)
        terminal = {**common, 'kind': 'ISOLATED_BACKEND_PROCESS_STOPPED',
            'stop_reason': reason, 'control_error': control_error,
            'backend_drain': drain,
            'http_admission_stopped': _best_effort(errors, 'backend_admission_stats_failed', lambda:
                shared.checked_http_admission_stats(server, 'backend', limits_cfg)) if server is not None else None,
            'database_pool_closed': closed, 'database_pool_close_deferred': not drain.get('drained', False),
            'database_pool_close_error': close_error, 'database_pool_stopped': stats,
            'rpc_process_pool_stopped': _best_effort(errors,'rpc_process_snapshot_failed',app.rpc_client.snapshot)if cfg.get('rpc_process_pool')and app is not None else None,
            'settlement_cache_stopped': _best_effort(errors, 'backend_cache_stats_failed', lambda:
                shared.settlement_cache_snapshot(cfg)),
            'checkpoint_observation_stopped': _best_effort(errors, 'backend_observation_stats_failed', lambda:
                shared.checkpoint_observation_stats(cfg)),
            'frontend_quiescent': frontend_quiescent,
            'cleanup_errors': errors, 'descendant_cleanup_required': not clean}
        # Statistics may also fail. Re-evaluate rather than retaining stale clean.
        clean = clean and not errors
        terminal['descendant_cleanup_required'] = not clean
        try:
            publish(_node_path(root,'backend_stopped_receipt.json',backend_index), terminal)
            terminal_written = True
        except BaseException:
            _safe_error(errors, 'backend_terminal_publication_failed')
            clean = False
        _best_effort(errors, 'backend_signal_restore_failed', lambda: signal.signal(signal.SIGTERM, prior))
        if not clean or not terminal_written or errors:
            # On parent death there is nobody left to kill Lua descendants. This
            # process is still the verified session leader and cannot be reused.
            _kill_own_session(own_pid)
        complete.set()
    return 0


def _not_reaped_exit(pidfd, *, block=False):
    return os.waitid(os.P_PIDFD, pidfd, os.WEXITED | os.WNOWAIT | (0 if block else os.WNOHANG))


def _backend_argv(root, lua):
    return [sys.executable, '-B', str(root / 'run_lab.py'), 'serve-backend',
            '--directory', str(root), '--lua-executable', lua]


class _OwnedChild:
    """One strong Popen reference; all kill/reap transitions share this lock."""
    def __init__(self, child):
        self.child = child
        self.pidfd = None
        self.group_verified = False
        self.reserved = True
        self.forced = False
        self.exit_code = None
        self.lock = threading.RLock()

    def exit_info(self):
        need(self.pidfd is not None, 'backend_pidfd_not_available')
        return _not_reaped_exit(self.pidfd)

    def term(self):
        with self.lock:
            if self.reserved and self.pidfd is not None and self.exit_info() is None:
                signal.pidfd_send_signal(self.pidfd, signal.SIGTERM)

    def force(self):
        with self.lock:
            if not self.reserved:
                return
            if self.group_verified:
                try: os.killpg(self.child.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                self.forced = True
            elif self.pidfd is not None:
                try: signal.pidfd_send_signal(self.pidfd, signal.SIGKILL)
                except ProcessLookupError: pass
                self.forced = True
            else:
                raise ValueError('owned_child_signal_proof_unavailable')

    def reap(self, timeout):
        with self.lock:
            if self.reserved:
                # No poll(), Popen.kill()/send_signal(), context-manager or
                # watcher may reap behind this ownership transition.
                value = self.child.wait(timeout=max(0, timeout))
                self.exit_code = value
                self.reserved = False
            return self.exit_code

    def close_fd(self):
        with self.lock:
            # Keep the exact handle available to the hard watchdog if an OS
            # reap timed out. Process exit will close it; never trade a live
            # child handle for an unbound numeric PID.
            if self.pidfd is not None and not self.reserved:
                os.close(self.pidfd)
                self.pidfd = None



PAIR_PROFILE={'id':'full-business-pair-v1','workers':2,'per_worker_http':32,
              'per_worker_connections':16,'per_worker_waiters':32,'wait_seconds':2}

def validate_backend_pair(cfg):
    row=cfg.get('backend_process_pool')
    if row is None:return None
    need(row==PAIR_PROFILE and cfg.get('purpose')=='capacity'
         and cfg.get('process_topology')=='split-v1'and cfg.get('process_observation')=='pid-v1'
         and cfg.get('backend_db_pool')=='bounded-v2'and 'rpc_process_pool'not in cfg
         and cfg.get('db_concurrency')==32 and cfg.get('http_concurrency')==64
         and cfg.get('database_resource_profile')=='db32-4cpu-4g-v1'
         and cfg.get('database_pool_limits')=={'connections':32,'waiting':64,'wait_seconds':2}
         and any(r.get('id')=='http-admission-v8'for r in cfg.get('runtime_experiments',()))
         and 'operator/loadtest_lab/process_runtime.py'in cfg.get('sources',{}),
         'full_backend_pair_fixed_profile_required')
    return row

def _node_cfg(cfg):
    if not cfg.get('backend_process_pool'):return cfg
    validate_backend_pair(cfg)
    return {**{k:v for k,v in cfg.items()if k!='backend_process_pool'},
            'db_concurrency':16,'http_concurrency':32,'database_resource_profile':'db16-4cpu-4g-v1',
            'database_pool_limits':{'connections':16,'waiting':32,'wait_seconds':2},
            '_backend_pair_node':True}

def _node_path(root,name,index):
    return root/(name if index is None else name.replace('_receipt.json','_node'+str(index)+'_receipt.json'))

def _aggregate_counters(rows,fixed):
    need(len(rows)==2 and all(type(r)is dict and set(r)==set(rows[0])for r in rows),'pair_counter_shape')
    result={}
    for key in rows[0]:
        values=[r[key]for r in rows]
        if key in fixed:
            need(values[0]==values[1],'pair_fixed_counter_mismatch');result[key]=values[0]
        elif all(type(x)is bool for x in values):result[key]=all(values)
        else:
            need(all(type(x)in(int,float)and math.isfinite(x)for x in values),'pair_counter_not_numeric')
            result[key]=sum(values)
    return result

def _aggregate_backend(root,cfg,nonce,identities,terminal=False):
    name='backend_stopped_receipt.json'if terminal else'backend_started_receipt.json'
    kind='ISOLATED_BACKEND_PROCESS_STOPPED'if terminal else'ISOLATED_BACKEND_PROCESS_STARTED'
    nodes=[]
    for i,ident in enumerate(identities):
        path=_node_path(root,name,i);row=_bound(_read(path),cfg,nonce,kind)
        need(row['process_identity']==ident and row['process_group']==ident['pid'],'pair_node_identity_changed')
        nodes.append(row)
    result=dict(nodes[0],backend_nodes=nodes,backend_node_receipt_sha256=[sha(_node_path(root,name,i).read_bytes())for i in range(2)],
                backend_process_pool=dict(PAIR_PROFILE),aggregate_counters_are_sum_of_two_owned_nodes=True)
    pool_key='database_pool_stopped'if terminal else'database_pool_started'
    adm_key='http_admission_stopped'if terminal else'http_admission_started'
    result[pool_key]=_aggregate_counters([r[pool_key]for r in nodes],{'wait_timeout'})
    result[adm_key]=_aggregate_counters([r[adm_key]for r in nodes],{'layer','accept_wait_seconds'})
    # Cache and trace snapshots remain per-process raw facts. They are not
    # collapsed into a fictitious single cache or a single trace budget.
    if terminal:
        result['backend_drain']={'drained':all(r['backend_drain']['drained']for r in nodes),
            'worker_slots_not_drained':sum(r['backend_drain']['worker_slots_not_drained']for r in nodes)}
        for key in('database_pool_closed','frontend_quiescent'):result[key]=all(r[key]is True for r in nodes)
        for key in('database_pool_close_deferred','descendant_cleanup_required'):result[key]=any(r[key]is True for r in nodes)
        result['cleanup_errors']=list(dict.fromkeys(x for r in nodes for x in r['cleanup_errors']))
        for key in('database_pool_close_error','control_error'):
            result[key]=next((r[key]for r in nodes if r[key]is not None),None)
        need(all(r['stop_reason']=='parent_requested'for r in nodes),'pair_node_stop_reason_not_normal')
    return result

class _OwnedBackendPair:
    """Two fresh-exec complete apps, fixed W=2, no account scans or IPC RPC.

    Startup O(2*S); stable HTTP dispatch stays in the kernel (SO_REUSEPORT).
    Every accepted HTTP request has one original handler and one original SQL
    path. No extra business/database/network call; shutdown/snapshot O(2).
    Both owned pidfds remain unreaped until all group cleanup has completed.
    """
    def __init__(self,root,cfg,lua,nonce):
        validate_backend_pair(cfg)
        self.root,self.cfg,self.nonce=root,cfg,nonce
        self.nodes=[];self.identities=[];self.lock=threading.RLock()
        self.ending=False;self.event=threading.Event();self.ready_complete=threading.Event();self.ready_error=None
        try:
            for index in range(2):
                child=subprocess.Popen(_backend_argv(root,lua)+['--backend-index',str(index)],
                                       stdin=subprocess.DEVNULL,start_new_session=True)
                node=_OwnedChild(child);self.nodes.append(node)
                node.pidfd=os.pidfd_open(child.pid,0)
                node.group_verified=os.getpgid(child.pid)==child.pid and os.getsid(child.pid)==child.pid
                need(node.group_verified,'pair_node_session_not_owned')
                ident=_identity(child.pid,['backend'if index==0 else'backend1']);self.identities.append(ident)
                def watch(fd=node.pidfd):
                    try:_not_reaped_exit(fd,block=True)
                    finally:self.event.set()
                threading.Thread(target=watch,daemon=True).start()
        except BaseException:
            for node in self.nodes:
                try:node.force()
                except BaseException:pass
            for node in self.nodes:
                try:node.reap(3);node.close_fd()
                except BaseException:pass
            raise
        self.child=self.nodes[0].child;self.pidfd=self.nodes[0].pidfd
        threading.Thread(target=self._publish_ready,daemon=True).start()
    def _publish_ready(self):
        try:
            deadline=time.monotonic()+STARTUP_SECONDS
            for index in range(2):
                path=_node_path(self.root,'backend_started_receipt.json',index)
                while not path.is_file():
                    need(not self.event.is_set()and not self.ending and time.monotonic()<deadline,'pair_node_not_ready')
                    self.event.wait(.05)
            publish(self.root/'backend_started_receipt.json',_aggregate_backend(self.root,self.cfg,self.nonce,self.identities))
        except BaseException as error:
            self.ready_error=type(error).__name__;self.event.set()
        finally:self.ready_complete.set()
    @property
    def reserved(self):return any(n.reserved for n in self.nodes)
    @property
    def forced(self):return any(n.forced for n in self.nodes)
    @property
    def exit_code(self):
        if any(n.exit_code is None for n in self.nodes):return None
        return next((n.exit_code for n in self.nodes if n.exit_code!=0),0)
    def exit_info(self):
        need(self.ready_error is None,'pair_ready_publication_failed')
        values=[n.exit_info()for n in self.nodes]
        if not self.ending:
            need(not any(v is not None for v in values),'pair_node_exited_before_shutdown')
            return None
        if any(v is None for v in values):return None
        path=self.root/'backend_stopped_receipt.json'
        if not path.exists():
            need(all(v.si_code==os.CLD_EXITED and v.si_status==0 for v in values),'pair_node_abnormal_exit')
            publish(path,_aggregate_backend(self.root,self.cfg,self.nonce,self.identities,terminal=True))
        return values[0]
    def wait_exit(self):self.event.wait()
    def term(self):
        with self.lock:
            self.ending=True
            for n in self.nodes:n.term()
    def force(self):
        with self.lock:
            self.ending=True
            for n in self.nodes:n.force()
    def reap(self,timeout):
        with self.lock:
            deadline=time.monotonic()+timeout
            for n in self.nodes:n.reap(max(0,deadline-time.monotonic()))
            return self.exit_code
    def close_fd(self):
        for n in self.nodes:n.close_fd()


def _parent_hard_watchdog(complete, owner_box, deadline):
    if complete.wait(max(0, deadline - time.monotonic())):
        return
    owner = owner_box[0]
    if owner is not None:
        # If another cleanup call is briefly reaping, do not race its reserved
        # flag or ever signal a PGID after reap. Parent death also triggers BE's
        # own bounded watchdog. A kernel D-state cannot be promised immediate.
        locked = owner.lock.acquire(timeout=.2)
        if locked:
            try:
                try: owner.force()
                except BaseException: pass
            finally:
                owner.lock.release()
    os._exit(2)  # Never kill the FE/user shell process group.


def serve_split(directory, *, lua_executable=None, _loaded=None):
    _linux()
    root, cfg, private = load(directory) if _loaded is None else _loaded
    need(validate_process_options(cfg) == 'split-v1', 'split_process_mode_required')
    production_host_guard(cfg)
    need(not (root / 'started_receipt.json').exists()
         and all(not (root / name).exists() for name in FILES), 'new_process_lab_required')
    from .frontend_experiments import checked_sqlite_environment, checked_sqlite_connection
    sqlite_dependency = checked_sqlite_environment(cfg)
    lua, lua_sha, lua_version = shared.resolve_lua(lua_executable)
    import psycopg
    with psycopg.connect(dsn(cfg, private, admin=True), connect_timeout=3) as conn:
        conn.execute('SET TRANSACTION READ ONLY'); marker_guard(conn, cfg, private, seeded=True)
    nonce = secrets.token_hex(16)
    own = _identity(os.getpid(), ['frontend'])
    owner_box = [None]
    startup_complete = threading.Event()
    # Source/preflight finished; bound all subsequent boot/READY publication
    # and FE constructor waits, even if a blocking call never reaches finally.
    threading.Thread(target=_parent_hard_watchdog,
        args=(startup_complete, owner_box, time.monotonic() + STARTUP_SECONDS + DRAIN_SECONDS + 3),
        daemon=True).start()
    publish(root / 'process_parent_boot.json', {'kind': 'ISOLATED_PROCESS_PARENT_BOOT',
        'run_id': cfg['run_id'], 'manifest_sha256': sha(canonical(cfg)),
        'startup_nonce': nonce, 'parent_identity': own, 'started_monotonic': time.monotonic()})
    stop, exited, expected_exit = threading.Event(), threading.Event(), threading.Event()
    hard_complete = threading.Event()
    pending = threading.Condition(); pending.inflight = 0
    owner = None
    service = web = None
    response_encoder = None
    response_terminal = None
    web_running = False
    started = terminal = None
    child_identity = None
    scope = None
    errors = []
    backend_normal_exit = False
    web_drain = {'drained': True, 'worker_slots_not_drained': 0}
    backend_drain = {'drained': False, 'worker_slots_not_drained': cfg['http_concurrency']}
    old_sigterm = signal.signal(signal.SIGTERM, lambda *_: stop.set())
    try:
        if cfg.get('backend_process_pool'):
            owner=_OwnedBackendPair(root,cfg,lua,nonce);child=owner.child
            owner_box[0]=owner;child_identity=owner.identities[0]
        else:
            child = subprocess.Popen(_backend_argv(root, lua), stdin=subprocess.DEVNULL,
                                     start_new_session=True)
            owner = _OwnedChild(child); owner_box[0] = owner
            owner.group_verified = os.getpgid(child.pid) == child.pid and os.getsid(child.pid) == child.pid
            need(owner.group_verified, 'backend_session_not_owned')
            owner.pidfd = os.pidfd_open(child.pid, 0)
            child_identity = _identity(child.pid, ['backend'])
        deadline = time.monotonic() + STARTUP_SECONDS
        while not (root / 'backend_started_receipt.json').exists():
            need(owner.exit_info() is None, 'backend_exited_before_ready')
            need(not stop.is_set() and time.monotonic() < deadline, 'backend_startup_deadline')
            stop.wait(min(.1, max(0, deadline - time.monotonic())))
        started = _bound(_read(root / 'backend_started_receipt.json'), cfg, nonce,
                         'ISOLATED_BACKEND_PROCESS_STARTED')
        need(started.get('process_identity') == child_identity
             and started.get('process_group') == child.pid
             and started.get('lua_sha256') == lua_sha and started.get('lua_version') == lua_version
             and started.get('actual_catalog_preflight_passed') is True
             and started.get('actual_database_pool_limits_verified') is True,
             'backend_ready_identity_or_preflight_mismatch')
        need(owner.exit_info() is None, 'backend_exited_at_ready')
        def watch():
            try:
                owner.wait_exit()if cfg.get('backend_process_pool')else _not_reaped_exit(owner.pidfd, block=True)
            except BaseException:
                pass
            finally:
                exited.set()
                if not expected_exit.is_set(): stop.set()
        threading.Thread(target=watch, daemon=True).start()
        sys.path.insert(0, str(root / 'runtime'))
        from .identity import IdentityService
        from player_web_auth.http_api import BoundedServer
        service = IdentityService(root, cfg, private, lambda path, raw: shared.forward(private, path, raw))
        sqlite_dependency = checked_sqlite_connection(service, sqlite_dependency)
        from .experiments import has_http_admission, http_admission_backlog, http_admission_wait
        admission = has_http_admission(cfg)
        options = ({'max_concurrency': cfg['web_concurrency'],
                    'request_backlog': http_admission_backlog(cfg, layer='frontend'),
                    'admission_wait_seconds': http_admission_wait(cfg, layer='frontend')}
                   if admission else {})
        response_encoder = shared.prepare_response_encoder(cfg)
        web = BoundedServer(('127.0.0.1', PORTS['web']),
                    shared.frontend_handler(service, cfg, private, stop, pending, response_encoder), **options)
        web.block_on_close = False
        if not admission: web.slots = threading.BoundedSemaphore(cfg['web_concurrency'])
        scope_rows=[own,child_identity]
        if cfg.get('backend_process_pool'):scope_rows.extend(owner.identities[1:])
        if cfg.get('rpc_process_pool'):
            workers=started['rpc_process_pool_started']['worker_lifecycle']['worker_identities']
            need(len(workers)==cfg['rpc_process_pool']['workers'],'rpc_owned_worker_count_mismatch')
            for index,worker in enumerate(workers):
                descriptor=_identity(worker['pid'],['rpc'+str(index)])
                need(descriptor['starttime_ticks']==worker['starttime_ticks'],'rpc_owned_worker_identity_changed')
                scope_rows.append(descriptor)
        scope = publish_scope(root, cfg, scope_rows)
        write_new(root / 'started_receipt.json', {'kind': 'ISOLATED_REAL_API_LAB_STARTED',
            'artifact_root': str(root), 'run_id': cfg['run_id'], 'purpose': cfg['purpose'],
            'http_concurrency': cfg['http_concurrency'], 'database_concurrency': cfg['db_concurrency'],
            'web_concurrency': cfg['web_concurrency'], 'global_http_per_minute': cfg['global_http_per_minute'],
            'registered_accounts': cfg['accounts'], 'max_active': cfg['active'], 'ports': PORTS,
            'wire_mode': cfg.get('wire_mode', 'business-wire-v1'),
            'backend_db_pool': cfg['backend_db_pool'], 'database_pool_limits': cfg['database_pool_limits'],
            'database_pool_parameters': cfg.get('database_pool_parameters'),
            'runtime_experiments': cfg.get('runtime_experiments', []),
            'http_admission_started': {'frontend': shared.checked_http_admission_stats(web, 'frontend', cfg),
                                       'backend': started['http_admission_started']},
            'checkpoint_observation_started': None,
            'checkpoint_observation_by_process': {'frontend': shared.checkpoint_observation_stats(cfg),
                                                  'backend': started['checkpoint_observation_started']},
            'actual_database_pool_limits_verified': True, 'database_pool_started': started['database_pool_started'],
            'rpc_process_pool_started': started.get('rpc_process_pool_started'),
            'requested_postgres_image': cfg.get('postgres_image', 'postgres:17'),
            'topology': cfg.get('topology', 'same_host_database_diagnostic'),
            'requested_local_database_limits': {'memory_mib': cfg['database_memory_mib'],
                                                 'cpus': cfg['database_cpu_limit']},
            'lua_executable': lua, 'lua_sha256': lua_sha, 'lua_version': lua_version,
            'actual_catalog_preflight_passed': True,
            **({'settlement_cache_warmup': started['settlement_cache_warmup']}
               if started.get('settlement_cache_warmup') is not None else {}),
            'synthetic_identity_policy': service.identity_policy(),
            **({'sqlite_dependency': sqlite_dependency} if sqlite_dependency is not None else {}),
            'process_topology': 'split-v1', 'processes': scope,
            'backend_process': {'child_identity': child_identity,
                'start_receipt_sha256': sha((root / 'backend_started_receipt.json').read_bytes())},
            'response_encoding_pool': None if response_encoder is None else response_encoder.snapshot(),
            'steam_calls_enabled': False, 'payment_calls_enabled': False, 'public_listener': False})
        threading.Thread(target=web.serve_forever, daemon=True).start(); web_running = True
        startup_complete.set()
        print(json.dumps({'status': 'LAB_READY', 'run_id': cfg['run_id'],
                         'process_topology': 'split-v1', 'target': 'http://127.0.0.1:' + str(PORTS['web'])}), flush=True)
        stop.wait(cfg['duration_seconds'])
        if exited.is_set() and not expected_exit.is_set(): _safe_error(errors, 'backend_exited_during_measurement')
    except BaseException:
        _safe_error(errors, 'frontend_run_not_completed')
    finally:
        deadline = time.monotonic() + DRAIN_SECONDS
        hard_deadline = deadline + 3
        threading.Thread(target=_parent_hard_watchdog,
            args=(hard_complete, owner_box, hard_deadline), daemon=True).start()
        startup_complete.set()  # Cleanup now has its own shared drain watchdog.
        try:
            if service is not None:
                _best_effort(errors, 'frontend_tracking_not_ended', service.end_tracking)
            if web is not None:
                if web_running: _best_effort(errors, 'frontend_listener_shutdown_failed', web.shutdown)
                web_drain = _best_effort(errors, 'frontend_drain_failed', lambda:
                    shared.drain_server_workers(web, 'slots', cfg['web_concurrency'], deadline),
                    {'drained': False, 'worker_slots_not_drained': cfg['web_concurrency']})
                _best_effort(errors, 'frontend_server_close_failed', web.server_close)
            try:
                with pending:
                    while pending.inflight and time.monotonic() < deadline:
                        pending.wait(min(1, max(0, deadline - time.monotonic())))
            except BaseException:
                _safe_error(errors, 'frontend_pending_drain_failed')
        finally:
            if response_encoder is not None:
                _best_effort(errors,'response_encoder_close_failed',lambda:response_encoder.close(deadline=deadline))
                response_terminal = _best_effort(errors,'response_encoder_snapshot_failed',response_encoder.snapshot,{'pending':1,'forced_workers':1})
                if (response_terminal['pending'] or response_terminal['forced_workers']
                    or not response_terminal.get('manager_joined')
                    or not all(response_terminal.get('worker_exit_confirmed',[]))):
                    _safe_error(errors,'response_encoder_not_cleanly_closed')
            expected_exit.set()
            # This block cannot be skipped by FE shutdown/tracking/publication
            # errors. The hard watchdog covers blocking calls and disk IO.
            try:
                if owner is not None:
                    if owner.pidfd is not None:
                        try:
                            request = root / 'backend_stop_request.json'
                            if not request.exists():
                                publish(request, {'kind': 'ISOLATED_BACKEND_STOP_REQUEST', 'run_id': cfg['run_id'],
                                    'manifest_sha256': sha(canonical(cfg)), 'startup_nonce': nonce,
                                    'deadline_monotonic': deadline,
                                    'frontend_drained': web_drain.get('drained') is True,
                                    'frontend_pending': pending.inflight})
                        except BaseException:
                            _safe_error(errors, 'backend_stop_publication_failed')
                        _best_effort(errors, 'backend_term_signal_failed', owner.term)
                        try:
                            while owner.exit_info() is None and time.monotonic() < deadline:
                                time.sleep(min(.05,max(0,deadline-time.monotonic())))if cfg.get('backend_process_pool')else exited.wait(min(.1, max(0, deadline - time.monotonic())))
                        except BaseException:
                            _safe_error(errors, 'backend_exit_observation_failed')
                        stop_path = root / 'backend_stopped_receipt.json'
                        if stop_path.exists():
                            try:
                                terminal = _bound(_read(stop_path), cfg, nonce, 'ISOLATED_BACKEND_PROCESS_STOPPED')
                                need(terminal.get('process_identity') == child_identity,
                                     'backend_terminal_identity_mismatch')
                                backend_drain = terminal['backend_drain']
                                code = owner.exit_info()
                                backend_normal_exit = (code is not None and code.si_code == os.CLD_EXITED
                                    and code.si_status == 0 and backend_drain.get('drained') is True
                                    and terminal.get('database_pool_closed') is True
                                    and terminal.get('database_pool_close_error') is None
                                    and terminal.get('control_error') is None
                                    and terminal.get('stop_reason') == 'parent_requested'
                                    and terminal.get('frontend_quiescent') is True
                                    and terminal.get('cleanup_errors') == []
                                    and terminal.get('descendant_cleanup_required') is False)
                            except BaseException:
                                _safe_error(errors, 'backend_terminal_invalid'); terminal = None
                    else:
                        _safe_error(errors, 'backend_pidfd_not_available')
                    if not backend_normal_exit or errors:
                        _safe_error(errors, 'backend_exit_or_cleanup_not_confirmed')
                        _best_effort(errors, 'owned_backend_force_failed', owner.force)
                    _best_effort(errors, 'backend_reap_failed', lambda:
                        owner.reap(min(3, max(0, hard_deadline - time.monotonic()))))
                else:
                    _safe_error(errors, 'backend_not_started')
            finally:
                if owner is not None:
                    _best_effort(errors, 'backend_pidfd_close_failed', owner.close_fd)
                # Keep signal restoration and SQLite close independent of all
                # child/proof/statistics/receipt failures. A hang stays watched.
                if service is not None and web_drain.get('drained') is True:
                    _best_effort(errors, 'frontend_service_close_failed', service.close)
                _best_effort(errors, 'frontend_signal_restore_failed', lambda:
                    signal.signal(signal.SIGTERM, old_sigterm))
        drained = (web_drain.get('drained') is True and pending.inflight == 0
                   and backend_drain.get('drained') is True and not errors
                   and owner is not None and not owner.reserved and not owner.forced and owner.exit_code == 0)
        if service is not None:
            value = terminal or {}
            try:
                # Service.close does not mutate cached lease/ready counters.
                stopped = {'kind': 'ISOLATED_LOADTEST_LAB_STOPPED', 'artifact_root': str(root),
                    'run_id': cfg['run_id'], 'requests_accepted': service.request_count,
                    'remaining_http_requests': pending.inflight, 'active_synthetic_leases': service.active,
                    'synthetic_activity': service.counts(), 'synthetic_identity_policy': service.identity_policy(),
                    **({'sqlite_dependency': sqlite_dependency} if sqlite_dependency is not None else {}),
                    'frontend_drain': web_drain, 'backend_drain': backend_drain,
                    'backend_db_pool': cfg['backend_db_pool'],
                    'database_pool_parameters': cfg.get('database_pool_parameters'),
                    'runtime_experiments': cfg.get('runtime_experiments', []),
                    'http_admission_stopped': {'frontend': shared.checked_http_admission_stats(web, 'frontend', cfg)
                        if web is not None else None, 'backend': value.get('http_admission_stopped')},
                    'checkpoint_observation_stopped': None,
                    'checkpoint_observation_by_process': {'frontend': shared.checkpoint_observation_stats(cfg),
                                                          'backend': value.get('checkpoint_observation_stopped')},
                    'actual_database_pool_limits_verified': bool(started),
                    'database_pool_close_deferred': value.get('database_pool_close_deferred', True),
                    'database_pool_closed': value.get('database_pool_closed', False),
                    'database_pool_close_error': value.get('database_pool_close_error', errors[0] if errors else None),
                    'database_pool_stopped': value.get('database_pool_stopped'),
                    'rpc_process_pool_stopped': value.get('rpc_process_pool_stopped'),
                    **({'settlement_cache_warmup': started['settlement_cache_warmup'],
                        'settlement_cache_stopped': value.get('settlement_cache_stopped')}
                       if started is not None and started.get('settlement_cache_warmup') is not None else {}),
                    'process_topology': 'split-v1', 'processes': scope,
                    'backend_process': {'child_identity': child_identity,
                        'exit_code': owner.exit_code if owner is not None else None,
                        'normal_exit': backend_normal_exit,
                        'forced_group_kill': owner.forced if owner is not None else False,
                        'error': errors[0] if errors else None, 'cleanup_errors': list(errors),
                        'start_receipt_sha256': sha((root / 'backend_started_receipt.json').read_bytes())
                            if (root / 'backend_started_receipt.json').is_file() else None,
                        'stop_receipt_sha256': sha((root / 'backend_stopped_receipt.json').read_bytes())
                            if (root / 'backend_stopped_receipt.json').is_file() else None},
                    'response_encoding_pool': response_terminal,
                    'account_state_modified_only_in_lab': True, 'capacity_certified': False}
                write_new(root / 'stopped_receipt.json', stopped)
            except BaseException:
                _safe_error(errors, 'frontend_terminal_publication_failed')
                drained = False
        else:
            _best_effort(errors, 'frontend_start_failure_publication_failed', lambda:
                publish(root / 'process_start_failure_receipt.json', {'kind': 'ISOLATED_PROCESS_START_FAILED',
                    'run_id': cfg['run_id'], 'manifest_sha256': sha(canonical(cfg)),
                    'error': errors[0] if errors else None,
                    'exit_code': owner.exit_code if owner is not None else None,
                    'forced_group_kill': owner.forced if owner is not None else False}))
        if owner is None or not owner.reserved:
            hard_complete.set()
        else:
            _safe_error(errors, 'backend_still_unreaped')
            # Do not disarm the watchdog while an owned child remains live or
            # unreaped, even if this function was called by a test supervisor.
    return 0 if drained and not errors else 2
