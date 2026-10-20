"""Checked mode-only release driver. Default is local; no phase runs on import.

`preflight` is the only remote action used while preparing this operator. All
remote mutation phases require the exact locally reviewed payload SHA explicitly.
"""
from __future__ import annotations
import argparse
import base64
import contextlib
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import tarfile
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT/'output/mode_progression_release_20261020/operator_caps_review'
BUNDLE = 'b3c342e1de0de5d8c5b21471eb87a6af288a177e88d1875e43d9fcae24c3af93'
PARENT = 'ecf55dd6ba24d0b391a1640f7e25c06c50d79ec1eb37f0bfcdb86c28afde22f7'
SEALED = '3271354e33297ee4da9c25713037a8049fdd2be5548bed324f0911e095aaf4c3'
BASELINE = '20261020-archive-caps-v1'
BASELINE_SHA = '30b3400ce2389c150290810097919e648beeae79dc96cbd4bd1ea27bb6310668'
PAYMENT = '20261018-checkout-gcoin-v1'
RELEASE = '20261020-mode-chain-'+BUNDLE[:12]+'-v1'
SQL = {'202610200004_mode_unlock_chain.sql':'da1b05ef4398929735e1b08f093bb11f1fef6bbf92a43cd772b2c2d5ccac4ec5'}
BACKEND = {'backend/archive_backend/'+name for name in ('match_modes.py','unique_points.py')}
CHANGED_LUA = {'systems/archive_welfare_rewards.lua','config/recorded_mode_balance.lua'}


def need(condition, code):
    if not condition:
        raise RuntimeError(code)


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def safe_name(name):
    p = PurePosixPath(name)
    need(isinstance(name,str) and name and p.parts and not p.is_absolute() and '..' not in p.parts
         and '\\' not in name and ':' not in name and '\x00' not in name and p.as_posix()==name,'unsafe_payload_member')
    return p


def unpack(raw):
    need(len(raw)<64*1024*1024,'payload_too_large')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as stream:
        members = stream.getmembers()
        need(sum(m.size for m in members)<128*1024*1024,'expanded_payload_too_large')
        for member in members:
            safe_name(member.name)
            need(member.isfile() and member.name not in files,'unsafe_payload_member')
            files[member.name] = stream.extractfile(member).read()
    return files


def pack(files):
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output,mode='wb',mtime=0) as gz:
        with tarfile.open(fileobj=gz,mode='w') as stream:
            for name,raw in sorted(files.items()):
                safe_name(name)
                item=tarfile.TarInfo(name);item.size=len(raw);item.mode=0o600;item.mtime=0
                stream.addfile(item,io.BytesIO(raw))
    return output.getvalue()


def sealed_candidate():
    pointer=json.loads((ROOT/'output/mode_progression_release_20261020/sealed_mode_only_candidate.json').read_bytes())
    need(pointer['sha256']==SEALED and pointer['bundle']==BUNDLE,'sealed_candidate_changed')
    source=(ROOT/pointer['package']).resolve()
    need(source.is_relative_to(ROOT/'output/mode_progression_release_20261020/mode_only_sealed'),'sealed_path_refused')
    raw=source.read_bytes();need(sha(raw)==SEALED,'sealed_tar_changed')
    files=unpack(raw);review=json.loads(files['package_review.json'])
    need(review['status']=='LOCALLY_VERIFIED_MODE_ONLY_PACKAGE_NOT_DEPLOYED'
         and review['bundle']==BUNDLE and review['parent']==PARENT
         and review['baseline_manifest_sha256']==BASELINE_SHA and review['baseline_release']==BASELINE
         and review['changed_configs']==[] and review['daily_parent_behavior_preserved'] is True,'sealed_review_changed')
    need(set(files)==set(review['files'])|{'package_review.json'},'sealed_member_scope_changed')
    need(all(sha(files[n])==v for n,v in review['files'].items()),'sealed_member_digest_changed')
    test=json.loads(files['verification/mode_only.json'])
    need(test['status']=='PASS' and test['cluster_stopped'] is True and test['bundle']==BUNDLE,'sealed_http_checks_changed')
    candidate=json.loads(files['review.json'])
    need(set(candidate['changed_lua_sources'])==CHANGED_LUA
         and set(candidate['changed_backend_files'])==BACKEND,'mode_source_scope_changed')
    need({n for n in files if n.startswith('overlay/database/')}=={'overlay/database/'+n for n in SQL},'applied_schema_overlay_refused')
    return files,candidate,test


