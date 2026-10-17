"""Real PostgreSQL recharge fixtures; caller must roll back the entire transaction.

Imports never connect and no gateway is called. Each account/order ID is synthetic.
Apply upgrade_ucoin_recharge.sql, then call run_checks inside a rollback transaction.
"""
from copy import deepcopy
import hashlib
import secrets
from . import ucoin_recharge as recharge


def run_checks(conn):
    from psycopg.types.json import Jsonb
    assert not conn.autocommit and conn.info.transaction_status.name=='INTRANS'
    nonce=secrets.token_hex(12);session='ucoin_recharge_fixture_'+nonce
    defaults=conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
    providers={r[0]:r[1:] for r in conn.execute('SELECT provider,appid,mchid FROM payments.providers WHERE enabled')}
    assert 'wechat' in providers and 'alipay' in providers
    p=recharge.product();checks=[]
    conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,
     grants,category_id,product_type,icon,purchase_limit) VALUES(%s,%s,%s,%s,%s,%s,true,%s,%s,%s,%s,%s,0)
     ON CONFLICT(sku) DO UPDATE SET item_id=excluded.item_id,title=excluded.title,description=excluded.description,
     amount=excluded.amount,effects=excluded.effects,enabled=true,grants=excluded.grants,product_type=excluded.product_type,purchase_limit=0''',
     (p['sku'],p['item_id'],p['title'],p['description'],p['amount'],Jsonb(p['effects']),p['sort_order'],Jsonb(p['grants']),p['category_id'],p['product_type'],p['icon']))
    def digest(label):return hashlib.sha256(('recharge:'+nonce+':'+label).encode()).hexdigest()
    def call(name,*args):return conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
    def buyer(label,wallet=17,create_archive=True):
        a=digest('buyer:'+label)
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(a,)).fetchone()
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)',(a,Jsonb(defaults)))
        assert conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)',(a,session,'standard',Jsonb(defaults))).fetchone()[0]['ok']
        if create_archive:conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
            (a,Jsonb({'keep':7,'commerce':{'keep':'yes','balances':{'u_coin':wallet,'shop_points':19,'shop_gold':23}}}),Jsonb({'keep_item':3})))
        return a
    def make(a,label,q=1,provider='wechat',sku=recharge.SKU):
        return call('create_order_quantity',a,session,('WX' if provider=='wechat' else 'AL')+digest('order:'+label)[:30],sku,provider,q)
    def tx(label):return '420000'+str(int(digest('tx:'+label)[:28],16)).zfill(35)
    def pay(o,label,amount=None):return call('deliver',o['order_id'],tx(label),o['amount'] if amount is None else amount,*providers[o['provider']])
    def archive(a):return conn.execute('SELECT archive,content_inventory FROM public.player_archive_state WHERE account_id=%s',(a,)).fetchone()
    def wallet(a):return call('recharge_wallet_balance',a)
    def raises(callback):
        try:
            with conn.transaction():callback()
        except Exception:return
        raise AssertionError('invalid recharge accepted')
    a=buyer('main');other=buyer('other');before=deepcopy(archive(a))
    listed=next(row for row in call('catalog',a,session)['products'] if row['sku']==recharge.SKU)
    assert (listed['max_quantity'],listed['amount_fen'],listed['product_type'],listed['recharge_u_coin_per_unit'])==(999999,100,'recharge',100)
    checks.append('catalog fixed cash unit and maximum 999999')
    for q in (None,0,-1,1000000):assert make(a,'bad'+str(q),q)['error']=='quantity_invalid'
    assert call('create_order_quantity',a,session,'WX'+digest('badsession')[:30],recharge.SKU,'wechat',1)['sku']==recharge.SKU
    # The preceding valid intent is reused; quantity/provider changes never mutate it.
    first=make(a,'one');assert first['amount']==100 and first['reward']['quantity']==1
    conflict=make(a,'different',2);assert conflict['order_id']==first['order_id'] and conflict['warning']=='order_quantity_conflict'
    assert make(a,'provider_conflict',1,'alipay')['warning']=='order_provider_conflict'
    assert wallet(a)==17 and archive(a)==before
    raises(lambda:pay(first,'wrong',99));assert wallet(a)==17
    assert pay(first,'one')['state']=='delivered';assert pay(first,'one')['state']=='delivered'
    assert wallet(a)==117 and wallet(other)==17
    after=archive(a);assert after[1]==before[1] and after[0]['keep']==7
    assert after[0]['commerce']['balances']=={'u_coin':117,'shop_points':19,'shop_gold':23}
    assert after[0]['commerce']['keep']=='yes'
    assert conn.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s',(a,)).fetchone()[0]==1
    assert conn.execute('SELECT vip_recharge_total_fen FROM public.player_gameplay_stats WHERE player_id=%s',(a,)).fetchone()[0]==100
    checks.append('one yuan delivers 100U exactly once; VIP cash credit once; unrelated fields/account preserved')
    maximum=make(a,'maximum',999999,'alipay');assert maximum['amount']==99999900
    assert maximum['reward']['grants']['lines'][0]['quantity']==99999900
    assert pay(maximum,'maximum')['state']=='delivered';assert pay(maximum,'maximum')['state']=='delivered'
    assert wallet(a)==99999900+117
    checks.append('999999 quantity: amount99999900 fen, reward99999900U, repeated Alipay delivery idempotent')
    raises(lambda:pay(maximum,'different_transaction'))
    # An existing immutable order remains payable after catalog edits/disable.
    later=make(a,'catalog_change',2)
    conn.execute('UPDATE payments.products SET enabled=false,amount=200 WHERE sku=%s',(recharge.SKU,))
    assert pay(later,'catalog_change')['state']=='delivered';assert wallet(a)==99999900+317
    conn.execute('UPDATE payments.products SET enabled=true,amount=100 WHERE sku=%s',(recharge.SKU,))
    checks.append('pending snapshot survives catalog disable/price edits without changing wallet reward')
    empty=buyer('empty',create_archive=False);o=make(empty,'empty')
    assert pay(o,'empty')['state']=='delivered' and wallet(empty)==100
    assert archive(empty)[1]=={}
    checks.append('new account without archive row receives wallet correctly')
    limited=buyer('wallet_limit',recharge.MAX_WALLET_BALANCE-50)
    info=next(row for row in call('catalog',limited,session)['products'] if row['sku']==recharge.SKU)
    assert info['max_quantity']==0 and make(limited,'wallet_limit')['error']=='wallet_limit_reached'
    checks.append('wallet safe integer capacity enforced before ordering')
    stale=buyer('stale');o=make(stale,'stale')
    conn.execute('INSERT INTO payments.test_accounts(account_id,generation,enabled) VALUES(%s,1,false)',(stale,))
    assert pay(o,'stale')['state']=='paid_review' and wallet(stale)==17
    checks.append('reset generation mismatch grants no wallet value')
    for field,value in [('quantity',1000000),('recharge_u_coin_per_unit',1000),('unit_amount_fen',1),('version',5)]:
        forged=deepcopy(first['reward']);forged[field]=value
        raises(lambda:call('validate_order_quantity_snapshot',Jsonb(forged),100))
    checks.append('forged reward/amount/count/version snapshots rejected')
    normal='recharge_normal_'+nonce;marker='recharge_owned_'+nonce
    conn.execute('''INSERT INTO payments.products(sku,item_id,title,description,amount,effects,enabled,sort_order,grants,category_id,product_type,icon,purchase_limit)
      VALUES(%s,%s,'normal fixture','fixture',100,'{}',true,999,%s,'item','single','',0)''',
      (normal,marker,Jsonb({'items':{},'item_limits':{},'entitlements':[],'lines':[],'effect_labels':{}})))
    assert make(other,'old_limit',101,sku=normal)['error']=='quantity_invalid'
    normal_order=make(other,'old_normal',2,sku=normal);assert normal_order['reward']['version']==5
    assert pay(normal_order,'old_normal')['state']=='delivered' and wallet(other)==17
    assert archive(other)[1][marker]==2
    checks.append('ordinary products retain 100-count cap, old amount quote, version5 delivery')
    for helper in ('recharge_wallet_balance(text)','receipt_quantity(jsonb)','deliver_pre_recharge(text,text,integer,text,text)',
                   'create_order_quantity_pre_recharge(text,text,text,text,text,integer)'):
        assert not conn.execute("SELECT has_function_privilege('goufayu_payment',%s,'EXECUTE')",('payments.'+helper,)).fetchone()[0]
    checks.append('payment role cannot mutate/read through private wallet or legacy helpers')
    reset=buyer('reset');conn.execute('UPDATE payments.test_settings SET enabled=true WHERE singleton')
    conn.execute('INSERT INTO payments.test_accounts(account_id,enabled) VALUES(%s,true)',(reset,))
    o=make(reset,'reset',3);assert pay(o,'reset')['state']=='delivered' and wallet(reset)==317
    assert call('begin_reset',reset,session,'refreshmoney','recharge_reset_'+nonce)['ok']
    assert call('finish_reset',reset,session,'refreshmoney','recharge_reset_'+nonce)['ok']
    assert wallet(reset)==17
    assert call('finish_reset',reset,session,'refreshmoney','recharge_reset_'+nonce)['ok'] and wallet(reset)==17
    checks.append('test-only money reset reverses recharge once and preserves baseline wallet')
    return dict(passed=True,checks=checks,external_gateway_requests=0,real_accounts_modified=False,caller_must_rollback=True)
