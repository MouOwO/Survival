"""Read-only evidence from real WS4 grants and narrowly selected account rows."""
import hashlib
import hmac
import json
from decimal import Decimal
from pathlib import Path
import re
import sqlite3
import time

STEAM_BASE=76561197960265728
MATCH=re.compile(r'[A-Za-z0-9_:.-]{8,200}\Z')
MAX_WALLET=9007199254740991
AUTH_DB='/var/lib/goufayu-ws4-web/auth.sqlite3'


def need(value,code):
    if not value:raise RuntimeError(code)


def account(value):
    need(isinstance(value,str) and re.fullmatch(r'[0-9]{1,20}',value),'readback_account_invalid')
    number=int(value)
    if number>=STEAM_BASE:number-=STEAM_BASE
    need(0<number<2**32,'readback_account_invalid')
    return str(number)


def session_evidence(connection,account_id,match,now):
    need(MATCH.fullmatch(match) and not match.startswith('lobby_'),'readback_match_invalid')
    rows=connection.execute('''SELECT created,approved_at,token_expires,revoked,
        approved_steam=?,token_hash IS NOT NULL FROM challenges
        WHERE account=? AND match_id=? ORDER BY created DESC,approved_at DESC LIMIT 10''',
        (str(STEAM_BASE+int(account_id)),account_id,match)).fetchall()
    active=[row for row in rows if type(row[1]) is int and row[1]<=now and type(row[2]) is int
            and row[2]>now and row[3]==0 and row[4]==1 and row[5]==1]
    result={'matching_challenges':len(rows),'active_grants':len(active),'approved':False,
            'not_revoked':False,'not_expired':False,'steam_identity_matches':False,'token_hash_present':False}
    if len(active)==1:
        row=active[0]
        result.update(approved=True,not_revoked=True,not_expired=True,steam_identity_matches=True,
                      token_hash_present=True,challenge_created_at=row[0],approved_at=row[1],token_expires_at=row[2])
    return result


def wallet(raw):
    need(isinstance(raw,dict) and type(raw.get('profile_exists')) is bool,'readback_profile_shape_invalid')
    if not raw['profile_exists']:
        return {'profile_exists':False,'profile_revision':None,'u_coin':None,'wallet_field_absent':None}
    revision=raw.get('profile_revision')
    need(type(revision) is int and revision>=0,'readback_profile_revision_invalid')
    need(all(raw.get(key) in (None,'object') for key in ('archive_kind','commerce_kind','balances_kind')),
         'readback_wallet_parent_type_invalid')
    kind=raw.get('wallet_kind');text=raw.get('wallet_text')
    if kind is None:
        value=0
    else:
        need(kind=='number' and isinstance(text,str),'readback_wallet_type_invalid')
        value=Decimal(text)
        need(value.is_finite() and value==value.to_integral() and 0<=value<=MAX_WALLET,'readback_wallet_value_invalid')
        value=int(value)
    return {'profile_exists':True,'profile_revision':revision,'u_coin':value,'wallet_field_absent':kind is None}


def scalar_literal(value):
    need(isinstance(value,str) and '\0' not in value,'readback_literal_invalid')
    return "'"+value.replace("'","''")+"'"


def profile_query(database_id):
    need(re.fullmatch(r'[a-f0-9]{64}',database_id),'readback_private_mapping_invalid')
    key=scalar_literal(database_id)
    return """SELECT json_build_object('profile_exists',p.account_id IS NOT NULL,'profile_revision',p.profile_revision,
      'archive_kind',jsonb_typeof(a.archive),'commerce_kind',jsonb_typeof(a.archive->'commerce'),
      'balances_kind',jsonb_typeof(a.archive#>'{commerce,balances}'),
      'wallet_kind',jsonb_typeof(a.archive#>'{commerce,balances,u_coin}'),
      'wallet_text',a.archive#>>'{commerce,balances,u_coin}')
      FROM (SELECT 1) singleton LEFT JOIN public.survival_players p ON p.account_id="""+key+"""
      LEFT JOIN public.player_archive_state a ON a.account_id=p.account_id;"""


