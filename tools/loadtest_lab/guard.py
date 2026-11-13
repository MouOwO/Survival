"""Fail-closed boundaries for synthetic identities and isolated databases."""
from __future__ import annotations
import hashlib
import hmac
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import socket
from urllib.parse import urlsplit

PORTS = {'database': 25432, 'backend': 29565, 'web': 29567}
ACCOUNT_START = 4000000000
MAX_ACCOUNTS = 100000
MAX_ACTIVE = 4000
DEFAULT_POSTGRES_IMAGE = 'postgres:17'
POSTGRES_IMAGE = re.compile(
    r'(?:docker\.io/library/postgres|public\.ecr\.aws/docker/library/postgres)@sha256:[a-f0-9]{64}\Z')


def need(value, code):
    if not value:
        raise ValueError(code)


def validate_postgres_image(value, *, allow_default=False):
    """Only known official repositories and immutable lowercase SHA256 digests.

    The historical default is accepted only when reading a manifest or using
    the omitted CLI option. Explicit CLI values must always pin a digest.
    """
    if allow_default and value == DEFAULT_POSTGRES_IMAGE:
        return value
    need(type(value) is str and POSTGRES_IMAGE.fullmatch(value), 'lab_postgres_image_invalid')
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def relative(name):
    p = PurePosixPath(name)
    need(isinstance(name, str) and '\\' not in name and not p.is_absolute()
         and bool(p.parts) and all(v not in ('..', '.', '') for v in p.parts), 'invalid_lab_relative_path')
    return p


def read_json(path):
    path = Path(path)
    need(path.is_file() and not path.is_symlink() and path.stat().st_size < 8*1024*1024, 'invalid_lab_document')
    return json.loads(path.read_bytes())


def write_new(path, value):
    path = Path(path)
    with path.open('xb') as stream:
        stream.write(canonical(value) + b'\n'); stream.flush(); os.fsync(stream.fileno())
    path.chmod(0o600)


def register_storage(receipt):
    """Windows ledger is authoritative. Remote receipts must be harvested first."""
    import subprocess
    import sys
    ledger = Path(__file__).resolve().parents[2] / 'tools/release_storage_ledger.py'
    if os.name != 'nt' or not ledger.is_file():
        return {'status': 'PENDING_LOCAL_LEDGER_IMPORT', 'receipt_preserved': str(receipt)}
    result = subprocess.run([sys.executable, '-X', 'utf8', '-B', str(ledger), 'record',
                             '--receipt', str(receipt)], capture_output=True)
    if result.returncode:
        return {'status': 'REGISTRATION_FAILED_RECEIPT_PRESERVED', 'receipt': str(receipt)}
    return json.loads(result.stdout)


def resolve_database_pool(mode, *, http_concurrency=None, db_concurrency=4,
                          web_concurrency=24, pool_max_waiters=None,
                          pool_wait_seconds=None):
    """Resolve explicit inputs once; baseline/v1 retain their historical defaults."""
    need(mode in ('baseline', 'bounded-v1', 'bounded-v2'), 'lab_database_pool_mode_invalid')
    requested = {'http_concurrency': http_concurrency, 'db_concurrency': db_concurrency,
                 'web_concurrency': web_concurrency, 'pool_max_waiters': pool_max_waiters,
                 'pool_wait_seconds': pool_wait_seconds}
    http = (24 if mode == 'bounded-v2' else 8) if http_concurrency is None else http_concurrency
    for value, maximum in ((http, 32), (db_concurrency, 16), (web_concurrency, 128)):
        need(type(value) is int and 1 <= value <= maximum, 'lab_concurrency_budget_invalid')
    limits = None
    if mode != 'baseline':
        need(db_concurrency == 4, 'reviewed_database_pool_requires_four_connections')
        if mode == 'bounded-v1':
            need(pool_max_waiters is None and pool_wait_seconds is None,
                 'bounded_v1_pool_parameters_are_fixed')
            waiting, wait = 4, 2
        else:
            waiting = 20 if pool_max_waiters is None else pool_max_waiters
            wait = 2 if pool_wait_seconds is None else pool_wait_seconds
            need(type(waiting) is int and 0 <= waiting <= 32, 'lab_database_pool_queue_invalid')
            need(type(wait) in (int, float) and math.isfinite(wait) and 0 < wait <= 5,
                 'lab_database_pool_wait_invalid')
            need(http <= db_concurrency + waiting, 'http_exceeds_database_pool_admission_budget')
        limits = {'connections': db_concurrency, 'waiting': waiting, 'wait_seconds': wait}
    else:
        need(pool_max_waiters is None and pool_wait_seconds is None,
             'baseline_database_pool_parameters_forbidden')
    effective = {'http_concurrency': http, 'db_concurrency': db_concurrency,
                 'web_concurrency': web_concurrency,
                 'pool_max_waiters': None if limits is None else limits['waiting'],
                 'pool_wait_seconds': None if limits is None else limits['wait_seconds']}
    return {'requested': requested, 'effective': effective}, limits


