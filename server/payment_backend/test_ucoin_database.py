"""PostgreSQL U-coin order checks; caller MUST roll back the outer transaction.

Call run_checks(conn, package['catalog']) after applying that catalog and its
stat rules in the same transaction. Requires the v4 product/order schema,
provider migration and existing profile/session functions. Only nonce-derived
synthetic accounts and orders are created. No payment gateway is called.
"""
import copy
from decimal import Decimal
import hashlib
import json
import secrets

from .ucoin_catalog import U_COIN_PER_YUAN


def run_checks(conn, catalog):
    assert not conn.autocommit, 'fixture requires a caller-owned rollback transaction'
    assert conn.info.transaction_status.name == 'INTRANS', 'apply the catalog before running the fixture'
    products = [product for product in catalog['products'] if 'u_coin_price' in product]
    assert len(products) == 24, 'expected the reviewed 24 U-coin payment products'
    assert all(product['enabled'] for product in products)
    by_sku = {product['sku']: product for product in products}
    stat_product = by_sku['video_p004']
    ticket_product = by_sku['video_p001']
    assert stat_product['effects'] and stat_product['purchase_limit'] == 1
    assert ticket_product['grants']['items'] == {'special_lottery_ticket': 1}
    assert ticket_product['purchase_limit'] == 0

    nonce = secrets.token_hex(16)

    def digest(label):
        return hashlib.sha256(('ucoin_database_fixture:' + nonce + ':' + label).encode()).hexdigest()

    account, wallet_account = digest('buyer'), digest('wallet_owner')
    session = 'ucoin_fixture_' + nonce

    def oid(label):
        return 'WX' + digest('order:' + label)[:30]

    def transaction(label):
        return '420000' + str(int(digest('transaction:' + label)[:30], 16)).zfill(37)

    def call(name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def profile(identity=account):
        return conn.execute('SELECT public.fishing_profile_json(%s)', (identity,)).fetchone()[0]

    def make(product, label, identity=account):
        return call('create_order', identity, session, oid(label), product['sku'])

    provider = conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()
    assert provider, 'the existing WeChat provider must be enabled'

    def pay(order, label, amount=None):
        stored = call('get_order', order['order_id'])
        assert stored['account_id'] == account, 'delivery is restricted to this synthetic buyer'
        return call('deliver', order['order_id'], transaction(label),
                    order['amount'] if amount is None else amount, provider[0], provider[1])

    defaults = conn.execute("SELECT coalesce(jsonb_object_agg(field_id,default_value),'{}'::jsonb) FROM payments.stat_rules").fetchone()[0]
    assert defaults, 'payment stat rules must be deployed before the fixture'
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id IN (%s,%s)',
                            (account, wallet_account)).fetchone(), 'synthetic fixture identity collision'
    wallet_inventory = {'keep_item': 3}
    limited = [product for product in products if product['purchase_limit'] > 0]
    for product in limited:
        wallet_inventory[product['item_id']] = product['purchase_limit']
    archive = {'keep_archive': 123, 'commerce': {'balances': {'u_coin': 17, 'shop_points': 19, 'shop_gold': 23}}}
    for identity, inventory in ((account, {'keep_item': 3}), (wallet_account, wallet_inventory)):
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)', (identity, json.dumps(defaults)))
        login = conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',
                             (identity, session, 'standard', json.dumps(defaults))).fetchone()[0]
        assert login['ok']
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s::jsonb,%s::jsonb)',
                     (identity, json.dumps(archive), json.dumps(inventory)))
        assert not call('is_test_account', identity), 'purchase limits must use normal account rules'

    before = profile()
    orders = {}
    for product in products:
        sku = product['sku']
        order = make(product, sku)
        assert order.get('order_id') == oid(sku), (sku, order)
        assert order['account_id'] == account and order['provider'] == 'wechat'
        assert order['amount'] == product['amount'] == product['u_coin_price'] // 10
        assert product['u_coin_per_yuan'] == U_COIN_PER_YUAN
        reward = order['reward']
        assert reward['version'] == 4
        assert reward['item_id'] == product['item_id'] and reward['quantity'] == 1
        assert reward['purchase_limit'] == product['purchase_limit']
        assert reward['effects'] == product['effects'] and reward['grants'] == product['grants']
        assert reward['grants']['pricing'] == {'u_coin_price': product['u_coin_price'], 'u_coin_per_yuan': 1000}
        assert make(product, 'retry:' + sku)['order_id'] == order['order_id'], 'pending order was duplicated: ' + sku
        orders[sku] = order
    assert profile() == before, 'unpaid intents changed the synthetic buyer profile'
    assert conn.execute('SELECT count(*) FROM payments.orders WHERE account_id=%s', (account,)).fetchone()[0] == 24

    def verify_delivery(product, order, label):
        prior = profile()
        receipt = pay(order, label)
        assert receipt['state'] == 'delivered' and receipt['amount'] == order['amount']
        assert receipt['reward'] == order['reward'], 'delivery changed the immutable reward'
        after = profile()
        expected = copy.deepcopy(prior['save']['content_inventory'])
        expected[product['item_id']] = expected.get(product['item_id'], 0) + 1
        for item, quantity in product['grants']['items'].items():
            expected[item] = expected.get(item, 0) + quantity
        assert after['save']['content_inventory'] == expected, 'incomplete or extra item reward'
        for field, delta in product['effects'].items():
            assert Decimal(str(after['save']['gameplay_stats'][field])) - Decimal(str(prior['save']['gameplay_stats'][field])) == Decimal(str(delta)), field
            assert Decimal(str(receipt['effect_changes'][field]['delta'])) == Decimal(str(delta)), field
        assert receipt['applied_effects'] == product['effects']
        assert after['save']['archive'] == prior['save']['archive'], 'cash purchase debited the wallet or changed unrelated archive data'
        assert pay(order, label)['state'] == 'delivered'
        assert profile() == after, 'duplicate delivery granted a second reward'
        return receipt

    first = orders[stat_product['sku']]
    # A failed SQL delivery must roll back to its savepoint before more checks.
    try:
        with conn.transaction():
            pay(first, 'wrong_amount', first['amount'] + 1)
    except Exception as error:
        assert getattr(error, 'sqlstate', None) == 'P0001', 'unexpected SQL failure instead of amount rejection'
        assert 'payment_mismatch' in str(error), 'wrong amount failed for an unrelated reason'
    else:
        raise AssertionError('wrong payment amount was accepted')
    assert call('get_order', first['order_id'])['state'] == 'created'
    assert profile() == before, 'failed delivery left partial rewards'

    # Change only the newly applied product inside a rollback savepoint. Both the
    # catalog update and fixture delivery are undone before returning to caller.
    with conn.transaction(force_rollback=True):
        changed_grants = copy.deepcopy(stat_product['grants'])
        changed_grants['pricing']['u_coin_price'] += 100
        conn.execute('UPDATE payments.products SET amount=%s,effects=%s::jsonb,grants=%s::jsonb WHERE sku=%s',
                     (stat_product['amount'] + 10, json.dumps({'initial_wood': 999}), json.dumps(changed_grants), stat_product['sku']))
        repeated = make(stat_product, 'after_price_update')
        assert repeated['order_id'] == first['order_id']
        assert repeated['amount'] == first['amount'] and repeated['reward'] == first['reward']
        verify_delivery(stat_product, repeated, 'immutable_snapshot')
    assert profile() == before and call('get_order', first['order_id'])['state'] == 'created'
    restored = conn.execute('SELECT amount,effects,grants FROM payments.products WHERE sku=%s', (stat_product['sku'],)).fetchone()
    assert restored == (stat_product['amount'], stat_product['effects'], stat_product['grants'])

    verify_delivery(stat_product, first, 'stat_delivery')
    assert make(stat_product, 'owned_retry')['error'] == 'already_owned'
    with conn.transaction(force_rollback=True):
        conn.execute('UPDATE public.player_archive_state SET content_inventory=content_inventory-%s WHERE account_id=%s',
                     (stat_product['item_id'], account))
        assert make(stat_product, 'historical_limit')['error'] == 'purchase_limit_reached'

    ticket_order = orders[ticket_product['sku']]
    verify_delivery(ticket_product, ticket_order, 'ticket_delivery')
    repeated_ticket = make(ticket_product, 'second_ticket')
    assert repeated_ticket['order_id'] != ticket_order['order_id']
    verify_delivery(ticket_product, repeated_ticket, 'second_ticket_delivery')
    assert profile()['save']['content_inventory']['special_lottery_ticket'] == 2
    assert profile()['save']['content_inventory'][ticket_product['item_id']] == 2

    wallet_before = profile(wallet_account)
    for product in limited:
        rejected = make(product, 'wallet_owned:' + product['sku'], wallet_account)
        assert rejected.get('error') == 'already_owned', (product['sku'], rejected)
    assert profile(wallet_account) == wallet_before
    assert conn.execute('SELECT count(*) FROM payments.orders WHERE account_id=%s', (wallet_account,)).fetchone()[0] == 0
    return {
        'passed': True, 'ucoin_skus': 24, 'u_coin_per_yuan': 1000,
        'all_order_prices_rewards_and_limits_match': True, 'unpaid_grants_nothing': True,
        'pending_orders_reused': True, 'immutable_price_and_reward_snapshot': True,
        'wrong_amount_rejected_with_savepoint': True, 'duplicate_delivery_safe': True,
        'permanent_and_repeatable_item_delivery': True, 'historical_purchase_limit': True,
        'wallet_owned_products_rejected': len(limited), 'real_accounts_modified': False,
        'fixture_writes': 'caller_must_rollback',
    }