def schema(review):
    connection=sqlite3.connect('file:'+AUTH_DB+'?mode=ro',uri=True,timeout=3)
    try:
        connection.execute('PRAGMA query_only=ON')
        tables=[row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        challenge_columns=[row[1] for row in connection.execute('PRAGMA table_info(challenges)')]
    finally:connection.close()
    columns=review.sql("""SELECT coalesce(json_agg(json_build_object('table',table_name,'column',column_name,'type',data_type)
      ORDER BY table_name,ordinal_position),'[]'::json) FROM information_schema.columns WHERE table_schema='public'
      AND table_name IN ('survival_players','player_archive_state','match_profile_sessions');""")
    return {'ok':True,'kind':'WS4_READBACK_SCHEMA_ONLY','auth_tables':tables,'challenge_columns':challenge_columns,
            'ws4_columns':columns,'proxy_success_receipt_table_present':False,
            'proxy_receipt_limit':'Current PWA schema has no durable auth/profile HTTP success receipt; rate counters are not success evidence.',
            'player_rows_read':0,'remote_writes':0,'real_player_grant':False,'cloud_profile_readback':False}


def snapshot(review,request):
    primary=account(request['account']);match=request['match_session_id']
    need(MATCH.fullmatch(match) and not match.startswith('lobby_'),'readback_match_invalid')
    control=account(request['control_account']) if request.get('control_account') else None
    need(control!=primary,'readback_control_must_differ')
    env=review.env_values('/etc/goufayu-ws4/api.env')
    roster={account(value) for value in env['SURVIVAL_TEST_STEAM_IDS64'].split(',')}
    need(len(roster)==4 and primary in roster and (control is None or control in roster),'readback_four_account_gate')
    connection=sqlite3.connect('file:'+AUTH_DB+'?mode=ro',uri=True,timeout=3)
    try:
        connection.execute('PRAGMA query_only=ON');connection.execute('BEGIN')
        now=int(time.time());grant=session_evidence(connection,primary,match,now)
        connection.rollback()
    finally:connection.close()
    result={'kind':'WS4_REAL_SESSION_READONLY_SNAPSHOT','ok':False,'observed_at':now,
            'account_id':primary,'match_session_id':match,'control_account_id':control,'grant':grant,
            'real_player_grant':grant['approved'],'cloud_profile_readback':False,'server_snapshot_ready':False,
            'api_proxy_receipt_available':False,'proxy_receipt_limit':'No durable PWA auth/profile HTTP success receipt exists; client readback evidence is separate.',
            'target':{'container':'goufayu-ws4-db','database':'goufayu_ws4','published_port':15432,'legacy_database_accessed':False},
            'secrets_exported':False,'remote_writes':0}
    if not grant['approved']:
        result['status']='waiting_for_real_approved_session';return result
    pepper=env['FISHING_ACCOUNT_ID_PEPPER']
    need(isinstance(pepper,str) and len(pepper)>=24,'readback_ws4_identity_configuration_invalid')
    mapped=hmac.new(pepper.encode(),primary.encode(),hashlib.sha256).hexdigest()
    # Only SELECTs of specific account/match and selected scalar fields. Never
    # call profile/auth RPCs: they may drain grants or update session baselines.
    data=review.sql(profile_query(mapped));result['wallet']=wallet(data)
    context=review.sql("""SELECT coalesce((SELECT json_build_object('exists',true,'mode',mode,
      'created_at',extract(epoch FROM created_at)::bigint,'baseline_revision',baseline->'revision')
      FROM public.match_profile_sessions WHERE account_id="""+scalar_literal(mapped)+
      ' AND match_session_id='+scalar_literal(match)+"),json_build_object('exists',false));")
    result['cloud_login']=context
    if control is not None:
        other=hmac.new(pepper.encode(),control.encode(),hashlib.sha256).hexdigest()
        result['control_wallet']=wallet(review.sql(profile_query(other)))
    ready=(result['wallet']['profile_exists'] and context.get('exists') is True
           and type(context.get('created_at')) is int and context['created_at']>=grant['approved_at']-2)
    result['server_snapshot_ready']=ready
    result['ok']=ready
    result['status']='server_evidence_ready_client_receipt_required' if ready else 'waiting_for_cloud_match_login'
    return result