def baseline_pins():
    need((OUT/'preflight.json').is_file(),'fresh_live_preflight_required_before_plan')
    pins=json.loads((OUT/'preflight.json').read_bytes())
    need(pins['status']=='MODE_RELEASE_READONLY_PREFLIGHT_PASS' and pins['database_writes']==0
         and pins['remote_files_written']==0,'preflight_not_readonly')
    need((pins['archive_release'],pins['archive_manifest_sha256'],pins['archive_bundle'],pins['payment_release'])
         ==(BASELINE,BASELINE_SHA,PARENT,PAYMENT),'baseline_fingerprint_changed')
    perms=pins['permissions']
    need(len(perms['rpc'])==16 and not any(perms['role_flags']) and not perms['memberships']
         and perms['table_access_count']==0 and perms['schema_create'] is False,'application_privileges_changed')
    need(pins['ledger'].get('target/202610200002_archive_match_modes.sql')=='70a8ddb268ea419431630961653d61e4d2404bc7d1772fb7012e9495d25cf817'
         and pins['ledger'].get('target/202610200003_archive_daily_limits.sql')=='522891724d0d1df7e105f5da4f508a87e4cdd53c4ea21768a1022f26895ce9b2','applied_baseline_migrations_changed')
    need('target/202610200004_mode_unlock_chain.sql' not in pins['ledger'],'mode004_already_applied_replan_required')
    return pins


