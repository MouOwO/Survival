"""Build model-keyed native 3D portraits from the actual compiled mesh bounds.

No extra scene panels or proxy units: the engine draws the selected entity.
Run after rebuilding building models or changing worker model CSVs.
"""
from pathlib import Path
import copy
import csv
import io
import itertools
import json
import math
import re
import subprocess
from build_wave_monster_cosmetics import Vpk, parse_kv

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
WORK = ROOT / 'output/model_portraits_20260926'
INFO = ENGINE / 'game/bin/win64/resourceinfo.exe'


def rows(name):
    path = next((ROOT / 'data/csv').rglob(name))
    result = csv.DictReader(io.StringIO(path.read_text(encoding='utf-8-sig')))
    return [r for r in result if not str(next(iter(r.values()), '')).startswith('#')]


def vector(v):
    return ' '.join(f'{x:.4f}' for x in v)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def fitted_camera(lo, hi, building):
    # Buildings face south; creatures face +X in their native model coordinates.
    pitch = math.radians(24 if building else 8)
    yaw = math.radians(120 if building else 160)
    forward = [math.cos(pitch)*math.cos(yaw), math.cos(pitch)*math.sin(yaw), -math.sin(pitch)]
    right = [-math.sin(yaw), math.cos(yaw), 0]
    up = [math.sin(pitch)*math.cos(yaw), math.sin(pitch)*math.sin(yaw), math.cos(pitch)]
    target = [(a+b)/2 for a, b in zip(lo, hi)]
    fov = 30
    # Native portrait is nearly square. Fit both axes even at aspect ratio 0.9.
    tangent = math.tan(math.radians(fov/2))
    corners = list(itertools.product(*zip(lo, hi)))
    distance = 1
    for corner in corners:
        q = [c-t for c, t in zip(corner, target)]
        distance = max(distance, max(abs(dot(q, right)), abs(dot(q, up))/0.9) / (tangent*0.88) - dot(q, forward))
    position = [t-distance*f for t, f in zip(target, forward)]
    return dict(PortraitPosition=vector(position), PortraitAngles=f'{math.degrees(pitch):.4f} {math.degrees(yaw):.4f} 0', PortraitFOV=str(fov), PortraitFar=str(math.ceil(distance + max(hi)-min(lo) + 1000)))


def mesh_bounds(model, vpk):
    path = ROOT / (model+'_c')
    if not path.exists():
        path = WORK / 'valve' / (model+'_c')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(vpk.read(model+'_c'))
    proc = subprocess.run([str(INFO), '-i', str(path), '-b', 'MDAT', '-maxelements', '2'], capture_output=True, text=True, encoding='utf-8', errors='replace', check=True)
    # Use scene node render bounds, not the later bone-local hitbox bounds.
    values = {}
    for name in ('Min', 'Max'):
        matches = re.findall(r'^\t{3}m_v'+name+r'Bounds = \[ ([^\]]+) \]', proc.stdout, re.M)
        if not matches:
            matches = re.findall(r'm_v'+name+r'Bounds = \[ ([^\]]+) \]', proc.stdout)[:1]
        if not matches:
            raise RuntimeError('Missing compiled mesh bounds: '+model)
        parsed = [[float(v.strip()) for v in m.split(',')] for m in matches]
        fn = min if name == 'Min' else max
        values[name] = [fn(v[i] for v in parsed) for i in range(3)]
    assert all(b>a for a,b in zip(values['Min'],values['Max'])), model
    return values['Min'], values['Max']


def kv(data, indent=0):
    lines=[]
    for key, value in data.items():
        prefix='    '*indent
        if isinstance(value, dict):
            lines += [prefix+json.dumps(key), prefix+'{', kv(value, indent+1), prefix+'}']
        else:
            lines.append(prefix+json.dumps(key)+' '+json.dumps(str(value)))
    return '\n'.join(lines)


