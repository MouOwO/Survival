"""Build secret-free, scope-checked video-bundle release artifacts, never deploy."""
from pathlib import Path
import hashlib,json,shutil,tarfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/video_shop_20261015/release'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def archive(source,target):
 with tarfile.open(target,'w:gz') as t:
  def normalize(info):
   info.uid=info.gid=0;info.uname=info.gname='root';info.mode=0o755 if info.isdir() else 0o644;return info
  t.add(source,arcname=source.name,filter=normalize)

def main():
 diff=json.loads((OUT/'archive_overlay_diff.json').read_text(encoding='utf8'))
 assert diff['all_other_configs_sources_preserved'] and diff['old_108_commerce_products_exactly_preserved'] and diff['worker_unchanged']
 payment=ROOT/'output/payment_release/20261015-payment01'
 # Existing migration is unrelated to this task and must remain byte-identical.
 shutil.copyfile(ROOT/'output/video_shop_20261015/deployed_baseline/upgrade_vip_recharge.sql',payment/'payment_backend/upgrade_vip_recharge.sql')
 stat=Path('玩家档案系统/player_gameplay_stats.csv')
 shutil.copyfile(OUT/'reference_csv'/stat,payment/'reference_csv'/stat)
 manifest={p.relative_to(payment).as_posix():sha(p) for p in payment.rglob('*') if p.is_file() and p.name!='manifest.json' and '__pycache__' not in p.parts}
 (payment/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
 old=json.loads((ROOT/'output/video_shop_20261015/deployed_baseline/payment_manifest.json').read_text(encoding='utf-8-sig'))
 changed=[p for p in old if manifest.get(p)!=old[p]]
 assert not any('upgrade_vip_recharge.sql' in p for p in changed)
 allowed={'payment_backend/csv_catalog.py','payment_backend/service.py','payment_backend/sync_catalog.py','payment_backend/test_ucoin_catalog.py','payment_backend/test_ucoin_service.py','payment_backend/ucoin_catalog.py','reference_csv/商城兑换系统/commerce_products.csv','reference_csv/玩家档案系统/player_gameplay_stats.csv'}
 assert set(changed)<=allowed,changed
 payment_tar=payment.with_suffix('.tar.gz');archive(payment,payment_tar)
 stage=OUT/'survival-video-bundles-20261015';stage.mkdir(exist_ok=True)
 shutil.copytree(OUT/'archive_bundle_overlay',stage/'archive_bundle_overlay',dirs_exist_ok=True)
 shutil.copyfile(OUT/'archive_bundle_compatibility_function.sql',stage/'archive_bundle_compatibility_function.sql')
 shutil.copyfile(ROOT/'tools/video_shop_20261015/remote_archive_operator.py',stage/'remote_archive_operator.py')
 patch=json.loads((OUT/'archive_compatibility_patch.json').read_text())
 base_manifest=json.loads((ROOT/'output/video_shop_20261015/deployed_baseline/release_manifest.json').read_text())
 inp={'candidate_hash':diff['overlay'],'baseline_manifest_files':base_manifest['files'],'compatibility_sql_file':'archive_bundle_compatibility_function.sql','compatibility_sql_sha256':sha(stage/'archive_bundle_compatibility_function.sql'),'previous_function_sha256':patch['baseline_sha256'],'patched_function_sha256':patch['patched_sha256'],'payment_manifest_sha256':sha(payment/'manifest.json')}
 (stage/'archive_operator_input.json').write_text(json.dumps(inp,indent=2)+'\n',encoding='utf8')
 stage_tar=stage.with_suffix('.tar.gz');archive(stage,stage_tar)
 files=[stage_tar,payment_tar,OUT/'payment_catalog_310_overlay.json']
 report={'prepared':True,'deployed':False,'archive_bundle':diff['overlay'],'catalog_hash':diff['payment_catalog_hash'],'files':[{'path':str(p.relative_to(ROOT)),'sha256':sha(p),'bytes':p.stat().st_size} for p in files],'payment_existing_files_changed':changed,'unrelated_migration_preserved':True,'old_108_commerce_products_exactly_preserved':True,'includes_secrets':False}
 (OUT/'release_artifacts.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps(report,ensure_ascii=True))
if __name__=='__main__':main()
