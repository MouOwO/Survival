"""Audit actual compiled wall meshes, physics, textures and the CSV migration."""
import csv
import io
import json
import re
import subprocess
from pathlib import Path
from wall_asset_spec import name_for, model_for, mesh_for, HEIGHT_MULTIPLIER, WEATHERING
from asset_validation import installed_source

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/reference_walls'
INSPECTOR=ROOT.parents[1]/'bin/win64/resourceinfo.exe'

def dump(relative):
    return subprocess.check_output([str(INSPECTOR),'-i',str(ROOT/relative),'-all']).decode('utf-8',errors='replace')

def bounds(text):
    return [[float(x) for x in re.search(field+r' = \[([^\]]+)\]',text)[1].split(',')]
            for field in ('m_vMinBounds','m_vMaxBounds')]

def rows(text):
    values=list(csv.DictReader(io.StringIO(text)));key=next(iter(values[0]))
    return {v[key]:v for v in values if v[key] and not v[key].startswith('#')}

manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
original={a['name']:a for a in json.loads((OUT/'before_height_weathering/manifest.json').read_text(encoding='utf-8'))}
assert len(manifest)==10
assets=[]
for entry in manifest:
    name=entry['name'];relative='models/survival_buildings/'+name
    source=OUT/'source'/relative
    assert entry['footprint']==[4,4] and entry['runtime_scale']==1 and entry['baked_yaw_degrees']==0
    assert entry['revision']==2 and entry['height_multiplier']==HEIGHT_MULTIPLIER
    assert entry['weathering']==WEATHERING[entry['stage']-1]
    normal=dump(relative+'.vmdl_c');flow=dump(relative+'_white_shell.vmdl_c')
    (OUT/(name+'_compiled.txt')).write_text(normal,encoding='utf-8')
    (OUT/(name+'_flow_compiled.txt')).write_text(flow,encoding='utf-8')
    for suffix,fbx in [('', '.fbx'),('_white_shell','_flow.fbx')]:
        compiled=ROOT/(relative+suffix+'.vmdl_c')
        installed_source(Path(str(source)+fbx), relative+fbx)
        installed_source(Path(str(source)+suffix+'.vmdl'), relative+suffix+'.vmdl')
    for key in ('m_boneName = "root"','m_sBoneName = "root"','m_name = "select_low"','m_name = "select_high"','--- vmdl block PHYS'):
        assert key in normal,(name,key)
    nb,fb=bounds(normal),bounds(flow)
    assert all(abs(a-b)<.01 for sa,sb in zip(nb,fb) for a,b in zip(sa,sb)),(name,'flow mesh differs')
    assert max(nb[1][i]-nb[0][i] for i in (0,1))<=248.02,(name,nb)
    assert abs(nb[0][2])<.01,(name,'floating mesh')
    assert abs((nb[1][2]-nb[0][2])-original[name]['dimensions'][2]*HEIGHT_MULTIPLIER)<.01,(name,'height must be exactly 2.5 times original')
    assert abs(entry['collision_height']-original[name]['collision_height']*HEIGHT_MULTIPLIER)<.01
    hitboxes=normal.split('m_hitboxsets =',1)[1].split('m_attachments',1)[0]
    for label,expected in [('default',entry['dimensions'][2]),('select_low',min(entry['dimensions'][2],125*HEIGHT_MULTIPLIER)),('select_high',entry['dimensions'][2])]:
        hitbox=hitboxes.split('m_name = "'+label+'"',1)[1]
        assert abs(bounds(hitbox)[1][2]-expected)<.01,(name,label,'selection height')
    phys=normal.split('--- vmdl block PHYS',1)[1].split('--- vmdl block',1)[0]
    pb=bounds(phys)
    assert all(abs(pb[0][i]+122)<.01 and abs(pb[1][i]-122)<.01 for i in (0,1)),(name,pb)
    assert abs(pb[0][2])<.01 and abs(pb[1][2]-entry['collision_height'])<.01,(name,pb)
    assert '--- vmdl block PHYS' not in flow and 'm_hitboxsets = [  ]' in flow
    for i in range(49):assert f'build_flow_{i:02}.vmat' in flow,(name,i)
    material=dump('materials/survival_buildings/'+name+'.vmat_c')
    for key in ('F_NORMAL_MAP = 1','F_SPECULAR = 1','g_tNormal','g_tSpecular'):assert key in material,(name,key)
    textures=set(re.findall(r'resource:"(materials/survival_buildings/[^"\r\n]+\.vtex)"',material))
    assert len(textures)>=3
    for t in textures:assert (ROOT/(t+'_c')).is_file(),t
    assets.append(dict(name=name,dimensions=[nb[1][i]-nb[0][i] for i in range(3)],physics_bounds=pb,triangles=entry['triangles'],texture_dependencies=len(textures),selection_sets=3,flow_groups=49))

