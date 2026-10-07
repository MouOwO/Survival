"""Run against a staging PostgreSQL transaction and roll it back afterwards.
Requires the VIP wallet migration and upgrade_vip_recharge.sql.
These checks exercise the trigger; gateway signature checks stay in test_payments.
"""
import json
from pathlib import Path
ACCOUNT='f6'*32

def run_checks(conn,defaults):
    assert not conn.execute('select 1 from public.survival_players where account_id=%s',(ACCOUNT,)).fetchone()
    conn.execute('select public.ensure_player_gameplay_stats(%s,%s::jsonb)',(ACCOUNT,json.dumps(defaults)))
    sku=conn.execute('select sku from payments.products where enabled order by sku limit 1').fetchone()[0]
    sequence=0
    def stats():
        return conn.execute('select vip_recharge_total_fen,vip_level,shop_paid_currency from public.player_gameplay_stats where player_id=%s',(ACCOUNT,)).fetchone()
    def receipt(amount,state='delivered'):
        nonlocal sequence
        sequence+=1;order='WX'+f'{900000+sequence:030x}';transaction=str(4200000000000000000000000+sequence)
        conn.execute("insert into payments.orders(order_id,account_id,sku,amount,state) values(%s,%s,%s,%s,'pending')",(order,ACCOUNT,sku,amount))
        before=stats()
        conn.execute('update payments.orders set state=%s,transaction_id=%s where order_id=%s',(state,transaction,order))
        return order,before
    receipt(100,'paid_review');assert stats()[:2]==(0,0)
    thresholds=[5000,10000,25000,50000,100000,150000,250000,400000,600000,750000,1000000,1250000]
    for level,fen in enumerate(thresholds,1):
        receipt(fen-1-stats()[0]);assert stats()[:2]==(fen-1,level-1)
        order,_=receipt(1);assert stats()[:2]==(fen,level)
        conn.execute("update payments.orders set state='delivered' where order_id=%s",(order,));assert stats()[:2]==(fen,level)
    conn.execute('update public.player_gameplay_stats set shop_paid_currency=0 where player_id=%s',(ACCOUNT,))
    assert stats()[:2]==(1250000,12)
    assert conn.execute("select active and expires_at is null from public.archive_entitlements where account_id=%s and entitlement_id='vip'",(ACCOUNT,)).fetchone()[0]
    assert conn.execute('select count(*) from payments.vip_recharge_credits where account_id=%s',(ACCOUNT,)).fetchone()[0]==24
    receipt(100);assert stats()[:2]==(1250100,12)
    return {'vip_recharge_boundaries':12,'duplicate_receipts':True,'pending_review_excluded':True,'spend_retains_level':True}
