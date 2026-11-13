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
                service.budget()
                parsed = urlsplit(self.path)
                if parsed.path == '/_loadtest/context':
                    service.controller(self.headers.get('Authorization'))
                    query = parse_qs(parsed.query, strict_parsing=True)
                    if set(query) != {'nonce'} or len(query['nonce']) != 1 or not re.fullmatch('[a-f0-9]{32}', query['nonce'][0]):
                        raise AuthError('lab_nonce_required', 400)
                    self.reply(200, attest(cfg, private, query['nonce'][0]))
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
                service.budget()
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
    app = build_application(settings)
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
    backend = BoundedThreadingHTTPServer(('127.0.0.1', PORTS['backend']), base,
                                        max_concurrency=cfg['http_concurrency'])
    web = None
    running = []
    try:
        web = BoundedServer(('127.0.0.1', PORTS['web']), frontend_handler(service, cfg, private, stop, pending))
        web.slots = threading.BoundedSemaphore(cfg['web_concurrency'])
        write_new(root / 'started_receipt.json', {'kind': 'ISOLATED_REAL_API_LAB_STARTED',
            'artifact_root': str(root), 'run_id': cfg['run_id'], 'purpose': cfg['purpose'],
            'http_concurrency': cfg['http_concurrency'], 'database_concurrency': cfg['db_concurrency'],
            'web_concurrency': cfg['web_concurrency'], 'global_http_per_minute': cfg['global_http_per_minute'],
            'registered_accounts': cfg['accounts'], 'max_active': cfg['active'], 'ports': PORTS,
            'wire_mode': cfg.get('wire_mode', 'business-wire-v1'),
            'requested_local_database_limits': {
                'memory_mib': cfg.get('database_memory_mib', 256 if cfg['purpose'] == 'functional-smoke' else 8192),
                'cpus': cfg.get('database_cpu_limit', .5 if cfg['purpose'] == 'functional-smoke' else 4)},
            'lua_executable': lua, 'lua_sha256': lua_sha256, 'lua_version': lua_version,
            'actual_catalog_preflight_passed': True,
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
        if backend in running:
            backend.shutdown()
        backend.server_close()
        if web is not None:
            if web in running:
                web.shutdown()
            web.server_close()
        deadline = time.monotonic() + 45
        with pending:
            while pending.inflight and time.monotonic() < deadline:
                pending.wait(min(1, max(0, deadline - time.monotonic())))
        write_new(root / 'stopped_receipt.json', {'kind': 'ISOLATED_LOADTEST_LAB_STOPPED',
            'artifact_root': str(root), 'run_id': cfg['run_id'], 'requests_accepted': service.request_count,
            'remaining_http_requests': pending.inflight, 'active_synthetic_leases': service.active,
            'synthetic_activity': service.counts(),
            'account_state_modified_only_in_lab': True, 'capacity_certified': False})
        service.close()
    return 0 if pending.inflight == 0 else 2
