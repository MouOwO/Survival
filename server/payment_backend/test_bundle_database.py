"""Run after the stat fixtures in the same rollback-only transaction."""
import json
from .test_shop_database import ACCOUNT,OTHER,SESSION

def run_checks(conn):
    def call(name,*args):return conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
    def profile():return conn.execute('SELECT public.fishing_profile_json(%s)',(ACCOUNT,)).fetchone()[0]
    def oid(n):return 'WX'+f'{n:030x}'
    def paid(n):return call('deliver',oid(n),f'420000000000000000000{n:07d}',5000,'wx164e25a570fb636a','1117928493')
    conn.execute("UPDATE payments.products SET enabled=true,grants=jsonb_set(grants,'{entitlements}','[\"vip\",\"archive_pass\"]') WHERE sku='starter_bundle_v4'")
    before=profile()
    made=call('create_order',ACCOUNT,SESSION,oid(500),'starter_bundle_v4')
    assert made['reward']['version']==4 and len(made['reward']['effects'])==5
    # Changing the catalog after an intent exists must not change its reward/price.
    conn.execute("UPDATE payments.products SET amount=777,effects='{\"initial_wood\":999}',enabled=false WHERE sku='starter_bundle_v4'")
    receipt=paid(500);after=profile()
    assert receipt['state']=='delivered' and receipt['amount']==5000
    for field in made['reward']['effects']:
        assert after['save']['gameplay_stats'][field]-before['save']['gameplay_stats'][field]==100
        assert receipt['effect_changes'][field]['delta']==100
    assert after['save']['content_inventory']['special_lottery_ticket']==10
    assert after['entitlements']['vip']['active'] and after['entitlements']['archive_pass']['active']
    assert paid(500)['effect_changes']==receipt['effect_changes'] and profile()==after
    assert call('begin_reset',OTHER,SESSION,'refreshmoney','bundle_other_reset')['error']=='test_reset_disabled'
    assert call('begin_reset',ACCOUNT,SESSION,'refreshmoney','bundle_reset_500')['ok']
    assert call('finish_reset',ACCOUNT,SESSION,'refreshmoney','bundle_reset_500')['ok']
    cleared=profile()
    assert cleared['save']['content_inventory'].get('special_lottery_ticket',0)==0
    assert not cleared['entitlements'].get('vip',{}).get('active')
    assert not cleared['entitlements'].get('archive_pass',{}).get('active')
    for field in made['reward']['effects']:assert cleared['save']['gameplay_stats'][field]==before['save']['gameplay_stats'][field]
    paid(500);assert profile()==cleared,'old paid callback restored cleared bundle'
    conn.execute("UPDATE payments.products SET enabled=true,amount=5000,effects=%s::jsonb WHERE sku='starter_bundle_v4'",(json.dumps(made['reward']['effects']),))
    assert call('create_order',ACCOUNT,SESSION,oid(501),'starter_bundle_v4')['order_id']==oid(501)
    # Corrupt an internal fixture only: even an error after items/rights are written rolls back all grants.
    conn.execute("UPDATE payments.orders SET reward=jsonb_set(reward,'{effects}','{\"missing_field\":1}') WHERE order_id=%s",(oid(501),))
    try:
        with conn.transaction():paid(501)
    except Exception:pass
    else:raise AssertionError('invalid bundle unexpectedly settled')
    assert profile()==cleared,'partial bundle leaked after failed stat grant'
    assert call('get_order',oid(501))['state']=='created'
    call('update_gateway',oid(501),'closed',None)
    conn.execute("INSERT INTO public.archive_entitlements(account_id,entitlement_id,active) VALUES(%s,'vip',true)",(ACCOUNT,))
    assert call('create_order',ACCOUNT,SESSION,oid(502),'starter_bundle_v4')['error']=='entitlement_already_owned'
    conn.execute("DELETE FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='vip'",(ACCOUNT,))
    with conn.transaction(force_rollback=True):
        conn.execute("UPDATE payments.products SET effects=effects||'{\"wall_health_bonus_pct\":1}'::jsonb WHERE sku='starter_bundle_v4'")
        conn.execute('UPDATE public.player_gameplay_stats SET wall_health_bonus_pct=10000 WHERE player_id=%s',(ACCOUNT,))
        assert call('create_order',ACCOUNT,SESSION,oid(503),'starter_bundle_v4')['error']=='attribute_limit_reached'
    for helper in ('deliver_v3(text,text,integer,text,text)','finish_reset_v3(text,text,text,text)','product_block(text,text,integer,jsonb,jsonb)'):
        assert not conn.execute('SELECT has_function_privilege(%s,%s,%s)',('goufayu_payment','payments.'+helper,'EXECUTE')).fetchone()[0]
    return {'bundle_attributes_items_permissions_atomic':True,'immutable_price_and_rewards':True,'duplicate_and_reset_replay_safe':True}
