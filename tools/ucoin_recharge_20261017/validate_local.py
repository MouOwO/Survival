"""Rollback-only native PostgreSQL + payment-role RPC + fake gateway validation."""
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import sys
from unittest.mock import Mock

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps'),str(ROOT)]
import psycopg
from psycopg.types.json import Jsonb
from payment_backend import ucoin_recharge as recharge
from payment_backend.service import Payments,CALLS
from payment_backend.wechat import APPID,MCHID,PaymentError
from payment_backend.test_ucoin_recharge_database import run_checks
from payment_backend.upgrade_ucoin_recharge import check_connection
from tools.compact_checkout_20261015.test_quantity_database import run_checks as legacy_quantity_checks
from payment_backend.test_starjoy_progress_database import run_checks as starjoy_checks
from payment_backend.csv_catalog import build as build_catalog


class LocalRPC:
    def __init__(self,conn):self.conn=conn
    def call(self,name,*args):
        assert name in CALLS and len(args)==CALLS[name]
        try:
            self.conn.execute('SET LOCAL ROLE goufayu_payment')
            result=self.conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
        finally:self.conn.execute('SET LOCAL ROLE goufayu_owner')
        if isinstance(result,dict) and result.get('error'):raise PaymentError(result['error'],409)
        return result


def run():
    conn=psycopg.connect('host=127.0.0.1 port=54627 dbname=survival_bundle_test user=postgres',connect_timeout=3)
    assert conn.info.host=='127.0.0.1' and conn.info.dbname=='survival_bundle_test'
    try:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');conn.execute('SET ROLE goufayu_owner')
        # The disposable DB can have no published shop metadata; seed only this
        # rollback transaction. The production operator correctly refuses it.
        conn.execute("INSERT INTO payments.catalog_state(singleton,catalog_hash,categories) VALUES(true,%s,'[]') ON CONFLICT(singleton) DO NOTHING",('f'*64,))
        online=json.loads((ROOT/'design_refs/ucoin_recharge_20261017/remote/current_schema.json').read_bytes())
        # The isolated DB predates the production starjoy repair. Load exactly
        # that reviewed pure function inside this rollback transaction so all
        # 12 definitions match the real deployment baseline before migration.
        for signature,entry in online['functions'].items():
            definition=conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))',(signature,)).fetchone()[0]
            if hashlib.sha256(definition.encode()).hexdigest()!=entry['sha256']:
                assert signature=='payments.apply_effects(text,jsonb,boolean)','unexpected_local_schema_drift'
                conn.execute(entry['definition'])
        expected_functions={k:v['sha256'] for k,v in online['functions'].items()}
        operator_report=check_connection(conn,expected_functions,'survival_bundle_test')
        sql=(ROOT/'server/payment_backend/upgrade_ucoin_recharge.sql').read_text(encoding='utf-8')
        conn.execute(sql);conn.execute(sql) # Explicit idempotence, no data seeding.
        legacy_report=legacy_quantity_checks(conn)
        starjoy_report=starjoy_checks(conn,build_catalog(ROOT)['catalog'])
        fixture_report=run_checks(conn)
        nonce=secrets.token_hex(16);public='12345678';pepper=nonce*2;session='recharge_service_'+nonce
        account=hmac.new(pepper.encode(),public.encode(),hashlib.sha256).hexdigest()
        assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone()
        defaults=conn.execute('SELECT jsonb_object_agg(field_id,default_value) FROM payments.stat_rules').fetchone()[0]
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)',(account,Jsonb(defaults)))
        assert conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s)',(account,session,'standard',Jsonb(defaults))).fetchone()[0]['ok']
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',
            (account,Jsonb({'commerce':{'balances':{'u_coin':17,'shop_points':19}}}),Jsonb({'keep':3})))
        wx=Mock();wx.query.side_effect=PaymentError('ORDER_NOT_EXIST',502)
        wx.create.return_value='weixin://wxpay/bizpayurl?local-recharge-fixture'
        app=Payments(dict(allowed_accounts=[public],pepper=pepper,checkout_key=nonce*2),LocalRPC(conn),wx)
        identity=dict(account_id=public,match_session_id=session)
        listed=next(p for p in app.game('catalog',identity)['products'] if p['sku']==recharge.SKU)
        assert listed['max_quantity']==999999 and listed['recharge_u_coin_per_unit']==100
        created=app.game('create',dict(identity,sku=recharge.SKU,quantity=999999))
        assert (created['amount_fen'],created['quantity'],created['recharge_u_coin_total'])==(99999900,999999,99999900)
        assert wx.create.call_count==1 and wx.create.call_args.args[0]['amount']==99999900
        conflict=app.game('create',dict(identity,sku=recharge.SKU,quantity=1))
        assert conflict['order_id']==created['order_id'] and conflict['warning']=='order_quantity_conflict' and conflict['quantity']==999999
        assert wx.create.call_count==1
        receipt=dict(out_trade_no=created['order_id'],appid=APPID,mchid=MCHID,trade_state='SUCCESS',trade_type='NATIVE',
            transaction_id='420000'+str(int(nonce[:24],16)).zfill(34),amount=dict(total=99999900,currency='CNY'))
        assert app.success(receipt)['state']=='delivered' and app.success(receipt)['state']=='delivered'
        final=app.game('status',dict(identity,order_id=created['order_id']))
        assert final['state']=='delivered' and final['recharge_u_coin_total']==99999900
        stored=conn.execute('SELECT archive,content_inventory FROM public.player_archive_state WHERE account_id=%s',(account,)).fetchone()
        assert stored[0]['commerce']['balances']=={'u_coin':99999917,'shop_points':19} and stored[1]=={'keep':3}
        assert conn.execute('SELECT count(*) FROM payments.vip_recharge_credits WHERE account_id=%s',(account,)).fetchone()[0]==1
        report=dict(passed=True,database=fixture_report,operator_validation=operator_report,legacy_quantity_regression=legacy_report,
            production_baseline_functions_verified=len(expected_functions),production_starjoy_regression=starjoy_report,
            service_integration='actual Payments -> real local SQL as goufayu_payment -> fake WeChat -> real SQL wallet',
            service_max_quantity=999999,service_amount_fen=99999900,service_credit_u_coin=99999900,
            repeated_callback_once=True,pending_quantity_conflict_preserved=True,migration_idempotent=True,
            external_gateway_requests=0,real_accounts_modified=False,all_fixture_and_migration_writes_rolled_back=True)
        return report
    finally:conn.rollback();conn.close()


if __name__=='__main__':
    report=run();destination=ROOT/'design_refs/ucoin_recharge_20261017/server_validation_rebased.json'
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