def reviewed_scope():
    files,review,test=sealed_candidate()
    baseline=ROOT/'output/mode_spawn_progression_20261020/live_caps/baseline'
    old=json.loads((baseline/'release_manifest.json').read_bytes())
    need(sha((baseline/'release_manifest.json').read_bytes())==BASELINE_SHA,'local_baseline_changed')
    data=json.loads(files['overlay/addon/server/bundles/'+BUNDLE+'/bundle.json'])
    parent=json.loads((baseline/'addon/server/bundles'/PARENT/'bundle.json').read_bytes())
    need(data['configs']==parent['configs'] and data['csv_hashes']==parent['csv_hashes'],'parent_configs_changed')
    need(all(data['compatible_config_hashes'].get(k)==v for k,v in parent.get('compatible_config_hashes',{}).items()),'historical_compatibility_changed')
    need(set(data['sources'])==set(parent['sources'])
         and {name for name in data['sources'] if data['sources'][name]!=parent['sources'][name]}==CHANGED_LUA,'bundle_lua_scope_changed')
    configuration={'configs':data['configs'],'compatible_config_hashes':data['compatible_config_hashes']}
    prefix='addon/server/bundles/'+BUNDLE+'/'
    allowed=BACKEND|{'addon/server/bundles/current.json','addon/scripts/vscripts/config/generated/archive_http_bundle.lua',prefix+'bundle.json',*(prefix+n for n in data['sources'])}
    overlay={n.removeprefix('overlay/'):b for n,b in files.items() if n.startswith('overlay/') and n.removeprefix('overlay/') in allowed}
    need(set(overlay)==allowed,'whitelisted_overlay_missing')
    # Every unchanged live HTTP/catalog/daily file and every historical hash
    # stays byte-for-byte in the parent; only the reviewed allowlist is copied.
    changed_backend={n for n,d in review['files'].items() if n.startswith('backend/') and old['files'].get(n)!=d}
    need(changed_backend==BACKEND,'backend_overlay_scope_changed')
    for name,digest in review['files'].items():
        if name.startswith('backend/') and name not in BACKEND:
            need(digest==old['files'][name],'live_daily_catalog_or_transport_changed')
    for digest in review['retained_old_bundles']:
        need(old['files'].get('addon/server/bundles/'+digest+'/bundle.json')==digest,'live_historical_bundle_missing')
    # Match Python read_text / PostgreSQL's captured definition across the
    # Windows packaging host and Linux operator; retain sealed raw hash proof.
    guard=files['database/archive_sync_registration_REVIEW_ONLY.sql'].decode().replace('\r\n','\n')
    before=(OUT/'archive_sync_before.sql').read_text('utf-8-sig')
    need(sha(before.encode())=='4b7f47f62b983770f9d02f81a772bda66e8e4433ba305b4fec6b89a8ed834b5d','frozen_caps_guard_changed')
    start=guard.index(' -- Reviewed mode-chain004 candidate:');end=guard.index(' -- Reviewed daily unique points:',start)
    need(guard[:start]+guard[end:]==before,'registration_guard_would_drop_existing_logic')
    payload={'archive/'+n:b for n,b in overlay.items()}
    payload.update({'configuration.json':canonical(configuration),'archive_sync_before.sql':before.encode(),
        'archive_sync_candidate.sql':guard.encode(),
        'operator.py':HERE.joinpath('mode_release_remote.py').read_bytes(),
        'sealed_package_review.json':files['package_review.json'],'verification/mode_only.json':files['verification/mode_only.json']})
    migrations=[]
    for name,digest in SQL.items():
        raw=files['overlay/database/'+name]
        need(sha(raw)==digest,'canonical_mode_sql_changed')
        key='target/'+name
        payload['database/'+name]=raw;migrations.append({'id':key,'file':'database/'+name,'sha256':digest})
    need(len(migrations)==1 and migrations[0]['id']=='target/202610200004_mode_unlock_chain.sql','mode004_scope_changed')
    post=test['registration']['post_functions']
    login=post['public.match_profile_login(text,text,text,jsonb)']
    need(sha(login['definition'].encode())==login['sha256'],'tested_mode_login_digest_changed')
    need(post['public.archive_sync_config(text,jsonb)']['sha256']==sha(guard.encode()),'tested_sync_digest_changed')
    return dict(payload=payload,migrations=migrations,overlay=overlay,test=test,
        new_function_hashes={'public.match_profile_login(text,text,text,jsonb)':login['sha256'],
            'public.archive_sync_config(text,jsonb)':sha(guard.encode())})


def preview(save=True):
    scope=reviewed_scope()
    result={'status':'LOCALLY_PREPARED_PENDING_LIVE_PREFLIGHT','bundle':BUNDLE,'parent_bundle':PARENT,
        'archive_baseline':BASELINE,'archive_manifest_sha256':BASELINE_SHA,'archive_release':RELEASE,
        'sealed_candidate_sha256':SEALED,'mode_migrations':scope['migrations'],
        'archive_files':{name:sha(raw) for name,raw in scope['overlay'].items()},
        'new_function_hashes':scope['new_function_hashes'],'changed_lua_sources':sorted(CHANGED_LUA),
        'configuration_jsonb_sha256':scope['test']['registration']['configuration_jsonb_sha256'],
        'next_steps':['readonly preflight','plan with exact fresh ledger/functions/constraints','independent review before mutation'],
        'remote_executed':False,'deployable':False}
    if save:
        OUT.mkdir(parents=True,exist_ok=True);(OUT/'local_scope_preview.json').write_bytes(canonical(result))
    return result