before=json.loads((OUT/'config_before.json').read_text(encoding='utf-8'))
current={table:rows(next((ROOT/'data/csv').rglob(table+'.csv')).read_text(encoding='utf-8-sig')) for table in before}
for table,original in before.items():
    old=rows(original);new=current[table]
    if table!='asset_catalog':assert old.keys()==new.keys(),table
    for key,row in old.items():
        allowed=set()
        if table=='building_levels' and row.get('building_id')=='building_wall':allowed={'display_name','model_name'}
        if table=='wall_visual_levels':allowed={'model_asset_id','model_scale','notes'}
        if table=='asset_catalog' and key.startswith('wall_tiny_'):allowed={'enabled','notes'}
        if table=='building_definitions' and key=='wall':allowed={'footprint_x','footprint_y'}
        if table=='building_construction_rules' and key=='wall':allowed={'build_visual_scale'}
        for field,value in row.items():
            if field not in allowed:assert new[key][field]==value,(table,key,field)
for level in range(1,31):
    row=current['building_levels'][f'building_wall_lv{level:02}']
    visual=current['wall_visual_levels'][f'wall_visual_lv{level:02}']
    assert row['display_name']==name_for(level) and row['model_name']==model_for(level)
    assert visual['model_asset_id']=='wall_reference_'+mesh_for(level)
    assert float(visual['model_scale'])==1
    asset=current['asset_catalog'][visual['model_asset_id']]
    assert asset['primary_model']==model_for(level) and asset['enabled']=='1' and not asset['environment_particles']
    assert (ROOT/(model_for(level)+'_c')).is_file()
report=dict(status='PASS',models=10,playable_levels=30,footprint=[4,4],world_footprint=256,max_mesh_width=248,
            model_scale=1,existing_yaw_preserved=True,economy_unchanged=True,normal_map=True,collision_models=10,flow_models=10,
            height_multiplier=HEIGHT_MULTIPLIER,weathering_progression=WEATHERING,revision=2,
            triangles=sum(a['triangles'] for a in assets),workshop_verified=False,assets=assets)
(OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
cards=[]
for entry in manifest:
    stage=entry['stage'];label=entry['display_name']
    cards.append(f'<article><img src="previews/{entry["name"]}.png" alt="{label}"><h2>{stage:02} · {label}</h2><p>等级 {stage*3-2}–{stage*3} · Ⅰ / Ⅱ / Ⅲ</p></article>')
(OUT/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>城墙 · 十阶模型预览</title><style>body{background:#152024;color:#eee;font:16px system-ui;margin:32px}h1{color:#d8bf81}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px}article{background:#26343a;padding:12px;border-radius:12px}img{width:100%;border-radius:6px}h2{font-size:19px}p{color:#c1cbd0}</style><h1>城墙 · 十阶模型预览 · 材质第二版</h1><p>高度为初版 2.5 倍，宽度仍为四格 × 四格；旧木、风化砌石逐渐过渡至精修金属和晶石。每三个玩法等级共用一种模型。以下为实际网格的 Blender 渲染。</p><main>'+''.join(cards)+'</main></html>',encoding='utf-8')
print('REFERENCE_WALLS_PASS models=10 levels=30 collision=10 flow=10 names=30 unchanged_economy')
