"""Monthly pass SQL checks. Caller must roll back the outer transaction.

Apply upgrade_monthly_pass.sql and the compiled catalog before run_checks.
Only nonce-derived fixture identities are created; no gateway is contacted.
"""
from datetime import timedelta
import hashlib
import json
import secrets


def run_checks(conn, catalog):
    from psycopg.types.json import Jsonb
    assert not conn.autocommit, 'monthly fixture requires an outer rollback transaction'
    assert conn.info.transaction_status.name == 'INTRANS'
    product = next(p for p in catalog['products'] if p['sku'] == 'archive_pass_monthly')
    assert product['amount'] == 2000 and product['purchase_limit'] == 0
    assert product['grants']['entitlement_days'] == {'archive_pass': 30}
    nonce = secrets.token_hex(16)

    def digest(label):
        return hashlib.sha256(('monthly_fixture:' + nonce + ':' + label).encode()).hexdigest()

    account, permanent = digest('buyer'), digest('permanent_owner')
    legacy, reset_buyer = digest('legacy_vip'), digest('reset_buyer')
    session = 'monthly_fixture_' + nonce

    def oid(label):
        return 'WX' + digest('order:' + label)[:30]

    def transaction(label):
        return '420000' + str(int(digest('transaction:' + label)[:30], 16)).zfill(37)

    def call(name, *args):
        return conn.execute('SELECT payments.' + name + '(' + ','.join(['%s'] * len(args)) + ')', args).fetchone()[0]

    def entitlement(identity=account, name='archive_pass'):
        row = conn.execute('SELECT active,starts_at,expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id=%s',
                           (identity, name)).fetchone()
        return row

    def make(label, identity=account):
        return call('create_order', identity, session, oid(label), product['sku'])

    provider = conn.execute("SELECT appid,mchid FROM payments.providers WHERE provider='wechat' AND enabled").fetchone()
    assert provider, 'fixture requires the configured WeChat provider'
    defaults = conn.execute("SELECT coalesce(jsonb_object_agg(field_id,default_value),'{}'::jsonb) FROM payments.stat_rules").fetchone()[0]
    now = conn.execute('SELECT now()').fetchone()[0]
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id IN (%s,%s)',
                            (account, permanent)).fetchone(), 'fixture identity collision'
    for identity in (account, permanent, legacy, reset_buyer):
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)', (identity, json.dumps(defaults)))
        login = conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',
                             (identity, session, 'standard', json.dumps(defaults))).fetchone()[0]
        assert login['ok']
        conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{\"keep_archive\":123}','{\"keep_item\":3}')",
                     (identity,))

    def pay(order, label, amount=2000):
        assert order['account_id'] in (account, reset_buyer), 'only synthetic monthly buyers can be delivered'
        return call('deliver', order['order_id'], transaction(label), amount, provider[0], provider[1])

    initial = make('first')
    assert initial['amount'] == 2000 and initial['reward']['grants']['entitlement_days'] == {'archive_pass': 30}
    assert make('duplicate_intent')['order_id'] == initial['order_id']
    assert entitlement() is None, 'opening an unpaid order granted membership'
    # Price and duration changes after creation cannot affect this paid receipt.
    with conn.transaction(force_rollback=True):
        conn.execute("UPDATE payments.products SET amount=777,grants=jsonb_set(grants,'{entitlement_days,archive_pass}','7') WHERE sku=%s",
                     (product['sku'],))
        receipt = pay(initial, 'first')
        assert receipt['state'] == 'delivered' and receipt['amount'] == 2000
        assert entitlement()[2] - now == timedelta(days=30)
        before_replay = entitlement()
        assert pay(initial, 'first')['state'] == 'delivered'
        assert entitlement() == before_replay, 'duplicate callback extended the monthly pass'
    try:
        with conn.transaction():
            pay(initial, 'wrong_amount', 1999)
    except Exception:
        pass
    else:
        raise AssertionError('incorrect amount was accepted')
    assert entitlement() is None, 'invalid payment leaked an entitlement'
    receipt = pay(initial, 'first')
    assert receipt['state'] == 'delivered'
    first_expiry = entitlement()[2]
    assert first_expiry - now == timedelta(days=30)
    renewal = make('renewal')
    assert renewal['order_id'] == oid('renewal'), 'active finite membership cannot renew'
    assert pay(renewal, 'renewal')['state'] == 'delivered'
    assert entitlement()[2] - first_expiry == timedelta(days=30), 'renewal lost the remaining days'
    # Expired or revoked membership starts a fresh month, rather than adding to
    # a stale expiry or resurrecting revoked unused time.
    conn.execute("UPDATE public.archive_entitlements SET expires_at=now()-interval '1 day' WHERE account_id=%s AND entitlement_id='archive_pass'", (account,))
    assert pay(make('expired'), 'expired')['state'] == 'delivered'
    assert entitlement()[2] - now == timedelta(days=30)
    conn.execute("UPDATE public.archive_entitlements SET active=false,expires_at=now()+interval '100 days' WHERE account_id=%s AND entitlement_id='archive_pass'", (account,))
    assert pay(make('revoked'), 'revoked')['state'] == 'delivered'
    assert entitlement()[2] - now == timedelta(days=30)
    old = entitlement()
    conn.execute("INSERT INTO public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at) VALUES(%s,'archive_pass',true,now(),NULL)", (permanent,))
    retained = entitlement(permanent)
    assert make('permanent', permanent)['error'] == 'entitlement_already_owned'
    assert entitlement(permanent) == retained, 'existing permanent pass changed'
    # A permanent entitlement received while payment was pending is retained;
    # payment remains visible for manual review rather than being shortened.
    race = make('permanent_race')
    conn.execute("UPDATE public.archive_entitlements SET expires_at=NULL WHERE account_id=%s AND entitlement_id='archive_pass'", (account,))
    assert pay(race, 'permanent_race')['state'] == 'paid_review'
    assert entitlement()[2] is None
    conn.execute("UPDATE public.archive_entitlements SET expires_at=%s WHERE account_id=%s AND entitlement_id='archive_pass'", (old[2], account))
    # Historical permanent reward metadata still grants permanent VIP rights.
    assert call('entitlement_days', Jsonb({'entitlement_days': {'archive_pass': 30}}), 'vip') is None
    assert call('entitlement_days', Jsonb({}), 'archive_pass') is None
    legacy_sku = 'monthly_fixture_vip_' + nonce[:12]
    conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,grants,category_id,product_type,icon,purchase_limit)
      VALUES(%s,%s,'fixture permanent VIP','fixture',5000,'{}',true,100,%s,'technology','single','custom_game/reward_art_v5/daily_wealth_talisman.png',1)''',
      (legacy_sku, 'fixture_vip_' + nonce[:12], Jsonb({'items': {}, 'item_limits': {}, 'entitlements': ['vip'], 'lines': []})))
    old_order = call('create_order', legacy, session, oid('legacy_vip'), legacy_sku)
    assert 'entitlement_days' not in old_order['reward']['grants']
    assert call('deliver', old_order['order_id'], transaction('legacy_vip'), 5000, provider[0], provider[1])['state'] == 'delivered'
    assert entitlement(legacy, 'vip')[0] and entitlement(legacy, 'vip')[2] is None
    assert entitlement(legacy) is None, 'permanent VIP unexpectedly granted a monthly pass'
    with conn.transaction(force_rollback=True):
        conn.execute('UPDATE payments.test_settings SET enabled=true WHERE singleton')
        conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)', (reset_buyer,))
        reset_first = make('reset_first', reset_buyer)
        assert pay(reset_first, 'reset_first')['state'] == 'delivered'
        assert pay(make('reset_renewal', reset_buyer), 'reset_renewal')['state'] == 'delivered'
        assert entitlement(reset_buyer)[2] - now == timedelta(days=60)
        assert call('begin_reset', reset_buyer, session, 'refreshmoney', 'monthly_fixture_reset')['ok']
        assert call('finish_reset', reset_buyer, session, 'refreshmoney', 'monthly_fixture_reset')['ok']
        assert entitlement(reset_buyer) is None, 'test reset did not reverse the renewal chain'
        assert pay(reset_first, 'reset_first')['state'] == 'delivered'
        assert entitlement(reset_buyer) is None, 'old callback restored a cleared monthly pass'
    for invalid in (0, -1, 1.5, 366):
        try:
            with conn.transaction():
                call('entitlement_days', Jsonb({'entitlement_days': {'archive_pass': invalid}}), 'archive_pass')
        except Exception:
            pass
        else:
            raise AssertionError('invalid monthly duration was accepted')
    assert not conn.execute('SELECT has_function_privilege(%s,%s,%s)',
                            ('goufayu_payment', 'payments.entitlement_days(jsonb,text)', 'EXECUTE')).fetchone()[0]
    return {'monthly_price_fen': 2000, 'duration_days': 30, 'renewal_preserves_remaining_days': True,
            'duplicate_delivery_does_not_extend': True, 'immutable_order_price_and_duration': True,
            'expired_and_revoked_memberships_restart': True, 'permanent_entitlements_preserved': True,
            'test_reset_reverses_renewals_and_replay_is_safe': True}
