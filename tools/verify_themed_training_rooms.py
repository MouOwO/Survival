"""Inspect compiled themed rooms, installed sources and review-map VPK payloads.

Usage: python tools/verify_themed_training_rooms.py [--theme wood|attribute|greater_attribute]
Full room namespaces are accepted too. Without a filter, verify all three rooms.
This is an asset/spatial check, not a claim of in-game visual or navigation QA.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

from asset_validation import installed_source, verify_map_vpk

ROOT = Path(__file__).resolve().parents[1]
INSPECTOR = ROOT.parents[1] / 'bin/win64/resourceinfo.exe'
THEMES = {
    'wood_training_room': 'challenge_01',
    'attribute_training_room': 'challenge_03',
    'greater_attribute_training_room': 'challenge_04',
}
REVISION = 'themed_training_surfaces_v1'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def dump(relative):
    return subprocess.check_output([str(INSPECTOR), '-i', str(ROOT / relative), '-all']).decode('utf-8', errors='replace')


def compiled_float(text, name, expected, material):
    match = re.search(r'm_name = "' + re.escape(name) + r'"\s+m_flValue = ([\d.eE+-]+)', text)
    assert match and abs(float(match[1]) - expected) < .001, (material, name, 'compiled value missing or wrong', expected)


def bounds(text, key):
    match = re.search(re.escape(key) + r' = \[ ([^\]]+) \]', text)
    assert match, ('compiled bound missing', key)
    values = [float(v) for v in match[1].split(',')]
    assert len(values) == 3, (key, values)
    return values


def verify(theme):
    out = ROOT / 'output' / theme
    source = out / 'source'
    assets = read_json(out / 'asset_manifest.json')
    materials = read_json(out / 'material_manifest.json')
    layout = read_json(out / 'room_layout.json')
    map_meta = read_json(out / 'map_manifest.json')
    blend = out / (theme + '.blend')
    assert blend.is_file() and blend.stat().st_size > 1024, ('packed Blender source missing', blend)
    assert assets and materials, (theme, 'missing assets/materials')
    models = {a['name']: a for a in assets}
    assert len(models) == len(assets), (theme, 'duplicate asset names')
    model_checks = []
    for asset in assets:
        name = asset['name']
        text = dump(f'models/{theme}/{name}.vmdl_c')
        actual = [bounds(text, 'm_vMinBounds'), bounds(text, 'm_vMaxBounds')]
        error = max(abs(v - wanted) for row, expected in zip(actual, asset['bounds']) for v, wanted in zip(row, expected))
        assert error < .04, (theme, name, 'render bounds/orientation/scale mismatch', error)
        physics = '--- vmdl block PHYS' in text
        assert physics == (asset['collision_hulls'] > 0), (name, 'collision presence mismatch')
        for material in asset['materials']:
            assert material.startswith(f'materials/{theme}/'), (name, 'unexpected shared material', material)
            assert material in text, (name, 'missing compiled material dependency', material)
        assert asset['triangles'] > 0 and not asset.get('emissive', False), name
        model_checks.append(dict(name=name, bounds_error=error, physics=physics, triangles=asset['triangles']))
    # Read installed geometry sources as well as metadata. CRLF normalization
    # is handled by installed_source, so Git checkout dates do not affect this.
    model_sources = list((source / 'models' / theme).rglob('*'))
    for path in model_sources:
        if path.is_file() and path.suffix.lower() in ('.fbx', '.vmdl', '.obj'):
            installed_source(path, path.relative_to(source).as_posix())

    material_checks = []
    for material in materials:
        name = material['name']
        assert material.get('revision') == REVISION, (theme, name, 'stale material revision')
        assert not material.get('emissive', False), (theme, name, 'emissive metadata')
        text = dump(f'materials/{theme}/{name}.vmat_c')
        assert 'global_lit_simple' in text, (name, 'unexpected shader')
        assert 'F_NORMAL_MAP = 1' in text and name + '_normal' in text, (name, 'normal map unavailable')
        assert name + '_reflectance' in text and 'm_name = "g_tSpecular"' in text, (name, 'reflection mask unavailable')
        assert 'F_FULLBRIGHT = 1' not in text and 'F_SELF_ILLUM = 1' not in text, (name, 'emission/fullbright enabled')
        assert material['normal_std'] > .0001 and material['color_std'] > .005, (name, 'flat texture payload')
        for parameter, expected in [('g_flSpecularIntensity', material['specular_intensity']),
                                    ('g_flBumpStrength', material['bump_strength']), ('g_flSpecularBloom', 0.)]:
            compiled_float(text, parameter, expected, name)
        assert 0 <= material['reflectance_mean'] <= 1 and material['reflectance_std'] >= 0, (name, 'invalid reflection metadata')
        assert 0 <= material['roughness_mean'] <= 1, (name, 'invalid preview roughness')
        for suffix in ('.vmat', '_color.png', '_normal.png', '_reflectance.png', '_roughness.png', '_metallic.png'):
            relative = f'materials/{theme}/{name}{suffix}'
            installed_source(source / relative, relative)
        material_checks.append(dict(name=name, shader='global_lit_simple.vfx', revision=material['revision'],
                                    specular_intensity=material['specular_intensity'], bump_strength=material['bump_strength'],
                                    specular_bloom=0., installed_source_match=True, emission=False))
    support_path = f'materials/{theme}/floor_support.vmat'
    installed_source(source / support_path, support_path)
    support = dump(support_path + '_c')
    assert 'dota.nav.walkable = 1.0' in support, (theme, 'continuous floor missing navigation attribute')
    # The approved courtyard uses a recessed mortar support (-0.75), not
    # nodraw: visible mortar in narrow board/slab joints is intentional.

    assert layout['interior'] == [2048, 2304], (theme, 'unexpected room dimensions')
    assert not layout.get('emissive', False), theme
    for placement in layout['placements']:
        if not placement.get('native', False):
            assert placement['name'] in models, (theme, 'unknown placement', placement['name'])
        group = placement.get('group', '').lower()
        if any(tag in group for tag in ('edge planting', 'exterior details', 'nature')):
            x, y = placement['origin'][:2]
            assert abs(x) > 850 or abs(y) > 970, (theme, 'nature/exterior prop enters central combat area', placement['name'], x, y)
    prefix = THEMES[theme]
    markers = {m['name']: m for m in layout['markers']}
    expected_markers = {prefix + '_entry', prefix + '_home'} | {f'{prefix}_spawn_{i:02}' for i in range(1, 9)}
    assert len(markers) == len(layout['markers']) and set(markers) == expected_markers, (theme, 'marker contract mismatch', list(markers))
    assert markers[prefix + '_entry']['origin'][1] > 900, (theme, 'arrival must remain at rear')
    assert markers[prefix + '_home']['origin'][2] > 0, (theme, 'home below floor')
    for i in range(1, 9):
        x, y, z = markers[f'{prefix}_spawn_{i:02}']['origin']
        assert abs(x) < 500 and abs(y) < 600 and z > 0, (theme, 'spawn outside central zone', i)

    review = theme + '_review'
    map_path, prefab_path = f'maps/{review}.vmap', f'maps/prefabs/{theme}.vmap'
    map_text = (source / map_path).read_text(encoding='utf-8-sig')
    prefab = (source / prefab_path).read_text(encoding='utf-8-sig')
    for path in (map_path, prefab_path):
        installed_source(source / path, path)
    assert 'info_particle_system' not in map_text and 'info_particle_system' not in prefab, (theme, 'unexpected particles')
    assert 'env_global_light' not in prefab, (theme, 'prefab unexpectedly owns map light')
    assert map_text.count('"classname" "string" "prop_static"') == len(layout['placements']), (theme, 'review instance count')
    assert prefab.count('"classname" "string" "prop_static"') == len(layout['placements']), (theme, 'prefab instance count')
    assert '"gridWidth" "int" "16"' in map_text, (theme, 'navigation grid width')
    for name in expected_markers:
        assert name in map_text and name in prefab, (theme, 'marker absent from map/prefab', name)
    assert map_meta['review'] == review and map_meta['prefab'] == 'prefabs/' + theme, (theme, 'map manifest paths')
    assert map_meta['instances'] == len(layout['placements']) and map_meta['customAssets'] == len(assets), (theme, 'map manifest asset counts')
    assert set(map_meta['markers']) == expected_markers and map_meta['emissiveEntities'] == 0, (theme, 'map manifest markers/emission')
    map_entries = verify_map_vpk(ROOT / f'maps/{review}.vpk')
    report = dict(status='PASS', theme=theme, custom_modules=len(assets), material_sets=len(materials),
                  material_revision=REVISION, instances=len(layout['placements']), interior=layout['interior'],
                  markers=len(markers), native_models=layout.get('native_models', []), emission=False,
                  walkable_support_variant=True, source2_bounds_and_dependencies=model_checks,
                  compiled_materials=material_checks, compiled_map=review + '.vpk', vpk_crc_entries=map_entries,
                  packed_blender_source=blend.name, installed_sources_match=True,
                  main_map_modified=False, runtime_verified=False,
                  runtime_note='Compiled resources and static layout verified; in-game appearance/navigation not claimed.')
    (out / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('THEMED_ROOM_VERIFY_PASS', theme, len(assets), 'models', len(materials), 'materials', len(layout['placements']), 'placements', flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--theme', choices=list(THEMES) + ['wood', 'attribute', 'greater_attribute'])
    args = parser.parse_args()
    wanted = args.theme
    if wanted and wanted not in THEMES:
        wanted += '_training_room'
    for theme in [wanted] if wanted else THEMES:
        verify(theme)


if __name__ == '__main__':
    main()
