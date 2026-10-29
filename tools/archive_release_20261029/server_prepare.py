"""Create a new pinned server overlay locally; no network or active pointers."""
from __future__ import annotations
import argparse, ast, difflib, hashlib, json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/release_archive_20261029/server_plan'
TARGET='d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
canonical=lambda value:json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()

def prepare(bundle_directory, destination):
    sys.path.insert(0,str(ROOT/'server'))
    from archive_backend.bundle import Bundle
    from fishing_api_overrides.archive_challenge_postgres import patch_postgres
    baseline=json.loads((OUT/'live_audit.json').read_bytes())
    bundle=Bundle(bundle_directory)
    if bundle.hash!=TARGET: raise ValueError('target_bundle_changed')
    data=json.loads((bundle.directory/'bundle.json').read_bytes())
    missing={r['field_id'] for r in data['configs']['player_gameplay_stats']['rows']}-set(baseline['gameplay_stat_columns'])
    if missing: raise ValueError('database_stat_columns_missing')
    if destination.exists(): raise ValueError('candidate_already_exists')
    overlay={}
    diff=[]
    for path in sorted((ROOT/'server/archive_backend').glob('*.py')):
        name='backend/archive_backend/'+path.name
        raw=path.read_bytes().replace(b'\r\n',b'\n');ast.parse(raw)
        previous=OUT/'baseline'/name
        old=previous.read_bytes().replace(b'\r\n',b'\n') if previous.exists() else b''
        if raw!=old:
            overlay[name]=raw
            diff.extend(difflib.unified_diff(old.decode().splitlines(True),raw.decode().splitlines(True),fromfile='online/'+name,tofile='candidate/'+name))
    name='backend/fishing_api/postgres.py'
    original=(OUT/'baseline'/name).read_text(encoding='utf-8')
    updated=patch_postgres(original)
    before='valid = value in ("pure", "standard", "rich", "cold", "scourge")'
    after='valid = value in ("pure", "standard", "rich", "cold", "scourge", "ruins", "celestial")'
    if updated.count(before)!=1: raise ValueError('mode_converter_anchor_changed')
    updated=updated.replace(before,after,1);ast.parse(updated)
    overlay[name]=updated.encode()
    diff.extend(difflib.unified_diff(original.splitlines(True),updated.splitlines(True),fromfile='online/'+name,tofile='candidate/'+name))
    for path in bundle.directory.rglob('*'):
        if path.is_file():
            if path.is_symlink(): raise ValueError('bundle_symlink')
            overlay['addon/server/bundles/'+bundle.hash+'/'+path.relative_to(bundle.directory).as_posix()]=path.read_bytes()
    for relative,digest in data['csv_hashes'].items():
        raw=(ROOT/relative).read_bytes().replace(b'\r\n',b'\n')
        if sha(raw)!=digest: raise ValueError('candidate_csv_drift')
        overlay['addon/'+relative]=raw
    for name in ('star_blessing_reward_definitions','fishing_system_rules','player_gameplay_stats'):
        relative='data/csv/玩家档案系统/'+name+'.csv'
        overlay['addon/'+relative]=(ROOT/relative).read_bytes().replace(b'\r\n',b'\n')
    overlay['addon/server/bundles/current.json']=canonical(dict(hash=bundle.hash,protocol=1))
    migrations=[]
    for source,wrapped in (
        ('server/aliyun/database/target/202610220001_human_spec_mode_admission.sql',True),
        ('server/aliyun/database/target/202610290001_archive_challenge_receipts.sql',True),
        ('server/aliyun/database/harden_archive_challenge_receipts.sql',False)):
        path='deploy/database/'+('target/' if '/target/' in source else '')+Path(source).name
        identity=('target/' if '/target/' in source else 'security/')+Path(source).name
        if identity in baseline['ledger']: raise ValueError('new_migration_already_applied')
        raw=(ROOT/source).read_bytes().replace(b'\r\n',b'\n');overlay[path]=raw
        migrations.append(dict(id=identity,path=path,sha256=sha(raw),transaction_wrapper=wrapped))
    # Keep the exactly exercised real-SQL receipt probe in the sealed payload.
    overlay['validation/archive_challenge_receipts_database.sql']=(ROOT/'server/tests/archive_challenge_receipts_database.sql').read_bytes().replace(b'\r\n',b'\n')
    overlay['validation/runtime_probe.py']=(Path(__file__).with_name('server_runtime_probe.py')).read_bytes().replace(b'\r\n',b'\n')
    safe=dict(overlay)
    for name in list(safe):
        if name.startswith(('backend/archive_backend/','addon/data/csv/')):
            safe.pop(name)
    safe['addon/server/bundles/current.json']=canonical(dict(hash=baseline['bundle'],protocol=1))
    # Safe copies parent archive Python/CSV, retaining only the new transport
    # allowlist/mode enum so the committed DB's extra RPC does not fail ready.
    plan=dict(format=1,operator_revision=2,archive_release=baseline['release'],archive_manifest_sha256=baseline['manifest_sha256'],
        archive_bundle=baseline['bundle'],bundle=bundle.hash,new_release='20261029-archive-'+bundle.hash[:12],
        rollback_release='20261029-archive-'+bundle.hash[:12]+'-safe',payment_release=baseline['payment_release'],
        payment_manifest_sha256=baseline['payment_manifest_sha256'],payment_pid=baseline['services']['goufayu-payment.service']['MainPID'],
        ledger=baseline['ledger'],functions=baseline['functions'],configs=baseline['configs'],app_rpcs=baseline['app_rpcs'],
        all_backend_hashes=baseline['backend_source_hashes'],migrations=migrations,
        overlay={name:sha(raw) for name,raw in overlay.items()},safe_overlay={name:sha(raw) for name,raw in safe.items()},
        source_baseline_time=baseline['time_utc'],requires_old_games_restarted=True,
        compatibility_alias_added=False,stat_columns_added=False,payment_changed=False)
    destination.mkdir(parents=True)
    for folder,files in (('overlay',overlay),('safe_overlay',safe)):
        for name,raw in files.items():
            target=destination/folder/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
    (destination/'plan.json').write_bytes(canonical(plan))
    (destination/'source_diff.patch').write_text(''.join(diff),encoding='utf-8')
    parent=json.loads((OUT/'parent_bundle.json').read_bytes())
    changes={name:dict(before_rows=len(parent['configs'].get(name,{}).get('rows',[])),after_rows=len(config.get('rows',[])))
             for name,config in data['configs'].items() if parent['configs'].get(name)!=config}
    (destination/'config_diff.json').write_bytes(canonical(changes))
    return dict(ok=True,phase='LOCAL_CANDIDATE_PREPARED_NOT_UPLOADED',release=plan['new_release'],bundle=bundle.hash,
        overlay_files=len(overlay),changed_config_tables=changes,new_migrations=len(migrations),payment_changed=False)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle',type=Path,default=ROOT/'output/archive_layout_20261029/bundle_candidate'/TARGET)
    parser.add_argument('--output',type=Path,default=OUT/'candidate')
    args=parser.parse_args()
    try: print(json.dumps(prepare(args.bundle,args.output),ensure_ascii=False))
    except Exception as error:
        print(json.dumps(dict(ok=False,error=str(error) if type(error) is ValueError else 'server_prepare_failed')))
        raise SystemExit(1)
