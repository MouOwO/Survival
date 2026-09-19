"""Audit compiled reference models, physics, material dependencies and CSVs."""
import csv
import io
import json
import re
import subprocess
from pathlib import Path
from sync_reference_building_config import FAMILIES,mesh_for,SCALE,FOOTPRINT,identity
from reference_building_modeldoc import MODEL_SOURCE_SCALE, BASE_WIDTH
from asset_validation import installed_source

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/unique_buildings'
manifest=json.loads((OUT/'manifest.json').read_text())
expected={mesh_for(b,l) for b,(_,count,_) in FAMILIES.items() for l in range(1,count+1)}
assert len(manifest)==24 and {a['name'] for a in manifest}==expected
inspector=ROOT.parents[1]/'bin/win64/resourceinfo.exe'
reports=[]
for a in manifest:
    name=a['name'];assert a['revision']==4 and a['runtime_scale']==float(SCALE)
    assert a['model_source_scale']==MODEL_SOURCE_SCALE
    assert a['baked_yaw_degrees']==-90
    assert 0<a['triangles']<75000,(name,a['triangles'])
    assert abs(max(a['dimensions'][:2])-118)<.01
    assert abs(a['minimum'][2])<.001 and a['baseplate'] is False
    assert a['texture_resolution']==2048 and a['uv_layers']==1
    assert a['selection_sets']==['default','select_low','select_high']
    source=OUT/'source/models/survival_buildings'/(name+'.fbx')
    compiled=ROOT/'models/survival_buildings'/(name+'.vmdl_c')
    modeldoc=source.with_suffix('.vmdl')
    # Git checkout does not preserve build times; validate sources and actual resources.
    installed_source(source, 'models/survival_buildings/'+name+'.fbx')
    installed_source(modeldoc, 'models/survival_buildings/'+name+'.vmdl')
    dump=subprocess.check_output([str(inspector),'-i',str(compiled),'-all']).decode('utf-8',errors='replace')
    (OUT/(name+'_compiled.txt')).write_text(dump,encoding='utf-8')
    for key in ('m_boneName = "root"','m_sBoneName = "root"','m_name = "select_low"','m_name = "select_high"','--- vmdl block PHYS','m_hulls ='):
        assert key in dump,(name,key)
    phys=dump.split('--- vmdl block PHYS',1)[1].split('--- vmdl block',1)[0]
    bounds=[]
    for field in ('m_vMinBounds','m_vMaxBounds'):
        values=re.search(field+r' = \[([^\]]+)\]',phys);assert values,(name,field)
        bounds.append([float(x) for x in values[1].split(',')])
    radius=a['collision_radius']*MODEL_SOURCE_SCALE;height=a['collision_height']*MODEL_SOURCE_SCALE
    assert abs(bounds[0][2])<.01 and abs(bounds[1][2]-height)<.01,(name,'collider is not Z-up and grounded',bounds)
    for axis in (0,1):
        assert abs(bounds[0][axis]+radius)<.01 and abs(bounds[1][axis]-radius)<.01,(name,bounds)
    material=ROOT/'materials/survival_buildings'/(name+'.vmat_c')
    assert material.is_file()
    matdump=subprocess.check_output([str(inspector),'-i',str(material),'-all']).decode('utf-8',errors='replace')
    (OUT/(name+'_material_compiled.txt')).write_text(matdump,encoding='utf-8')
    for key in ('F_NORMAL_MAP = 1','F_SPECULAR = 1','g_tNormal','g_tSpecular'):assert key in matdump,(name,key)
    textures=set(re.findall(r'resource:"(materials/survival_buildings/[^"\r\n]+\.vtex)"',matdump))
    assert len(textures)>=3,(name,textures)
    for texture in textures:assert (ROOT/(texture+'_c')).is_file(),texture
    for suffix in ('color','normal','ao','roughness','reflectance'):
        assert (OUT/'source/materials/survival_buildings'/(name+'_'+suffix+'.png')).stat().st_size>1000
    assert (OUT/'previews'/(name+'.png')).stat().st_size>10000
    mesh_bounds=[]
    for field in ('m_vMinBounds','m_vMaxBounds'):
        match=re.search(field+r' = \[([^\]]+)\]',dump)
        mesh_bounds.append([float(x) for x in match[1].split(',')])
    # Compiled mesh, not metadata alone, must prove the requested doubling.
    compiled_width=max(mesh_bounds[1][i]-mesh_bounds[0][i] for i in (0,1))
    assert abs(compiled_width-BASE_WIDTH*MODEL_SOURCE_SCALE)<.02,(name,compiled_width)
    pick=dump.split('m_name = "default"',1)[1].split('m_name = "select_low"',1)[0]
    for field,sign in (('m_vMinBounds',-1),('m_vMaxBounds',1)):
        match=re.search(field+r' = \[([^\]]+)\]',pick)
        values=[float(x) for x in match[1].split(',')]
        assert all(abs(values[i]-sign*59*MODEL_SOURCE_SCALE)<.01 for i in (0,1)),name
    runtime_width=compiled_width*float(SCALE)
    reports.append(dict(name=name,physics_bounds=bounds,triangles=a['triangles'],runtime_width=round(runtime_width,2),status='PASS'))

def rows(text):
    result=list(csv.DictReader(io.StringIO(text)));key=next(iter(result[0]))
    return {r[key]:r for r in result if r[key] and not r[key].startswith('#')}

