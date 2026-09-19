"""Verify compiled white geometry, material binding, and absence of collision."""
import json
import re
import subprocess
from pathlib import Path
from build_building_flow_materials import REVEAL_STEPS
from asset_validation import installed_source

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / 'output/unique_buildings'
OUT = ROOT / 'output/building_presentation'
INSPECTOR = ROOT.parents[1] / 'bin/win64/resourceinfo.exe'


def bounds(dump):
    return [[float(v) for v in re.search(field+r' = \[([^\]]+)\]', dump)[1].split(',')]
            for field in ('m_vMinBounds', 'm_vMaxBounds')]


def verify():
    manifest = json.loads((STAGE / 'manifest.json').read_text(encoding='utf-8'))
    result = []
    for entry in manifest:
        name = entry['name']
        assert entry['baked_yaw_degrees'] == -90
        relative = 'models/survival_buildings/' + name + '_white_shell.vmdl'
        source = STAGE / 'source' / relative
        fbx = source.with_name(name+'_flow.fbx')
        compiled = ROOT / (relative+'_c')
        installed_source(source, relative)
        installed_source(fbx, 'models/survival_buildings/'+name+'_flow.fbx')
        dump = subprocess.check_output([str(INSPECTOR), '-i', str(compiled), '-all']).decode('utf-8', errors='replace')
        (OUT / (name+'_white_shell_compiled.txt')).write_text(dump, encoding='utf-8')
        assert '--- vmdl block PHYS' not in dump, (name, 'unexpected physics')
        assert 'm_hitboxsets = [  ]' in dump, (name, 'unexpected hitboxes')
        materials = set(re.findall(r'resource:"([^"]+\.vmat)"', dump))
        expected = {f'materials/survival_buildings/build_flow_{step:02d}.vmat' for step in range(REVEAL_STEPS+1)}
        assert materials == expected, (name, materials)
        for step in range(1,REVEAL_STEPS+1):
            assert f'"reveal_{step:02d}"' in dump, (name,step)
        normal = subprocess.check_output([str(INSPECTOR), '-i', str(ROOT / ('models/survival_buildings/'+name+'.vmdl_c')), '-all']).decode('utf-8', errors='replace')
        shell_bounds, normal_bounds = bounds(dump), bounds(normal)
        assert all(abs(a-b)<.01 for side_a,side_b in zip(shell_bounds,normal_bounds) for a,b in zip(side_a,side_b)), (name, shell_bounds, normal_bounds)
        result.append(dict(name=name, material='build_flow', material_groups=REVEAL_STEPS+1, matches_building_bounds=True, physics=False, hitboxes=False))
    report = dict(status='PASS', count=len(result), models=result)
    (OUT/'white_shell_verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('BUILDING_WHITE_SHELL_ASSETS_PASS models='+str(len(result)))
    return report


if __name__ == '__main__':
    verify()
