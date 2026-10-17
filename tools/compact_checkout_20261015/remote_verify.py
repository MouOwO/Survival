"""SSH-stdin post-release checks. Read-only: no login/session/order/gateway call.

Execute from a reviewed runner with the current payment virtualenv interpreter.
Only loopback health and authenticated /catalog are requested; private identity,
configuration values, sessions, tokens, order records and key material are never
printed, including on failure.
"""
import hashlib
import hmac
import json
from pathlib import Path
import sys
import urllib.request

PAY = Path('/opt/goufayu/payments/20261015-payment02')
OLD = Path('/opt/goufayu/payments/20261015-payment01')
ARCHIVE = Path('/opt/goufayu/releases/current')
ARCHIVE_NAME = '20261015-video-bundles-v1'
ARCHIVE_HASH = 'dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
CATALOG_HASH = 'b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe'
BUNDLES = {
    'video_bundle_b001': (4768, True, 59600),
    'video_bundle_b002': (4768, True, 59600),
    'video_bundle_b003': (4656, False, 58200),
    'video_bundle_b004': (2200, True, 27500),
    'video_bundle_b005': (8112, False, 101400),
    'video_bundle_vip_01': (192, True, 2400),
    'video_bundle_vip_02': (448, True, 5600),
    'video_bundle_vip_03': (848, True, 10600),
    'video_bundle_vip_04': (1248, True, 15600),
    'video_bundle_vip_05': (1728, True, 21600),
    'video_bundle_vip_06': (2368, True, 29600),
    'video_bundle_vip_07': (2688, True, 33600),
    'video_bundle_vip_08': (3808, True, 47600),
    'video_bundle_vip_09': (4288, True, 53600),
    'video_bundle_vip_10': (4768, True, 59600),
}


class VerificationError(Exception):
    pass


def require(condition, code):
    if not condition:
        raise VerificationError(code)


def current_versions():
    require(Path('/opt/goufayu/payments/current').resolve() == PAY, 'payment_current_mismatch')
    require(ARCHIVE.resolve().name == ARCHIVE_NAME, 'archive_current_mismatch')
    pointer = json.loads((ARCHIVE / 'addon/server/bundles/current.json').read_text(encoding='utf-8'))
    require(pointer.get('hash') == ARCHIVE_HASH, 'archive_bundle_mismatch')