before=json.loads((OUT/'reference_config_before.json').read_text(encoding='utf-8'))
for name in ('building_levels','building_construction_rules'):
    old=rows(before[name]);current=rows(next((ROOT/'data/csv').rglob(name+'.csv')).read_text(encoding='utf-8-sig'))
    assert old.keys()==current.keys()
    for key,row in old.items():
        for field,value in row.items():
            if name=='building_levels' and row.get('building_id')=='building_wall' and field=='display_name':
                from wall_asset_spec import name_for
                assert current[key][field]==name_for(int(row['level']))
                continue
            if field not in ('model_name','build_visual_scale','notes','build_particle','build_start_particle','build_loop_particle','build_complete_particle'):
                assert current[key][field]==value,(name,key,field)
visuals=rows(next((ROOT/'data/csv').rglob('building_visual_levels.csv')).read_text(encoding='utf-8-sig'))
for bid,(_,count,_) in FAMILIES.items():
    group=[r for r in visuals.values() if r['building_id']==bid]
    assert len(group)==count
    for r in group:
        assert r['model_name']=='models/survival_buildings/'+mesh_for(bid,int(r['level']))+'.vmdl'
        assert float(r['model_scale'])==float(SCALE)
        assert float(r['model_yaw'])==0
definitions=rows(next((ROOT/'data/csv').rglob('building_definitions.csv')).read_text(encoding='utf-8-sig'))
for bid,row in definitions.items():
    if identity(bid) in FAMILIES:
        assert int(row['footprint_x'])==FOOTPRINT and int(row['footprint_y'])==FOOTPRINT

city=['木石议事厅','双翼执政厅','古树议厅','古树王庭','翠晶圣城']
farm=['丰穗粮仓','林地农舍','双院庄屋','风车庄园','丰饶大庄园']
mine=['露脉矿丘','支护矿山','双洞矿岭','阶岩采场','卷扬矿峰','双峰索道矿山','环轨矿山','深井矿山','巨脉矿山','天辉金脉圣山']
other={'research_lab':'研究所 · 炼金工坊','advanced_research_lab':'高级研究所 · 星象高塔','hero_altar':'英雄祭坛','challenge_arena':'挑战竞技场'}
cards=[]
for a in manifest:
    name=a['name'];family=a['family'];stage=a['stage']
    if family=='city':label=f'主城 {stage}级 · '+city[stage-1]
    elif family=='farm':label=f'农场 {stage}级 · '+farm[stage-1]
    elif family=='mine':label=f'金矿外观 {stage} · '+mine[stage-1]+f'（玩法 {stage*3-2}–{stage*3}级）'
    else:label=other[name]
    group=family if family in ('city','farm','mine') else 'other'
    cards.append(f'<article data-group="{group}"><a href="previews/{name}.png"><img loading="lazy" src="previews/{name}.png" alt="{label}"></a><h2>{label}</h2><p>{a["triangles"]:,} 三角面 · 2K 独立贴图 · 凸碰撞体</p></article>')
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Survival · 参考图建筑模型</title><style>
*{box-sizing:border-box}body{margin:0;background:#e8e7df;color:#253c3b;font:16px/1.6 system-ui,"Microsoft YaHei",sans-serif}header,main{max-width:1500px;margin:auto;padding:30px}header{padding-bottom:0}h1{font-size:30px;margin:0}header p{max-width:960px;color:#586761}nav{display:flex;gap:10px;flex-wrap:wrap}button{font:inherit;border:1px solid #9aa79c;border-radius:6px;padding:7px 18px;background:#f5f4ed;color:#253c3b;cursor:pointer}button[aria-pressed=true]{background:#376766;color:white}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px}article{overflow:hidden;border:1px solid #c3cabd;border-radius:10px;background:#f7f6f0}article[hidden]{display:none}img{display:block;width:100%}h2{font-size:17px;margin:15px 18px 7px}article p{color:#68736a;margin:0 18px 18px;font-size:14px}</style>
<header><h1>Survival · 24 款参考图建筑</h1><p>主城五级、农场五级、金矿十种外观，以及炼金工坊、星象塔、英雄祭坛和挑战竞技场。模型资源等比例放大两倍，游戏最大横向宽度约 236 码；实体比例保持 1.0，逻辑占地仍为 2×2、共四格。金矿每 3 个玩法等级切换一次外观。</p><p>下方为实际导出网格与贴图的 Blender 渲染。无展示底板；保留建筑台阶和矿场工作平台。Source 2 编译、选择盒、碰撞体方向和等级配置已离线检查；游戏内光照、相邻建筑间距和点击手感仍需新开一局确认。</p><nav aria-label="建筑类别">'''
for key,label in [('all','全部 24'),('city','主城 5'),('farm','农场 5'),('mine','金矿 10'),('other','研究所与其他 4')]:html+=f'<button data-filter="{key}" aria-pressed="{str(key=="all").lower()}">{label}</button>'
html+='</nav></header><main>'+''.join(cards)+'''</main><script>document.querySelectorAll('button[data-filter]').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('button[data-filter]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));document.querySelectorAll('article').forEach(a=>a.hidden=b.dataset.filter!=='all'&&a.dataset.group!==b.dataset.filter)}));</script></html>'''
(OUT/'index.html').write_text(html,encoding='utf-8')
report=dict(status='PASS',revision=4,models=24,playable_levels=44,triangles=sum(a['triangles'] for a in manifest),scale=float(SCALE),model_source_scale=MODEL_SOURCE_SCALE,footprint=[FOOTPRINT,FOOTPRINT],texture_resolution=2048,economy_fields='unchanged',city_hull_radius=48*float(SCALE),city_model_physics_radius=48*MODEL_SOURCE_SCALE,workshop_verified=False,assets=reports)
(OUT/'verification.json').write_text(json.dumps(report,indent=2))
print('REFERENCE_BUILDING_ASSETS_PASS models=24 levels=44 physics=24 textures=72 economy=unchanged')
