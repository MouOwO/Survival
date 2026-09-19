"""Install the authored building mappings through CSV authority and its generator."""
import csv
import io
import re
from pathlib import Path
from build_configs import build

ROOT = Path(__file__).resolve().parents[1]
MAPPING = {
    'building_research_lab': ('research_lab', '科技研究所：星仪与蓝晶高塔'),
    'building_advanced_research_lab': ('advanced_research_lab', '高级研究所：双晶尖塔与外星环'),
    'building_gold_mine': ('gold_mine', '金矿：矿洞、金矿石与轨道矿车'),
    'building_farm': ('population_farm', '人口农场：谷仓、粮筒与麦田'),
    'building_hero_altar': ('hero_altar', '英雄祭坛：圣剑与双翼祭台'),
    'building_challenge': ('challenge_arena', '挑战建筑：角斗场与红色战旗'),
}

def model(name):
    return 'models/survival_buildings/' + name + '.vmdl'

def encode(row, newline):
    out = io.StringIO(newline='')
    csv.writer(out, lineterminator=newline).writerow(row)
    return out.getvalue()

def update_csv(name):
    path = next((ROOT/'data/csv').rglob(name+'.csv'))
    raw = path.read_bytes()
    bom = raw.startswith(b'\xef\xbb\xbf')
    text = raw.decode('utf-8-sig')
    lines = text.splitlines(keepends=True)
    headers = next(csv.reader([lines[0]]))
    newline = '\r\n' if '\r\n' in text else '\n'
    output = []
    for line in lines:
        row = next(csv.reader([line])) if line.strip() else []
        if not row or row[0].startswith('#') or row[0] == headers[0]:
            output.append(line); continue
        values = dict(zip(headers,row))
        identity = values.get('building_id','')
        identity = {'gold_mine':'building_gold_mine','hero_altar':'building_hero_altar'}.get(identity,identity)
        changes = {}
        if identity in MAPPING:
            mesh, label = MAPPING[identity]
            if name == 'building_visual_levels':
                changes = dict(model_name=model(mesh),model_scale='1',notes=label+'；原点居中贴地，占地124码。')
            elif name == 'building_levels':
                changes = dict(model_name=model(mesh))
            elif name == 'building_construction_rules':
                changes = dict(build_visual_scale='1',notes='独立建筑模型使用1倍缩放；沿用原施工时间、特效和选择生命周期。')
        if changes:
            for key,value in changes.items():row[headers.index(key)] = value
            output.append(encode(row,newline))
        else: output.append(line)
    if name == 'asset_catalog':
        existing={r.get('asset_id') for r in csv.DictReader(io.StringIO(text))}
        for i,(mesh,label) in enumerate(MAPPING.values()):
            asset_id='building_unique_'+mesh
            if asset_id in existing: continue
            values=dict(asset_id=asset_id,display_name=label,asset_type='model_bundle',primary_model=model(mesh),
                        model_scale='1',load_group='initial_required',load_order=str(30+i),priority='960',
                        first_use_wave='0',resident_policy='permanent',fallback_asset_id='building_radiant_ancient',enabled='1',
                        notes='项目原创静态建筑；不依赖饰品或外部纹理；启动预载。')
            output.append(encode([values.get(key,'') for key in headers],newline))
    path.write_bytes((b'\xef\xbb\xbf' if bom else b'')+''.join(output).encode('utf-8'))
    build(path,ROOT/'scripts/vscripts/config/generated'/(name+'.lua'))

def main():
    for mesh,_ in MAPPING.values():
        compiled=ROOT/(model(mesh)+'_c')
        assert compiled.is_file() and compiled.stat().st_size>1024, f'Compile before wiring: {compiled}'
    for name in ('building_visual_levels','building_levels','building_construction_rules','asset_catalog'):
        update_csv(name)
    path=ROOT/'scripts/npc/npc_units_custom.txt'
    raw=path.read_bytes()
    bom=raw.startswith(b'\xef\xbb\xbf')
    text=raw.decode('utf-8-sig')
    for unit,(mesh,_) in MAPPING.items():
        pattern=r'("'+re.escape(unit)+r'"\s*\{)([^{}]*)(\})'
        def replace(match):
            body,n=re.subn(r'("Model"\s*")[^"]*(")',lambda m:m[1]+model(mesh)+m[2],match[2])
            assert n==1,unit
            body,n=re.subn(r'("ModelScale"\s*")[^"]*(")',r'\g<1>1\2',body)
            assert n==1,unit
            return match[1]+body+match[3]
        text,n=re.subn(pattern,replace,text)
        assert n==1,unit
    path.write_bytes((b'\xef\xbb\xbf' if bom else b'')+text.encode('utf-8'))
    print('UNIQUE_BUILDING_CONFIG_SYNC_PASS')

if __name__ == '__main__':main()