def validate_database_pool(cfg):
    """Fixed reviewed experiment budgets and source bindings, once per load."""
    from .experiments import validate_experiments
    restored = validate_experiments(cfg)
    mode = cfg.get('backend_db_pool', 'baseline')
    need(mode in ('baseline', 'bounded-v1', 'bounded-v2'), 'lab_database_pool_mode_invalid')
    parameters = cfg.get('database_pool_parameters')
    if parameters is not None:
        keys = {'http_concurrency', 'db_concurrency', 'web_concurrency',
                'pool_max_waiters', 'pool_wait_seconds'}
        need(type(parameters) is dict and set(parameters) == {'requested', 'effective'}
             and type(parameters['requested']) is dict and set(parameters['requested']) == keys
             and type(parameters['effective']) is dict and set(parameters['effective']) == keys,
             'database_pool_parameter_audit_invalid')
        resolved, limits = resolve_database_pool(mode, **parameters['requested'])
        need(parameters == resolved and cfg.get('database_pool_limits') == limits
             and all(cfg.get(k) == resolved['effective'][k]
                     for k in ('http_concurrency', 'db_concurrency', 'web_concurrency')),
             'database_pool_requested_effective_mismatch')
    elif mode == 'bounded-v2':
        need(False, 'bounded_v2_parameter_audit_required')
    if mode == 'baseline':
        need(cfg.get('database_pool_limits') is None and cfg.get('backend_overlay') is None,
             'baseline_database_pool_overlay_forbidden')
        return mode
    if mode == 'bounded-v1':
        need(cfg.get('db_concurrency') == 4 and cfg.get('database_pool_limits') ==
             {'connections': 4, 'waiting': 4, 'wait_seconds': 2},
             'reviewed_database_pool_limits_changed')
    overlay = cfg.get('backend_overlay')
    need(type(overlay) is dict and set(overlay) == {
        'id', 'source_revision', 'overlay_sources', 'parent_runtime_sha256',
        'runtime_sha256', 'helper_sha256'}, 'reviewed_database_pool_binding_required')
    need(overlay['id'] == mode and overlay['source_revision'] == cfg.get('csv_source_revision')
         and type(overlay['source_revision']) is str
         and re.fullmatch('[a-f0-9]{40}', overlay['source_revision']),
         'database_pool_operator_revision_mismatch')
    patch_names = ('db_pool_patch.py', 'db_pool_http_patch.py', 'bounded_pool.py')
    if mode == 'bounded-v2':
        patch_names += ('db_pool_patch_v2.py',)
    expected = {'server/fishing_api_overrides/' + name for name in patch_names}
    need(type(overlay['overlay_sources']) is dict and set(overlay['overlay_sources']) == expected,
         'database_pool_overlay_sources_invalid')
    digests = list(overlay['overlay_sources'].values()) + [overlay['helper_sha256']]
    for key in ('parent_runtime_sha256', 'runtime_sha256'):
        need(type(overlay[key]) is dict and set(overlay[key]) ==
             {'postgres.py', 'server.py', 'http_request_timing.py'},
             'database_pool_transport_binding_invalid')
        digests.extend(overlay[key].values())
    need(all(type(value) is str and re.fullmatch('[a-f0-9]{64}', value) for value in digests),
         'database_pool_binding_digest_invalid')
    sources = cfg.get('sources', {})
    for name in patch_names:
        target = ('runtime/fishing_api/_bounded_pool.py' if name == 'bounded_pool.py'
                  else 'operator/db_pool_overlays/' + name)
        need(restored.get(target, sources.get(target)) ==
             overlay['overlay_sources']['server/fishing_api_overrides/' + name],
             'database_pool_overlay_hash_mismatch')
    need(restored.get('runtime/fishing_api/_bounded_pool.py',
                      sources.get('runtime/fishing_api/_bounded_pool.py')) == overlay['helper_sha256'],
         'database_pool_helper_hash_mismatch')
    for name, target in (('postgres.py', 'runtime/fishing_api/postgres.py'),
                         ('server.py', 'runtime/fishing_api/server.py'),
                         ('http_request_timing.py', 'runtime/archive_backend/http_request_timing.py')):
        need(restored.get(target, sources.get(target)) == overlay['runtime_sha256'][name]
             and overlay['parent_runtime_sha256'][name] != overlay['runtime_sha256'][name],
             'database_pool_transport_hash_mismatch')
    return mode


