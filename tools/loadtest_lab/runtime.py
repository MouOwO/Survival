"""Run unchanged business handlers against an attested synthetic database.

No import side effects. This entry is never added to a production service.
The frontend preserves real SQLite/session/proxy/rate-limit work; Steam consent
is replaced only by the separately authenticated synthetic lease endpoint.
"""
from __future__ import annotations
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit

from .guard import PORTS, load, dsn, marker_guard, production_host_guard, attest, write_new, need, sha

BUSINESS_PATHS = frozenset(('/v1/session/authenticate', '/v1/session/login', '/v1/profile',
    '/v1/archive/config', '/v1/lottery/catalog', '/v1/lottery/snapshot',
    '/v1/archive/command', '/v1/archive/endless-batch', '/v1/online-time/checkpoint'))


def forward(private, path, raw):
    need(path in BUSINESS_PATHS, 'unreviewed_lab_forward_path')
    conn = http.client.HTTPConnection('127.0.0.1', PORTS['backend'], timeout=30)
    try:
        conn.request('POST', path, body=raw, headers={'Authorization': 'Bearer ' + private['backend'],
                     'Content-Type': 'application/json'})
        response = conn.getresponse()
        body = response.read(8*1024*1024 + 1)
        need(len(body) <= 8*1024*1024, 'lab_response_budget_exceeded')
        return response.status, body
    finally:
        conn.close()


def frontend_handler(service, cfg, private, stop, pending):
    from player_web_auth.http_api import handler
    from player_web_auth.service import AuthError
    base = handler(service)

    class Handler(base):
        def do_GET(self):
            try:
                parsed = urlsplit(self.path)
                service.budget(controller=parsed.path in ('/_loadtest/context', '/_loadtest/status'))
                if parsed.path in ('/_loadtest/context', '/_loadtest/status'):
                    if len(self.headers.get_all('Authorization', [])) != 1:
                        raise AuthError('lab_controller_required', 401)
                    service.controller(self.headers.get('Authorization'))
                    query = parse_qs(parsed.query, strict_parsing=True)
                    if set(query) != {'nonce'} or len(query['nonce']) != 1 or not re.fullmatch('[a-f0-9]{32}', query['nonce'][0]):
                        raise AuthError('lab_nonce_required', 400)
                    value = (service.status(query['nonce'][0]) if parsed.path == '/_loadtest/status'
                             else attest(cfg, private, query['nonce'][0]))
                    self.reply(200, value)
                elif self.path == '/health':
                    self.reply(200, {'ok': True, 'service': 'survival-loadtest', 'synthetic_only': True})
                else:
                    self.reply(404, {'ok': False, 'error': 'lab_route_not_found'})
            except AuthError as error:
                self.reply(error.status, {'ok': False, 'error': error.code})
            except Exception:
                self.reply(400, {'ok': False, 'error': 'invalid_lab_request'})

        def do_POST(self):
            with pending:
                pending.inflight += 1
            try:
                service.budget(controller=self.path in (
                    '/_loadtest/identity', '/_loadtest/release', '/_loadtest/ready', '/_loadtest/stop'))
                if self.path in ('/_loadtest/identity', '/_loadtest/release', '/_loadtest/ready', '/_loadtest/stop'):
                    if len(self.headers.get_all('Authorization', [])) != 1:
                        raise AuthError('lab_controller_required', 401)
                    service.controller(self.headers.get('Authorization'))
                    payload = self.body()
                    if self.path == '/_loadtest/identity':
                        value = service.issue(payload)
                    elif self.path == '/_loadtest/release':
                        value = service.release(payload)
                    elif self.path == '/_loadtest/ready':
                        value = service.mark_ready(payload)
                    else:
                        if payload != {'run_id': cfg['run_id']}:
                            raise AuthError('invalid_lab_stop', 400)
                        value = {'ok': True}; stop.set()
                    self.reply(200, value)
                elif self.path in BUSINESS_PATHS:
                    super().do_POST()
                else:
                    self.reply(403, {'ok': False, 'error': 'lab_business_route_not_allowed'})
            except AuthError as error:
                self.reply(error.status, {'ok': False, 'error': error.code})
            except Exception:
                self.reply(503, {'ok': False, 'error': 'lab_request_not_completed'})
            finally:
                with pending:
                    pending.inflight -= 1
                    pending.notify_all()
    return Handler


