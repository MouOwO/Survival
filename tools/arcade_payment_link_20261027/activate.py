"""Create a reviewed activation capsule; default command never accesses SSH."""
from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path

from deploy_plan import ROOT, TRANSPORT_PIN, build, encoded_files
from catalog_validation import canonical
from activation_remote import capsule_identity, validate_capsule

MODES = ('plan','stage','activate','verify','enable','disable','rollback-no-orders')


def build_activation(snapshot,audit_path):
    candidate,files=build(cloud_snapshot=snapshot)
    path=Path(audit_path).resolve(strict=True)
    allowed=(ROOT/'output/arcade_payment_link_20261027').resolve()
    if path.parent!=allowed or not path.name.startswith('audit_'):
        raise ValueError('fixed_readonly_audit_record_required')
    raw=path.read_bytes();audit=json.loads(raw)
    if audit.get('ok') is not True or audit.get('kind')!='WS4_PAYMENT_LINK_READ_ONLY_AUDIT':
        raise ValueError('reviewed_readonly_audit_required')
    capsule={'kind':'WS4_REVIEWED_ISOLATED_PAYMENT_ACTIVATION','version':1,'candidate':candidate,
             'audit':audit,'audit_record_sha256':hashlib.sha256(raw).hexdigest(),
             'database_strategy':'SEED_EMPTY_TABLES_ONLY_NO_MIGRATIONS','payments_initially_enabled':False,
             'steps':['Private host-only backups of empty payment namespace, public metadata, role state and PWA unit/env.',
                      'Recheck exact 35 function bodies/owner/security/search_path, ten immutable bundle CSV hashes and all eleven empty payment tables.',
                      'Rollback-only compile/catalog/bundle validation with no synthetic transactions or player rows.',
                      'Create independent service account, runtime/dependencies, config and private read-only copies of existing merchant keys.',
                      'One serializable seed transaction for stat rules, VIP twelve levels, providers, full frozen cash catalog, disabled reset; enable only isolated role LOGIN/CONNECT.',
                      'Start new loopback18769; add only ten exact WS4 cashier/callback/static public routes.',
                      'Deploy new PWA source release with original SQLite/browser secret and payments0; restart only PWA plus new payment unit.',
                      'Root performs authentic Steam grant and cloud profile readback; a separately reviewed enable records its receipt hash.',
                      'Disable blocks new PWA payment intents while callbacks/worker and receipts remain; rollback requires an empty unchanged new ledger.'],
             'forbidden':['No old service/DB/payment restart or release pointer edits.','No legacy ledger/config/key ACL changes.',
                          'No SQL schema replay or public player writes.','No new order or gateway call by operator.',
                          'No credentials or private backups exported locally.']}
    identity=capsule_identity(capsule);capsule['activation_sha256']=identity
    capsule['activation_stage']='/root/goufayu_upload/ws4-payment-activation-'+identity[:20]
    validate_capsule(capsule)
    return capsule,files


def remote(mode,capsule,files=None,evidence=None):
    driver=ROOT/'tools/archive_caps_20261020/remote_driver.py'
    if hashlib.sha256(driver.read_bytes()).hexdigest()!=TRANSPORT_PIN:
        raise ValueError('pinned_ssh_transport_changed')
    spec=importlib.util.spec_from_file_location('ws4_activation_transport',driver)
    transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
    sources={}
    for name in ('remote_review.py','activation_remote.py'):
        raw=Path(__file__).with_name(name).read_bytes().replace(b'\r\n',b'\n')
        if hashlib.sha256(raw).hexdigest()!=capsule['candidate']['source_hashes']['review_tools/'+name]:
            raise ValueError('reviewed_activation_operator_changed')
        sources[name]=raw.decode()
    source='import types,sys\n'
    source+="review=types.ModuleType('remote_review')\nexec("+repr(sources['remote_review.py'])+",review.__dict__)\nsys.modules['remote_review']=review\n"
    source+="operator=types.ModuleType('ws4_reviewed_activation')\nexec("+repr(sources['activation_remote.py'])+",operator.__dict__)\n"
    source+='operator.activation_main('+repr(mode)+','+repr(capsule)+','+repr(encoded_files(files) if files is not None else None)+','+repr(evidence)+')\n'
    value=json.loads(transport.remote(source,timeout=300))
    if value.get('ok') is not True or value.get('activation_sha256')!=capsule['activation_sha256']:
        raise RuntimeError('reviewed_activation_failed')
    return value


def arguments(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=MODES,nargs='?',default='plan')
    parser.add_argument('--cloud-snapshot',type=Path)
    parser.add_argument('--audit',type=Path)
    parser.add_argument('--review-hash')
    parser.add_argument('--profile-readback-record',type=Path)
    parser.add_argument('--save-plan',action='store_true')
    args=parser.parse_args(argv)
    if args.mode!='plan' and (not args.cloud_snapshot or not args.audit or not args.review_hash):
        parser.error('network actions require exact --cloud-snapshot, --audit and --review-hash')
    if args.mode=='enable' and not args.profile_readback_record:
        parser.error('enable requires a real helper cloud-profile-readback record')
    if args.profile_readback_record and args.mode!='enable':
        parser.error('readback evidence applies only to enable')
    return args


def main(argv=None):
    args=arguments(argv)
    if args.mode=='plan' and (not args.cloud_snapshot or not args.audit):
        print(json.dumps({'network':False,'activation_executed':False,'needs':['reviewed cloud snapshot','fresh semantic read-only audit'],
                          'payments_initially_enabled':False}))
        return
    capsule,files=build_activation(args.cloud_snapshot,args.audit)
    if args.mode!='plan' and args.review_hash!=capsule['activation_sha256']:
        raise ValueError('reviewed_activation_candidate_changed')
    evidence=None
    if args.mode=='enable':
        path=args.profile_readback_record.resolve(strict=True)
        if (ROOT/'output').resolve() not in path.parents:
            raise ValueError('local_ignored_readback_receipt_required')
        raw=path.read_bytes();record=json.loads(raw)
        if record.get('ok') is not True or record.get('real_player_grant') is not True or record.get('cloud_profile_readback') is not True:
            raise ValueError('authentic_cloud_readback_receipt_required')
        evidence={'ok':True,'real_player_grant':True,'cloud_profile_readback':True,'record_sha256':hashlib.sha256(raw).hexdigest()}
    value=capsule if args.mode=='plan' else remote(args.mode,capsule,files if args.mode=='stage' else None,evidence)
    saved=None
    if args.save_plan or args.mode!='plan':
        stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        directory=ROOT/'output/arcade_payment_link_20261027';directory.mkdir(parents=True,exist_ok=True)
        saved=directory/(args.mode+'_activation_'+stamp+'.json')
        with saved.open('xb') as stream:stream.write(canonical(value))
    print(json.dumps({'mode':args.mode,'activation_sha256':capsule['activation_sha256'],
                      'candidate_sha256':capsule['candidate']['plan_sha256'],'record':str(saved) if saved else None,
                      'payments_enabled':value.get('payments_enabled',False),'activation_executed':args.mode=='activate'},separators=(',',':')))


if __name__=='__main__':
    main()
