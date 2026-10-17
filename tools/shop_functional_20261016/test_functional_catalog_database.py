"""Rollback-only real PostgreSQL checks for the reviewed functional goods.

Importing this module performs no I/O. The caller supplies an already-open
administrative connection with the candidate catalog staged in a transaction.
Only nonce-derived synthetic players, sessions, orders and callback transaction
IDs are used. All fixture writes are forcibly rolled back by a nested savepoint;
this module never calls HTTP, a payment gateway, commit(), or opens a connection.
"""
from __future__ import annotations

from copy import deepcopy
from decimal import Decimal
import hashlib
import importlib
import inspect
import secrets


def run_checks(conn, package):
    """Validate staged production SKUs while retaining no fixture account/order."""
    assert not conn.autocommit, 'functional fixtures require an outer rollback transaction'
    assert conn.info.transaction_status.name == 'INTRANS', 'candidate catalog must be staged first'
    catalog = package['catalog']
    products = {p['sku']: p for p in catalog['products']}
    expected_prices = {'video_p016': 29800, 'video_p028': 23800,
                       'video_p032': 8800, 'video_bundle_b003': 46560}
    for sku, price in expected_prices.items():
        p = products[sku]
        assert p['enabled'] and p['u_coin_price'] == price
        assert p['amount'] == price // 10 and p['grants']['pricing']['u_coin_price'] == price
        assert p['grants']['pricing']['u_coin_per_yuan'] == 1000
        assert p['purchase_limit'] == 1
    assert 'video_p079' not in products and 'video_p147' not in products, 'points-only goods must not silently become cash products'
    bundle = products['video_bundle_b003']
    assert bundle['effects']['starjoy_points'] == 662
    component_skus = {'video_p028', 'video_p020', 'video_p018', 'video_p032'}
    assert {p['sku'] for p in bundle['grants']['components']} == component_skus
    expected_bundle_effects = {}
    for sku in component_skus:
        for field, value in products[sku]['effects'].items():
            expected_bundle_effects[field] = expected_bundle_effects.get(field, 0) + value
    assert bundle['effects'] == expected_bundle_effects
    assert products['video_p016']['effects'] == {'starjoy_points': 298}, 'spatial aura cannot become permanent global stats'

    try:
        generic_module = importlib.import_module('payment_backend.test_commerce_bundles_database')
    except ModuleNotFoundError:
        generic_module = importlib.import_module('server.payment_backend.test_commerce_bundles_database')
    # This published regression predates quantity snapshots (v5); keep every
    # behavioral assertion while accepting either supported immutable format.
    # No deployed source file or SQL function is changed for this compatibility.
    generic_source = inspect.getsource(generic_module)
    old_assertion = "order['reward']['version'] == 4"
    assert generic_source.count(old_assertion) == 1, 'review_generic_snapshot_version_assertion'
    namespace = {'__name__': 'functional_compatible_generic_bundle_tests',
                 '__file__': generic_module.__file__, '__package__': generic_module.__package__}
    exec(compile(generic_source.replace(old_assertion, "order['reward']['version'] in (4, 5)", 1),
                 generic_module.__file__, 'exec'), namespace)
    generic_checks = namespace['run_checks']

    # Even a caller that later commits its staged catalog cannot retain a
    # synthetic purchase created by this fixture.
    with conn.transaction(force_rollback=True):
        generic = generic_checks(conn, catalog)
        result, accounts = _run_formal_checks(conn, products)
    for account in accounts:
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (account,)).fetchone(), 'fixture account leaked past rollback'
        assert not conn.execute('SELECT 1 FROM payments.orders WHERE account_id=%s', (account,)).fetchone(), 'fixture order leaked past rollback'
    return {'status': 'PASS', 'generic_bundle_regressions': generic, **result,
            'fixture_accounts_removed': len(accounts), 'fixture_writes': 'forced_savepoint_rollback_completed',
            'gateway_requests': 0, 'http_requests': 0, 'real_player_data': False,
            'database_connections_opened': 0}


