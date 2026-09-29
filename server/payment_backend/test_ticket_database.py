"""Real PostgreSQL ticket checks; caller MUST roll back the enclosing transaction.

Uses only an isolated synthetic account and SQL fixtures, never a payment gateway.
"""
import json

SKU = 'special_lottery_ticket_single'
ACCOUNT = 'f6' * 32
SESSION = 'payment_ticket_fixture_session'


def run_checks(conn, defaults):
    def call(name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def profile():
        return conn.execute('SELECT public.fishing_profile_json(%s)', (ACCOUNT,)).fetchone()[0]

    def oid(n):
        return 'WX' + f'{n:030x}'

    def paid(n, amount=5000):
        return call('deliver', oid(n), f'420000000000000000000{n:07d}', amount, 'wx164e25a570fb636a', '1117928493')

    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s', (ACCOUNT,)).fetchone()
    conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)', (ACCOUNT, json.dumps(defaults)))
    conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)', (ACCOUNT, SESSION, 'standard', json.dumps(defaults)))
    conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{}','{}')", (ACCOUNT,))
    assert not call('is_test_account', ACCOUNT), 'repeatability must work without reset/test privileges'
    before = profile()
    for n, count in ((660, 1), (661, 2)):
        product = next(p for p in call('catalog', ACCOUNT, SESSION)['products'] if p['sku'] == SKU)
        assert product['enabled'] and product['amount_fen'] == 5000 and product['purchase_limit'] == 0
        made = call('create_order', ACCOUNT, SESSION, oid(n), SKU)
        assert made['amount'] == 5000 and made['reward']['grants']['items'] == {'special_lottery_ticket': 1}
        assert call('create_order', ACCOUNT, SESSION, oid(n + 100), SKU)['order_id'] == oid(n), 'pending intent must be reused'
        unpaid = profile()
        assert unpaid['save']['content_inventory'].get('special_lottery_ticket', 0) == count - 1
        try:
            with conn.transaction():
                paid(n, 4999)
        except Exception:
            pass
        else:
            raise AssertionError('wrong payment amount accepted')
        assert profile() == unpaid
        receipt = paid(n)
        assert receipt['state'] == 'delivered'
        after = profile()
        assert after['save']['content_inventory']['special_lottery_ticket'] == count
        assert after['save']['gameplay_stats'] == before['save']['gameplay_stats']
        assert after['entitlements'] == before['entitlements']
        paid(n)
        assert profile() == after, 'duplicate callback must not add a second ticket'
    assert next(p for p in call('catalog', ACCOUNT, SESSION)['products'] if p['sku'] == SKU)['enabled']
    return {'ticket_price_fen': 5000, 'quantity_per_payment': 1, 'repeatable_without_test_privileges': True,
            'unpaid_grants_nothing': True, 'wrong_amount_rejected': True, 'duplicate_callback_safe': True}
