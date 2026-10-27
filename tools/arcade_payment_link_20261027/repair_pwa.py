"""Independent reviewed repair; frozen original activation sources stay intact."""
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

ORIGINAL='9cc5a4e583f1ce0de1b1832bca6b804a5ad29a172d21e679070643b59e713700'
CAPSULE=ROOT/'output/arcade_payment_link_20261027/plan_activation_20261027T000220028511Z.json'
INSPECTION=ROOT/'output/arcade_payment_link_20261027/pwa_repair_inspection_20261027.json'


def original():
    value=json.loads(CAPSULE.read_bytes());validate_capsule(value)
    if value['activation_sha256']!=ORIGINAL:raise ValueError('repair_original_capsule_required')
    return value


def build():
    capsule=original();inspection=json.loads(INSPECTION.read_bytes())
    if inspection.get('ok') is not True or inspection.get('original_capsule')!=ORIGINAL:
        raise ValueError('repair_reviewed_inspection_required')
    plan={'kind':'WS4_PWA_INDENTED_UNIT_FORWARD_REPAIR','original_capsule':ORIGINAL,'inspection':inspection,
          'remote_source_sha256':hashlib.sha256(Path(__file__).with_name('repair_pwa_remote.py').read_bytes().replace(b'\r\n',b'\n')).hexdigest(),
          'runner_sha256':hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n',b'\n')).hexdigest(),
          'scope':['Validate normalized systemd directives while preserving all unrelated unit bytes.',
                   'Reuse already frozen PWA release and precomputed payments0 environment.',
                   'Restart only PWA, preserve original SQLite and browser secrets.',
                   'Write original activation receipt and run original frozen verify; never seed or restart payment again.']}
    plan['repair_sha256']=hashlib.sha256(canonical(plan)).hexdigest()
    return capsule,plan


def remote(mode,capsule,plan=None):
    driver=ROOT/'tools/archive_caps_20261020/remote_driver.py'
    if hashlib.sha256(driver.read_bytes()).hexdigest()!=TRANSPORT_PIN:raise ValueError('pinned_transport_changed')
    spec=importlib.util.spec_from_file_location('pwa_fixed_repair_transport',driver)
    transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    repair_raw=Path(__file__).with_name('repair_pwa_remote.py').read_bytes().replace(b'\r\n',b'\n')
    if plan and hashlib.sha256(repair_raw).hexdigest()!=plan['remote_source_sha256']:raise ValueError('reviewed_repair_source_changed')
    # Load the original operators from their immutable, hash-checked stage;
    # no monkeypatch or mutation of the frozen candidate is necessary.
    source='CAPSULE='+repr(capsule)+'\n'+r'''
from pathlib import Path
import hashlib,json,sys,types
stage=Path(CAPSULE['activation_stage'])
def module(name,file):
 raw=(stage/'review_tools'/file).read_bytes()
 assert hashlib.sha256(raw).hexdigest()==CAPSULE['candidate']['source_hashes']['review_tools/'+file]
 result=types.ModuleType(name);exec(raw.decode(),result.__dict__);sys.modules[name]=result;return result
review=module('remote_review','remote_review.py')
operator=module('ws4_original_frozen_activation','activation_remote.py')
'''
    source+="repair=types.ModuleType('ws4_independent_pwa_repair')\nexec("+repr(repair_raw.decode())+",repair.__dict__)\n"
    source+='result=repair.'+('inspect(operator,CAPSULE)' if mode=='inspect' else 'apply(operator,CAPSULE,'+repr(plan)+')')+'\nprint(json.dumps(result,separators=(\",\",\":\")))\n'
    return json.loads(transport.remote(source,timeout=120))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('plan','inspect','apply'),nargs='?',default='plan')
    parser.add_argument('--review-hash');parser.add_argument('--save-plan',action='store_true');args=parser.parse_args(argv)
    if args.mode=='inspect':
        value=remote('inspect',original())
        if INSPECTION.exists():raise ValueError('repair_inspection_record_exists')
        INSPECTION.write_bytes(canonical(value));print(json.dumps(value));return
    if not INSPECTION.exists():
        print(json.dumps({'network':False,'repair_executed':False,'needs':'read-only inspect before review'}));return
    capsule,plan=build()
    if args.mode=='apply':
        if args.review_hash!=plan['repair_sha256']:raise ValueError('reviewed_repair_hash_required')
        value=remote('apply',capsule,plan)
    else:value=plan
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');saved=None
    if args.save_plan or args.mode=='apply':
        saved=INSPECTION.parent/('pwa_repair_'+args.mode+'_'+stamp+'.json')
        with saved.open('xb') as stream:stream.write(canonical(value))
    print(json.dumps({'mode':args.mode,'repair_sha256':plan['repair_sha256'],'record':str(saved) if saved else None,
                      'payments_enabled':value.get('payments_enabled',False),'repair_executed':args.mode=='apply'}))


if __name__=='__main__':main()
