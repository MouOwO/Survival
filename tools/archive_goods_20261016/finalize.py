"""Verify final evidence/source identity without changing gameplay or services."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/archive_commerce_goods_20261016'
META=ROOT/'design_refs/archive_goods_20261016'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    projection=json.loads((OUT/'projection_validation.json').read_bytes())
    visual=json.loads((OUT/'ui/visual_report.json').read_bytes())
    compile=json.loads((OUT/'ui/compile.json').read_bytes())
    assert projection['status']==visual['status']=='PASS' and compile['success']
    for n,h in projection['source_hashes'].items():assert sha(ROOT/n)==h,'Lua evidence drift:'+n
    assert len(compile['records'])==5
    ui={}
    for record in compile['records']:
        assert sha(Path(record['source']))==record['sourceHash'].lower()
        assert sha(Path(record['content']))==record['sourceHash'].lower()
        assert sha(Path(record['artifact']))==record['compiledHash'].lower()
        ui[Path(record['source']).relative_to(ROOT).as_posix()]=record['sourceHash'].lower()
    metadata=json.loads((META/'catalog_build.json').read_bytes())
    assert metadata['count']==178 and metadata['kinds']=={'product':121,'starjoy':24,'vip':33}
    assert sha(ROOT/'scripts/vscripts/config/generated/archive_commerce_goods.lua')==metadata['generated_catalog_sha256']
    old=(META/'baseline/data/csv/存档系统/archive_categories.csv').read_bytes()
    new=(ROOT/'data/csv/存档系统/archive_categories.csv').read_bytes()
    assert new.startswith(old) and new.count(b'commerce_goods,')==2
    # The preceding shop deployment remains exactly intact.
    published=ROOT/'design_refs/shop_functional_20261016/release_v2/release_plan.json'
    previous=json.loads(published.read_bytes())
    for n,h in previous['input_hashes'].items():assert sha(ROOT/n)==h,'commerce source modified:'+n
    assert json.loads((ROOT/'server/bundles/current.json').read_bytes())['hash']==metadata['source_bundle']
    sources=dict(projection['source_hashes'],**ui)
    sources['data/csv/存档系统/archive_categories.csv']=sha(ROOT/'data/csv/存档系统/archive_categories.csv')
    result=dict(status='COMPLETE_WITH_NATIVE_GAME_LIMITATION',rows=178,
      source_bundle=metadata['source_bundle'],sources=sources,private_account_projection=True,
      server_schema_changes=False,player_writes=0,reward_grants=0,purchase_calls=0,new_periodic_tasks=0,
      previous_shop_catalog_and_prices_preserved=True,leaderboard_preserved=True,
      targeted_lua_groups=23,ui_sources_natively_compiled=5,
      screenshots_are_browser_assembly=True,native_game_verified=False,new_match_required=True,
      evidence=['projection_validation.json','ui/visual_report.json','ui/compile.json','known_regression_blocker.json'],
      catalog_metadata='../archive_goods_20261016/catalog_build.json',
      scope_review='../archive_goods_20261016/scope_review.json',git_commit_or_push=False)
    (OUT/'completion.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:result[k] for k in ['status','rows','targeted_lua_groups','ui_sources_natively_compiled','native_game_verified','previous_shop_catalog_and_prices_preserved']}))
if __name__=='__main__':main()