def resolve_lua(executable=None):
    from pathlib import Path
    selected = shutil.which(executable) if executable else (shutil.which('lua5.1') or shutil.which('lua'))
    need(selected, 'lua_executable_required')
    path = Path(selected).resolve(strict=True)
    result = subprocess.run([str(path), '-e', 'io.write(_VERSION)'], capture_output=True, timeout=5)
    need(result.returncode == 0 and result.stdout in (b'Lua 5.1', b'Lua 5.2', b'Lua 5.3', b'Lua 5.4'),
         'supported_lua_version_required')
    return str(path), sha(path.read_bytes()), result.stdout.decode('ascii')


def drain_server_workers(server, semaphore_name, capacity, deadline):
    """Prove every accepted worker released its slot after shutdown.

    O(capacity) only once at shutdown (HTTP <=32, frontend <=128); no scan of
    players or threads. Holding all slots also covers a thread not yet started.
    Both known servers use daemon worker threads; server_close must not join
    them without the same bounded deadline.
    """
    semaphore = getattr(server, semaphore_name)
    acquired = 0
    try:
        for _ in range(capacity):
            if not semaphore.acquire(timeout=max(0, deadline - time.monotonic())):
                break
            acquired += 1
        return {'drained': acquired == capacity, 'worker_slots_not_drained': capacity - acquired}
    finally:
        for _ in range(acquired):
            semaphore.release()


def checked_database_pool_stats(client, cfg):
    """Fixed O(1) aggregates, including effective constructor budget checks."""
    stats = client.pool_stats()
    limits = cfg['database_pool_limits']
    need(type(stats) is dict and type(stats.get('max_size')) is int
         and type(stats.get('max_waiters')) is int
         and type(stats.get('wait_timeout')) in (int, float)
         and stats['max_size'] == limits['connections']
         and stats['max_waiters'] == limits['waiting']
         and stats['wait_timeout'] == limits['wait_seconds'],
         'actual_database_pool_budget_mismatch')
    return stats


def checked_http_admission_stats(server, layer, cfg):
    """Read fixed counters once at startup/shutdown, with effective limits."""
    from .experiments import has_experiment
    if not has_experiment(cfg, 'http-admission-v1'):
        return None
    stats = server.admission_stats()
    need(type(stats) is dict and stats.get('layer') == layer
         and stats.get('max_concurrency') == (48 if layer == 'frontend' else 32)
         and stats.get('backlog') == 64
         and stats.get('accept_wait_seconds') == (0 if layer == 'frontend' else 2),
         'actual_http_admission_budget_mismatch')
    return stats


def checkpoint_observation_stats(cfg):
    from .experiments import has_experiment
    if not has_experiment(cfg, 'checkpoint-observation-v1'):
        return None
    from archive_backend._checkpoint_observation import observation_stats
    return observation_stats()