def build_plan():
    scope=reviewed_scope();pins=baseline_pins()
    payload=scope['payload'];migrations=scope['migrations'];overlay=scope['overlay'];test=scope['test']
    need(payload['archive_sync_before.sql'].decode()==pins['functions']['public.archive_sync_config(text,jsonb)']['definition'],
         'fresh_live_guard_differs_from_reviewed_caps_guard')
    payload['baseline_pins.json']=canonical(pins)
    plan={'status':'REVIEWED_MODE_RELEASE_NOT_DEPLOYED','scope':'mode predecessor gates, clear totals and approved temporary tiers; preserve deployed daily quotas/catalog',
        'bundle':BUNDLE,'parent_bundle':PARENT,'archive_baseline':BASELINE,'archive_manifest_sha256':BASELINE_SHA,
        'archive_release':RELEASE,'payment_release':PAYMENT,'sealed_candidate_sha256':SEALED,
        'configuration_sha256':sha(payload['configuration.json']),'configuration_jsonb_sha256':test['registration']['configuration_jsonb_sha256'],
        'new_function_hashes':scope['new_function_hashes'],
        'old_config_rows':pins['config_rows'],'old_ledger':pins['ledger'],'permissions':pins['permissions'],
        'payment_manifest_sha256':pins['payment_manifest_sha256'],'payment_catalog_hash':pins['payment_catalog_hash'],
        'payment_function_hashes':pins['payment_function_hashes'],'mode_migrations':migrations,
        'archive_files':{n:sha(b) for n,b in overlay.items()},'files':{n:sha(b) for n,b in payload.items()},
        'driver_sha256':sha(Path(__file__).read_bytes()),'remote_operator_sha256':sha(payload['operator.py']),
        'upload_operator_sha256':sha(HERE.joinpath('mode_release_upload.py').read_bytes()),
        'rollback_policy':'Restore service pointer only; retain additive mode schema/guard/config/ledger and every earned session/counter. Never restore a DB dump over paid or earned data. Unknown COMMIT outcome leaves archive stopped.',
        'game_hash_activation':'Separate final step after backend verify; this driver changes no local game pointer',
        'no_payment_changes':True,'no_player_updates':True,'preserved_applied_migrations':{name:digest for name,digest in pins['ledger'].items()}}
    payload['plan.json']=canonical(plan);raw=pack(payload);digest=sha(raw)
    folder=OUT/'plans'/digest;folder.mkdir(parents=True,exist_ok=True)
    for name,body in (('mode_release.tar.gz',raw),('plan.json',canonical(plan))):
        path=folder/name;need(not path.exists() or path.read_bytes()==body,'immutable_plan_changed');path.write_bytes(body)
    pointer={'status':plan['status'],'sha256':digest,'tar':str((folder/'mode_release.tar.gz').relative_to(ROOT)),
        'plan':str((folder/'plan.json').relative_to(ROOT)),'bundle':BUNDLE,'remote_executed':False}
    (OUT/'checked_mode_release.json').write_bytes(canonical(pointer))
    return pointer


def checked_plan():
    need((OUT/'checked_mode_release.json').is_file(),'live_preflight_and_plan_required')
    pointer=json.loads((OUT/'checked_mode_release.json').read_bytes())
    source=(ROOT/pointer['tar']).resolve();need(source.is_relative_to(OUT/'plans'),'operator_tar_path_refused')
    raw=source.read_bytes();need(sha(raw)==pointer['sha256'],'operator_payload_changed')
    files=unpack(raw);plan=json.loads(files.pop('plan.json'))
    need(plan['bundle']==BUNDLE and plan['archive_release']==RELEASE and plan['sealed_candidate_sha256']==SEALED,'operator_scope_changed')
    need({n:sha(b) for n,b in files.items()}==plan['files'],'operator_file_manifest_changed')
    need(sha(HERE.joinpath('mode_release_remote.py').read_bytes())==plan['remote_operator_sha256'],'remote_operator_changed_after_review')
    need(sha(Path(__file__).read_bytes())==plan['driver_sha256'],'driver_changed_after_review')
    need(sha(HERE.joinpath('mode_release_upload.py').read_bytes())==plan['upload_operator_sha256'],'upload_operator_changed_after_review')
    return pointer,plan,raw


