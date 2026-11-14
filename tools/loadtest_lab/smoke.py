"""Small real-HTTP transaction verification; never a capacity test."""
from __future__ import annotations
import http.client
import json
from pathlib import Path
import secrets
import time

from .guard import PORTS, load_client, target_url, write_new, need, verify_attestation
from .workload import Player, BusinessFailure, checked, persisted_fingerprint
from .wire_client import WireClient, WIRE_MODE, http_error_label


class JsonTransport:
    def __init__(self, *, wire_mode=WIRE_MODE):
        self.requests = 0
        self.timings = {}
        self.wire = WireClient(wire_mode)

    def __call__(self, method, path, body, authorization, name):
        conn = http.client.HTTPConnection('127.0.0.1', PORTS['web'], timeout=35)
        started = time.monotonic()
        try:
            raw = None if body is None else json.dumps(body, separators=(',', ':')).encode()
            conn.request(method, path, body=raw, headers=self.wire.headers(method, path, authorization))
            response = conn.getresponse(); data = response.read(8*1024*1024 + 1)
            need(len(data) <= 8*1024*1024, 'response_budget_exceeded')
            try:
                value = self.wire.decode(method, path, data, response.status, request_body=body)
            except Exception:
                if response.status != 200:
                    raise BusinessFailure(http_error_label(response.status, None)) from None
                raise
            if response.status != 200:
                raise BusinessFailure(http_error_label(response.status, value))
            return checked(value)
        finally:
            self.requests += 1
            elapsed = round((time.monotonic() - started) * 1000, 2)
            self.timings.setdefault(name, []).append(elapsed)
            conn.close()


def stop_lab(client_path):
    cfg, controller = load_client(client_path)
    transport = JsonTransport(wire_mode=cfg.get('wire_mode', WIRE_MODE)); nonce = secrets.token_hex(16)
    value = transport('GET', '/_loadtest/context?nonce=' + nonce, None,
                      'Bearer ' + controller, 'attestation')
    verify_attestation(value, cfg, controller, nonce)
    return transport('POST', '/_loadtest/stop', {'run_id': cfg['run_id']}, 'Bearer ' + controller, 'stop')


def smoke(directory, *, stop=False):
    root = Path(directory).resolve()
    cfg, controller = load_client(root / 'client.json')
    transport = JsonTransport(wire_mode=cfg.get('wire_mode', WIRE_MODE))
    a, b = (Player(transport, cfg, controller) for _ in range(2))
    need(cfg['active'] >= 2, 'two_active_fixture_accounts_required_for_smoke')
    success, reason, cleanup_failures = False, None, 0
    try:
        a.start(); b.start()
        before_b = persisted_fingerprint(b.read_profile())
        before = a.read_profile()['save'].get('content_inventory', {}).get('lottery_ticket', 0)
        a.draw(replay=True)
        after = a.read_profile()['save'].get('content_inventory', {}).get('lottery_ticket', 0)
        need(before - after == 10, 'draw_debit_not_exactly_ten_once')
        a.claim(replay=True)
        a.local_view() if cfg.get('client_workload') == 'client-v3' else a.snapshot()
        a.catalog()
        a.catalog(force_miss=True)
        a.endless_batch(32, replay=True)
        need(before_b == persisted_fingerprint(b.read_profile()), 'another_account_changed')
        success = True
    except Exception as error:
        import re
        value = str(error)
        reason = value if re.fullmatch('[a-z0-9_:]{1,100}', value) else 'smoke_transaction_not_confirmed'
    finally:
        for player in (a, b):
            try:
                player.stop()
            except Exception:
                cleanup_failures += 1
        if stop:
            try:
                stop_lab(root / 'client.json')
            except Exception:
                cleanup_failures += 1
    receipt = {'kind': 'REAL_API_SYNTHETIC_TRANSACTION_SMOKE', 'artifact_root': str(root),
        'run_id': cfg['run_id'], 'ok': success and cleanup_failures == 0, 'error': reason,
        'cleanup_failures': cleanup_failures, 'http_requests': transport.requests,
        'business_wire': transport.wire.report(),
        'http_timing_scope': 'request_elapsed_includes_client_wire_decode',
        'request_elapsed_ms': transport.timings, 'draws': a.draws,
        'idempotent_mutation_replays_verified': a.replays_verified,
        'endless_batches': a.endless_batches, 'endless_waves': a.endless_waves,
        'catalog_requests': a.catalog_requests, 'catalog_hits': a.catalog_hits,
        'catalog_md5': a.catalog_md5,
        'other_account_unchanged': success, 'real_player_accounts_used': 0,
        'steam_calls': 0, 'payment_calls': 0, 'capacity_test': False, 'capacity_certified': False}
    path = root / ('smoke_' + secrets.token_hex(8) + '_verification.json')
    write_new(path, receipt)
    return {k: v for k, v in receipt.items() if k != 'request_elapsed_ms'} | {'receipt': str(path)}
