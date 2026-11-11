"""Fail-closed boundaries for synthetic identities and isolated databases."""
from __future__ import annotations
import hashlib
import hmac
import json
import os
from pathlib import Path, PurePosixPath
import re
import socket
from urllib.parse import urlsplit

PORTS = {'database': 25432, 'backend': 29565, 'web': 29567}
ACCOUNT_START = 4000000000
MAX_ACCOUNTS = 100000
MAX_ACTIVE = 4000


def need(value, code):
    if not value:
        raise ValueError(code)


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
    for key in ('controller', 'backend', 'auth_secret', 'pepper', 'database_admin', 'database_app', 'marker'):
        need(bool(re.fullmatch('[a-f0-9]{64}', private.get(key, ''))), 'independent_lab_secret_required')
    need(len(set(private.values())) == 7, 'lab_secrets_must_be_independent')
    for key, limit in (('http_concurrency', 128), ('db_concurrency', 16), ('web_concurrency', 128),
                       ('global_http_per_minute', 1000000)):
        need(type(cfg.get(key)) is int and 1 <= cfg[key] <= limit, 'lab_concurrency_budget_invalid')
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
    actual = conn.execute('SELECT current_database(),inet_server_addr()::text,inet_server_port()').fetchone()
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
    return cfg, controller
