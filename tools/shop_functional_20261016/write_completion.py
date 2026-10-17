"""Collect reviewable source hashes and completed validation evidence."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/shop_functional_20261016'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    verified=json.loads((OUT/'deployment_v2/verify.json').read_bytes())
    installed=json.loads((OUT/'release_v2/local_installation.json').read_bytes())
    assert verified['status']=='VERIFIED' and installed['bundle']==verified['archive_bundle']
    assert json.loads((ROOT/'server/bundles/current.json').read_bytes())['hash']==verified['archive_bundle']
    tabs=json.loads((OUT/'ui/tabs_validation.json').read_bytes())
    p147=json.loads((OUT/'p147/validation.json').read_bytes())
    worker=json.loads((OUT/'release/worker_smoke.json').read_bytes())
    assert tabs['status']==p147['status']==worker['status']=='PASS'
    assert p147['syntax_files']==7 and worker['baseline_prices_compared']==125
    for name,digest in p147['sources'].items():assert sha(ROOT/name)==digest,'gameplay_validation_source_drift:'+name
    visual=json.loads((OUT/'ui/functional/visual_checks.json').read_bytes())
    assert visual['status']=='PASS'
    for item in visual['sourceGraph']:
        assert sha(ROOT/'panorama/src'/item['path'])==item['sha256'],'preview_validation_source_drift:'+item['path']
    sources=[
      'data/csv/商城兑换系统/commerce_products.csv','data/csv/商城兑换系统/commerce_rewards.csv',
      'data/csv/商城兑换系统/commerce_bundle_members.csv','data/csv/商城兑换系统/commerce_import_status.csv',
      'data/ui/shop_catalog_presentation_20261016.json',
      'panorama/src/scripts/custom_game/black_lion_market.js','panorama/src/styles/custom_game/black_lion_market.css',
      'panorama/src/scripts/custom_game/black_lion_market_model.js',
      'panorama/src/scripts/custom_game/video_shop_bundles.js','panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js',
      'panorama/src/scripts/custom_game/common/commerce_components.js',
      'scripts/vscripts/systems/building_system.lua','scripts/vscripts/systems/building_upgrade_process.lua',
      'scripts/vscripts/systems/commerce_service.lua','scripts/vscripts/systems/commerce_titan_aura_service.lua',
      'scripts/vscripts/systems/commerce_titan_aura_values.lua','scripts/vscripts/modifiers/modifier_commerce_titan_aura.lua',
      'scripts/vscripts/combat/damage_filter_service.lua','scripts/vscripts/ui/ui_request_router.lua',
      'scripts/vscripts/ui/combat_stats_ui_service.lua','scripts/vscripts/systems/commerce_hero_privileges.lua',
      'scripts/vscripts/systems/hero_combat_stat_service.lua','scripts/vscripts/systems/hero_skill_choice_service.lua',
      'scripts/vscripts/systems/blademaster_exclusive_service.lua','scripts/vscripts/systems/monkey_king_exclusive_service.lua',
      'scripts/vscripts/combat/hero_display_bonus.lua','scripts/vscripts/config/generated/archive_http_bundle.lua',
      'server/bundles/current.json']
    # Metadata is a scoped diff against the already dirty initial files, never
    # a claim that all current git differences belong to this task.
    report={'status':'COMPLETE_WITH_GAMEPLAY_NATIVE_LIMITATION','archive_bundle':verified['archive_bundle'],
      'cash_catalog':verified['payment_catalog_hash'],'server':verified,'sources':{n:sha(ROOT/n) for n in sources},
      'new_products':['video_p016','video_p028','video_p079','video_p147'],'enabled_bundle':'video_bundle_b003',
      'old_prices_preserved':True,'old_player_data_and_orders_preserved':True,'no_real_orders_created':True,
      'tests':{'tabs':'ui/tabs_validation.json','p147':'p147/validation.json','worker':'release/worker_smoke.json',
       'postgres_rollback':'deployment_v2/validate.json','deployed_server':'deployment_v2/verify.json',
       'local_installation':'release_v2/local_installation.json','ui_functional':'ui/functional/visual_checks.json'},
      'native_game_screenshots':[p.relative_to(OUT).as_posix() for p in (OUT/'ui').glob('*native*.png')],
      'assembled_preview_screenshots':[p.relative_to(OUT).as_posix() for p in (OUT/'ui/functional').glob('*.png')],
      'native_gameplay_verified':False,'native_gameplay_blocker':'Existing console29000 fails history/ready handshake; old match retains old Lua. No live ownership injection.',
      'new_match_required':True,'remaining_product_audit':'audit/functional_audit.md',
      'recovery':'README.md','git_commit_or_push_performed':False,'preexisting_worktree_changes_retained':True}
    assert report['native_game_screenshots'] and report['assembled_preview_screenshots']
    (OUT/'completion.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'status':report['status'],'source_files':len(sources),'native_screenshots':len(report['native_game_screenshots']),
      'preview_screenshots':len(report['assembled_preview_screenshots']),'server_verified':True,'native_gameplay_verified':False}))
if __name__=='__main__':main()
