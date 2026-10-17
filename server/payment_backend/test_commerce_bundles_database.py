"""Real SQL checks for commerce bundles; run_checks fixtures must be rolled back.

Apply upgrade_commerce_bundles.sql after the existing monthly-pass and VIP
recharge migrations, then call run_checks inside an outer rollback transaction.
Importing the module never opens a connection, creates an order, or contacts a gateway.
Synthetic accounts, products, order IDs and transaction IDs use a fresh nonce.
The separately invoked concurrency helper commits/cleans synthetic fixtures only
inside the exact, disposable localhost database survival_bundle_test.
"""
from copy import deepcopy
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
import hashlib
from pathlib import Path
import secrets
import threading
import unittest


MIGRATION = Path(__file__).with_name('upgrade_commerce_bundles.sql')


def run_checks(conn, catalog=None):
    from psycopg.types.json import Jsonb

    assert not conn.autocommit, 'commerce fixtures require an outer rollback transaction'
    assert conn.info.transaction_status.name == 'INTRANS'
    nonce = secrets.token_hex(16)
    fixture_accounts = set()
    session = 'commerce_bundle_fixture_' + nonce
    defaults = conn.execute("SELECT coalesce(jsonb_object_agg(field_id,default_value),'{}'::jsonb) FROM payments.stat_rules").fetchone()[0]
    provider = conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()
    assert provider, 'fixture requires the existing configured provider'

    def digest(label):
        return hashlib.sha256(('commerce_bundle_fixture:' + nonce + ':' + label).encode()).hexdigest()

    def oid(label):
        return 'WX' + digest('order:' + label)[:30]

    def transaction(label):
        return '420000' + str(int(digest('transaction:' + label)[:30], 16)).zfill(37)

    def call(name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def buyer(label, recharge=0, archive=None, inventory=None):
        account = digest('account:' + label)
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (account,)).fetchone()
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)', (account, Jsonb(defaults)))
        assert conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',
                            (account, session, 'standard', Jsonb(defaults))).fetchone()[0]['ok']
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
                     (account, Jsonb(archive or {'keep': 123}), Jsonb(inventory or {'keep_item': 3})))
        conn.execute('UPDATE public.player_gameplay_stats SET vip_recharge_total_fen=%s,vip_level=0 WHERE player_id=%s',
                     (recharge, account))
        fixture_accounts.add(account)
        return account

    def state(account):
        return conn.execute('''SELECT to_jsonb(s),a.archive,a.content_inventory,p.profile_revision,
          (SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY entitlement_id),'[]') FROM public.archive_entitlements e WHERE e.account_id=p.account_id)
          FROM public.player_gameplay_stats s JOIN public.survival_players p ON p.account_id=s.player_id
          LEFT JOIN public.player_archive_state a ON a.account_id=p.account_id WHERE s.player_id=%s''', (account,)).fetchone()

    def wood(account):
        return Decimal(str(state(account)[0]['initial_wood']))

    fixtures = {}

    def product(label, amount, effects, grants=None, marker=None):
        sku = 'cbf_' + label + '_' + nonce[:12]
        marker = marker or 'cbf_owned_' + label + '_' + nonce[:12]
        grants = dict(items={}, item_limits={}, entitlements=[], lines=[]) | deepcopy(grants or {})
        data = dict(sku=sku, item_id=marker, amount=amount, effects=effects, grants=grants)
        conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
          grants,category_id,product_type,icon,purchase_limit)
          VALUES(%s,%s,%s,'rollback-only synthetic fixture',%s,%s,true,100,%s,'bundles',%s,
          'custom_game/reward_art_v5/daily_wealth_talisman.png',1)''',
          (sku, marker, label, amount, Jsonb(effects), Jsonb(grants), 'bundle' if grants.get('components') or grants.get('vip_claims') else 'single'))
        fixtures[label] = data
        return data

    a = product('single_a', 100, {'initial_wood': 11})
    b = product('single_b', 200, {'initial_wood': 17})
    c = product('single_c', 300, {'initial_wood': 23})

    def bundle(label, components):
        return product(label, 250, {'initial_wood': sum(p['effects']['initial_wood'] for p in components)}, {
            'components': [dict(sku=p['sku'], item_id=p['item_id'], quantity=1, purchase_limit=1) for p in components],
            'items': {p['item_id']: 1 for p in components}, 'item_limits': {p['item_id']: 1 for p in components},
            'pricing': {'u_coin_price': 2500, 'u_coin_per_yuan': 1000, 'original_u_coin_price': 3000},
        })

    ab, bc = bundle('bundle_ab', [a, b]), bundle('bundle_bc', [b, c])
    vip = product('vip_one', 500, {'initial_wood': 107}, {
        'required_vip_level': 1, 'vip_claims': ['vip_package_01', 'vip_medal_01'],
        'vip_claim_effects': {'vip_medal_01': {'initial_wood': 7}},
        'pricing': {'u_coin_price': 5000, 'u_coin_per_yuan': 1000, 'original_u_coin_price': 6000},
    })
    multi_vip = product('vip_multi', 1000, {'initial_wood': 320}, {
        'required_vip_level': 2,
        'vip_claims': ['vip_package_01', 'vip_medal_01', 'vip_package_02', 'vip_medal_02'],
        'vip_claim_effects': {'vip_medal_01': {'initial_wood': 7}, 'vip_medal_02': {'initial_wood': 13}},
    })

    def make(account, p, label):
        return call('create_order', account, session, oid(label), p['sku'])

    def pay(order, label, amount=None):
        assert order['account_id'] in fixture_accounts, 'only nonce-derived fixture accounts may receive a test delivery'
        assert order['order_id'].startswith('WX') and order['sku'] in {p['sku'] for p in fixtures.values()}
        return call('deliver', order['order_id'], transaction(label), order['amount'] if amount is None else amount, *provider)

    def raises(callback):
        try:
            with conn.transaction():
                callback()
        except Exception:
            return
        raise AssertionError('invalid internal fixture unexpectedly accepted')

    # No endpoint accepts a caller-provided price/grant JSON. Opening a catalog
    # and an unpaid intent changes no ownership, attributes or archive claims.
    main = buyer('main')
    before = state(main)
    assert call('catalog', main, 'missing_session')['error'] == 'match_session_missing'
    listed = {p['sku']: p for p in call('catalog', main, session)['products']}
    assert listed[ab['sku']]['original_u_coin_price'] == 3000
    assert listed[vip['sku']]['required_vip_level'] == 1
    assert listed[vip['sku']]['disabled_reason'] == 'vip_level_required'
    order = make(main, ab, 'immutable')
    assert make(main, ab, 'same_intent')['order_id'] == order['order_id']
    assert state(main) == before
    assert order['reward']['version'] == 4 and order['reward']['grants'] == ab['grants']
    raises(lambda: pay(order, 'wrong_amount', 1))
    assert state(main) == before and call('get_order', order['order_id'])['state'] == 'created'
    # Re-publishing prices, component lists or effects cannot change an existing
    # order. The original receipt is delivered with its immutable snapshot.
    with conn.transaction(force_rollback=True):
        conn.execute("UPDATE payments.products SET amount=777,effects='{\"initial_wood\":999}',grants='{}',enabled=false WHERE sku=%s", (ab['sku'],))
        receipt = pay(order, 'immutable')
        assert receipt['state'] == 'delivered' and receipt['amount'] == 250
        assert receipt['reward'] == order['reward']
        assert wood(main) - Decimal(str(before[0]['initial_wood'])) == 28
    receipt = pay(order, 'immutable')
    assert receipt['state'] == 'delivered'
    assert receipt['applied_items'] == {ab['item_id']: 1, a['item_id']: 1, b['item_id']: 1}
    settled = state(main)
    assert pay(order, 'immutable')['state'] == 'delivered' and state(main) == settled
    assert make(main, a, 'bundle_then_single')['error'] == 'already_owned'
    # Even missing/deleted ownership cache cannot bypass a paid component cap.
    conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s', (a['item_id'], main))
    assert make(main, a, 'bundle_then_single_history')['error'] == 'purchase_limit_reached'
    single_owner = buyer('single_owner')
    assert pay(make(single_owner, a, 'single_first'), 'single_first')['state'] == 'delivered'
    assert make(single_owner, ab, 'single_then_bundle')['error'] == 'component_already_owned'
    conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s', (a['item_id'], single_owner))
    assert make(single_owner, ab, 'single_then_bundle_history')['error'] == 'component_already_owned'

    # Two different intents may predate each other. Settlement is serialized by
    # the account row locks and rechecks the immutable component limits; the
    # losing paid receipt is retained for review with no partial extra rewards.
    overlap = buyer('overlap')
    first, second = make(overlap, ab, 'overlap_ab'), make(overlap, bc, 'overlap_bc')
    assert pay(first, 'overlap_ab')['state'] == 'delivered'
    overlap_before = state(overlap)
    assert pay(second, 'overlap_bc')['state'] == 'paid_review'
    assert state(overlap) == overlap_before and c['item_id'] not in state(overlap)[2]
    assert pay(second, 'overlap_bc')['state'] == 'paid_review' and state(overlap) == overlap_before

    # A membership entitlement or a forged cached vip_level cannot substitute
    # for actual cumulative recharge thresholds. Max tier governs multi-packs.
    member_only = buyer('member_only')
    conn.execute("INSERT INTO public.archive_entitlements(account_id,entitlement_id,active) VALUES(%s,'vip',true)", (member_only,))
    conn.execute('UPDATE public.player_gameplay_stats SET vip_level=12 WHERE player_id=%s', (member_only,))
    assert make(member_only, vip, 'member_not_level')['error'] == 'vip_level_required'
    below_tier = buyer('below_tier', 4999)
    assert make(below_tier, vip, 'below_tier')['error'] == 'vip_level_required'
    low_tier = buyer('low_tier', 5000)
    assert make(low_tier, multi_vip, 'low_multi')['error'] == 'vip_level_required'
    legacy_package = buyer('legacy_package', 5000, {'keep': 123, 'vip_claimed': {'vip_package_01': True, 'vip_medal_01': True}})
    assert make(legacy_package, vip, 'legacy_package')['error'] == 'already_owned'
    vip_buyer = buyer('vip_buyer', 5000)
    old_wood = wood(vip_buyer)
    vip_order = make(vip_buyer, vip, 'vip_first')
    vip_receipt = pay(vip_order, 'vip_first')
    assert vip_receipt['state'] == 'delivered' and wood(vip_buyer) - old_wood == 107
    assert state(vip_buyer)[1]['vip_claimed'] == {'vip_package_01': True, 'vip_medal_01': True}
    assert set(vip_receipt['applied_archive']['vip_claimed']) == {'vip_package_01', 'vip_medal_01'}
    after_vip = state(vip_buyer)
    assert pay(vip_order, 'vip_first')['state'] == 'delivered' and state(vip_buyer) == after_vip
    assert make(vip_buyer, vip, 'vip_again')['error'] == 'already_owned'
    medal_owner = buyer('medal_owner', 5000, {'keep': 123, 'vip_claimed': {'vip_medal_01': True}})
    medal_wood = wood(medal_owner)
    medal_catalog = next(p for p in call('catalog', medal_owner, session)['products'] if p['sku'] == vip['sku'])
    assert medal_catalog['enabled']
    assert next(p['delta'] for p in medal_catalog['stat_preview'] if p['field_id'] == 'initial_wood') == 100
    medal_order = make(medal_owner, vip, 'medal_owned')
    medal_receipt = pay(medal_order, 'medal_owned')
    assert medal_receipt['state'] == 'delivered' and wood(medal_owner) - medal_wood == 100
    assert medal_receipt['reward']['effects']['initial_wood'] == 107, 'immutable reward was rewritten'
    assert medal_receipt['applied_effects']['initial_wood'] == 100
    assert set(medal_receipt['applied_archive']['vip_claimed']) == {'vip_package_01'}
    medal_inventory_owner = buyer('medal_inventory_owner', 5000, inventory={'keep_item': 3, 'vip_medal_01': 1})
    inventory_medal_wood = wood(medal_inventory_owner)
    assert pay(make(medal_inventory_owner, vip, 'medal_inventory'), 'medal_inventory')['state'] == 'delivered'
    assert wood(medal_inventory_owner) - inventory_medal_wood == 100
    assert state(medal_inventory_owner)[1]['vip_claimed']['vip_medal_01'] is True
    high_tier = buyer('high_tier', 10000, {'keep': 123, 'vip_claimed': {'vip_medal_01': True}})
    high_wood = wood(high_tier)
    assert pay(make(high_tier, multi_vip, 'multi_vip'), 'multi_vip')['state'] == 'delivered'
    assert wood(high_tier) - high_wood == 313
    assert set(state(high_tier)[1]['vip_claimed']) == {'vip_package_01', 'vip_medal_01', 'vip_package_02', 'vip_medal_02'}
    # Legacy archive claim wins while payment is pending: no package/medal/stat
    # duplication and the verified paid order remains visible for review.
    race_buyer = buyer('legacy_race', 5000)
    race_order = make(race_buyer, vip, 'legacy_race')
    conn.execute("UPDATE public.player_archive_state SET archive=archive||'{\"vip_claimed\":{\"vip_package_01\":true,\"vip_medal_01\":true}}' WHERE account_id=%s", (race_buyer,))
    race_before = state(race_buyer)
    assert pay(race_order, 'legacy_race')['state'] == 'paid_review' and state(race_buyer) == race_before

    # Errors after ownership/archive writes roll back every earlier operation,
    # transaction ID, receipt and profile revision in the same SQL statement.
    broken = buyer('broken', 5000)
    broken_order = make(broken, vip, 'broken')
    conn.execute("UPDATE payments.orders SET reward=jsonb_set(reward,'{effects}','{\"initial_wood\":107,\"missing_field\":1}') WHERE order_id=%s", (broken_order['order_id'],))
    broken_before = state(broken)
    raises(lambda: pay(broken_order, 'broken'))
    assert state(broken) == broken_before
    assert call('get_order', broken_order['order_id'])['state'] == 'created'
    assert call('get_order', broken_order['order_id'])['transaction_id'] is None
    call('update_gateway', broken_order['order_id'], 'closed', None)

    # Test resets remove only this purchase's claims/effects. An existing medal
    # and unrelated archive content survive, including already captured baselines.
    with conn.transaction(force_rollback=True):
        reset_buyer = buyer('reset', 5000, {'keep': 123, 'vip_claimed': {'vip_medal_01': True, 'vip_package_02': False}})
        conn.execute('UPDATE payments.test_settings SET enabled=true WHERE singleton')
        conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)', (reset_buyer,))
        original = state(reset_buyer)
        reset_order = make(reset_buyer, vip, 'reset_vip')
        assert pay(reset_order, 'reset_vip')['state'] == 'delivered'
        assert pay(make(reset_buyer, ab, 'reset_ab'), 'reset_ab')['state'] == 'delivered'
        # Baselines created during this payment generation must also lose only
        # the cleared purchase; pre-existing medal/other gains are retained.
        later_session = session + '_later'
        conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)', (reset_buyer, later_session, 'standard', Jsonb(defaults)))
        conn.execute("UPDATE public.player_archive_state SET archive=archive||'{\"later_gain\":9}' WHERE account_id=%s", (reset_buyer,))
        assert call('begin_reset', reset_buyer, session, 'refreshmoney', 'commerce_bundle_reset')['ok']
        assert call('finish_reset', reset_buyer, session, 'refreshmoney', 'commerce_bundle_reset')['ok']
        cleared = state(reset_buyer)
        assert cleared[1] == original[1] | {'later_gain': 9}
        assert cleared[2] == original[2]
        assert cleared[0]['initial_wood'] == original[0]['initial_wood']
        baseline = conn.execute('SELECT baseline FROM public.match_profile_sessions WHERE account_id=%s AND match_session_id=%s',
                                (reset_buyer, later_session)).fetchone()[0]
        assert baseline['save']['archive']['vip_claimed'] == original[1]['vip_claimed']
        assert pay(reset_order, 'reset_vip')['state'] == 'delivered' and state(reset_buyer) == cleared
        assert call('finish_reset', reset_buyer, session, 'refreshmoney', 'commerce_bundle_reset')['ok']
        assert state(reset_buyer) == cleared, 'reset retry changed the archive again'
        assert make(reset_buyer, vip, 'reset_repurchase')['order_id'] == oid('reset_repurchase')
        empty_reset_buyer = buyer('reset_empty_claims', 5000)
        conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)', (empty_reset_buyer,))
        empty_before = state(empty_reset_buyer)
        empty_order = make(empty_reset_buyer, vip, 'reset_empty_claims')
        assert pay(empty_order, 'reset_empty_claims')['state'] == 'delivered'
        assert call('begin_reset', empty_reset_buyer, session, 'refreshmoney', 'commerce_empty_claim_reset')['ok']
        assert call('finish_reset', empty_reset_buyer, session, 'refreshmoney', 'commerce_empty_claim_reset')['ok']
        assert state(empty_reset_buyer)[1] == empty_before[1], 'reset left an empty/new VIP claim map behind'
        assert state(empty_reset_buyer)[2] == empty_before[2]
        assert wood(empty_reset_buyer) == Decimal(str(empty_before[0]['initial_wood']))

    # Invalid server-side publication metadata fails closed, rather than silently
    # dropping components, granting negative effects or claiming the wrong medal.
    invalid_grants = []
    for quantity in (0, -1, 0.5):
        bad = deepcopy(ab['grants']); bad['components'][0]['quantity'] = quantity; invalid_grants.append((bad, ab['effects']))
    bad = deepcopy(ab['grants']); bad['components'].append(deepcopy(bad['components'][0])); invalid_grants.append((bad, ab['effects']))
    bad = deepcopy(ab['grants']); bad['items'][a['item_id']] = 2; invalid_grants.append((bad, ab['effects']))
    bad = deepcopy(vip['grants']); bad['required_vip_level'] = 0; invalid_grants.append((bad, vip['effects']))
    bad = deepcopy(multi_vip['grants']); bad['required_vip_level'] = 1; invalid_grants.append((bad, multi_vip['effects']))
    bad = deepcopy(vip['grants']); bad['vip_claims'].append('vip_medal_02'); invalid_grants.append((bad, vip['effects']))
    bad = deepcopy(vip['grants']); bad['vip_claim_effects']['vip_medal_01']['initial_wood'] = 108; invalid_grants.append((bad, vip['effects']))
    for grants, effects in invalid_grants:
        raises(lambda: call('validate_commerce_bundle', Jsonb(grants), Jsonb(effects)))
    formal_bundles_tested = 0
    disabled_bundles_blocked = []
    if catalog is not None:
        for p in catalog['products']:
            if p['enabled']:
                call('validate_commerce_bundle', Jsonb(p['grants']), Jsonb(p['effects']))
            if not p['sku'].startswith('video_bundle_'):
                continue
            formal_account = buyer('formal:' + p['sku'], 1250000)
            formal_label = 'formal:' + p['sku']
            formal_order = make(formal_account, p, formal_label)
            if not p['enabled']:
                assert formal_order['error'] == 'product_unavailable'
                assert p['sku'] not in {listed['sku'] for listed in call('catalog', formal_account, session)['products']}
                disabled_bundles_blocked.append(p['sku'])
                continue
            formal_before = state(formal_account)
            assert formal_order['amount'] == p['amount']
            assert formal_order['reward']['grants'] == p['grants']
            assert formal_order['reward']['effects'] == p['effects']
            # Only synthetic nonce-derived buyers receive these direct SQL
            # callbacks. The real provider/gateway is never contacted.
            assert formal_account in fixture_accounts
            formal_receipt = call('deliver', formal_order['order_id'], transaction(formal_label), p['amount'], *provider)
            assert formal_receipt['state'] == 'delivered', p['sku']
            formal_after = state(formal_account)
            for field, delta in p['effects'].items():
                assert Decimal(str(formal_after[0][field])) - Decimal(str(formal_before[0][field])) == Decimal(str(delta)), (p['sku'], field)
            for item, quantity in p['grants']['items'].items():
                assert formal_after[2][item] - formal_before[2].get(item, 0) == quantity, (p['sku'], item)
            assert formal_after[2][p['item_id']] == 1
            for claim in p['grants'].get('vip_claims', []):
                assert formal_after[1]['vip_claimed'][claim] is True
            assert call('deliver', formal_order['order_id'], transaction(formal_label), p['amount'], *provider)['state'] == 'delivered'
            assert state(formal_account) == formal_after, p['sku'] + ': replay duplicated a formal reward'
            formal_bundles_tested += 1
    for role in ('goufayu_payment', 'goufayu_app'):
        for helper in ('validate_commerce_bundle(jsonb,jsonb)', 'commerce_bundle_effects(text,jsonb,jsonb)',
                       'product_block(text,text,integer,jsonb,jsonb)', 'finish_reset_pre_commerce_bundles(text,text,text,text)'):
            assert not conn.execute('SELECT has_function_privilege(%s,%s,%s)',
                                    (role, 'payments.' + helper, 'EXECUTE')).fetchone()[0]
    return dict(component_single_bundle_mutual_exclusion=True, historical_limits=True,
                overlapping_pending_deliveries_atomic=True, immutable_amount_and_grants=True,
                vip_real_recharge_gate=True, vip_multiple_packages_and_medal_deduplication=True,
                legacy_claim_races_reviewed=True, failed_grants_fully_rollback=True,
                reset_reverses_only_actual_claims_and_preserves_baselines=True,
                private_helpers=True, fixture_writes='caller_must_roll_back',
                parallel_connections_tested=False, formal_bundles_delivered=formal_bundles_tested,
                disabled_formal_bundles_blocked=disabled_bundles_blocked)


def run_concurrency_checks(connect):
    """Two real connections, only in the disposable localhost test database.

    Unlike run_checks, concurrent connections need committed synthetic fixtures.
    This explicitly restricted helper removes only its nonce-derived rows in a
    finally block. It never accepts a production DSN or touches original players.
    The supplied zero-argument factory must open an administrative connection.
    """
    from psycopg.types.json import Jsonb

    nonce = secrets.token_hex(16)
    accounts, products = set(), set()
    session = 'commerce_parallel_' + nonce

    def digest(label):
        return hashlib.sha256(('commerce_parallel:' + nonce + ':' + label).encode()).hexdigest()

    def checked_connection():
        conn = connect()
        if conn.info.host != '127.0.0.1' or conn.info.dbname != 'survival_bundle_test':
            conn.close()
            raise AssertionError('parallel_fixture_requires_disposable_localhost_database')
        conn.execute('SET ROLE goufayu_owner')
        conn.execute("SET statement_timeout='15s'")
        conn.execute("SET lock_timeout='10s'")
        return conn

    def call(conn, name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def oid(label):
        return 'WX' + digest('order:' + label)[:30]

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
            assert conn.execute("SELECT to_regprocedure('payments.validate_commerce_bundle(jsonb,jsonb)') IS NOT NULL").fetchone()[0]
            defaults = conn.execute("SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules").fetchone()[0]
            provider = conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()

            def account(label, recharge=0):
                identity = digest('account:' + label)
                assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (identity,)).fetchone()
                accounts.add(identity)
                conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)', (identity, Jsonb(defaults)))
                conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)', (identity, session, 'standard', Jsonb(defaults)))
                conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{\"keep\":123}','{\"keep_item\":3}')", (identity,))
                conn.execute('UPDATE public.player_gameplay_stats SET vip_recharge_total_fen=%s WHERE player_id=%s', (recharge, identity))
                return identity

            def product(label, amount, effects, grants=None):
                sku, marker = 'cpf_' + label + '_' + nonce[:12], 'cpf_owned_' + label + '_' + nonce[:12]
                products.add(sku)
                grants = dict(items={}, item_limits={}, entitlements=[], lines=[]) | (grants or {})
                conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
                  grants,category_id,product_type,icon,purchase_limit)
                  VALUES(%s,%s,'parallel synthetic fixture','local disposable DB only',%s,%s,true,100,%s,'bundles','bundle','',1)''',
                  (sku, marker, amount, Jsonb(effects), Jsonb(grants)))
                return dict(sku=sku, item_id=marker, amount=amount, effects=effects)

            single_a = product('single_a', 100, {'initial_wood': 11})
            single_b = product('single_b', 100, {'initial_wood': 17})
            single_c = product('single_c', 100, {'initial_wood': 23})

            def bundle(label, parts):
                return product(label, 250, {'initial_wood': sum(p['effects']['initial_wood'] for p in parts)}, {
                    'components': [dict(sku=p['sku'], item_id=p['item_id'], quantity=1, purchase_limit=1) for p in parts],
                    'items': {p['item_id']: 1 for p in parts}, 'item_limits': {p['item_id']: 1 for p in parts}})

            bundle_ab, bundle_bc = bundle('bundle_ab', [single_a, single_b]), bundle('bundle_bc', [single_b, single_c])
            vip_grants = dict(required_vip_level=1, vip_claims=['vip_package_01', 'vip_medal_01'],
                              vip_claim_effects={'vip_medal_01': {'initial_wood': 7}})
            vip_a = product('vip_a', 500, {'initial_wood': 107}, vip_grants)
            vip_b = product('vip_b', 500, {'initial_wood': 107}, vip_grants)
            buyers = {name: account(name, 5000 if name == 'vip' else 0)
                      for name in ('create', 'retry', 'overlap', 'single_bundle', 'vip')}
            orders = {}
            for label, who, p in [('retry', 'retry', bundle_ab), ('overlap_ab', 'overlap', bundle_ab),
                                  ('overlap_bc', 'overlap', bundle_bc), ('single', 'single_bundle', single_a),
                                  ('bundle', 'single_bundle', bundle_ab), ('vip_a', 'vip', vip_a), ('vip_b', 'vip', vip_b)]:
                orders[label] = call(conn, 'create_order', buyers[who], session, oid(label), p['sku'])
                assert orders[label].get('order_id') == oid(label)

        def pay(label):
            order = orders[label]
            return lambda conn: call(conn, 'deliver', order['order_id'], tx(label), order['amount'], *provider)

        created = concurrent([
            lambda conn: call(conn, 'create_order', buyers['create'], session, oid('create_a'), single_c['sku']),
            lambda conn: call(conn, 'create_order', buyers['create'], session, oid('create_b'), single_c['sku'])])
        assert created[0]['order_id'] == created[1]['order_id'], 'concurrent intent retry created two payable orders'
        retries = concurrent([pay('retry'), pay('retry')])
        assert all(result['state'] == 'delivered' for result in retries)
        overlap = concurrent([pay('overlap_ab'), pay('overlap_bc')])
        assert sorted(result['state'] for result in overlap) == ['delivered', 'paid_review']
        single_bundle = concurrent([pay('single'), pay('bundle')])
        assert sorted(result['state'] for result in single_bundle) == ['delivered', 'paid_review']
        vip_results = concurrent([pay('vip_a'), pay('vip_b')])
        assert sorted(result['state'] for result in vip_results) == ['delivered', 'paid_review']
        with checked_connection() as conn:
            def saved(who):
                return conn.execute('''SELECT initial_wood,archive,content_inventory FROM public.player_gameplay_stats s
                  JOIN public.player_archive_state a ON a.account_id=s.player_id WHERE s.player_id=%s''', (buyers[who],)).fetchone()
            base_wood = Decimal(str(defaults['initial_wood']))
            retry_state = saved('retry')
            assert Decimal(retry_state[0]) - base_wood == 28
            assert retry_state[2][single_a['item_id']] == retry_state[2][single_b['item_id']] == 1
            overlap_state = saved('overlap')
            winner = next(result for result in overlap if result['state'] == 'delivered')
            assert Decimal(overlap_state[0]) - base_wood == Decimal(str(winner['applied_effects']['initial_wood']))
            assert overlap_state[2][single_b['item_id']] == 1
            single_state = saved('single_bundle')
            winner = next(result for result in single_bundle if result['state'] == 'delivered')
            assert Decimal(single_state[0]) - base_wood == Decimal(str(winner['applied_effects']['initial_wood']))
            assert single_state[2][single_a['item_id']] == 1
            vip_state = saved('vip')
            assert Decimal(vip_state[0]) - base_wood == 107
            assert vip_state[1]['vip_claimed'] == {'vip_package_01': True, 'vip_medal_01': True}
            assert conn.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s', (buyers['retry'],)).fetchone()[0] == 1
        return dict(real_parallel_connections=True, simultaneous_intent_idempotency=True,
                    simultaneous_callback_idempotency=True, overlapping_bundles_one_review=True,
                    simultaneous_single_bundle_one_review=True, simultaneous_vip_package_medal_once=True,
                    fixture_scope='disposable_localhost_database_only', fixture_cleanup=True)
    finally:
        # These identities/products are generated locally, never accepted from a
        # caller. Do not weaken the exact localhost/name guard above.
        with checked_connection() as conn:
            identities, skus = sorted(accounts), sorted(products)
            conn.execute('DELETE FROM payments.vip_recharge_credits WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM payments.orders WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM payments.test_resets WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM payments.test_accounts WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.match_profile_sessions WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.archive_entitlements WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.player_archive_state WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.player_gameplay_stats WHERE player_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM public.survival_players WHERE account_id=ANY(%s)', (identities,))
            conn.execute('DELETE FROM payments.products WHERE sku=ANY(%s)', (skus,))