def load(directory):
    root = Path(directory).resolve()
    need(not Path(directory).is_symlink(), 'lab_symlink_refused')
    cfg = read_json(root / 'lab.json')
    private = read_json(root / 'private.json')
    need(cfg.get('schema') == 1 and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST', 'explicit_lab_manifest_required')
    run = cfg.get('run_id', '')
    need(bool(re.fullmatch('[a-f0-9]{32}', run)), 'invalid_lab_run_id')
    need(cfg.get('database') == 'survival_loadtest_' + run, 'isolated_database_name_required')
    need(cfg.get('ports') == PORTS and cfg.get('account_start') == ACCOUNT_START, 'fixed_lab_namespace_required')
    need(type(cfg.get('accounts')) is int and 1 <= cfg['accounts'] <= MAX_ACCOUNTS, 'lab_account_budget_invalid')
    need(type(cfg.get('active')) is int and 1 <= cfg['active'] <= min(MAX_ACTIVE, cfg['accounts']), 'lab_active_budget_invalid')
    need(cfg.get('purpose') in ('capacity', 'functional-smoke'), 'lab_purpose_required')
    need(type(cfg.get('duration_seconds')) is int and 60 <= cfg['duration_seconds'] <= 18000, 'lab_duration_budget_invalid')
    if cfg['purpose'] == 'functional-smoke':
        need(cfg['active'] <= 5 and cfg['accounts'] <= 10 and cfg['duration_seconds'] <= 180,
             'functional_smoke_budget_exceeded')
    need(cfg.get('wire_mode', 'business-wire-v1') in ('business-wire-v1', 'legacy-json'),
         'lab_wire_mode_invalid')
    validate_postgres_image(cfg.get('postgres_image', DEFAULT_POSTGRES_IMAGE), allow_default=True)
    catalog_md5 = cfg.get('lottery_catalog_md5')
    need(catalog_md5 is None or type(catalog_md5) is str and re.fullmatch('[a-f0-9]{32}', catalog_md5),
         'lab_catalog_seed_invalid')
    memory = cfg.get('database_memory_mib', 256 if cfg['purpose'] == 'functional-smoke' else 8192)
    cpu = cfg.get('database_cpu_limit', .5 if cfg['purpose'] == 'functional-smoke' else 4)
    need(type(memory) is int and 256 <= memory <= 32768, 'lab_database_memory_budget_invalid')
    need(type(cpu) in (int, float) and .25 <= cpu <= 16, 'lab_database_cpu_budget_invalid')
    if cfg['purpose'] == 'functional-smoke':
        need(memory <= 512 and cpu <= 1, 'functional_smoke_database_budget_exceeded')
    for key in ('controller', 'backend', 'auth_secret', 'pepper', 'database_admin', 'database_app', 'marker'):
        need(bool(re.fullmatch('[a-f0-9]{64}', private.get(key, ''))), 'independent_lab_secret_required')
    need(len(set(private.values())) == 7, 'lab_secrets_must_be_independent')
    for key, limit in (('http_concurrency', 32), ('db_concurrency', 16), ('web_concurrency', 128),
                       ('global_http_per_minute', 1000000)):
        need(type(cfg.get(key)) is int and 1 <= cfg[key] <= limit, 'lab_concurrency_budget_invalid')
    validate_database_pool(cfg)
    sources = cfg.get('sources')
    need(isinstance(sources, dict) and 1 <= len(sources) <= 300, 'pinned_lab_sources_required')
    for name, digest in sources.items():
        path = root.joinpath(*relative(name).parts)
        need(path.resolve().is_relative_to(root) and not path.is_symlink() and path.is_file()
             and sha(path.read_bytes()) == digest, 'lab_source_changed:' + name)
    return root, cfg, private


def account(cfg, index):
    need(type(index) is int and 0 <= index < cfg['accounts'], 'synthetic_account_out_of_range')
    return str(ACCOUNT_START + index)


def database_account(private, raw_account):
    return hmac.new(private['pepper'].encode('ascii'), raw_account.encode('ascii'), hashlib.sha256).hexdigest()


def target_url(value):
    p = urlsplit(value)
    need(value == 'http://127.0.0.1:' + str(PORTS['web']) and p.hostname == '127.0.0.1',
         'only_fixed_loopback_lab_target_allowed')
    return value


def dsn(cfg, private, *, admin=False):
    # No inherited service files, hostaddr, multi-host DSNs or production ports.
    user = 'postgres' if admin else 'goufayu_app'
    password = private['database_admin' if admin else 'database_app']
    return ('host=127.0.0.1 port=' + str(PORTS['database']) + ' dbname=' + cfg['database']
            + ' user=' + user + ' password=' + password)


def marker_guard(conn, cfg, private, *, seeded=False):
    actual = conn.execute('SELECT current_database(),host(inet_server_addr()),inet_server_port()').fetchone()
    need(actual == (cfg['database'], '127.0.0.1', PORTS['database']), 'database_endpoint_scope_mismatch')
    row = conn.execute('SELECT run_id,proof,manifest_sha256,seeded FROM loadtest_lab.marker WHERE singleton').fetchone()
    need(row is not None and row[:3] == (cfg['run_id'], private['marker'], sha(canonical(cfg))),
         'database_lab_marker_mismatch')
    if seeded:
        need(row[3] is True, 'synthetic_seed_not_complete')


def production_host_guard(cfg):
    """One startup check, never a per-request scan. Capacity requires its own host."""
    if cfg['purpose'] != 'capacity':
        return
    for port in (15432, 18765, 18767, 18769):
        with socket.socket() as sock:
            sock.settimeout(.2)
            need(sock.connect_ex(('127.0.0.1', port)) != 0, 'production_service_on_capacity_host')
    # Startup only: keep capacity for the application on a small shared host.
    # Preserve old declared budgets, refusing an oversized old local-DB lab
    # instead of silently changing the meaning of an immutable experiment.
    if os.name == 'posix' and Path('/proc/meminfo').is_file():
        memory_kib = None
        for line in Path('/proc/meminfo').read_text().splitlines():
            if line.startswith('MemTotal:'):
                memory_kib = int(line.split()[1])
                break
        requested_memory = cfg.get('database_memory_mib', 8192)
        requested_cpu = cfg.get('database_cpu_limit', 4)
        need(memory_kib is not None and requested_memory * 1024 <= memory_kib * .6,
             'local_database_leaves_insufficient_host_memory')
        need(requested_cpu <= (os.cpu_count() or 1) * .5,
             'local_database_leaves_insufficient_host_cpu')


def attest(cfg, private, nonce):
    value = {'run_id': cfg['run_id'], 'database': cfg['database'], 'purpose': cfg['purpose'],
             'nonce': nonce, 'synthetic_only': True, 'manifest_sha256': sha(canonical(cfg))}
    return {**value, 'signature': hmac.new(private['controller'].encode(), canonical(value), hashlib.sha256).hexdigest()}


def verify_attestation(value, cfg, controller, nonce):
    expected = {'run_id': cfg['run_id'], 'database': cfg['database'], 'purpose': cfg['purpose'],
                'nonce': nonce, 'synthetic_only': True, 'manifest_sha256': sha(canonical(cfg))}
    signature = hmac.new(controller.encode(), canonical(expected), hashlib.sha256).hexdigest()
    need(isinstance(value, dict) and set(value) == {*expected, 'signature'}
         and all(value[k] == v for k, v in expected.items())
         and hmac.compare_digest(value.get('signature', ''), signature), 'lab_target_attestation_failed')


def load_client(path):
    value = read_json(path)
    cfg, controller = value.get('config', {}), value.get('controller', '')
    need(value.get('manifest_sha256') == sha(canonical(cfg)) and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
         and cfg.get('ports') == PORTS and re.fullmatch('[a-f0-9]{32}', cfg.get('run_id', ''))
         and re.fullmatch('[a-f0-9]{64}', controller), 'invalid_lab_client_configuration')
    need(cfg.get('database') == 'survival_loadtest_' + cfg['run_id'] and cfg.get('account_start') == ACCOUNT_START
         and type(cfg.get('active')) is int and 1 <= cfg['active'] <= MAX_ACTIVE
         and type(cfg.get('accounts')) is int and cfg['active'] <= cfg['accounts'] <= MAX_ACCOUNTS,
         'invalid_lab_client_namespace')
    need(cfg.get('wire_mode', 'business-wire-v1') in ('business-wire-v1', 'legacy-json'),
         'lab_wire_mode_invalid')
    validate_postgres_image(cfg.get('postgres_image', DEFAULT_POSTGRES_IMAGE), allow_default=True)
    return cfg, controller
