"""Check authored resources, non-visual CSV invariants, and publish a preview gallery."""
import csv
import io
import json
import subprocess
import re
from pathlib import Path
from sync_unique_building_config import MAPPING

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/unique_buildings'
manifest=json.loads((OUT/'manifest.json').read_text())
assert len(manifest)==6
for asset in manifest:
    name=asset['name']
    assert 0 < asset['triangles'] < 30000
    assert max(asset['dimensions'][:2]) <= 128
    assert abs(asset['minimum'][2]) < .001
    assert asset['revision']==3 and asset['uv_layers']==1
    assert asset['texture_resolution']==1024
    assert asset['baseplate'] is False
    assert asset['root_bone']=='root'
    assert set(asset['selection_sets'])=={'default','select_low','select_high'}
    assert len(asset['materials'])==1
    for extension in ('vmdl','fbx'):
        assert (OUT/'source/models/survival_buildings'/(name+'.'+extension)).is_file()
    compiled=ROOT/'models/survival_buildings'/(name+'.vmdl_c')
    assert compiled.stat().st_size > 1024
    assert compiled.stat().st_mtime >= (OUT/'source/models/survival_buildings'/(name+'.fbx')).stat().st_mtime
    inspector=ROOT.parents[1]/'bin/win64/resourceinfo.exe'
    compiled_text=subprocess.check_output([str(inspector),'-i',str(compiled),'-all']).decode('utf-8',errors='replace')
    (OUT/(name+'_compiled.txt')).write_text(compiled_text,encoding='utf-8')
    for key in ('m_boneName = "root"','m_sBoneName = "root"','m_name = "select_low"','m_name = "select_high"'):
        assert key in compiled_text,(name,'compiled resource lacks '+key)
    assert '0 failed' in (OUT/(name+'.vmdl.log')).read_text(errors='replace')
    model_source=(OUT/'source/models/survival_buildings'/(name+'.vmdl')).read_text()
    for required in ('HitboxSetList','select_low','select_high','parent_bone="root"','bone_cull_type="None"'):
        assert required in model_source,(name,required)
    for material in asset['materials']:
        assert (ROOT/(material+'_c')).is_file(),material
        material_text=subprocess.check_output([str(inspector),'-i',str(ROOT/(material+'_c')),'-all']).decode('utf-8',errors='replace')
        (OUT/(name+'_material_compiled.txt')).write_text(material_text,encoding='utf-8')
        for key in ('F_NORMAL_MAP = 1','F_SPECULAR = 1','g_tNormal','g_tSpecular'):
            assert key in material_text,(material,key)
        textures=re.findall(r'resource:"(materials/survival_buildings/[^"\r\n]+\.vtex)"',material_text)
        assert len(set(textures))>=3,material
        for texture in textures:assert (ROOT/(texture+'_c')).is_file(),texture
        for suffix in ('color','normal','reflectance','ao','roughness'):
            texture=OUT/'source'/material.replace('.vmat','_'+suffix+'.png')
            assert texture.is_file(),texture
            assert texture.stat().st_size>100,texture
    assert (OUT/'previews'/(name+'.png')).stat().st_size > 10000

def rows(text):
    result=list(csv.DictReader(io.StringIO(text)))
    key=next(iter(result[0]))
    return {r[key]:r for r in result if r[key] and not r[key].startswith('#')}

for filename in ('building_levels','building_construction_rules','building_visual_levels'):
    path=next((ROOT/'data/csv').rglob(filename+'.csv'))
    previous=subprocess.check_output(['git','show','HEAD:'+path.relative_to(ROOT).as_posix()],cwd=ROOT).decode('utf-8-sig')
    before=rows(previous);after=rows(path.read_text(encoding='utf-8-sig'))
    assert before.keys()==after.keys()
    for key,row in before.items():
        for field,value in row.items():
            if field not in ('model_name','model_scale','build_visual_scale','notes'):
                assert after[key][field]==value,(filename,key,field)

labels={mesh:label for mesh,label in MAPPING.values()}
labels.update(research_lab='科技研究所：炼金工坊、熔炉与蒸馏罐',advanced_research_lab='高级研究所：三翼石柱与能量核心')
cards=[]
for asset in manifest:
    name=asset['name']
    cards.append(f'<article><a href="previews/{name}.png"><img src="previews/{name}.png" alt="{labels[name]}"></a><h2>{labels[name]}</h2><p>第三版 · {asset["triangles"]:,} 个三角面 · 无展示底板 · 独立烘焙贴图</p></article>')
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Survival · 独立建筑模型</title><style>
*{box-sizing:border-box}body{margin:0;background:#141c24;color:#e7e7df;font:16px/1.6 system-ui,"Microsoft YaHei",sans-serif}header,main{max-width:1300px;margin:auto;padding:32px}header{padding-bottom:0}h1{font-size:32px;margin:0}header p{color:#aebdc5}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}article{overflow:hidden;border:1px solid #39434a;border-radius:12px;background:#202b34}img{display:block;width:100%}h2{font-size:17px;margin:18px 20px 8px}article p{color:#aebdc5;margin:0 20px 20px;font-size:14px}</style><header><h1>Survival · 独立建筑模型</h1><p>五类建筑，六个模型版本。点击查看大图。以下为实际模型的 Blender 渲染，游戏内光照效果待实机确认。</p></header><main>'''+''.join(cards)+'</main></html>'
(OUT/'index.html').write_text(html,encoding='utf-8')
report={'status':'PASS','models':len(manifest),'triangles':sum(x['triangles'] for x in manifest),'economy_and_gameplay_fields':'unchanged','workshop_verified':False}
(OUT/'verification.json').write_text(json.dumps(report,indent=2))
print('UNIQUE_BUILDING_ASSETS_PASS',json.dumps(report))
