"""Provider migration/fulfilment checks on an isolated account; always roll back."""
import json
from psycopg.types.json import Jsonb

ACCOUNT='f7'*32
SESSION='alipay_database_fixture'
APPID='2021007102660118'
SKU='special_lottery_ticket_single'

def run_checks(conn,defaults,seller):
    def call(name,*args):
        return conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
    def profile():return conn.execute('SELECT public.fishing_profile_json(%s)',(ACCOUNT,)).fetchone()[0]
    def oid(n,channel='alipay'):return ('AL' if channel=='alipay' else 'WX')+f'{n:030x}'
    def make(n,sku=SKU,channel='alipay'):return call('create_order_channel',ACCOUNT,SESSION,oid(n,channel),sku,channel)
    def pay(n,channel='alipay',**changes):
        args=dict(amount=5000,appid=APPID if channel=='alipay' else 'wx164e25a570fb636a',mchid=seller if channel=='alipay' else '1117928493')
        args.update(changes)
        return call('deliver',oid(n,channel),f'20260930000000000000{n:08d}',args['amount'],args['appid'],args['mchid'])
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(ACCOUNT,)).fetchone()
    conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)',(ACCOUNT,json.dumps(defaults)))
    conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',(ACCOUNT,SESSION,'standard',json.dumps(defaults)))
    conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{}','{}')",(ACCOUNT,))
    before=profile()
    first=make(770)
    assert first['provider']=='alipay' and first['appid']==APPID and first['mchid']==seller
    assert first['amount']==5000 and first['reward']['grants']['items']=={'special_lottery_ticket':1}
    assert make(771,channel='wechat')['order_id']==first['order_id'],'cross-channel intent must be reused'
    for changes in ({'amount':1},{'appid':'wx164e25a570fb636a'},{'mchid':'2088000000000000'}):
        try:
            with conn.transaction():pay(770,**changes)
        except Exception:pass
        else:raise AssertionError('mismatched payment accepted')
        assert profile()==before
    call('update_gateway',oid(770),'pending','alipay:page_pay')
    assert pay(770)['state']=='delivered'
    after=profile();assert after['save']['content_inventory']['special_lottery_ticket']==1
    assert pay(770)['state']=='delivered' and profile()==after
    assert make(771,channel='wechat')['provider']=='wechat'
    assert pay(771,channel='wechat')['state']=='delivered'
    assert profile()['save']['content_inventory']['special_lottery_ticket']==2
    make(772);call('update_gateway',oid(772),'closed',None)
    assert make(773,channel='wechat')['provider']=='wechat'
    call('update_gateway',oid(773,'wechat'),'closed',None)
    # Complete mixed bundle: consumable, initial resources, combat stat and permissions.
    grants={'items':{'special_lottery_ticket':2},'item_limits':{'special_lottery_ticket':100000},'entitlements':['vip','archive_pass'],'lines':[],'effect_labels':{}}
    effects={'initial_wood':100,'initial_gold':100,'wall_armor':100,'wall_initial_health':100,'tower_attack_flat':100}
    conn.execute("INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,purchase_limit,grants) VALUES('alipay_fixture_bundle','pay_alipay_fixture_bundle','fixture','fixture',5000,%s,true,999,1,%s)",(Jsonb(effects),Jsonb(grants)))
    before=profile();made=make(774,'alipay_fixture_bundle');assert made['provider']=='alipay'
    receipt=pay(774);assert receipt['state']=='delivered'
    after=profile()
    for field,delta in effects.items():assert after['save']['gameplay_stats'][field]==before['save']['gameplay_stats'][field]+delta
    assert after['save']['content_inventory']['special_lottery_ticket']==4
    assert after['entitlements']['vip']['active'] and after['entitlements']['archive_pass']['active']
    assert pay(774)['state']=='delivered' and profile()==after
    assert make(775,'alipay_fixture_bundle',channel='wechat').get('error')=='already_owned'
    conn.execute("UPDATE public.player_archive_state SET content_inventory=content_inventory-'pay_alipay_fixture_bundle' WHERE account_id=%s",(ACCOUNT,))
    assert make(775,'alipay_fixture_bundle',channel='wechat').get('error')=='purchase_limit_reached'
    assert not conn.execute("SELECT has_table_privilege('goufayu_payment','payments.providers','SELECT')").fetchone()[0]
    assert conn.execute("SELECT has_function_privilege('goufayu_payment','payments.create_order_channel(text,text,text,text,text)','EXECUTE')").fetchone()[0]
    return dict(alipay_ticket=True,wechat_after_alipay=True,cross_channel_pending_reused=True,
        wrong_identity_and_amount_rejected=True,duplicate_notice_safe=True,mixed_bundle_all_grants=True,
        cross_channel_purchase_limit=True,real_accounts_modified=False)
