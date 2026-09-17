"""Targeted CSV edits: ten meshes / thirty names, without altering wall economy."""
import csv
import io
import json
import re
from pathlib import Path
from build_configs import build
from wall_asset_spec import NAMES, name_for, mesh_for, model_for

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/reference_walls'
TABLES=('building_levels','wall_visual_levels','asset_catalog','building_definitions','building_construction_rules')

def update(name):
    path=next((ROOT/'data/csv').rglob(name+'.csv'))
    raw=path.read_bytes();text=raw.decode('utf-8-sig');lines=text.splitlines(keepends=True)
    headers=next(csv.reader([lines[0]]));newline='\r\n' if '\r\n' in text else '\n'
    def line(row):
        out=io.StringIO(newline='');csv.writer(out,lineterminator=newline).writerow(row);return out.getvalue()
    seen=set();result=[]
    for original in lines:
        row=next(csv.reader([original])) if original.strip() else []
        if not row or row[0].startswith('#') or row[0]==headers[0]:result.append(original);continue
        values=dict(zip(headers,row));changes={}
        if name=='building_levels' and values.get('building_id')=='building_wall':
            level=int(values['level']);changes={'display_name':name_for(level),'model_name':model_for(level)}
        elif name=='wall_visual_levels':
            level=int(values['level'])
            # Four identical sides need no new facing logic; preserve existing yaw.
            changes={'model_asset_id':'wall_reference_'+mesh_for(level),'model_scale':'1.0',
                     'notes':name_for(level)+'；每3级一个外观；4×4格；保留原朝向。'}
        elif name=='building_definitions' and values.get('building_id')=='wall':
            changes={'footprint_x':'4','footprint_y':'4'}
        elif name=='building_construction_rules' and row[0]=='wall':
            changes={'build_visual_scale':'1.0'}
        elif name=='asset_catalog':
            aid=values['asset_id']
            if aid.startswith('wall_tiny_'):
                changes={'enabled':'0','notes':'已由10阶段参考图城墙替代；保留历史资源索引。'}
            if aid.startswith('wall_reference_wall_lv'):seen.add(aid)
        if changes:
            for key,value in changes.items():row[headers.index(key)]=value
            result.append(line(row))
        else:result.append(original)
    if name=='asset_catalog':
        for stage,label in enumerate(NAMES,1):
            aid=f'wall_reference_wall_lv{stage:02}'
            if aid in seen:continue
            values=dict(asset_id=aid,display_name=label+'城墙',asset_type='model_bundle',
                        primary_model=model_for((stage-1)*3+1),model_scale='1.0',load_group='initial_required',
                        load_order=str(70+stage),priority='950',first_use_wave='0',resident_policy='permanent',
                        fallback_asset_id='building_wall_fallback',enabled='1',
                        notes=f'参考图城墙{stage}阶；{(stage-1)*3+1}–{stage*3}级；2K颜色/法线/反射贴图、root选择盒、方形凸碰撞。')
            result.append(line([values.get(h,'') for h in headers]))
    path.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+''.join(result).encode('utf-8'))
    build(path,ROOT/'scripts/vscripts/config/generated'/(name+'.lua'))

def main():
    for i in range(1,31):assert (ROOT/(model_for(i)+'_c')).is_file(),model_for(i)
    snapshot=OUT/'config_before.json'
    if not snapshot.exists():
        snapshot.write_text(json.dumps({name:next((ROOT/'data/csv').rglob(name+'.csv')).read_text(encoding='utf-8-sig') for name in TABLES},ensure_ascii=False,indent=2),encoding='utf-8')
    for name in TABLES:update(name)
    path=ROOT/'scripts/npc/npc_units_custom.txt';raw=path.read_bytes();text=raw.decode('utf-8-sig')
    def replace(match):
        body,n=re.subn(r'("Model"\s*")[^"]*(")',lambda m:m[1]+model_for(1)+m[2],match[2]);assert n==1
        body,n=re.subn(r'("ModelScale"\s*")[^"]*(")',lambda m:m[1]+'1.0'+m[2],body);assert n==1
        return match[1]+body+match[3]
    text,n=re.subn(r'("building_wall"\s*\{)([^{}]*)(\})',replace,text);assert n==1
    path.write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+text.encode('utf-8'))
    print('REFERENCE_WALL_CONFIG_PASS models=10 levels=30 footprint=4x4 yaw=preserved economy=preserved')

if __name__=='__main__':main()
