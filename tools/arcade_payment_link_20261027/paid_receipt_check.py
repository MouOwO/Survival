"""Plan by default; inspect only real orders bound to a specified WS4 session."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path

from deploy_plan import ROOT,TRANSPORT_PIN
from catalog_validation import canonical
from activation_remote import validate_capsule
from live_readback_remote import account,MATCH


def remote(request):
    capsule=json.loads((ROOT/'output/arcade_payment_link_20261027/plan_activation_20261027T000220028511Z.json').read_bytes())
    validate_capsule(capsule)
    if capsule['activation_sha256']!='9cc5a4e583f1ce0de1b1832bca6b804a5ad29a172d21e679070643b59e713700':
        raise ValueError('paid_original_ws4_capsule_required')
    driver=ROOT/'tools/archive_caps_20261020/remote_driver.py'
    if hashlib.sha256(driver.read_bytes()).hexdigest()!=TRANSPORT_PIN:raise ValueError('pinned_transport_changed')
    spec=importlib.util.spec_from_file_location('paid_readonly_transport',driver)
    transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    raw=Path(__file__).with_name('paid_receipt_remote.py').read_text(encoding='utf-8')
    source='CAPSULE='+repr(capsule)+'\n'+r'''
from pathlib import Path
import hashlib,json,types
stage=Path(CAPSULE['activation_stage'])
raw=(stage/'review_tools/remote_review.py').read_bytes()
assert hashlib.sha256(raw).hexdigest()==CAPSULE['candidate']['source_hashes']['review_tools/remote_review.py']
review=types.ModuleType('ws4_paid_frozen_readonly_queries');exec(raw.decode(),review.__dict__)
'''
    source+="audit=types.ModuleType('ws4_paid_receipts');exec("+repr(raw)+",audit.__dict__)\nresult=audit.check(review,"+repr(request)+')\nprint(json.dumps(result,separators=(\",\",\":\")))\n'
    return json.loads(transport.remote(source,timeout=55))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('plan','check'),nargs='?',default='plan')
    parser.add_argument('--account');parser.add_argument('--match',dest='match_id');parser.add_argument('--save-record',action='store_true')
    args=parser.parse_args(argv)
    if args.mode=='plan':
        value={'network':False,'remote_writes':0,'gateway_called':False,
               'scope':'Read exact account+match PWA order bindings, then only matching owner orders and minimal reward/VIP fields in isolated WS4.'}
    else:
        if not args.account or not args.match_id or not MATCH.fullmatch(args.match_id):parser.error('check requires exact --account and --match')
        value=remote({'account':account(args.account),'match_session_id':args.match_id})
    saved=None
    if args.save_record:
        stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        saved=ROOT/'output/arcade_payment_link_20261027'/('paid_receipt_'+stamp+'.json')
        with saved.open('xb') as stream:stream.write(canonical(value))
    print(json.dumps({'mode':args.mode,'record':str(saved) if saved else None,'result':value},ensure_ascii=False))


if __name__=='__main__':main()
