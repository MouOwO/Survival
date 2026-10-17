"""Build a narrow overlay on the running archive service; no activation."""
from pathlib import Path
import hashlib,importlib.util,io,json,shutil,tarfile,ast
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/endless_leaderboard_20261016/release'
DEPLOY=ROOT/'design_refs/endless_leaderboard_20261016/deployment/rebase_v2'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def main():
    preflight=json.loads((DEPLOY/'preflight.json').read_bytes());meta=preflight['metadata'];base=DEPLOY/'online_baseline'
    assert meta['archive_release']=='/opt/goufayu/releases/20261016-endless-titles-v1'
    assert meta['bundle']=='60d6ce00a7d3257b6982492fdfdf68aa8deacdb4d46f837248ecfbef5ebdec94'
    assert sha((base/'release_manifest.json').read_bytes())==meta['archive_manifest_sha256']
    assert len(preflight['tables'])==28
    # Preserve the complete concurrent title/rarity release, including every
    # original commerce product, reward, source and historical sibling bundle.
    old_bundle=json.loads((ROOT/'server/bundles/eb49cbe03cd338757949a3d7449457005d9e79ddd0f51b9ec1d8becc9e66a261/bundle.json').read_bytes())
    current_raw=(base/'addon/server/bundles'/meta['bundle']/'bundle.json').read_bytes()
    assert sha(current_raw)==meta['bundle']
    current_bundle=json.loads(current_raw)
    for table in ['commerce_catalog','commerce_products','commerce_rewards','commerce_bundle_members','commerce_import_status']:
        assert current_bundle['configs'][table]==old_bundle['configs'][table],'concurrent_commerce_changed:'+table
    patcher=load('leaderboard_http_patcher',ROOT/'tools/patch_endless_leaderboard_handler.py')
    dbpatch=load('leaderboard_postgres_patcher',Path(__file__).with_name('patch_postgres.py'))
    old_service=(base/'backend/archive_backend/service.py').read_text('utf-8')
    old_handler=(base/'backend/fishing_api/server.py').read_text('utf-8')
    old_postgres=(base/'backend/fishing_api/postgres.py').read_text('utf-8')
    new_service=patcher.patch_archive_install(old_service);new_handler=patcher.patch_handler(old_handler)
    new_postgres=dbpatch.patch_postgres(old_postgres)
    hook='    from .endless_leaderboard import install as install_endless_leaderboard\n    install_endless_leaderboard(service)\n'
    assert new_service.replace(hook,'',1)==old_service
    start=new_handler.index('                elif self.path == "/v1/archive/endless-leaderboard":')
    end=new_handler.index('                elif self.path == "/v1/archive/command":',start)
    assert new_handler[:start]+new_handler[end:]==old_handler
    assert dbpatch.restore_postgres(new_postgres)==old_postgres
    payload=OUT/'payload';overlay=payload/'overlay';rollback=payload/'rollback_overlay'
    products={
      'backend/archive_backend/service.py':new_service.encode(),
      'backend/fishing_api/server.py':new_handler.encode(),
      'backend/fishing_api/postgres.py':new_postgres.encode(),
      'backend/archive_backend/endless_leaderboard.py':(ROOT/'server/archive_backend/endless_leaderboard.py').read_bytes(),
    }
    for name,raw in products.items():
        ast.parse(raw);dest=overlay/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
    target=rollback/'backend/fishing_api/postgres.py';target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(new_postgres.encode())
    migration=(ROOT/'server/migrations/202610160001_endless_leaderboard.sql').read_text('utf-8')
    assert migration.count('\nBEGIN;\n')==1 and migration.rstrip().endswith('\nCOMMIT;')
    body=migration.replace('\nBEGIN;\n','\n',1).rstrip()[:-len('COMMIT;')].rstrip()+'\n'
    (payload/'migration_body.sql').write_text(body,encoding='utf-8')
    shutil.copyfile(ROOT/'server/tests/test_endless_leaderboard_database.py',payload/'test_database.py')
    expected={'overlay/'+name for name in products}|{'rollback_overlay/backend/fishing_api/postgres.py','migration_body.sql','test_database.py'}
    files={p.relative_to(payload).as_posix():sha(p.read_bytes()) for p in payload.rglob('*') if p.is_file()}
    assert set(files)==expected
    package=OUT/'overlay.tar.gz';OUT.mkdir(parents=True,exist_ok=True)
    with tarfile.open(package,'w:gz') as tar:
        for name in sorted(files):
            raw=(payload/name).read_bytes();info=tarfile.TarInfo(name);info.size=len(raw);info.mode=0o600;info.mtime=0;tar.addfile(info,io.BytesIO(raw))
    report={
      'version':1,'kind':'endless_leaderboard_readonly','old_release':meta['archive_release'],
      'target_release':'/opt/goufayu/releases/20261016-endless-leaderboard-v1',
      'rollback_release':'/opt/goufayu/releases/20261016-endless-leaderboard-rollback-v1',
      'old_manifest':meta['archive_manifest_sha256'],'bundle':meta['bundle'],
      'payment_release':meta['payment_release'],'payment_manifest':meta['payment_manifest_sha256'],
      'payment_catalog_hash':meta['catalog_hash'],
      'old_sync_function':sha(preflight['function_definitions']['public.archive_sync_config(text,jsonb)'].encode()),
      'old_apply_function':sha(preflight['function_definitions']['payments.apply_effects(text,jsonb,boolean)'].encode()),
      'tar_sha256':sha(package.read_bytes()),'files':files,
      'target_files':{name:sha(raw) for name,raw in products.items()},
      'rollback_files':{'backend/fishing_api/postgres.py':sha(new_postgres.encode())},
      'old_business_tables':28,'new_business_tables':29,'old_bundle_and_cash_catalog_unchanged':True,
      'reverse_patches_verified':True,'requires_archive_service_stop':True,
      'migration_source_sha256':sha(migration.encode()),'legacy_scores_retained_when_identity_unknown':True,
      'status':'READY_FOR_BACKED_UP_SERVER_VALIDATION',
    }
    (OUT/'release_plan.json').write_bytes(canonical(report))
    print(json.dumps({k:report[k] for k in ['status','old_release','target_release','bundle','tar_sha256','reverse_patches_verified','old_bundle_and_cash_catalog_unchanged']}))
    print(json.dumps({'payload_files':len(files),'bytes':package.stat().st_size,'remote_mutations':0}))
if __name__=='__main__':main()
