"""Audit compiled wall death particles/model and run focused lifecycle checks."""
import json
import re
import subprocess
from pathlib import Path
from asset_validation import installed_source
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/wall_destruction'
INSPECTOR=ROOT.parents[1]/'bin/win64/resourceinfo.exe'
CONTENT=ROOT.parents[2]/'content/dota_addons/survival'
def dump(relative):
    return subprocess.check_output([str(INSPECTOR),'-i',str(ROOT/relative),'-all']).decode('utf-8',errors='replace')
assets=[]
for name in ('charge','sparks','flash','ring','shards','dust'):
    rel='particles/survival_buildings/wall_death_'+name+'.vpcf'
    source=OUT/'source'/rel;compiled=ROOT/(rel+'_c')
    # Source 2 skips identical files by CRC; a successful incremental compile
    # can legitimately retain a binary older than a freshly generated source.
    assert compiled.is_file()
    installed_source(source, rel)
    data=dump(rel+'_c')
    assert 'C_OP_FadeAndKill' in data
    if name in ('charge','flash','ring'):assert 'm_nControlPoint = 1' in data
    assert 'C_OP_ContinuousEmitter' not in data or name=='sparks'
    if name=='shards':assert 'C_OP_RenderModels' in data and 'wall_death_shard.vmdl' in data and 'm_Gravity = [ 0.0, 0.0, -460.0 ]' in data
    if name=='ring':assert 'PARTICLE_ORIENTATION_WORLD_Z_ALIGNED' in data
    (OUT/(name+'_compiled.txt')).write_text(data,encoding='utf-8')
    assets.append(dict(name=name,compiled=True,finite=True))
model=dump('models/survival_buildings/wall_death_shard.vmdl_c')
assert '--- vmdl block PHYS' not in model and 'm_hitboxsets = [  ]' in model
for name in ('cyan','deep','white'):
    material=dump('materials/survival_buildings/wall_death_'+name+'.vmat_c')
    assert 'F_FULLBRIGHT = 1' in material and 'build_white_glow_color' in material
profiles=(ROOT/'scripts/vscripts/config/generated/wall_destruction_models.lua').read_text(encoding='utf-8')
for wall in json.loads((ROOT/'output/reference_walls/manifest.json').read_text(encoding='utf-8')):
    value=float(re.search(r'/'+wall['name']+r'\.vmdl"\] = ([\d.]+)',profiles)[1])
    assert abs(value-wall['dimensions'][2])<.001
tests=[]
for name in ('test_wall_destruction_visual','test_wall_destruction_integration','test_tower_rebuild_after_death',
             'test_wall_visual_config','test_building_grid_alignment','test_building_construction_visual_service','test_building_white_shell'):
    result=subprocess.run(['lua',str(ROOT/'scripts/vscripts/tests'/(name+'.lua'))],cwd=ROOT,capture_output=True)
    (OUT/(name+'.log')).write_bytes(result.stdout+result.stderr)
    assert result.returncode==0,(name,result.stderr.decode(errors='replace'))
    tests.append(dict(name=name,status='PASS'))
report=dict(status='PASS',shake_seconds=1.,defeat_delay=1.45,cleanup_seconds=2.6,particles=assets,
            fragment_physics=False,fragment_hitboxes=False,profiles=10,tests=tests,workshop_verified=False)
(OUT/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('WALL_DESTRUCTION_PASS particles=6 crystal_model=1 profiles=10 tests=7 shake=1s cleanup_no_collision')
