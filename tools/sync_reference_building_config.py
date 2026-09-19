"""Wire the 24 reference variants through authoritative CSVs and generators."""
import csv
import io
import json
import re
from pathlib import Path
from build_configs import build

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/unique_buildings'
SCALE='1.0'  # Enlargement is authored into ModelDoc, not the entity scale.
FOOTPRINT=2
YAW='0'  # South-facing orientation is baked into the FBX geometry.
WARP='particles/survival_buildings/white_build_'
FAMILIES={
    'building_main_city':('main_city',5,'主城'),
    'building_farm':('population_farm',5,'人口农场'),
    'building_gold_mine':('gold_mine',30,'金矿'),
    'building_research_lab':('research_lab',1,'研究所·炼金工坊'),
    'building_advanced_research_lab':('advanced_research_lab',1,'高级研究所·星象高塔'),
    'building_hero_altar':('hero_altar',1,'英雄祭坛'),
    'building_challenge':('challenge_arena',1,'挑战竞技场'),
}

def mesh_for(identity,level=1):
    stem,count,_=FAMILIES[identity]
    if count==1:return stem
    stage=(level+2)//3 if identity=='building_gold_mine' else level
    return f'{stem}_lv{stage:02}'

def model(name):return 'models/survival_buildings/'+name+'.vmdl'

def identity(value):
    return {'main_city':'building_main_city','gold_mine':'building_gold_mine','hero_altar':'building_hero_altar'}.get(value,value)

def write_row(row,newline):
    f=io.StringIO(newline='');csv.writer(f,lineterminator=newline).writerow(row);return f.getvalue()

def update_table(name):
    path=next((ROOT/'data/csv').rglob(name+'.csv'))
    raw=path.read_bytes();text=raw.decode('utf-8-sig');lines=text.splitlines(keepends=True)
    newline='\r\n' if '\r\n' in text else '\n';headers=next(csv.reader([lines[0]]))
    extra={'building_definitions':[('footprint_x','横向占格','number'),('footprint_y','纵向占格','number')],
           'building_construction_rules':[('build_complete_particle','施工或升级完成特效','string')]}.get(name,[])
    for key,label,kind in extra:
        if key in headers:continue
        for index,line in enumerate(lines):
            row=next(csv.reader([line])) if line.strip() else []
            if not row:continue
            row.append(key if index==0 else label if row[0].startswith('#中文名') else kind if row[0].startswith('#types') else '')
            lines[index]=write_row(row,newline)
        headers.append(key)
    output=[];seen=set()
    for line in lines:
        row=next(csv.reader([line])) if line.strip() else []
        if not row or row[0].startswith('#') or row[0]==headers[0]:output.append(line);continue
        values=dict(zip(headers,row));changes={}
        bid=identity(values.get('building_id',''))
        if name=='building_construction_rules':
            changes={'build_particle':WARP+'channel.vpcf','build_start_particle':'',
                     'build_loop_particle':WARP+'channel.vpcf','build_complete_particle':WARP+'reveal.vpcf',
                     'notes':'稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。'}
        if bid in FAMILIES:
            level=int(values.get('level') or 1);mesh=mesh_for(bid,level)
            if name=='building_definitions':changes={'footprint_x':str(FOOTPRINT),'footprint_y':str(FOOTPRINT)}
            elif name=='building_levels':changes={'model_name':model(mesh)}
            elif name=='building_visual_levels':
                seen.add((bid,level));changes={'model_name':model(mesh),'model_scale':SCALE,'model_yaw':YAW,'notes':FAMILIES[bid][2]+f'；模型资源等比例放大2倍；实体比例{SCALE}；正门朝南；{FOOTPRINT}×{FOOTPRINT}格居中。'}
            elif name=='building_construction_rules':
                changes['build_visual_scale']=SCALE
        if name=='asset_catalog':
            for bid,(stem,count,label) in FAMILIES.items():
                for level in range(1,count+1):
                    mesh=mesh_for(bid,level)
                    if values.get('asset_id')=='building_unique_'+mesh:
                        changes={'primary_model':model(mesh),'model_scale':SCALE,'display_name':label+(' '+mesh.rsplit('_',1)[-1] if count>1 else ''),'enabled':'1'};seen.add(mesh)
            if values.get('asset_id') in ('building_unique_population_farm','building_unique_gold_mine'):
                changes={'enabled':'0','notes':'已由分级参考图模型替代，保留历史资源索引。'}
        if changes:
            for key,value in changes.items():row[headers.index(key)]=value
            output.append(write_row(row,newline))
        else:output.append(line)
    if name=='building_visual_levels':
        for bid,(stem,count,label) in FAMILIES.items():
            for level in range(1,count+1):
                if (bid,level) in seen:continue
                values={'visual_id':bid.removeprefix('building_')+f'_visual_lv{level:02}','building_id':bid,'level':str(level),
                        'model_name':model(mesh_for(bid,level)),'model_scale':SCALE,'model_yaw':YAW,'enabled':'1',
                        'notes':label+'；每3个玩法等级切换一次外观。' if bid=='building_gold_mine' else label+'；参考图分级外观。'}
                output.append(write_row([values.get(h,'') for h in headers],newline))
    if name=='asset_catalog':
        for bid,(stem,count,label) in FAMILIES.items():
            for level in range(1,count+1):
                mesh=mesh_for(bid,level)
                if mesh in seen:continue
                seen.add(mesh)
                values=dict(asset_id='building_unique_'+mesh,display_name=label+' '+mesh,asset_type='model_bundle',primary_model=model(mesh),
                            model_scale=SCALE,load_group='initial_required',load_order=str(30+len(seen)),priority='960',first_use_wave='0',
                            resident_policy='permanent',fallback_asset_id='building_radiant_ancient',enabled='1',notes='参考图建筑；独立UV与2K贴图；root选择盒及凸碰撞体。')
                output.append(write_row([values.get(h,'') for h in headers],newline))
    path.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+''.join(output).encode('utf-8'))
    build(path,ROOT/'scripts/vscripts/config/generated'/(name+'.lua'))