class MigrationContractTests(unittest.TestCase):
    """Offline guardrails; these do not substitute for run_checks on PostgreSQL."""

    def test_no_fixture_or_client_grant_rpc_is_published(self):
        sql = MIGRATION.read_text(encoding='utf-8')
        self.assertNotIn('INSERT INTO payments.products', sql)
        self.assertNotIn('CREATE OR REPLACE FUNCTION payments.create_order', sql)
        self.assertNotIn('COMMIT;', sql.upper())
        self.assertIn('commerce_bundles_prerequisite_missing', sql)

    def test_delivery_keeps_gateway_validation_and_lock_order(self):
        sql = MIGRATION.read_text(encoding='utf-8')
        delivery = sql.split('CREATE OR REPLACE FUNCTION payments.deliver(', 1)[1].split('END; $$;', 1)[0]
        self.assertLess(delivery.index('player_gameplay_stats WHERE player_id=a FOR UPDATE'),
                        delivery.index('survival_players WHERE account_id=a FOR UPDATE'))
        self.assertLess(delivery.index('survival_players WHERE account_id=a FOR UPDATE'),
                        delivery.index('orders WHERE order_id=p_order FOR UPDATE'))
        self.assertIn("IF o.state IN ('delivered','paid_review')", delivery)
        self.assertIn("RAISE EXCEPTION 'payment_mismatch'", delivery)
        self.assertIn("payments.deliver_v3", delivery)


if __name__ == '__main__':
    unittest.main()