def transport(source,label):
    spec=importlib.util.spec_from_file_location('mode_checked_ssh',ROOT/'tools/shop_pricing_half_20261017/remote.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.OUT=OUT/'remote'
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            report=module.execute(source,label,timeout=180)
    except SystemExit:
        report=json.loads((module.OUT/(label+'.json')).read_bytes())
        record=(report.get('records') or [{}])[-1]
        code=record.get('error_code','ssh_transport_failure_'+str(report.get('ssh_exit','unknown')))
        raise RuntimeError('remote_'+label+'_refused:'+code) from None
    need(bool(report.get('records')),'remote_'+label+'_refused:missing_remote_record')
    return report['records'][-1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('check','preview','preflight','plan','upload','backup','prepare','validate','activate','verify','rollback'),nargs='?',default='check')
    parser.add_argument('--execute-reviewed-plan',help='Required exact tar SHA for every remote mutation phase')
    args=parser.parse_args()
    if args.mode=='preview':
        print(json.dumps(preview()));return
    if args.mode=='check' and not (OUT/'checked_mode_release.json').exists():
        result=preview(save=False)
        print(json.dumps({key:result[key] for key in ('status','bundle','sealed_candidate_sha256','remote_executed','deployable')}));return
    if args.mode=='preflight':
        try:row=transport(HERE.joinpath('mode_release_preflight.py').read_text('utf-8'),'preflight')
        except RuntimeError as error:
            OUT.mkdir(parents=True,exist_ok=True)
            status='TRANSPORT_UNAVAILABLE' if 'ssh_transport_failure_' in str(error) else 'REFUSED'
            (OUT/'preflight_status.json').write_bytes(canonical({'status':status,'reason':str(error),'remote_writes':0}))
            raise
        OUT.mkdir(parents=True,exist_ok=True);(OUT/'preflight.json').write_bytes(canonical(row))
        (OUT/'preflight_status.json').write_bytes(canonical({'status':'PASS','baseline_sha256':sha(canonical(row)),'remote_writes':0}))
        print(json.dumps({k:row[k] for k in ('status','archive_release','archive_bundle','payment_release','database_writes','remote_files_written')}));return
    if args.mode=='plan':
        print(json.dumps(build_plan()));return
    pointer,plan,raw=checked_plan()
    if args.mode=='check':
        status=json.loads((OUT/'preflight_status.json').read_bytes()) if (OUT/'preflight_status.json').exists() else {'status':'NOT_RECHECKED'}
        print(json.dumps(dict(status='LOCAL_MODE_RELEASE_CHECK_PASS',bundle=BUNDLE,tar_sha256=pointer['sha256'],migrations=[m['id'] for m in plan['mode_migrations']],remote_executed=False,latest_live_preflight=status['status'])));return
    if args.mode!='verify':
        need(args.execute_reviewed_plan==pointer['sha256'],'explicit_reviewed_plan_sha_required')
    if args.mode in ('upload','backup','prepare','validate','activate'):
        latest=json.loads((OUT/'preflight_status.json').read_bytes()) if (OUT/'preflight_status.json').exists() else {}
        need(latest.get('status')=='PASS' and latest.get('baseline_sha256')==plan['files']['baseline_pins.json'],
             'latest_live_preflight_required_or_baseline_drifted')
    stage='/tmp/survival-mode-release-20261020-'+pointer['sha256'][:12]
    source='STAGE='+repr(stage)+'\nMODE='+repr(args.mode)+'\n'
    if args.mode=='upload':
        source+='PAYLOAD='+repr(base64.b64encode(raw).decode())+'\nEXPECTED='+repr(pointer['sha256'])+'\n'
        source+=HERE.joinpath('mode_release_upload.py').read_text('utf-8')
    else:
        source+=HERE.joinpath('mode_release_remote.py').read_text('utf-8')
    print(json.dumps(transport(source,args.mode),ensure_ascii=False))


if __name__=='__main__':
    main()
