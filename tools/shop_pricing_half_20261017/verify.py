"""Post-release read-only checks. No order, login, gateway or grant calls."""
from pathlib import Path
import hashlib
import hmac
import json
import sys
import urllib.request

stage = Path(STAGE)
plan = json.loads((stage / 'plan.json').read_bytes())
payment = Path('/opt/goufayu/payments/current').resolve(strict=True)
archive = Path('/opt/goufayu/releases/current').resolve(strict=True)
assert payment.name == plan['payment_release'] and archive.name == plan['archive_release'], 'release_pointer_mismatch'
for root, filename, key in ((payment, 'manifest.json', None), (archive, 'release_manifest.json', 'files')):
    manifest = json.loads((root / filename).read_bytes())
    if key:
        manifest = manifest[key]
    for name, digest in manifest.items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, 'release_manifest_drift'
for unit, expected in (('goufayu-api.service', archive), ('goufayu-payment.service', payment)):
    import subprocess
    pid = subprocess.run(['systemctl', 'show', unit, '--property=MainPID', '--value'], capture_output=True, check=True, text=True).stdout.strip()
    assert pid.isdigit() and Path('/proc/' + pid + '/cwd').resolve() == expected, 'service_process_not_current'
sys.path.insert(0, str(payment))
from deploy import connection
from payment_backend.service import Payments
config = json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
app = Payments.__new__(Payments); app.config = config
package = json.loads((stage / 'payment_package.json').read_bytes())
expected = {p['sku']: p for p in package['catalog']['products']}
request_body = None
orders_checked = 0
with connection() as conn:
    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
    assert conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0] == plan['catalog_hash']
    products = {r[0]['sku']: r[0] for r in conn.execute('SELECT to_jsonb(p) FROM payments.products p')}
    for sku, product in expected.items():
        actual = products[sku]
        for key in ('amount', 'grants', 'effects', 'enabled', 'item_id', 'purchase_limit', 'description'):
            assert actual[key] == product[key], 'published_product_mismatch:' + sku
    for raw, in conn.execute('SELECT to_jsonb(o) FROM payments.orders o ORDER BY created_at DESC LIMIT 200'):
        shown = app.public(raw)
        assert shown['amount_fen'] == raw['amount'], 'historical_amount_changed'
        assert shown['u_coin_per_yuan'] in (100, 1000), 'historical_rate_invalid'
        orders_checked += 1
    registered = conn.execute('SELECT config FROM public.archive_config_sets WHERE config_hash=%s', (plan['bundle'],)).fetchone()[0]
    rows = registered['configs']['commerce_catalog']['rows']
    assert len(rows) == 129 and registered['compatible_config_hashes'][plan['parent_bundle']]['upgrade_commands'] == ['commerce_purchase']
    for account in config['allowed_accounts']:
        digest = hmac.new(config['pepper'].encode(), str(account).encode(), hashlib.sha256).hexdigest()
        found = conn.execute('SELECT match_session_id FROM public.match_profile_sessions WHERE account_id=%s ORDER BY created_at DESC LIMIT 1', (digest,)).fetchone()
        if found:
            request_body = dict(account_id=str(account), match_session_id=found[0]); break
    conn.rollback()
assert request_body is not None, 'existing_authorized_session_missing'
request = urllib.request.Request('http://127.0.0.1:8766/v1/payments/catalog', data=json.dumps(request_body).encode(), method='POST',
                                headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config['game_token']})
with urllib.request.urlopen(request, timeout=20) as response:
    catalog = json.load(response)
    assert response.status == 200 and catalog.get('ok') is True
assert catalog['catalog_hash'] == plan['catalog_hash'] and catalog['u_coin_per_yuan'] == 100
public = {p['sku']: p for p in catalog['products']}
assert set(public) == {sku for sku, p in expected.items() if p['enabled']}, 'catalog_enabled_set_mismatch'
for sku, product in public.items():
    assert product['amount_fen'] == product['unit_amount_fen'] == expected[sku]['amount']
    assert product['u_coin_per_yuan'] == 100 and product['u_coin_price'] == product['unit_u_coin_price'] == product['amount_fen']
assert public['u_coin_recharge']['amount_fen'] == 100 and public['u_coin_recharge']['recharge_u_coin_per_unit'] == 100
assert public['archive_pass_monthly']['amount_fen'] == 1000
health = {}
for name, port in (('archive', 8765), ('payments', 8766)):
    with urllib.request.urlopen('http://127.0.0.1:' + str(port) + '/health', timeout=5) as response:
        assert response.status == 200 and json.load(response).get('ok') is True
        health[name] = True
print(json.dumps(dict(status='DEPLOYMENT_VERIFIED', payment_release=payment.name, archive_release=archive.name,
                     bundle=plan['bundle'], catalog_hash=plan['catalog_hash'], u_coin_per_yuan=100,
                     payment_catalog_products=len(public), commerce_products=len(rows), historical_orders_readable=orders_checked,
                     recharge_fen=100, recharge_u_coin=100, monthly_pass_fen=1000,
                     health=health, read_only=True, orders_created=0, gateway_requests=0, player_commands=0)))