def main():
    current_versions()
    sys.path.insert(0, str(PAY))
    from deploy import connection
    from payment_backend.upgrade_order_quantity import verify_scope
    verify_scope(OLD)
    cfg = json.loads(Path('/etc/goufayu-payment/config.json').read_text(encoding='utf-8'))
    session_body, db_products = None, {}
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            state = conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()
            require(state is not None and state[0] == CATALOG_HASH, 'catalog_hash_mismatch')
            rows = conn.execute('''SELECT sku,amount,enabled,grants,purchase_limit,item_id
                FROM payments.products ORDER BY sku''').fetchall()
            db_products = {row[0]: dict(amount=row[1], enabled=row[2], grants=row[3],
                           purchase_limit=row[4], item_id=row[5]) for row in rows}
            require(len(db_products) == len(rows), 'duplicate_database_sku')
            bundles = {sku: p for sku, p in db_products.items() if sku.startswith('video_bundle_')}
            require(set(bundles) == set(BUNDLES), 'bundle_set_mismatch')
            for sku, (amount, enabled, original) in BUNDLES.items():
                p = bundles[sku]
                require((p['amount'], p['enabled'], p['purchase_limit']) == (amount, enabled, 1), 'bundle_price_status_or_limit_changed')
                pricing = p['grants'].get('pricing', {})
                require(pricing == dict(u_coin_price=amount*10, u_coin_per_yuan=1000,
                         original_u_coin_price=original), 'bundle_pricing_changed')
                if sku.startswith('video_bundle_vip_'):
                    require(p['grants'].get('required_vip_level') == int(sku[-2:]), 'vip_gate_changed')
            require(sum(p['enabled'] is True for p in bundles.values()) == 13, 'bundle_enabled_count_changed')
            # Reuse only a session already belonging to the configured authorized
            # account list. Never call a login, refresh, sync or order endpoint.
            for account in cfg['allowed_accounts']:
                hashed = hmac.new(cfg['pepper'].encode(), str(account).encode(), hashlib.sha256).hexdigest()
                existing = conn.execute('''SELECT match_session_id FROM public.match_profile_sessions
                    WHERE account_id=%s ORDER BY created_at DESC LIMIT 1''', (hashed,)).fetchone()
                if existing:
                    session_body = {'account_id': str(account), 'match_session_id': existing[0]}
                    break
        finally:
            conn.rollback()
    require(session_body is not None, 'no_existing_authorized_test_session')
    request = urllib.request.Request('http://127.0.0.1:8766/v1/payments/catalog',
        data=json.dumps(session_body).encode(), method='POST',
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + cfg['game_token']})
    with urllib.request.urlopen(request, timeout=20) as response:
        require(response.status == 200, 'catalog_http_status')
        catalog = json.load(response)
    require(catalog.get('ok') is True and catalog.get('catalog_hash') == CATALOG_HASH,
            'http_catalog_identity')
    require(catalog.get('u_coin_per_yuan') == 1000, 'exchange_rate_changed')
    products = catalog.get('products')
    require(isinstance(products, list), 'http_catalog_products_missing')
    http_products = {p['sku']: p for p in products}
    require(len(http_products) == len(products), 'duplicate_http_sku')
    enabled = {sku for sku, p in db_products.items() if p['enabled'] is True}
    require(set(http_products) == enabled, 'http_active_catalog_set_mismatch')
    limited_checked = 0
    for sku, p in http_products.items():
        expected = db_products[sku]
        amount, maximum = p.get('amount_fen'), p.get('max_quantity')
        require(type(amount) is int and amount == expected['amount'] and 1 <= amount <= 1000000,
                'http_authoritative_amount_mismatch')
        require(type(maximum) is int and 0 <= maximum <= 100, 'http_max_quantity_missing_or_invalid')
        require(type(p.get('unit_amount_fen')) is int and p['unit_amount_fen'] == amount,
                'http_unit_amount_mismatch')
        require(type(p.get('u_coin_price')) is int and p['u_coin_price'] == amount*10,
                'http_unit_ucoin_price_mismatch')
        require(type(p.get('unit_u_coin_price')) is int and p['unit_u_coin_price'] == amount*10,
                'http_explicit_unit_ucoin_price_mismatch')
        require(maximum*amount <= 1000000, 'http_total_money_cap_exceeded')
        require(p.get('enabled') is (maximum > 0), 'http_enabled_quantity_disagrees')
        require(p.get('reward_lines') == expected['grants'].get('lines'), 'http_reward_lines_changed')
        require(p.get('unit_pricing') == expected['grants'].get('pricing',
                 dict(u_coin_price=amount*10, u_coin_per_yuan=1000)), 'http_unit_pricing_changed')
        require((p.get('required_vip_level') or 0) == expected['grants'].get('required_vip_level', 0),
                'http_vip_gate_changed')
        require(p.get('original_u_coin_price') == expected['grants'].get('pricing', {}).get('original_u_coin_price'),
                'http_original_price_changed')
        grants = expected['grants']
        permanent = any(key not in grants.get('entitlement_days', {}) for key in grants.get('entitlements', []))
        if expected['purchase_limit'] == 1 or permanent or grants.get('vip_claims'):
            require(maximum <= 1, 'vip_or_one_time_or_permanent_quantity_exceeded')
            limited_checked += 1
    ticket = http_products.get('video_p001')
    require(ticket is not None and db_products['video_p001']['purchase_limit'] == 0,
            'repeatable_red_ticket_missing')
    require(db_products['video_p001']['grants'].get('items') == {'special_lottery_ticket': 1},
            'repeatable_red_ticket_grant_changed')
    require(ticket['max_quantity'] == 0 or ticket['max_quantity'] > 1,
            'repeatable_red_ticket_cannot_buy_multiple')
    visible_bundles = {sku for sku in http_products if sku.startswith('video_bundle_')}
    require(visible_bundles == {sku for sku, (_, enabled, _) in BUNDLES.items() if enabled},
            'http_13_ready_2_pending_bundle_set_mismatch')
    health = {}
    for name, port in [('archive', 8765), ('payments', 8766)]:
        with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
            health[name] = response.status == 200 and json.load(response).get('ok') is True
    require(all(health.values()), 'service_health_failed')
    current_versions()
    print(json.dumps(dict(status='PASS', payment_release=PAY.name, archive_release=ARCHIVE_NAME,
        archive_bundle=ARCHIVE_HASH, catalog_hash=CATALOG_HASH, manifest_scope_verified=True,
        catalog_products_checked=len(products), every_unit_price_and_max_quantity_verified=True,
        repeatable_red_ticket_multiple_or_capacity_blocked=True, limited_products_checked=limited_checked,
        ready_bundles=13, pending_bundles=2, bundle_prices_members_and_vip_gates_unchanged=True,
        health=health, read_only=True, used_existing_authorized_test_session=True,
        sessions_created=0, orders_created=0, gateway_requests=0)))


if __name__ == '__main__':
    try:
        main()
    except VerificationError as error:
        print(json.dumps({'status': 'FAIL', 'error': str(error), 'read_only': True,
                          'sessions_created': 0, 'orders_created': 0, 'gateway_requests': 0}))
        raise SystemExit(1)
    except Exception as error:
        # Exception messages can contain connection/configuration details. Emit
        # only the exception class; no traceback or customer values are logged.
        print(json.dumps({'status': 'FAIL', 'error_type': type(error).__name__, 'read_only': True,
                          'sessions_created': 0, 'orders_created': 0, 'gateway_requests': 0}))
        raise SystemExit(1)