def main():
    manifest=json.loads((OUT/'manifest.json').read_text())
    expected={mesh_for(b,l) for b,(_,count,_) in FAMILIES.items() for l in range(1,count+1)}
    assert {a['name'] for a in manifest}==expected and len(expected)==24
    for mesh in expected:assert (ROOT/(model(mesh)+'_c')).stat().st_size>1024,mesh
    snapshot=OUT/'reference_config_before.json'
    if not snapshot.exists():
        before={name:next((ROOT/'data/csv').rglob(name+'.csv')).read_text(encoding='utf-8-sig') for name in ('building_visual_levels','building_levels','building_construction_rules','asset_catalog')}
        snapshot.write_text(json.dumps(before,ensure_ascii=False,indent=2),encoding='utf-8')
    for name in ('building_definitions','building_visual_levels','building_levels','building_construction_rules','asset_catalog'):update_table(name)
    path=ROOT/'scripts/npc/npc_units_custom.txt';raw=path.read_bytes();text=raw.decode('utf-8-sig')
    for bid in FAMILIES:
        def replace(m):
            body,n=re.subn(r'("Model"\s*")[^"]*(")',lambda q:q[1]+model(mesh_for(bid))+q[2],m[2]);assert n==1,bid
            body,n=re.subn(r'("ModelScale"\s*")[^"]*(")',lambda q:q[1]+SCALE+q[2],body);assert n==1,bid
            return m[1]+body+m[3]
        text,n=re.subn(r'("'+re.escape(bid)+r'"\s*\{)([^{}]*)(\})',replace,text);assert n==1,bid
    path.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+text.encode('utf-8'))
    # Runtime scale is configuration metadata; no mesh/texture rebake is needed.
    for asset in manifest:asset['runtime_scale']=float(SCALE)
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(f'REFERENCE_BUILDING_CONFIG_PASS variants=24 playable_levels=44 scale={SCALE} footprint={FOOTPRINT}x{FOOTPRINT}')

if __name__=='__main__':main()
