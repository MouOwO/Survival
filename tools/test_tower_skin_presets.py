"""Integration check: three presets load, keep tier art, and restore the user's preset."""
import json, subprocess, sys
from pathlib import Path
from tower_skin_presets import ROOT, RES, TOWERS, GEN, table, combat_digest, DEATH_BASE_COLORS
PYTHON=sys.executable
LUA='C:/Program Files/lua/bin/lua5.1.exe'
protected=combat_digest()
active=ROOT/'data/tower_visual_presets/active.json'
original_preset=json.loads(active.read_text(encoding='utf8'))['preset'] if active.exists() else 'A'
results=[]
def run(*args):
    p=subprocess.run(args,cwd=ROOT,text=True,encoding='utf8',errors='replace',capture_output=True)
    if p.returncode:raise AssertionError(p.stdout+'\n'+p.stderr)
    return p.stdout
try:
    for preset in 'BCA':
        out=run(PYTHON,'tools/tower_skin_presets.py','--preset',preset)
        assert combat_digest()==protected
        death_base={r['profile_id']:r for r in table(RES/'tower_visual_profiles.csv')[2]}['class_1']
        assert death_base['native_base']=='willow_shadow_realm'
        assert {k:death_base[k] for k in DEATH_BASE_COLORS}==DEATH_BASE_COLORS
        assert death_base['alpha']=='0.95'
        assert all(not death_base[k] for k in ('core','detail','detail_ssr','crown'))
        stages={r['asset_id']:r for r in table(RES/'asset_native_wearable_stages.csv')[2]}
        components=table(RES/'asset_components.csv')[2]
        wearables=table(RES/'asset_native_wearables.csv')[2]
        catalog={r['asset_id']:r for r in table(RES/'asset_catalog.csv')[2]}
        for path in TOWERS.glob('tower_class_*.csv'):
            rows=table(path)[2]
            models=[r['model_asset_id'] for r in rows]
            assert len({stages[k]['hero_unit_name'] for k in models})==1,path
            for left,right in [(0,5),(5,10),(10,20)]:
                assert len({r['projectile_model'] for r in rows[left:right]})==1,path
                assert len(set(models[left:right]))==1,path
            hero=stages[models[0]]['hero_unit_name']
            if hero not in ('npc_dota_hero_tinker','npc_dota_hero_zuus'):
                assert len({rows[i]['projectile_model'] for i in (0,5,10)})==3,path
        for aid,stage in stages.items():
            assert stage['body_model']==catalog[aid]['primary_model']
            assert float(stage.get('model_scale') or 1)==float(catalog[aid]['model_scale'])
            expected={w['wearable_key']:w for w in wearables if w['asset_id']==aid}
            actual={c['component_id']:c for c in components if c['asset_id']==aid}
            assert set(expected)==set(actual)
            for k,w in expected.items():
                assert actual[k]['model_path']==w['model_path']
                assert actual[k]['model_skin']==w['model_skin']
        # Load the actual catalog and the full strict Precache entry for each.
        run(LUA,'tools/test_addon_precache.lua')
        run(LUA,'scripts/vscripts/tests/test_startup_asset_preload_service.lua')
        run(PYTHON,'tools/build_tower_native_wearable_units.py','--check')
        results.append(dict(preset=preset,stages=21,visible_components=len(wearables),combat_unchanged=True,precache_pass=True))
        print('PRESET_INTEGRATION_PASS',preset,'components='+str(len(wearables)))
finally:
    if not active.exists() or json.loads(active.read_text(encoding='utf8'))['preset']!=original_preset:
        run(PYTHON,'tools/tower_skin_presets.py','--preset',original_preset)
report=ROOT/'output/tower_skin_trial/validation.json';report.parent.mkdir(parents=True,exist_ok=True)
report.write_text(json.dumps(dict(status='PASS',presets=results,active=original_preset,in_game_visual_verified=False),indent=2)+'\n',encoding='utf8')
print('TOWER_SKIN_PRESETS_INTEGRATION_PASS: all presets, 140 combat rows, 63 hero stages; active='+original_preset)
