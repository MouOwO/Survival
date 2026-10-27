"""Read only explicitly bound real orders; never contact a payment gateway."""
import hashlib
import hmac
import json
import re
import sqlite3
import time

STEAM_BASE=76561197960265728
MATCH=re.compile(r'[A-Za-z0-9_:.-]{8,200}\Z')
ORDER=re.compile(r'(?:WX|AL)[a-f0-9]{30}\Z')


def need(value,code):
    if not value:raise RuntimeError(code)


def bindings(connection,account,match):
    rows=connection.execute('SELECT order_id,created FROM payment_order_bindings WHERE account=? AND match_id=? ORDER BY created,order_id LIMIT 51',
                            (account,match)).fetchall()
    need(len(rows)<=50 and all(isinstance(row[0],str) and ORDER.fullmatch(row[0]) for row in rows),'paid_bound_order_set_invalid')
    return [{'order_id':row[0],'bound_at':row[1]} for row in rows]


def literal(value):
    need(isinstance(value,str) and '\0' not in value,'paid_query_literal_invalid')
    return "'"+value.replace("'","''")+"'"


def orders_query(database_id,ids):
    need(re.fullmatch(r'[a-f0-9]{64}',database_id) and 1<=len(ids)<=50 and all(ORDER.fullmatch(value) for value in ids),'paid_order_scope_invalid')
    return """SELECT coalesce(json_agg(json_build_object(
       'order_id',o.order_id,'sku',o.sku,'amount_fen',o.amount,'currency',o.currency,'provider',o.provider,'state',o.state,
       'quantity',CASE WHEN o.reward ? 'quantity' THEN o.reward->'quantity' ELSE '1'::jsonb END,
       'reward_version',o.reward->'version','product_type',o.reward->>'product_type',
       'transaction_present',o.transaction_id IS NOT NULL AND length(o.transaction_id)>0,
       'created_at',extract(epoch FROM o.created_at)::bigint,'paid_at',extract(epoch FROM o.paid_at)::bigint,
       'granted_at',extract(epoch FROM o.granted_at)::bigint,'cleared',o.cleared_at IS NOT NULL,
       'delivered',o.state='delivered' AND o.paid_at IS NOT NULL AND o.granted_at IS NOT NULL,
       'applied_items',o.applied_items,
       'applied_stat_fields',(SELECT coalesce(json_agg(key ORDER BY key),'[]'::json) FROM jsonb_object_keys(o.applied_effects) key),
       'applied_entitlement_ids',(SELECT coalesce(json_agg(key ORDER BY key),'[]'::json) FROM jsonb_object_keys(o.applied_entitlements) key),
       'wallet_recharge_before',o.applied_archive#>'{u_coin_recharge,before}',
       'wallet_recharge_after',o.applied_archive#>'{u_coin_recharge,after}',
       'wallet_recharge_delta',o.applied_archive#>'{u_coin_recharge,delta}',
       'vip_credit_present',c.order_id IS NOT NULL,'vip_credit_amount_fen',c.amount_fen,
       'vip_credit_account_matches',c.account_id IS NULL OR c.account_id=o.account_id,
       'vip_credited_at',extract(epoch FROM c.credited_at)::bigint
       ) ORDER BY o.created_at,o.order_id),'[]'::json)
       FROM payments.orders o LEFT JOIN payments.vip_recharge_credits c ON c.order_id=o.order_id
       WHERE o.account_id="""+literal(database_id)+' AND o.order_id IN ('+','.join(literal(value) for value in ids)+');'


def check(review,request):
    account=request['account'];match=request['match_session_id']
    need(isinstance(account,str) and re.fullmatch(r'[1-9][0-9]{0,9}',account) and int(account)<2**32,'paid_account_invalid')
    need(isinstance(match,str) and MATCH.fullmatch(match) and not match.startswith('lobby_'),'paid_match_invalid')
    env=review.env_values('/etc/goufayu-ws4/api.env')
    roster={str(int(value)-STEAM_BASE) for value in env['SURVIVAL_TEST_STEAM_IDS64'].split(',')}
    need(len(roster)==4 and account in roster,'paid_four_account_gate')
    db=sqlite3.connect('file:/var/lib/goufayu-ws4-web/auth.sqlite3?mode=ro',uri=True,timeout=3)
    try:
        db.execute('PRAGMA query_only=ON');db.execute('BEGIN')
        bound=bindings(db,account,match);db.rollback()
    finally:db.close()
    result={'ok':True,'kind':'WS4_BOUND_REAL_PAID_RECEIPT_READONLY','observed_at':int(time.time()),
            'account_id':account,'match_session_id':match,'binding_count':len(bound),'bindings':bound,
            'orders':[],'paid_receipt_found':False,'delivered_count':0,
            'remote_writes':0,'gateway_called':False,'secrets_exported':False,'legacy_database_accessed':False}
    if not bound:
        result['status']='no_orders_bound_to_this_exact_session';return result
    pepper=env['FISHING_ACCOUNT_ID_PEPPER'];need(isinstance(pepper,str) and len(pepper)>=24,'paid_ws4_identity_configuration_invalid')
    mapped=hmac.new(pepper.encode(),account.encode(),hashlib.sha256).hexdigest()
    rows=review.sql(orders_query(mapped,[row['order_id'] for row in bound]))
    for row in rows:
        need(row['order_id'] in {item['order_id'] for item in bound},'paid_unbound_order_returned')
        need(type(row['quantity']) is int and 1<=row['quantity']<=999999,'paid_quantity_snapshot_invalid')
        need(row['vip_credit_account_matches'] is True,'paid_vip_credit_identity_mismatch')
    result['orders']=rows;result['missing_or_wrong_owner_order_count']=len(bound)-len(rows)
    result['delivered_count']=sum(row['delivered'] is True for row in rows)
    result['paid_receipt_found']=any(row['transaction_present'] is True and row['paid_at'] is not None for row in rows)
    result['status']='bound_real_receipts_read_only'
    result['vip']=review.sql("""SELECT json_build_object(
      'entitlement_exists',e.account_id IS NOT NULL,'stored_active',coalesce(e.active,false),
      'effective_active',coalesce(e.active AND e.starts_at<=now() AND (e.expires_at IS NULL OR e.expires_at>now()),false),
      'starts_at',extract(epoch FROM e.starts_at)::bigint,'expires_at',extract(epoch FROM e.expires_at)::bigint,
      'profile_revision',p.profile_revision,'vip_level',g.vip_level,'vip_recharge_total_fen',g.vip_recharge_total_fen)
      FROM (SELECT 1) singleton LEFT JOIN public.survival_players p ON p.account_id="""+literal(mapped)+"""
      LEFT JOIN public.archive_entitlements e ON e.account_id=p.account_id AND e.entitlement_id='vip'
      LEFT JOIN public.player_gameplay_stats g ON g.player_id=p.account_id;""")
    return result
