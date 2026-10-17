"""Quantity checkout PostgreSQL fixtures; run_checks requires outer rollback.

No gateway or production connection is made. run_concurrency_checks explicitly
restricts its committed/cleaned synthetic fixtures to the disposable localhost
survival_bundle_test database. Imports and offline tests open no connection.
"""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import timedelta
from decimal import Decimal
import hashlib
from pathlib import Path
import secrets
import threading
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / 'server/payment_backend/upgrade_order_quantity.sql'


def run_checks(conn, catalog=None):
    from psycopg.types.json import Jsonb
    assert not conn.autocommit and conn.info.transaction_status.name == 'INTRANS'
    nonce = secrets.token_hex(16)
    session = 'quantity_fixture_' + nonce
    fixture_accounts, fixtures = set(), {}
    defaults = conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
    providers = {row[0]: row[1:] for row in conn.execute('SELECT provider,appid,mchid FROM payments.providers WHERE enabled')}
    assert 'wechat' in providers and 'alipay' in providers

    def digest(label):
        return hashlib.sha256(('quantity_fixture:' + nonce + ':' + label).encode()).hexdigest()

    def oid(label, provider='wechat'):
        return ('WX' if provider == 'wechat' else 'AL') + digest('order:' + label)[:30]

    def tx(label):
        return '420000' + str(int(digest('transaction:' + label)[:30], 16)).zfill(37)

    def call(name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def buyer(label, recharge=0, archive=None, inventory=None, create_archive=True):
        identity = digest('account:' + label)
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (identity,)).fetchone()
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)', (identity, Jsonb(defaults)))
        conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)', (identity, session, 'standard', Jsonb(defaults)))
        if create_archive:
            conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
                         (identity, Jsonb(archive or {'keep': 123}), Jsonb(inventory or {'keep_item': 3})))
        conn.execute('UPDATE public.player_gameplay_stats SET vip_recharge_total_fen=%s WHERE player_id=%s', (recharge, identity))
        fixture_accounts.add(identity)
        return identity

    def product(label, amount=250, limit=0, effects=None, grants=None):
        sku, marker = 'qtf_' + label + '_' + nonce[:12], 'qtf_owned_' + label + '_' + nonce[:12]
        grants = dict(items={}, item_limits={}, entitlements=[], lines=[],
                      pricing={'u_coin_price': amount * 10, 'u_coin_per_yuan': 1000}) | deepcopy(grants or {})
        p = dict(sku=sku, item_id=marker, amount=amount, purchase_limit=limit, effects=effects or {}, grants=grants)
        conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
          grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,%s,'synthetic rollback fixture',%s,%s,true,100,%s,'bundles','bundle','',%s)''',
          (sku, marker, label, amount, Jsonb(p['effects']), Jsonb(grants), limit))
        fixtures[sku] = p
        return p

    def state(identity):
        return conn.execute('''SELECT to_jsonb(s),a.archive,a.content_inventory,p.profile_revision,
          (SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY entitlement_id),'[]') FROM public.archive_entitlements e WHERE e.account_id=p.account_id)
          FROM public.player_gameplay_stats s JOIN public.survival_players p ON p.account_id=s.player_id
          LEFT JOIN public.player_archive_state a ON a.account_id=p.account_id WHERE s.player_id=%s''', (identity,)).fetchone()

    def make(identity, p, label, quantity=1, provider='wechat', match_session=None):
        return call('create_order_quantity', identity, match_session or session, oid(label, provider), p['sku'], provider, quantity)

    def pay(order, label, amount=None):
        assert order['account_id'] in fixture_accounts and order['sku'] in fixtures
        return call('deliver', order['order_id'], tx(label), order['amount'] if amount is None else amount, *providers[order['provider']])

    def raises(callback):
        try:
            with conn.transaction():
                callback()
        except Exception:
            return
        raise AssertionError('invalid quantity/payment fixture was accepted')

    def listed(identity, p):
        return next(row for row in call('catalog', identity, session)['products'] if row['sku'] == p['sku'])

    token = 'qtf_token_' + nonce[:12]
    bulk = product('bulk', effects={'initial_wood': 2}, grants={
        'items': {token: 3}, 'item_limits': {token: 1000},
        'pricing': {'u_coin_price': 2500, 'u_coin_per_yuan': 1000, 'original_u_coin_price': 3000},
        'lines': [{'kind': 'item', 'id': token, 'quantity': 3}, {'kind': 'stat', 'id': 'initial_wood', 'quantity': 2}],
    })
    main, other = buyer('main'), buyer('other')
    for invalid in (None, 0, -1, 101):
        assert make(main, bulk, 'invalid_' + str(invalid), invalid)['error'] == 'quantity_invalid'
    # The integer RPC also has no numeric/boolean SQL overload; HTTP separately
    # rejects strings, booleans and fractional JSON values before calling it.
    for invalid in (True, 1.5):
        raises(lambda: make(main, bulk, 'invalid_type_' + str(invalid), invalid))
    info = listed(main, bulk)
    assert (info['max_quantity'], info['unit_amount_fen'], info['unit_u_coin_price']) == (100, 250, 2500)
    assert info['unit_pricing'] == bulk['grants']['pricing']
    before = state(main)
    order = make(main, bulk, 'main_bulk', 5)
    assert order['amount'] == 1250 and order['reward']['version'] == 5
    reward = order['reward']
    assert reward['quantity'] == 5 and reward['unit_amount_fen'] == 250 and reward['unit_pricing'] == bulk['grants']['pricing']
    assert reward['effects'] == {'initial_wood': 10} and reward['grants']['items'] == {token: 15}
    assert [r['quantity'] for r in reward['grants']['lines']] == [15, 10]
    assert reward['grants']['pricing'] == {'u_coin_price': 12500, 'u_coin_per_yuan': 1000, 'original_u_coin_price': 15000}
    assert state(main) == before
    assert make(main, bulk, 'same', 5)['order_id'] == order['order_id']
    assert call('update_gateway', order['order_id'], 'pending', 'weixin://wxpay/bizpayurl?quantity_fixture')['state'] == 'pending'
    frozen = call('get_order', order['order_id'])
    for quantity, provider, warning in [(2, 'wechat', 'order_quantity_conflict'), (5, 'alipay', 'order_provider_conflict'), (2, 'alipay', 'order_quantity_conflict')]:
        restored = make(main, bulk, 'conflict_' + str(quantity) + provider, quantity, provider)
        assert restored['warning'] == warning and restored['order_id'] == order['order_id']
        assert restored['reward'] == frozen['reward'] and restored['code_url'] == frozen['code_url']
        assert call('get_order', order['order_id']) == frozen
    assert call('create_order', main, session, oid('old_four'), bulk['sku'])['warning'] == 'order_quantity_conflict'
    assert call('create_order_channel', main, session, oid('old_five'), bulk['sku'], 'wechat')['warning'] == 'order_quantity_conflict'
    assert make(main, bulk, 'missing_auth', 5, match_session='missing_session')['error'] == 'match_session_missing'
    own = make(other, bulk, 'other', 2)
    assert own['account_id'] == other and own['order_id'] != order['order_id'] and own['reward']['quantity'] == 2
    # Recovery is still available when the catalog/channel is disabled; it does
    # not create a new gateway intent or rewrite an existing QR.
    with conn.transaction(force_rollback=True):
        conn.execute('UPDATE payments.products SET enabled=false WHERE sku=%s', (bulk['sku'],))
        conn.execute("UPDATE payments.providers SET enabled=false WHERE provider='alipay'")
        recovered = make(main, bulk, 'disabled_recover', 5, 'alipay')
        assert recovered['order_id'] == order['order_id'] and recovered['warning'] == 'order_provider_conflict'
    raises(lambda: pay(order, 'incorrect_amount', 250))
    assert state(main) == before
    with conn.transaction(force_rollback=True):
        conn.execute("UPDATE payments.products SET amount=777,effects='{\"initial_wood\":999}',enabled=false WHERE sku=%s", (bulk['sku'],))
        delivered = pay(order, 'main_bulk')
        assert delivered['state'] == 'delivered' and delivered['reward'] == reward
    delivered = pay(order, 'main_bulk')
    after = state(main)
    assert delivered['state'] == 'delivered' and after[2][bulk['item_id']] == 5 and after[2][token] == 15
    assert Decimal(str(after[0]['initial_wood'])) - Decimal(str(before[0]['initial_wood'])) == 10
    assert delivered['applied_items'][bulk['item_id']] == 5 and delivered['applied_effects'] == {'initial_wood': 10}
    assert pay(order, 'main_bulk')['state'] == 'delivered' and state(main) == after
    close_buyer = buyer('close')
    closed = make(close_buyer, bulk, 'close_five', 5)
    call('update_gateway', closed['order_id'], 'closed', None)
    reopened = make(close_buyer, bulk, 'after_close_two', 2)
    assert reopened['order_id'] != closed['order_id'] and reopened['reward']['quantity'] == 2

    # Product limits use purchased units, including after ownership-cache loss.
    finite = product('finite', limit=8)
    finite_buyer = buyer('finite', inventory={'keep_item': 3, finite['item_id']: 3})
    assert listed(finite_buyer, finite)['max_quantity'] == 5
    assert make(finite_buyer, finite, 'finite_six', 6)['error'] == 'quantity_limit_exceeded'
    assert pay(make(finite_buyer, finite, 'finite_five', 5), 'finite_five')['state'] == 'delivered'
    conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s', (finite['item_id'], finite_buyer))
    assert listed(finite_buyer, finite)['max_quantity'] == 3
    assert make(finite_buyer, finite, 'history_four', 4)['error'] == 'quantity_limit_exceeded'
    assert pay(make(finite_buyer, finite, 'history_three', 3), 'history_three')['state'] == 'delivered'
    assert listed(finite_buyer, finite)['max_quantity'] == 0
    single = product('single', limit=1)
    single_buyer = buyer('single')
    assert listed(single_buyer, single)['max_quantity'] == 1
    assert make(single_buyer, single, 'single_two', 2)['error'] == 'quantity_limit_exceeded'
    expensive = product('expensive', amount=250000)
    costly_buyer = buyer('costly')
    assert listed(costly_buyer, expensive)['max_quantity'] == 4
    assert make(costly_buyer, expensive, 'expensive_five', 5)['error'] == 'quantity_limit_exceeded'
    assert make(costly_buyer, expensive, 'expensive_four', 4)['amount'] == 1000000

    # Item and attribute remaining capacity are computed for the entire batch.
    item_buyer = buyer('item_cap', inventory={'keep_item': 3, token: 990})
    assert listed(item_buyer, bulk)['max_quantity'] == 3
    assert make(item_buyer, bulk, 'item_four', 4)['error'] == 'quantity_limit_exceeded'
    assert pay(make(item_buyer, bulk, 'item_three', 3), 'item_three')['state'] == 'delivered'
    assert state(item_buyer)[2][token] == 999 and listed(item_buyer, bulk)['max_quantity'] == 0
    stat_product = product('stat_cap', effects={'wall_health_bonus_pct': 3})
    maximum = conn.execute("SELECT maximum FROM payments.stat_rules WHERE field_id='wall_health_bonus_pct'").fetchone()[0]
    stat_buyer = buyer('stat_cap')
    no_archive_buyer = buyer('stat_cap_no_archive', create_archive=False)
    for identity in (stat_buyer, no_archive_buyer):
        conn.execute('UPDATE public.player_gameplay_stats SET wall_health_bonus_pct=%s WHERE player_id=%s', (maximum - 7, identity))
        assert listed(identity, stat_product)['max_quantity'] == 2
        assert make(identity, stat_product, 'stat_three_' + identity[:8], 3)['error'] == 'quantity_limit_exceeded'
    assert pay(make(stat_buyer, stat_product, 'stat_two', 2), 'stat_two')['state'] == 'delivered'
    assert state(stat_buyer)[0]['wall_health_bonus_pct'] == maximum - 1

    child = product('child', limit=6, effects={'initial_wood': 1})
    component = product('component', effects={'initial_wood': 2}, grants={
        'items': {child['item_id']: 2}, 'item_limits': {child['item_id']: 6},
        'components': [{'sku': child['sku'], 'item_id': child['item_id'], 'quantity': 2, 'purchase_limit': 6}],
        'lines': [{'kind': 'component', 'id': child['item_id'], 'quantity': 2}]})
    component_buyer = buyer('component')
    assert pay(make(component_buyer, child, 'child_two', 2), 'child_two')['state'] == 'delivered'
    assert listed(component_buyer, component)['max_quantity'] == 2
    component_order = make(component_buyer, component, 'component_two', 2)
    assert component_order['reward']['grants']['components'][0]['quantity'] == 4
    assert component_order['reward']['grants']['components'][0]['purchase_limit'] == 6
    assert pay(component_order, 'component_two')['state'] == 'delivered'
    assert state(component_buyer)[2][child['item_id']] == 6
    conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s', (child['item_id'], component_buyer))
    assert listed(component_buyer, child)['max_quantity'] == listed(component_buyer, component)['max_quantity'] == 0

    # A finite pass is one renewed entitlement with scaled duration, not N
    # permanent grants. A purchase batch is capped at floor(365 / 30) = 12.
    monthly = product('monthly', amount=2000, grants={'entitlements': ['archive_pass'], 'entitlement_days': {'archive_pass': 30},
        'lines': [{'kind': 'entitlement', 'id': 'archive_pass', 'quantity': 1, 'duration_days': 30}]})
    monthly_buyer = buyer('monthly')
    assert listed(monthly_buyer, monthly)['max_quantity'] == 12
    assert make(monthly_buyer, monthly, 'month_thirteen', 13)['error'] == 'quantity_limit_exceeded'
    now = conn.execute('SELECT now()').fetchone()[0]
    month_order = make(monthly_buyer, monthly, 'month_twelve', 12)
    assert month_order['amount'] == 24000 and month_order['reward']['grants']['entitlement_days'] == {'archive_pass': 360}
    assert month_order['reward']['grants']['lines'][0]['quantity'] == 12 and month_order['reward']['grants']['lines'][0]['duration_days'] == 360
    assert pay(month_order, 'month_twelve')['state'] == 'delivered'
    assert conn.execute("SELECT expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='archive_pass'", (monthly_buyer,)).fetchone()[0] - now == timedelta(days=360)
    assert pay(make(monthly_buyer, monthly, 'month_renew_two', 2), 'month_renew_two')['state'] == 'delivered'
    assert conn.execute("SELECT expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='archive_pass'", (monthly_buyer,)).fetchone()[0] - now == timedelta(days=420)
    permanent = product('permanent', grants={'entitlements': ['archive_pass']})
    permanent_buyer = buyer('permanent')
    assert listed(permanent_buyer, permanent)['max_quantity'] == 1
    assert make(permanent_buyer, permanent, 'permanent_two', 2)['error'] == 'quantity_limit_exceeded'
    vip = product('vip', effects={'initial_wood': 107}, grants={'required_vip_level': 1,
        'vip_claims': ['vip_package_01', 'vip_medal_01'], 'vip_claim_effects': {'vip_medal_01': {'initial_wood': 7}}})
    vip_buyer = buyer('vip', 5000, archive={'keep': 123, 'vip_claimed': {'vip_medal_01': True}})
    assert listed(vip_buyer, vip)['max_quantity'] == 1
    assert make(vip_buyer, vip, 'vip_two', 2)['error'] == 'quantity_limit_exceeded'
    vip_before = state(vip_buyer)
    vip_receipt = pay(make(vip_buyer, vip, 'vip_one'), 'vip_one')
    assert vip_receipt['applied_effects']['initial_wood'] == 100
    assert Decimal(str(state(vip_buyer)[0]['initial_wood'])) - Decimal(str(vip_before[0]['initial_wood'])) == 100

    # Already-stored v4 intents have implicit quantity one and retain their
    # original snapshot shape and amount after the additive upgrade.
    legacy_buyer = buyer('legacy')
    legacy_reward = dict(item_id=bulk['item_id'], version=4, quantity=1, title='legacy fixture', description='',
                         effects=bulk['effects'], grants=bulk['grants'], purchase_limit=0, catalog_hash='legacy')
    conn.execute('INSERT INTO payments.orders(order_id,account_id,sku,amount,reward) VALUES(%s,%s,%s,%s,%s)',
                 (oid('legacy'), legacy_buyer, bulk['sku'], bulk['amount'], Jsonb(legacy_reward)))
    legacy = call('get_order', oid('legacy'))
    assert make(legacy_buyer, bulk, 'legacy_conflict', 5)['warning'] == 'order_quantity_conflict'
    assert pay(legacy, 'legacy')['state'] == 'delivered'
    assert state(legacy_buyer)[2][bulk['item_id']] == 1 and state(legacy_buyer)[2][token] == 3
    assert call('get_order', oid('legacy'))['reward'] == legacy_reward
    # Invalid internal snapshots and late stat errors must roll back ownership,
    # entitlements, receipt timestamps and the root quantity together.
    broken_buyer = buyer('broken')
    broken = make(broken_buyer, bulk, 'broken_five', 5)
    broken_before = state(broken_buyer)
    with conn.transaction(force_rollback=True):
        conn.execute("UPDATE payments.orders SET reward=jsonb_set(reward,'{unit_amount_fen}','1') WHERE order_id=%s", (broken['order_id'],))
        raises(lambda: pay(broken, 'broken'))
        assert state(broken_buyer) == broken_before
    with conn.transaction(force_rollback=True):
        conn.execute("UPDATE payments.orders SET reward=jsonb_set(reward,'{effects,missing_field}','1') WHERE order_id=%s", (broken['order_id'],))
        raises(lambda: pay(broken, 'broken'))
        assert state(broken_buyer) == broken_before
    assert call('get_order', broken['order_id'])['state'] == 'created'

    with conn.transaction(force_rollback=True):
        reset_buyer = buyer('reset')
        conn.execute('UPDATE payments.test_settings SET enabled=true WHERE singleton')
        conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)', (reset_buyer,))
        reset_before = state(reset_buyer)
        reset_bulk = make(reset_buyer, bulk, 'reset_bulk', 5)
        reset_month = make(reset_buyer, monthly, 'reset_month', 3)
        assert pay(reset_bulk, 'reset_bulk')['state'] == pay(reset_month, 'reset_month')['state'] == 'delivered'
        assert call('begin_reset', reset_buyer, session, 'refreshmoney', 'quantity_fixture_reset')['ok']
        assert call('finish_reset', reset_buyer, session, 'refreshmoney', 'quantity_fixture_reset')['ok']
        cleared = state(reset_buyer)
        assert cleared[1:3] == reset_before[1:3] and cleared[0]['initial_wood'] == reset_before[0]['initial_wood']
        assert not conn.execute('SELECT 1 FROM public.archive_entitlements WHERE account_id=%s', (reset_buyer,)).fetchone()
        assert pay(reset_bulk, 'reset_bulk')['state'] == 'delivered' and state(reset_buyer) == cleared
        assert pay(reset_month, 'reset_month')['state'] == 'delivered' and state(reset_buyer) == cleared
        assert make(reset_buyer, bulk, 'reset_rebuy', 7)['reward']['quantity'] == 7
    if catalog is not None:
        public = {p['sku']: p for p in call('catalog', main, session)['products']}
        for p in catalog['products']:
            if p['enabled']:
                assert 0 <= public[p['sku']]['max_quantity'] <= 100
                assert public[p['sku']]['unit_amount_fen'] == p['amount']
                assert public[p['sku']]['unit_u_coin_price'] == p['amount'] * 10
    assert conn.execute('SELECT has_function_privilege(%s,%s,%s)',
                        ('goufayu_payment', 'payments.create_order_quantity(text,text,text,text,text,integer)', 'EXECUTE')).fetchone()[0]
    for helper in ('receipt_quantity(jsonb)', 'validate_order_quantity_snapshot(jsonb,integer)', 'purchased_units(text,text)',
                   'max_order_quantity(text,text,integer,jsonb,jsonb,integer)', 'scale_order_quantity(jsonb,jsonb,integer,integer)',
                   'product_block_quantity(text,text,integer,jsonb,jsonb,integer)', 'product_block_pre_quantity(text,text,integer,jsonb,jsonb)', 'catalog_pre_quantity(text,text)'):
        for role in ('goufayu_payment', 'goufayu_app'):
            assert not conn.execute('SELECT has_function_privilege(%s,%s,%s)', (role, 'payments.' + helper, 'EXECUTE')).fetchone()[0]
    return dict(quantity_range_1_to_100=True, authoritative_max_and_unit_prices=True, v5_immutable_unit_quantity_total_snapshot=True,
                scaled_effects_items_components_lines=True, pending_recovery_warning_and_unchanged_qr=True,
                authenticated_account_isolation=True, closed_intent_can_change_quantity=True, purchased_unit_history_and_caps=True,
                full_batch_item_attribute_component_money_caps=True, monthly_max_12_and_duration_renewal=True,
                permanent_and_vip_max_1_medal_deduplication=True, legacy_v4_implicit_one_preserved=True,
                failed_delivery_fully_atomic=True, reset_and_old_callback_safe=True, private_helpers=True,
                fixture_writes='caller_must_roll_back')


def run_concurrency_checks(connect):
    """Committed synthetic fixtures, exactly restricted to the disposable DB."""
    from psycopg.types.json import Jsonb
    nonce = secrets.token_hex(16)
    accounts, skus = set(), set()
    session = 'quantity_parallel_' + nonce

    def digest(label):
        return hashlib.sha256(('quantity_parallel:' + nonce + ':' + label).encode()).hexdigest()

    def checked_connection():
        conn = connect()
        if conn.info.host != '127.0.0.1' or conn.info.dbname != 'survival_bundle_test':
            conn.close()
            raise AssertionError('quantity_parallel_requires_disposable_localhost_database')
        conn.execute('SET ROLE goufayu_owner')
        conn.execute("SET statement_timeout='15s'")
        conn.execute("SET lock_timeout='10s'")
        return conn

    def call(conn, name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def oid(label, provider='wechat'):
        return ('WX' if provider == 'wechat' else 'AL') + digest('order:' + label)[:30]

    def tx(label):
        return '420000' + str(int(digest('transaction:' + label)[:30], 16)).zfill(37)

    def concurrent(jobs):
        barrier = threading.Barrier(len(jobs))

        def worker(job):
            with checked_connection() as conn:
                barrier.wait(timeout=10)
                return job(conn)

        with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
            futures = [pool.submit(worker, job) for job in jobs]
            return [future.result(timeout=20) for future in futures]

    try:
        with checked_connection() as conn:
            assert conn.execute("SELECT to_regprocedure('payments.create_order_quantity(text,text,text,text,text,integer)') IS NOT NULL").fetchone()[0]
            defaults = conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
            providers = {r[0]: r[1:] for r in conn.execute('SELECT provider,appid,mchid FROM payments.providers WHERE enabled')}
            token = 'qpc_token_' + nonce[:12]

            def product(label, token_limit):
                sku, marker = 'qpc_' + label + '_' + nonce[:12], 'qpc_owned_' + label + '_' + nonce[:12]
                skus.add(sku)
                grants = dict(items={token: 1}, item_limits={token: token_limit}, entitlements=[], lines=[],
                              pricing={'u_coin_price': 1000, 'u_coin_per_yuan': 1000})
                conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
                  grants,category_id,product_type,icon,purchase_limit)
                  VALUES(%s,%s,'quantity parallel fixture','isolated localhost only',100,'{"initial_wood":1}',true,100,%s,'item','single','',0)''',
                  (sku, marker, Jsonb(grants)))
                return dict(sku=sku, item_id=marker)

            bulk, capped_a, capped_b = product('bulk', 1000), product('cap_a', 10), product('cap_b', 10)
            buyers = {}
            for label in ('different', 'same', 'provider', 'cap'):
                identity = digest('account:' + label)
                accounts.add(identity)
                assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (identity,)).fetchone()
                conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)', (identity, Jsonb(defaults)))
                conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)', (identity, session, 'standard', Jsonb(defaults)))
                conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{}','{}')", (identity,))
                buyers[label] = identity
            cap_orders = [call(conn, 'create_order_quantity', buyers['cap'], session, oid('cap_a' if p == capped_a else 'cap_b'), p['sku'], 'wechat', 6)
                          for p in (capped_a, capped_b)]

        def make(who, label, quantity, provider='wechat'):
            return lambda conn: call(conn, 'create_order_quantity', buyers[who], session, oid(label, provider), bulk['sku'], provider, quantity)

        different = concurrent([make('different', 'five', 5), make('different', 'seven', 7)])
        assert different[0]['order_id'] == different[1]['order_id']
        assert sorted(r.get('warning', '') for r in different) == ['', 'order_quantity_conflict']
        assert different[0]['reward'] == different[1]['reward'] and different[0]['reward']['quantity'] in (5, 7)
        same = concurrent([make('same', 'same_a', 3), make('same', 'same_b', 3)])
        assert same[0]['order_id'] == same[1]['order_id'] and not any(r.get('warning') for r in same)
        channels = concurrent([make('provider', 'wechat', 5), make('provider', 'alipay', 5, 'alipay')])
        assert channels[0]['order_id'] == channels[1]['order_id']
        assert sorted(r.get('warning', '') for r in channels) == ['', 'order_provider_conflict']

        def pay(order, label):
            return lambda conn: call(conn, 'deliver', order['order_id'], tx(label), order['amount'], *providers[order['provider']])

        duplicate = concurrent([pay(same[0], 'retry'), pay(same[0], 'retry')])
        assert all(r['state'] == 'delivered' for r in duplicate)
        cap_results = concurrent([pay(cap_orders[0], 'cap_a'), pay(cap_orders[1], 'cap_b')])
        assert sorted(r['state'] for r in cap_results) == ['delivered', 'paid_review']
        with checked_connection() as conn:
            duplicate_state = conn.execute('''SELECT initial_wood,content_inventory FROM public.player_gameplay_stats s
              JOIN public.player_archive_state a ON a.account_id=s.player_id WHERE s.player_id=%s''', (buyers['same'],)).fetchone()
            assert Decimal(str(duplicate_state[0])) - Decimal(str(defaults['initial_wood'])) == 3
            assert duplicate_state[1][bulk['item_id']] == duplicate_state[1][token] == 3
            cap_state = conn.execute('''SELECT initial_wood,content_inventory FROM public.player_gameplay_stats s
              JOIN public.player_archive_state a ON a.account_id=s.player_id WHERE s.player_id=%s''', (buyers['cap'],)).fetchone()
            assert Decimal(str(cap_state[0])) - Decimal(str(defaults['initial_wood'])) == 6 and cap_state[1][token] == 6
            assert sum(cap_state[1].get(p['item_id'], 0) for p in (capped_a, capped_b)) == 6
            assert conn.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s', (buyers['same'],)).fetchone()[0] == 1
        return dict(real_parallel_connections=True, different_quantities_one_immutable_intent_warning=True,
                    same_quantity_one_intent=True, different_providers_one_intent_warning=True,
                    duplicate_callback_grants_exact_batch_once=True, overlapping_batch_item_caps_one_review=True,
                    synthetic_fixture_cleanup=True, database='disposable localhost only')
    finally:
        with checked_connection() as conn:
            identities, products = sorted(accounts), sorted(skus)
            conn.execute('DELETE FROM payments.vip_recharge_credits WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM payments.orders WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.match_profile_sessions WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.archive_entitlements WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.player_archive_state WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.player_gameplay_stats WHERE player_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.survival_players WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM payments.products WHERE sku=ANY(%s)', (products,))


class OfflineContractTests(unittest.TestCase):
    def test_migration_does_not_seed_or_mutate_existing_orders(self):
        sql = MIGRATION.read_text(encoding='utf-8')
        self.assertNotIn('UPDATE payments.orders SET reward', sql)
        self.assertNotIn('INSERT INTO payments.products', sql)
        self.assertNotIn('COMMIT;', sql.upper())
        self.assertIn('order_quantity_delivery_definition_unexpected', sql)


if __name__ == '__main__':
    unittest.main()
