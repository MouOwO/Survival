"""Audit the compiled island resources, source dimensions and assembly contract."""
import json,re,subprocess,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/main_island'
assets=json.loads((OUT/'asset_manifest.json').read_text(encoding='utf-8'))
layout=json.loads((OUT/'island_layout.json').read_text(encoding='utf-8'))
materials=json.loads((OUT/'material_manifest.json').read_text(encoding='utf-8'))
def dump(p):return subprocess.check_output([str(ROOT.parents[1]/'bin/win64/resourceinfo.exe'),'-i',str(ROOT/p),'-all']).decode('utf-8',errors='replace')
checks=[]
for a in assets:
    text=dump('models/main_island/'+a['name']+'.vmdl_c')
    actual=[[float(x)for x in re.search(r'm_v'+b+r'Bounds = \[ ([^\]]+) \]',text)[1].split(',')]for b in ['Min','Max']]
    error=max(abs(x-y)for u,v in zip(actual,a['bounds'])for x,y in zip(u,v))
    assert error<.05,(a['name'],'wrong scale/orientation',error)
    assert ('--- vmdl block PHYS' in text)==bool(a['collision_hulls']),a['name']
    for m in a['materials']:assert m in text,(a['name'],m)
    checks.append(dict(name=a['name'],bounds_error=error,collision_hulls=a['collision_hulls'],triangles=a['triangles']))
for m in materials:
    text=dump('materials/main_island/'+m['name']+'.vmat_c')
    assert 'F_NORMAL_MAP = 1' in text and m['name']+'_normal' in text,m['name']
    assert m['name']+'_reflectance' in text,m['name']
    assert 'F_SELF_ILLUM = 1' not in text and 'F_FULLBRIGHT = 1' not in text
assert 'dota.nav.walkable = 1.0' in dump('materials/main_island/floor_support.vmat_c')
assert 'mapbuilder.nodraw = 1.0' in dump('materials/main_island/floor_support.vmat_c')
water=dump('materials/main_island/ocean_surface.vmat_c')
assert 'F_SCROLL_WAVES = 1' in water and 'mapbuilder.nonsolid = 1.0' in water
assert 'materials/main_island/water_color' in water
models={a['name']:a for a in assets}
for p in layout['placements']:
    assert p['native'] or p['name'] in models
    assert all(s>0 for s in p['scale'])
assert len(layout['markers'])==12 and layout['stair_width']==576
for q in range(4):
    placed=[p for p in layout['placements']if p['quadrant']==q]
    assert len([p for p in placed if p['name']=='m01_player_platform'])==1
    assert len([p for p in placed if p['name']=='m03_stair_treads'])==1
    assert len([p for p in placed if p['name'].startswith('m14_flag_')])==2
    # Keep the central building rectangle of each platform free of decoration.
    for p in placed:
        if p['group']!='05 Edge planting':continue
        x,y=p['origin'][:2];a=-q*math.pi/2
        u=x*math.cos(a)-y*math.sin(a);v=x*math.sin(a)+y*math.cos(a)
        assert not(abs(u)<900 and 3000<v<4250),(p['name'],'obstructs building area')
maptext=(OUT/'source/maps/main_island_review.vmap').read_text(encoding='utf-8')
prefab=(OUT/'source/maps/prefabs/main_island.vmap').read_text(encoding='utf-8')
assert maptext.count('"classname" "string" "prop_static"')==len(layout['placements'])
assert 'env_global_light' not in prefab and 'info_player_start' not in prefab
from asset_validation import verify_map_vpk
verify_map_vpk(ROOT/'maps/main_island_review.vpk')
report=dict(status='PASS',models=len(assets),material_sets=len(materials),instances=len(layout['placements']),custom_instance_triangles=sum(models[p['name']]['triangles']for p in layout['placements']if not p['native']),compiled_assets=checks,markers=12,main_map_modified=False,runtime_report='runtime_verification.json')
(OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('MAIN_ISLAND_VERIFY_PASS',len(assets),len(materials),report['custom_instance_triangles'])
