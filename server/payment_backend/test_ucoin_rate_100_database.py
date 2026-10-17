"""Rollback-only real PostgreSQL fixtures for the exact rate-100 migration.

The caller applies upgrade_ucoin_rate_100.sql and the candidate product catalog
inside an existing transaction, calls run_checks(conn), and MUST roll it back.
Only nonce synthetic accounts/orders are created. Imports do not connect and
no gateway, real account API or client request is used.
"""
from copy import deepcopy
import hashlib
import secrets


def run_checks(conn):
    from psycopg.types.json import Jsonb
    from .test_ucoin_recharge_database import run_checks as recharge_checks
    assert not conn.autocommit and conn.info.transaction_status.name=='INTRANS'
    # Also exercise maximum recharge, VIP credit/idempotency, reset generation,
    # capacity and ordinary quantity caps using the existing complete fixture.
    existing=recharge_checks(conn)
    nonce=secrets.token_hex(12);session='rate_100_fixture_'+nonce;checks=[]
    defaults=conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
    providers={r[0]:r[1:] for r in conn.execute('SELECT provider,appid,mchid FROM payments.providers WHERE enabled')}
    assert 'wechat' in providers
    def digest(label):return hashlib.sha256(('rate100:'+nonce+':'+label).encode()).hexdigest()
    def call(name,*args):
        return conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
    def buyer(label):
        account=digest(label)
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone()
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)',(account,Jsonb(defaults)))
        assert conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)',(account,session,'standard',Jsonb(defaults))).fetchone()[0]['ok']
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
            (account,Jsonb({'keep':9,'commerce':{'balances':{'u_coin':17,'shop_points':19,'shop_gold':23}}}),Jsonb({'keep_item':3})))
        return account
    def make(account,label,sku,count=2):
        return call('create_order_quantity',account,session,'WX'+digest('order:'+label)[:30],sku,'wechat',count)
    def pay(order,label):
        transaction='420000'+str(int(digest('tx:'+label)[:28],16)).zfill(35)
        return call('deliver',order['order_id'],transaction,order['amount'],*providers['wechat'])
    def reject(reward,amount):
        try:
            with conn.transaction():call('validate_order_quantity_snapshot',Jsonb(reward),amount)
        except Exception:return
        raise AssertionError('forged rate snapshot accepted')
    sku='rate_normal_'+nonce;marker='rate_owned_'+nonce
    grants=dict(items={},item_limits={},entitlements=[],lines=[],effect_labels={},
        pricing=dict(u_coin_price=50,u_coin_per_yuan=100))
    conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
      grants,category_id,product_type,icon,purchase_limit)
      VALUES(%s,%s,'rate fixture','fixture',50,'{}',true,999,%s,'item','single','',0)''',(sku,marker,Jsonb(grants)))
    for rate in (100,1000):
        account=buyer('normal:'+str(rate));o=make(account,'normal:'+str(rate),sku)
        assert o['amount']==100 and o['reward']['unit_pricing']==dict(u_coin_price=50,u_coin_per_yuan=100)
        if rate==1000:
            # Build a historical nonce receipt, never edit an existing account.
            reward=deepcopy(o['reward'])
            reward['unit_pricing']=dict(u_coin_price=500,u_coin_per_yuan=1000)
            reward['grants']['pricing']=dict(u_coin_price=1000,u_coin_per_yuan=1000)
            conn.execute('UPDATE payments.orders SET reward=%s WHERE order_id=%s',(Jsonb(reward),o['order_id']))
            o['reward']=reward
        frozen=deepcopy(o['reward'])
        call('validate_order_quantity_snapshot',Jsonb(frozen),100)
        recovered=make(account,'reuse:'+str(rate),sku)
        assert recovered['order_id']==o['order_id'] and recovered['reward']==frozen
        assert pay(o,'normal:'+str(rate))['state']=='delivered'
        assert pay(o,'normal:'+str(rate))['state']=='delivered'
        saved=conn.execute('SELECT reward FROM payments.orders WHERE order_id=%s',(o['order_id'],)).fetchone()[0]
        assert saved==frozen
        inventory=conn.execute('SELECT content_inventory FROM public.player_archive_state WHERE account_id=%s',(account,)).fetchone()[0]
        assert inventory[marker]==2 and inventory['keep_item']==3
        checks.append('normal rate '+str(rate)+': frozen cash/pricing, pending recovery, delivery once')
        for path,value in [(('unit_pricing','u_coin_per_yuan'),None),
            (('unit_pricing','u_coin_per_yuan'),'100'),(('unit_pricing','u_coin_per_yuan'),10),
            (('grants','pricing','u_coin_per_yuan'),1000 if rate==100 else 100),
            (('unit_pricing','u_coin_price'),1),(('grants','pricing','u_coin_price'),1)]:
            forged=deepcopy(frozen);parent=forged
            for key in path[:-1]:parent=parent[key]
            parent[path[-1]]=value;reject(forged,100)
        forged=deepcopy(frozen);forged['unit_pricing']={};forged['grants']['pricing']={};reject(forged,100)
    checks.append('missing, unknown, mixed and forged normal quantity pricing rejected')
    for rate in (100,1000):
        account=buyer('recharge:'+str(rate));o=make(account,'recharge:'+str(rate),'u_coin_recharge')
        assert o['amount']==200 and o['reward']['unit_pricing']==dict(u_coin_price=100,u_coin_per_yuan=100)
        if rate==1000:
            reward=deepcopy(o['reward'])
            reward['unit_pricing']=dict(u_coin_price=1000,u_coin_per_yuan=1000)
            reward['grants']['pricing']=dict(u_coin_price=2000,u_coin_per_yuan=1000)
            conn.execute('UPDATE payments.orders SET reward=%s WHERE order_id=%s',(Jsonb(reward),o['order_id']))
            o['reward']=reward
        frozen=deepcopy(o['reward'])
        call('validate_order_quantity_snapshot',Jsonb(frozen),200)
        recovered=make(account,'recharge_reuse:'+str(rate),'u_coin_recharge')
        assert recovered['order_id']==o['order_id'] and recovered['reward']==frozen
        assert pay(o,'recharge:'+str(rate))['state']=='delivered'
        assert pay(o,'recharge:'+str(rate))['state']=='delivered'
        assert call('recharge_wallet_balance',account)==217
        assert conn.execute('SELECT vip_recharge_total_fen FROM public.player_gameplay_stats WHERE player_id=%s',(account,)).fetchone()[0]==200
        assert conn.execute('SELECT reward FROM payments.orders WHERE order_id=%s',(o['order_id'],)).fetchone()[0]==frozen
        checks.append('recharge rate '+str(rate)+': 200 fen grants exactly 200U and VIP cash credit once')
        forged=deepcopy(frozen);forged['grants']['lines'][0]['quantity']=2000;reject(forged,200)
        forged=deepcopy(frozen);forged['grants']['pricing']['u_coin_per_yuan']=1000 if rate==100 else 100;reject(forged,200)
    checks.append('historical display rate cannot forge wallet credit or mixed-rate recharge')
    for helper in ('scale_order_quantity(jsonb,jsonb,integer,integer)','catalog_pre_recharge(text,text)',
        'validate_order_quantity_snapshot_pre_recharge(jsonb,integer)','validate_order_quantity_snapshot(jsonb,integer)'):
        assert not conn.execute("SELECT has_function_privilege('goufayu_payment',%s,'EXECUTE')",('payments.'+helper,)).fetchone()[0]
    checks.append('all four replaced internal helpers remain private')
    return dict(passed=True,checks=checks,recharge_regressions=existing['checks'],external_gateway_requests=0,
        real_accounts_modified=False,caller_must_rollback=True)