def portrait_background():
    return dict(PortraitBackgroundTexture='materials/vgui/hud/heroportraits/portraitbackground_gradient_top.vmat',
        PortraitBackgroundColor1='0.055 0.09 0.105', PortraitBackgroundColor2='0.055 0.09 0.105',
        PortraitBackgroundColor3='0.025 0.045 0.055', PortraitBackgroundColor4='0.025 0.045 0.055',
        PortraitHideParticles='1', PortraitDesaturateHero='0')


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    vpk=Vpk(ENGINE / 'game/dota/pak01_dir.vpk')
    valve=parse_kv(vpk.read('scripts/npc/portraits.txt').decode('utf-8'))['Portraits']
    targets={r['primary_model']:'building' for r in rows('asset_catalog.csv') if r.get('enabled')=='1' and r.get('primary_model','').startswith('models/survival_buildings/') and not r['primary_model'].endswith('_white_shell.vmdl')}
    targets.update({r['model_name']:'worker' for r in rows('training_definitions.csv') if r.get('model_name','').startswith('models/')})
    source=(ROOT/'scripts/vscripts/systems/building_visual_service.lua').read_text(encoding='utf-8')
    native_block=source.split('local NATIVE_TOWER_MODELS = {',1)[1].split('}',1)[0]
    targets.update({m:'tower' for m in re.findall(r'"(models/[^\"]+\.vmdl)"',native_block)})
    targets['models/props_structures/radiant_tower001.vmdl']='tower'
    # Preserve Valve cameras and lighting, but use one grounded backdrop for
    # every model, including heroes rendered through SetUnit scene panels.
    portraits=copy.deepcopy(valve)
    for model, entry in portraits.items():
        if isinstance(entry, dict):
            entry.update(portrait_background())
    report=[]
    for model, kind in sorted(targets.items()):
        lo,hi=mesh_bounds(model,vpk)
        # Preserve Valve's authored face camera where it exists; supply missing
        # cameras for newer lane creeps, repairers, and our custom buildings.
        original=valve.get(model,{})
        camera=original.get('cameras',{}).get('default') if kind!='building' else None
        if camera:
            camera=dict(camera)
            camera['PortraitFOV']=str(round(float(camera.get('PortraitFOV',20))*1.12,3))
            method='valve_camera_with_margin'
        else:
            camera=fitted_camera(lo,hi,kind!='worker')
            method='compiled_mesh_fit'
        height=hi[2]-lo[2]
        lighting=max(height,120)
        entry={
            'PortraitLightPosition':vector([lighting*1.2,-lighting*1.4,lighting*2.2]),
            'PortraitLightAngles':'45 130 0',
            'PortraitLightFOV':'80',
            'PortraitLightDistance':str(math.ceil(lighting*4)),
            'PortraitLightColor':'245 235 218',
            'PortraitLightScale':'2.2',
            'PortraitAmbientColor':'100 131 140',
            'PortraitAmbientScale':'2.4',
            'PortraitAmbientDirection':'-35 55 -65',
            'PortraitShadowColor':'37 47 52',
            'PortraitShadowScale':'1.5',
            'PortraitGroundShadowScale':'1.5',
            'PortraitSpecularColor':'225 225 215',
            'PortraitBackgroundTexture':'materials/vgui/hud/heroportraits/portraitbackground_gradient_top.vmat',
            'PortraitBackgroundColor1':'0.10 0.17 0.19',
            'PortraitBackgroundColor2':'0.10 0.17 0.19',
            'PortraitBackgroundColor3':'0.035 0.055 0.065',
            'PortraitBackgroundColor4':'0.035 0.055 0.065',
            'PortraitHideHero':'0',
            'PortraitAnimationActivity':'ACT_DOTA_IDLE',
            'cameras':{'default':camera},
        }
        entry.update(portrait_background())
        portraits[model]=entry
        report.append(dict(model=model,kind=kind,minimum=lo,maximum=hi,method=method,camera=camera))
    primal=portraits.get('models/heroes/primal_beast/primal_beast_base.vmdl', {})
    if primal:
        primal['cameras']['default'].update(PortraitPosition='470 60 125',
            PortraitAngles='1 194 0', PortraitFOV='20', PortraitFar='5000')
    output=ROOT/'scripts/npc/portraits_custom.txt'
    output.write_text('// Generated by tools/build_unit_portraits.py; complete model profiles with a shared dark backdrop.\n'+kv({'Portraits':portraits})+'\n',encoding='utf-8')
    (WORK/'portrait_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    assert len(parse_kv(output.read_text(encoding='utf-8'))['Portraits'])==len(portraits)
    print(f'Generated {len(targets)} native 3D portrait profiles: '+str({k:sum(v==k for v in targets.values()) for k in set(targets.values())}))

if __name__=='__main__':
    main()