def serve(directory, *, lua_executable=None):
    root, cfg, private = load(directory)
    production_host_guard(cfg)
    need(not (root / 'started_receipt.json').exists(), 'lab_run_already_started_create_new_lab')
    lua, lua_sha256, lua_version = resolve_lua(lua_executable)
    import psycopg
    with psycopg.connect(dsn(cfg, private, admin=True), connect_timeout=3) as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        marker_guard(conn, cfg, private, seeded=True)
    sys.path.insert(0, str(root / 'runtime'))
    from fishing_api.config import Settings
    from fishing_api.server import build_application, make_handler, BoundedThreadingHTTPServer
    # Constructor with a complete controlled configuration, never from_env().
    settings = Settings(host='127.0.0.1', port=PORTS['backend'], api_token=private['backend'],
        supabase_url='', supabase_key='', account_id_pepper=private['pepper'],
        reward_csv=root / 'addon/data/csv/玩家档案系统/star_blessing_reward_definitions.csv',
        rule_csv=root / 'addon/data/csv/玩家档案系统/fishing_system_rules.csv',
        gameplay_stats_csv=root / 'addon/data/csv/玩家档案系统/player_gameplay_stats.csv',
        request_timeout_seconds=20, database_backend='postgres', postgres_dsn=dsn(cfg, private),
        postgres_max_concurrency=cfg['db_concurrency'], http_max_concurrency=cfg['http_concurrency'],
        payment_mode='test', archive_http=True, addon_root=root / 'addon', archive_lua_path=lua)
    # Production's optional five-account whitelist is a process setting. This
    # standalone process has its own bounded synthetic gate instead.
    os.environ.pop('SURVIVAL_TEST_STEAM_IDS64', None)
    pool_mode = cfg.get('backend_db_pool') in ('bounded-v1', 'bounded-v2')
    pool_options = ({'pool_max_waiters': cfg['database_pool_limits']['waiting'],
                     'pool_wait_timeout': cfg['database_pool_limits']['wait_seconds']}
                    if cfg.get('backend_db_pool') == 'bounded-v2' else {})
    app = build_application(settings, **pool_options)
    try:
        pool_started = checked_database_pool_stats(app.rpc_client, cfg) if pool_mode else None
    except Exception:
        # No listener or request worker exists yet; a constructor mismatch is
        # startup failure, never a ready lab or an assumed active pool budget.
        app.rpc_client.close()
        raise
    # Verify actual immutable Lua modules/config before opening listeners.
    from archive_backend.lottery_catalog import catalog_document
    catalog_document(app.archive.bundle, lua)
    base = make_handler(app, client_timeout=settings.http_client_timeout_seconds,
                        request_deadline=settings.http_request_deadline_seconds)
    from .identity import IdentityService
    from player_web_auth.http_api import BoundedServer
    service = IdentityService(root, cfg, private, lambda path, raw: forward(private, path, raw))
    stop = threading.Event()
    pending = threading.Condition(); pending.inflight = 0
    from .experiments import has_experiment
    admission_mode = has_experiment(cfg, 'http-admission-v1')
    backend_admission = ({'request_backlog': 64, 'admission_wait_seconds': 2.0}
                         if admission_mode else {})
    backend = BoundedThreadingHTTPServer(('127.0.0.1', PORTS['backend']), base,
                                        max_concurrency=cfg['http_concurrency'], **backend_admission)
    # The lab performs its own finite drain below. Never let ThreadingMixIn
    # add an unbounded join after an incomplete request or socket timeout.
    backend.block_on_close = False
    web = None
    running = []
    try:
        frontend_admission = ({'max_concurrency': cfg['web_concurrency'], 'request_backlog': 64}
                              if admission_mode else {})
        web = BoundedServer(('127.0.0.1', PORTS['web']),
                            frontend_handler(service, cfg, private, stop, pending), **frontend_admission)
        web.block_on_close = False
        if not admission_mode:
            web.slots = threading.BoundedSemaphore(cfg['web_concurrency'])
        frontend_started = checked_http_admission_stats(web, 'frontend', cfg)
        backend_started = checked_http_admission_stats(backend, 'backend', cfg)
        write_new(root / 'started_receipt.json', {'kind': 'ISOLATED_REAL_API_LAB_STARTED',
            'artifact_root': str(root), 'run_id': cfg['run_id'], 'purpose': cfg['purpose'],
            'http_concurrency': cfg['http_concurrency'], 'database_concurrency': cfg['db_concurrency'],
            'web_concurrency': cfg['web_concurrency'], 'global_http_per_minute': cfg['global_http_per_minute'],
            'registered_accounts': cfg['accounts'], 'max_active': cfg['active'], 'ports': PORTS,
            'wire_mode': cfg.get('wire_mode', 'business-wire-v1'),
            'backend_db_pool': cfg.get('backend_db_pool', 'baseline'),
            'database_pool_limits': cfg.get('database_pool_limits'),
            'database_pool_parameters': cfg.get('database_pool_parameters'),
            'runtime_experiments': cfg.get('runtime_experiments', []),
            'http_admission_started': {'frontend': frontend_started, 'backend': backend_started},
            'checkpoint_observation_started': checkpoint_observation_stats(cfg),
            'actual_database_pool_limits_verified': pool_mode,
            'database_pool_started': pool_started,
            'requested_postgres_image': cfg.get('postgres_image', 'postgres:17'),
            'topology': cfg.get('topology', 'same_host_database_diagnostic'),
            'requested_local_database_limits': {
                'memory_mib': cfg.get('database_memory_mib', 256 if cfg['purpose'] == 'functional-smoke' else 8192),
                'cpus': cfg.get('database_cpu_limit', .5 if cfg['purpose'] == 'functional-smoke' else 4)},
            'lua_executable': lua, 'lua_sha256': lua_sha256, 'lua_version': lua_version,
            'actual_catalog_preflight_passed': True,
            'synthetic_identity_policy': service.identity_policy(),
            'steam_calls_enabled': False, 'payment_calls_enabled': False, 'public_listener': False})
        threads = [threading.Thread(target=srv.serve_forever, daemon=True) for srv in (backend, web)]
        for srv, thread in zip((backend, web), threads):
            thread.start()
            running.append(srv)
        print(json.dumps({'status': 'LAB_READY', 'run_id': cfg['run_id'], 'purpose': cfg['purpose'],
                          'target': 'http://127.0.0.1:' + str(PORTS['web'])}), flush=True)
        stop.wait(cfg['duration_seconds'])
    except KeyboardInterrupt:
        stop.set()
    finally:
        # Measurement ends before accepting stops/drain waits. This never
        # cancels authorization for business requests accepted before shutdown.
        service.end_tracking()
        deadline = time.monotonic() + 45
        # Stop accepting new frontend requests while already accepted work can
        # still forward to a live backend. Then prove both handler sets ended.
        web_drain = {'drained': True, 'worker_slots_not_drained': 0}
        if web is not None:
            if web in running:
                web.shutdown()
            web_drain = drain_server_workers(web, 'slots', cfg['web_concurrency'], deadline)
            web.server_close()
        if backend in running:
            backend.shutdown()
        backend_drain = drain_server_workers(backend, '_workers', cfg['http_concurrency'], deadline)
        backend.server_close()
        with pending:
            while pending.inflight and time.monotonic() < deadline:
                pending.wait(min(1, max(0, deadline - time.monotonic())))
        drained = web_drain['drained'] and backend_drain['drained'] and pending.inflight == 0
        pool_closed = None
        pool_close_error = None
        if pool_mode and drained:
            try:
                app.rpc_client.close()
            except Exception:
                pool_closed = False
                pool_close_error = 'database_pool_close_not_completed'
        pool_stats = checked_database_pool_stats(app.rpc_client, cfg) if pool_mode else None
        if pool_mode and drained and pool_closed is not False:
            pool_closed = pool_stats.get('closed') is True and pool_stats.get('total') == 0
            if not pool_closed:
                pool_close_error = 'database_pool_close_not_completed'
        write_new(root / 'stopped_receipt.json', {'kind': 'ISOLATED_LOADTEST_LAB_STOPPED',
            'artifact_root': str(root), 'run_id': cfg['run_id'], 'requests_accepted': service.request_count,
            'remaining_http_requests': pending.inflight, 'active_synthetic_leases': service.active,
            'synthetic_activity': service.counts(),
            'synthetic_identity_policy': service.identity_policy(),
            'frontend_drain': web_drain, 'backend_drain': backend_drain,
            'backend_db_pool': cfg.get('backend_db_pool', 'baseline'),
            'database_pool_parameters': cfg.get('database_pool_parameters'),
            'runtime_experiments': cfg.get('runtime_experiments', []),
            'http_admission_stopped': {
                'frontend': checked_http_admission_stats(web, 'frontend', cfg) if web is not None else None,
                'backend': checked_http_admission_stats(backend, 'backend', cfg)},
            'checkpoint_observation_stopped': checkpoint_observation_stats(cfg),
            'actual_database_pool_limits_verified': pool_mode,
            'database_pool_close_deferred': pool_mode and not drained,
            'database_pool_closed': pool_closed, 'database_pool_close_error': pool_close_error,
            'database_pool_stopped': pool_stats,
            'account_state_modified_only_in_lab': True, 'capacity_certified': False})
        if web_drain['drained']:
            service.close()
    return 0 if drained and pool_closed is not False else 2