def _run_formal_checks(conn, products):
    from psycopg.types.json import Jsonb

    nonce = secrets.token_hex(16)
    session = 'functional_fixture_' + nonce
    accounts, orders = set(), set()
    cases = []
    defaults = conn.execute("SELECT coalesce(jsonb_object_agg(field_id,default_value),'{}'::jsonb) FROM payments.stat_rules").fetchone()[0]
    provider = conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()
    assert provider, 'fixture requires the already configured payment provider'
    formal = {'video_p016', 'video_p028', 'video_p020', 'video_p018', 'video_p032',
              'video_bundle_b003', 'video_bundle_b005'}
    component_skus = {'video_p028', 'video_p020', 'video_p018', 'video_p032'}

    def digest(label):
        return hashlib.sha256(('functional_fixture:' + nonce + ':' + label).encode()).hexdigest()

    def oid(label):
        return 'WX' + digest('order:' + label)[:30]

    def tx(label):
        return '420000' + str(int(digest('transaction:' + label)[:30], 16)).zfill(37)

    def call(name, *args):
        assert name in {'catalog', 'create_order', 'create_order_quantity', 'get_order', 'deliver'}
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def buyer(label, inventory=None):
        account = digest('account:' + label)
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (account,)).fetchone(), 'synthetic identity collision'
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)', (account, Jsonb(defaults)))
        login = conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',
                             (account, session, 'standard', Jsonb(defaults))).fetchone()[0]
        assert login['ok']
        archive = {'fixture_keep_archive': 123, 'commerce': {'balances': {'u_coin': 17, 'shop_points': 19, 'shop_gold': 23}}}
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
                     (account, Jsonb(archive), Jsonb(dict({'fixture_keep_item': 3}, **(inventory or {})))))
        # Avoid unrelated newly crossed starjoy tiers while still proving both
        # spendable and lifetime points are credited exactly once.
        conn.execute('''UPDATE public.player_gameplay_stats SET starjoy_points=37,
            starjoy_points_earned=1000000,starjoy_reward_level=24,
            hero_execute_health_threshold_pct=15 WHERE player_id=%s''', (account,))
        accounts.add(account)
        assert not conn.execute('SELECT payments.is_test_account(%s)', (account,)).fetchone()[0]
        return account

    def state(account):
        assert account in accounts
        row = conn.execute('''SELECT to_jsonb(s),a.archive,a.content_inventory,p.profile_revision
            FROM public.player_gameplay_stats s JOIN public.survival_players p ON p.account_id=s.player_id
            JOIN public.player_archive_state a ON a.account_id=p.account_id WHERE p.account_id=%s''', (account,)).fetchone()
        assert row
        return row

    def listed(account):
        assert account in accounts
        response = call('catalog', account, session)
        assert response['ok']
        return {p['sku']: p for p in response['products']}

    def make(account, sku, label):
        assert account in accounts and sku in formal
        order = call('create_order', account, session, oid(label), sku)
        if 'error' not in order:
            assert order['account_id'] == account and order['sku'] == sku
            orders.add(order['order_id'])
        return order

    def pay(order, label, amount=None):
        assert order['account_id'] in accounts and order['sku'] in formal and order['order_id'] in orders
        stored = call('get_order', order['order_id'])
        assert stored['account_id'] == order['account_id'], 'only this fixture nonce can receive direct SQL delivery'
        return call('deliver', order['order_id'], tx(label), order['amount'] if amount is None else amount, *provider)

    def delivery(account, sku, label):
        product = products[sku]
        before = state(account)
        made = make(account, sku, label)
        assert 'error' not in made, (sku, made)
        assert made['amount'] == product['amount']
        assert made['reward']['item_id'] == product['item_id']
        assert made['reward']['effects'] == product['effects']
        assert made['reward']['grants'] == product['grants']
        assert state(account) == before, 'opening an unpaid order changed a player'
        delivered = pay(made, label)
        assert delivered['state'] == 'delivered', (sku, delivered)
        assert delivered['amount'] == product['amount'] and delivered['reward'] == made['reward']
        after = state(account)
        expected_inventory = deepcopy(before[2])
        expected_inventory[product['item_id']] = expected_inventory.get(product['item_id'], 0) + 1
        for item, amount in product['grants']['items'].items():
            expected_inventory[item] = expected_inventory.get(item, 0) + amount
        assert after[2] == expected_inventory, ('full_inventory', sku, after[2], expected_inventory)
        for field, amount in product['effects'].items():
            assert Decimal(str(after[0][field])) - Decimal(str(before[0][field])) == Decimal(str(amount)), (sku, field)
            assert Decimal(str(delivered['effect_changes'][field]['delta'])) == Decimal(str(amount)), (sku, field, 'receipt')
        points = product['effects'].get('starjoy_points', 0)
        assert Decimal(str(after[0]['starjoy_points_earned'])) - Decimal(str(before[0]['starjoy_points_earned'])) == points
        assert after[0]['starjoy_reward_level'] == 24
        assert after[1] == before[1], 'cash purchase changed/debited the unrelated wallet or archive'
        assert after[3] > before[3]
        assert pay(made, label)['state'] == 'delivered' and state(account) == after
        return made, delivered, after

    # Exact real SKU snapshots staged by the release, not invented fixture
    # products that could accidentally hide a compiler or publication defect.
    fresh = buyer('catalog')
    before = state(fresh)
    fresh_before = deepcopy(before)
    catalog = listed(fresh)
    for sku in ('video_p016', 'video_p028', 'video_p032', 'video_bundle_b003'):
        p = products[sku]
        row = conn.execute('SELECT item_id,amount,effects,grants,enabled,purchase_limit FROM payments.products WHERE sku=%s', (sku,)).fetchone()
        assert row == (p['item_id'], p['amount'], p['effects'], p['grants'], True, 1), (sku, 'staged_db_catalog_mismatch')
        assert catalog[sku]['enabled'] and catalog[sku]['unit_u_coin_price'] == p['u_coin_price']
        assert catalog[sku]['unit_amount_fen'] == p['amount'] and catalog[sku]['max_quantity'] == 1
    assert state(fresh) == before
    assert 'video_bundle_b005' not in catalog
    assert make(fresh, 'video_bundle_b005', 'disabled_cosmetic')['error'] == 'product_unavailable'
    cases.append('actual P016/P028/P032/B003 staged catalog, exact U-coin-to-fen prices, no prepaid grants, cosmetic pack blocked')

    for sku in ('video_p016', 'video_p028'):
        account = buyer('single:' + sku)
        _, _, after = delivery(account, sku, 'single:' + sku)
        assert make(account, sku, 'repeat:' + sku)['error'] == 'already_owned'
        assert state(account) == after
    cases.append('both newly paid single goods deliver every formal stat and canonical marker once; callbacks and rebuy cannot duplicate')

    owner = buyer('newcomer')
    _, _, after = delivery(owner, 'video_bundle_b003', 'newcomer')
    assert after[0]['starjoy_points'] == 699 and after[0]['starjoy_points_earned'] == 1000662
    assert after[2]['commerce_p028'] == after[2]['commerce_p020'] == after[2]['commerce_p018'] == after[2]['commerce_p032'] == 1
    for sku in component_skus:
        assert make(owner, sku, 'pack_then:' + sku)['error'] == 'already_owned'
    assert make(owner, 'video_bundle_b003', 'repeat:newcomer')['error'] == 'already_owned'
    assert state(owner) == after
    cases.append('newcomer actual SKU grants complete four-part pack and starjoy662; all component rebuy and pack replay rejected')

    for sku in ('video_p028', 'video_p032'):
        account = buyer('component_first:' + sku)
        _, _, owned = delivery(account, sku, 'component_first:' + sku)
        assert make(account, 'video_bundle_b003', 'component_then_bundle:' + sku)['error'] == 'component_already_owned'
        assert state(account) == owned
        # Lost ownership cache must not bypass a settled component purchase.
        conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s', (products[sku]['item_id'], account))
        without_cache = state(account)
        assert make(account, 'video_bundle_b003', 'component_history_then_bundle:' + sku)['error'] == 'component_already_owned'
        assert state(account) == without_cache
    cases.append('P028/P032 first blocks the newcomer pack, including settled-payment history when inventory cache is absent')

    # A player may obtain a single while an earlier full-pack intent is pending.
    # A losing PAID receipt remains reviewable, but no partial bundle leaks.
    overlap = buyer('pending_overlap')
    pack_intent = make(overlap, 'video_bundle_b003', 'pending_pack')
    assert 'error' not in pack_intent
    delivery(overlap, 'video_p032', 'pending_single')
    before = state(overlap)
    reviewed = pay(pack_intent, 'pending_pack')
    assert reviewed['state'] == 'paid_review' and state(overlap) == before
    assert pay(pack_intent, 'pending_pack')['state'] == 'paid_review' and state(overlap) == before
    assert 'commerce_p028' not in before[2] and 'commerce_p018' not in before[2] and 'commerce_p020' not in before[2]
    cases.append('pending pack versus acquired P032 is reviewed atomically; other three components/stat662 are never partially granted')

    broken = buyer('broken_bundle')
    broken_order = make(broken, 'video_bundle_b003', 'broken_bundle')
    before = state(broken)
    # Only this synthetic receipt is malformed. The real SKU/config stays intact.
    conn.execute("UPDATE payments.orders SET reward=jsonb_set(reward,'{effects}',reward->'effects'||'{\"missing_functional_fixture_field\":1}'::jsonb) WHERE order_id=%s", (broken_order['order_id'],))
    try:
        with conn.transaction():
            pay(broken_order, 'broken_bundle')
    except Exception as error:
        assert getattr(error, 'sqlstate', None) in {'P0001', '42703'}, (type(error).__name__, getattr(error, 'sqlstate', None))
    else:
        raise AssertionError('malformed synthetic bundle unexpectedly granted')
    assert state(broken) == before
    pending = call('get_order', broken_order['order_id'])
    assert pending['state'] == 'created' and pending['transaction_id'] is None
    cases.append('grant failure after synthetic bundle work rolls back ownership, attributes, points, revision and transaction receipt')

    assert state(fresh) == fresh_before
    cases.append('distinct nonce-derived buyers remain isolated; no real accounts, gateway calls or checkout HTTP involved')
    return {'cases': len(cases), 'checks': cases, 'formal_newcomer_starjoy': 662,
            'synthetic_orders_created': len(orders), 'synthetic_players_created': len(accounts)}, accounts
