"""Real PostgreSQL tests; caller must roll back the entire transaction."""
import json
from decimal import Decimal
from .catalog import PRODUCTS

ACCOUNT, OTHER = 'f7'*32, 'f8'*32
SESSION = 'payment_shop_fixture_session'


def run_checks(conn, defaults):
    def call(name, *args):
        return conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
    def order(number): return 'WX'+f'{number:030x}'
    def transaction(number): return f'420000000000000000000{number:07d}'
    def inventory(account=ACCOUNT):
        return conn.execute('SELECT content_inventory FROM public.player_archive_state WHERE account_id=%s',(account,)).fetchone()[0]
    def stats():
        return conn.execute('SELECT to_jsonb(s) FROM public.player_gameplay_stats s WHERE player_id=%s',(ACCOUNT,)).fetchone()[0]
    def reset(kind, key):
        assert call('begin_reset',ACCOUNT,SESSION,kind,key)['ok']
        return call('finish_reset',ACCOUNT,SESSION,kind,key)
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id IN (%s,%s)',(ACCOUNT,OTHER)).fetchone()
    for account in (ACCOUNT,OTHER):
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)',(account,json.dumps(defaults)))
        conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',(account,SESSION,'standard',json.dumps(defaults)))
        conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{\"keep\":2}','{\"keep_item\":3}')",(account,))
    assert call('begin_reset',ACCOUNT,SESSION,'refreshdata','test_reset_0')['error']=='test_reset_disabled'
    conn.execute('UPDATE payments.test_settings SET enabled=true')
    conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)',(ACCOUNT,))
    assert call('begin_reset',OTHER,SESSION,'refreshdata','test_reset_0')['error']=='test_reset_disabled'
    catalog=call('catalog',ACCOUNT,SESSION)
    assert len(catalog['products'])==5 and all(p['amount_fen']==5000 for p in catalog['products'])
    assert call('create_order',ACCOUNT,'missing_session',order(1),PRODUCTS[0][0])['error']=='match_session_missing'
    assert call('create_order',ACCOUNT,SESSION,order(1),'fake_product')['error']=='product_unavailable'
    before=stats()
    for i,(sku,item,*_) in enumerate(PRODUCTS,1):
        made=call('create_order',ACCOUNT,SESSION,order(i),sku)
        assert made['amount']==5000 and made['reward']['item_id']==item
        assert call('create_order',ACCOUNT,SESSION,order(100+i),sku)['order_id']==order(i)
        if i==1:
            with conn.transaction(force_rollback=True):
                try:call('deliver',order(i),transaction(i),10,'wx164e25a570fb636a','1117928493')
                except Exception:pass
                else:raise AssertionError('old 10-fen amount accepted for 50-yuan product')
        receipt=call('deliver',order(i),transaction(i),5000,'wx164e25a570fb636a','1117928493')
        assert receipt['state']=='delivered' and inventory()[item]==1
        state=stats()
        call('deliver',order(i),transaction(i),5000,'wx164e25a570fb636a','1117928493')
        assert stats()==state
        assert call('create_order',ACCOUNT,SESSION,order(200+i),sku)['error']=='already_owned'
    conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',
        (ACCOUNT,'payment_pure_fixture','pure',json.dumps(defaults)))
    cleared=reset('refreshmoney','reset_money_fixture')
    assert cleared['ok'] and inventory()=={'keep_item':3}
    assert conn.execute('SELECT archive FROM public.player_archive_state WHERE account_id=%s',(ACCOUNT,)).fetchone()[0]=={'keep':2}
    assert {k:v for k,v in stats().items() if k not in ('updated_at',)}=={k:v for k,v in before.items() if k not in ('updated_at',)}
    assert call('finish_reset',ACCOUNT,SESSION,'refreshmoney','reset_money_fixture')['revision']==cleared['revision']
    baseline=conn.execute('SELECT baseline FROM public.match_profile_sessions WHERE account_id=%s AND match_session_id=%s',
        (ACCOUNT,'payment_pure_fixture')).fetchone()[0]
    assert baseline['save']['content_inventory']=={'keep_item':3}
    for field,value in defaults.items():assert Decimal(str(baseline['save']['gameplay_stats'][field]))==Decimal(str(value)),field
    call('deliver',order(1),transaction(1),5000,'wx164e25a570fb636a','1117928493')
    assert 'lottery_monkey_king' not in inventory(), 'late receipt restored cleared item'
    assert call('create_order',ACCOUNT,SESSION,order(20),PRODUCTS[0][0])['order_id']==order(20)
    # Reset blocks new order creation and waits for verified gateway closure.
    assert call('begin_reset',ACCOUNT,SESSION,'refreshmoney','reset_pending_fixture')['orders']
    assert call('finish_reset',ACCOUNT,SESSION,'refreshmoney','reset_pending_fixture')['error']=='pending_payment_unresolved'
    assert call('create_order',ACCOUNT,SESSION,order(21),PRODUCTS[1][0])['error']=='reset_in_progress'
    call('update_gateway',order(20),'closed',None)
    assert call('finish_reset',ACCOUNT,SESSION,'refreshmoney','reset_pending_fixture')['ok']
    assert call('deliver',order(20),transaction(20),5000,'wx164e25a570fb636a','1117928493')['state']=='paid_review'
    assert 'lottery_monkey_king' not in inventory(), 'pre-reset intent granted in a new reset generation'
    # Production mode ignores empty inventory and enforces historical purchase cap.
    conn.execute('UPDATE payments.test_settings SET enabled=false')
    assert call('create_order',ACCOUNT,SESSION,order(22),PRODUCTS[1][0])['error']=='purchase_limit_reached'
    assert call('begin_reset',ACCOUNT,SESSION,'refreshdata','reset_disabled_fixture')['error']=='test_reset_disabled'
    conn.execute('UPDATE payments.test_settings SET enabled=true')
    conn.execute("INSERT INTO public.archive_entitlements(account_id,entitlement_id,active) VALUES(%s,'vip',true)",(ACCOUNT,))
    conn.execute('UPDATE public.player_gameplay_stats SET starjoy_points=123,map_level=7 WHERE player_id=%s',(ACCOUNT,))
    reward=conn.execute("SELECT definition_version,value_min FROM public.star_blessing_reward_definitions WHERE reward_id='star_blessing_002' ORDER BY definition_version DESC LIMIT 1").fetchone()
    grant_id='00000000-0000-4000-8000-111111111111'
    conn.execute('SELECT public.grant_out_of_match_reward(%s,%s::uuid,%s,%s,%s)',
        (ACCOUNT,grant_id,'star_blessing_002',reward[0],reward[1]))
    profile=lambda:conn.execute('SELECT public.fishing_profile_json(%s)',(ACCOUNT,)).fetchone()[0]
    assert profile()['save']['fishing_inventory']['star_blessing_002']==1
    cleared=reset('refreshdata','reset_all_fixture')
    assert cleared['ok'] and inventory()=={}
    actual=stats()
    for field,value in defaults.items():assert Decimal(str(actual[field]))==Decimal(str(value)),field
    assert not conn.execute('SELECT 1 FROM public.archive_entitlements WHERE account_id=%s',(ACCOUNT,)).fetchone()
    assert inventory(OTHER)=={'keep_item':3}
    assert conn.execute('SELECT count(*) FROM payments.orders WHERE account_id=%s',(ACCOUNT,)).fetchone()[0]==6
    assert conn.execute('SELECT count(*) FROM public.match_profile_sessions WHERE account_id=%s',(ACCOUNT,)).fetchone()[0]==2
    assert profile()['save']['fishing_inventory']=={} and profile()['save']['permanent_effects']=={}
    conn.execute('SELECT public.grant_out_of_match_reward(%s,%s::uuid,%s,%s,%s)',
        (ACCOUNT,grant_id,'star_blessing_002',reward[0],reward[1]))
    assert profile()['save']['fishing_inventory']=={}, 'old non-payment receipt replayed after full reset'
    assert stats()['wall_initial_health']==defaults['wall_initial_health']
    for role in ('goufayu_app','goufayu_payment'):
        assert not conn.execute("SELECT has_table_privilege(%s,'payments.test_settings','SELECT,INSERT,UPDATE,DELETE')",(role,)).fetchone()[0]
        assert not conn.execute("SELECT has_function_privilege(%s,'payments.apply_effects(text,jsonb,boolean)','EXECUTE')",(role,)).fetchone()[0]
    return {'passed':True,'products':5,'price_fen':5000,'fixture_writes':'rolled_back',
        'reset_inventory_stats_receipts_isolation_and_production_limit':True}
