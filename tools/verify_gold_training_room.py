"""Verify actual Source 2 resources and the assembled prefab's spatial contract."""
import json,re,subprocess
from pathlib import Path
from asset_validation import installed_source
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/gold_training_room'
INSPECTOR=ROOT.parents[1]/'bin/win64/resourceinfo.exe'
assets=json.loads((OUT/'asset_manifest.json').read_text(encoding='utf-8'))
layout=json.loads((OUT/'room_layout.json').read_text(encoding='utf-8'))
materials=json.loads((OUT/'material_manifest.json').read_text(encoding='utf-8'))
checks=[]
def dump(path):return subprocess.check_output([str(INSPECTOR),'-i',str(ROOT/path),'-all']).decode('utf-8',errors='replace')
for a in assets:
    p='models/gold_training_room/'+a['name']+'.vmdl_c';text=dump(p)
    mins=[float(x)for x in re.search(r'm_vMinBounds = \[ ([^\]]+) \]',text)[1].split(',')]
    maxs=[float(x)for x in re.search(r'm_vMaxBounds = \[ ([^\]]+) \]',text)[1].split(',')]
    error=max(abs(x-y)for row,expected in zip([mins,maxs],a['bounds'])for x,y in zip(row,expected))
    assert error<.04,(a['name'],'render orientation or scale mismatch',error)
    physics='--- vmdl block PHYS' in text
    assert physics==(a['collision_hulls']>0),(a['name'],'wrong collision')
    for mat in a['materials']:assert mat in text,(a['name'],'missing material',mat)
    assert a['triangles']>0 and not a['emissive']
    checks.append(dict(name=a['name'],bounds_error=error,physics=physics,triangles=a['triangles']))
for m in materials:
    text=dump('materials/gold_training_room/'+m['name']+'.vmat_c')
    assert 'F_NORMAL_MAP = 1' in text and m['name']+'_normal' in text,m['name']
    assert m['name']+'_reflectance' in text,m['name']
    assert 'F_FULLBRIGHT = 1' not in text and 'F_SELF_ILLUM = 1' not in text
    assert m['normal_std']>.0001 and m['color_std']>.005
    if m.get('revision')=='gold_surface_response_v2':
        # Check the compiled values, not just the source flags. These parameters
        # must survive the shader compiler; roughness is Blender-only here.
        for parameter,expected in [('g_flSpecularIntensity',m['specular_intensity']),('g_flBumpStrength',m['bump_strength']),('g_flSpecularBloom',0)]:
            value=re.search(r'm_name = "'+parameter+r'"\s+m_flValue = ([\d.eE+-]+)',text)
            assert value and abs(float(value[1])-expected)<.001,(m['name'],parameter,'compiled value missing/wrong')
        assert 'm_name = "g_tSpecular"' in text
        for suffix in ('.vmat','_color.png','_normal.png','_reflectance.png','_roughness.png','_metallic.png'):
            rel='materials/gold_training_room/'+m['name']+suffix
            installed_source(OUT/'source'/rel,rel)
        if m['name'] in ('gold','bronze'):
            assert m['reflectance_mean']>.35 and m['reflectance_std']>.15,'metal needs polished/tarnished contrast'
        if m['name'] in ('stone','stone_light','stone_cool','rock'):
            assert m['normal_std']>.05 and m['reflectance_std']>.02,'stone relief/specular variation missing'
support=dump('materials/gold_training_room/floor_support.vmat_c')
assert 'dota.nav.walkable = 1.0' in support,'custom room floor must participate in Dota navigation'
models={a['name']:a for a in assets}
for p in layout['placements']:
    if not p['native']:assert p['name'] in models
    if p['group']=='04 Edge planting':
        assert abs(p['origin'][0])>850 or abs(p['origin'][1])>970,'plant obstructs battle center'
markers={m['name']:m for m in layout['markers']}
assert len(markers)==10 and markers['challenge_02_entry']['origin'][1]>900
for i in range(1,9):
    x,y,z=markers[f'challenge_02_spawn_{i:02}']['origin'];assert abs(x)<500 and abs(y)<600 and z>0
maptext=(OUT/'source/maps/gold_training_room_review.vmap').read_text(encoding='utf-8')
prefab=(OUT/'source/maps/prefabs/gold_training_room.vmap').read_text(encoding='utf-8')
assert 'info_particle_system' not in maptext and 'env_global_light' not in prefab
assert maptext.count('"classname" "string" "prop_static"')==len(layout['placements'])
assert '"gridWidth" "int" "16"' in maptext
from asset_validation import verify_map_vpk
verify_map_vpk(ROOT/'maps/gold_training_room_review.vpk')
report=dict(status='PASS',custom_modules=len(assets),native_models=layout['native_models'],material_sets=len(materials),walkable_support_variant=True,instances=len(layout['placements']),emission=False,
    source2_bounds_and_dependencies=checks,compiled_map='gold_training_room_review.vpk',markers=len(markers),main_map_modified=False,runtime_verified=False)
(OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('GOLD_ROOM_VERIFY_PASS',len(assets),'models',len(materials),'materials',len(layout['placements']),'placements')
