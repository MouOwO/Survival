"""Plan/read-only WS4 evidence and local pre/post wallet comparison."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re

from deploy_plan import ROOT,TRANSPORT_PIN
from catalog_validation import canonical
from live_readback_remote import account,MAX_WALLET,MATCH
from activation_remote import validate_capsule

CAPSULE=ROOT/'output/arcade_payment_link_20261027/plan_activation_20261027T000220028511Z.json'


def attach_client(snapshot,receipt):
    fields={'kind','account_id','match_session_id','observed_at','authenticated','loaded','profile_revision','u_coin','wallet_scope',
            'http_auth_status','http_profile_status'}
    required=fields-{'http_auth_status','http_profile_status'}
    if not isinstance(receipt,dict) or not required<=set(receipt) or set(receipt)-fields:
        raise ValueError('readback_client_receipt_fields_invalid')
    if (receipt['kind']!='WS4_HELPER_LIVE_READBACK' or receipt['account_id']!=snapshot['account_id']
            or receipt['match_session_id']!=snapshot['match_session_id'] or receipt['wallet_scope']!='account'
            or receipt['authenticated'] is not True or receipt['loaded'] is not True
            or type(receipt['observed_at']) is not int or type(receipt['profile_revision']) is not int
            or type(receipt['u_coin']) is not int or not 0<=receipt['u_coin']<=MAX_WALLET):
        raise ValueError('readback_client_receipt_identity_or_type_invalid')
    if not snapshot['server_snapshot_ready'] or not snapshot['real_player_grant']:
        raise ValueError('readback_real_server_session_required')
    if not snapshot['grant']['approved_at']<=receipt['observed_at']<=snapshot['observed_at']+10 or snapshot['observed_at']-receipt['observed_at']>300:
        raise ValueError('readback_client_receipt_not_fresh')
    if (receipt['profile_revision'],receipt['u_coin'])!=(snapshot['wallet']['profile_revision'],snapshot['wallet']['u_coin']):
        raise ValueError('readback_client_wallet_or_revision_mismatch')
    for name in ('http_auth_status','http_profile_status'):
        if name in receipt and (type(receipt[name]) is not int or receipt[name]!=200):
            raise ValueError('readback_client_http_status_invalid')
    result=dict(snapshot)
    result.update(ok=True,cloud_profile_readback=True,status='real_helper_client_and_server_readback_match',
                  api_proxy_receipt_available=all(name in receipt for name in ('http_auth_status','http_profile_status')),
                  client_evidence_source='operator-captured real helper runtime; not a durable PWA HTTP receipt',
                  client_receipt_sha256=hashlib.sha256(canonical(receipt)).hexdigest())
    return result


def compare(before,after,expected=100):
    for row in (before,after):
        if row.get('kind')!='WS4_REAL_SESSION_READONLY_SNAPSHOT' or row.get('server_snapshot_ready') is not True:
            raise ValueError('readback_real_server_snapshots_required')
    if any(before.get(key)!=after.get(key) for key in ('account_id','match_session_id','control_account_id')):
        raise ValueError('readback_snapshot_identity_mismatch')
    if after['observed_at']<before['observed_at'] or type(expected) is not int or expected<=0:
        raise ValueError('readback_comparison_time_or_delta_invalid')
    delta=after['wallet']['u_coin']-before['wallet']['u_coin']
    revision_delta=after['wallet']['profile_revision']-before['wallet']['profile_revision']
    isolated=(before.get('control_account_id') is not None and before.get('control_wallet',{}).get('profile_exists') is True
              and before.get('control_wallet')==after.get('control_wallet'))
    credit=delta==expected and revision_delta>=1
    client=before.get('cloud_profile_readback') is True and after.get('cloud_profile_readback') is True
    return {'kind':'WS4_REAL_WALLET_READONLY_COMPARISON','ok':credit and isolated,
            'account_id':before['account_id'],'match_session_id':before['match_session_id'],
            'expected_u_coin_delta':expected,'actual_u_coin_delta':delta,'profile_revision_delta':revision_delta,
            'wallet_credit_verified':credit,'control_account_unchanged':isolated,'client_readback_verified':client,
            'cloud_profile_readback':False,'server_data_comparison_verified':credit and isolated,
            'remote_writes':0,'gateway_called':False,'limit':'Server comparison only. Root may separately combine actual UI evidence; wallet delta alone does not identify a paid receipt or prove callback idempotency.'}


def remote(mode,request=None):
    capsule=json.loads(CAPSULE.read_bytes());driver=ROOT/'tools/archive_caps_20261020/remote_driver.py'
    validate_capsule(capsule)
    if capsule['activation_sha256']!='9cc5a4e583f1ce0de1b1832bca6b804a5ad29a172d21e679070643b59e713700':
        raise ValueError('readback_original_ws4_capsule_required')
    if hashlib.sha256(driver.read_bytes()).hexdigest()!=TRANSPORT_PIN:raise ValueError('pinned_transport_changed')
    spec=importlib.util.spec_from_file_location('ws4_live_readonly_transport',driver)
    transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    raw=Path(__file__).with_name('live_readback_remote.py').read_text(encoding='utf-8')
    source='CAPSULE='+repr(capsule)+'\n'+r'''
from pathlib import Path
import hashlib,json,types
stage=Path(CAPSULE['activation_stage'])
raw=(stage/'review_tools/remote_review.py').read_bytes()
assert hashlib.sha256(raw).hexdigest()==CAPSULE['candidate']['source_hashes']['review_tools/remote_review.py']
review=types.ModuleType('ws4_frozen_readonly_queries');exec(raw.decode(),review.__dict__)
'''
    source+="audit=types.ModuleType('ws4_live_readback');exec("+repr(raw)+",audit.__dict__)\n"
    source+='result=audit.'+('schema(review)' if mode=='schema' else 'snapshot(review,'+repr(request)+')')+'\nprint(json.dumps(result,separators=(\",\",\":\")))\n'
    return json.loads(transport.remote(source,timeout=55))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('plan','schema','snapshot','compare'),nargs='?',default='plan')
    parser.add_argument('--account');parser.add_argument('--match',dest='match_id');parser.add_argument('--control-account')
    parser.add_argument('--client-receipt',type=Path);parser.add_argument('--before',type=Path);parser.add_argument('--after',type=Path)
    parser.add_argument('--expected-u-coin',type=int,default=100);parser.add_argument('--save-record',action='store_true');args=parser.parse_args(argv)
    if args.mode=='plan':
        value={'kind':'WS4_READBACK_LOCAL_PLAN','network':False,'remote_writes':0,'real_player_grant':False,'cloud_profile_readback':False,
               'steps':['schema reads metadata only','snapshot requires explicit authorized account+fresh real match grant',
                        'read only selected wallet/revision fields from isolated WS4; optional named control account',
                        'optional real helper runtime scalar receipt must match account/session/wallet/revision',
                        'compare local before/after records for exact expected credit and unchanged control'],
               'api_receipt_limit':'Current PWA has no durable auth/profile proxy success receipts; grants/counters never substitute for them.'}
    elif args.mode=='schema':value=remote('schema')
    elif args.mode=='snapshot':
        if not args.account or not args.match_id or not MATCH.fullmatch(args.match_id):parser.error('snapshot requires --account and exact --match')
        request={'account':account(args.account),'match_session_id':args.match_id}
        if args.control_account:request['control_account']=account(args.control_account)
        value=remote('snapshot',request)
        if args.client_receipt:value=attach_client(value,json.loads(args.client_receipt.read_bytes()))
    else:
        if not args.before or not args.after:parser.error('compare requires --before and --after')
        value=compare(json.loads(args.before.read_bytes()),json.loads(args.after.read_bytes()),args.expected_u_coin)
    saved=None
    if args.save_record:
        directory=ROOT/'output/arcade_payment_link_20261027';directory.mkdir(parents=True,exist_ok=True)
        stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        saved=directory/('live_readback_'+args.mode+'_'+stamp+'.json')
        with saved.open('xb') as output:output.write(canonical(value))
    print(json.dumps({'mode':args.mode,'record':str(saved) if saved else None,'result':value},ensure_ascii=False))


if __name__=='__main__':main()
