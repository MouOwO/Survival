"""Validate installed ascension models, compiled materials and review-map VPK.

Run with ordinary Python; no Blender dependency. PASS describes asset/source and
static spatial checks, not an in-game appearance or navigation playtest.
"""
import json
import math
import re
import subprocess
from pathlib import Path

from ascension_arena_spec import NAMESPACE, REVISION, PALETTE, FOOTPRINT, LAYER_HEIGHT, LAYER_INSET, stage
from asset_validation import installed_source, verify_map_vpk

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output' / NAMESPACE
SOURCE = OUT / 'source'
INSPECTOR = ROOT.parents[1] / 'bin/win64/resourceinfo.exe'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def dump(relative):
    return subprocess.check_output([str(INSPECTOR), '-i', str(ROOT / relative), '-all']).decode('utf-8', errors='replace')


def vector(text, name):
    match = re.search(re.escape(name) + r' = \[ ([^\]]+) \]', text)
    assert match, ('missing compiled vector', name)
    values = [float(v) for v in match[1].split(',')]
    assert len(values) == 3 and all(math.isfinite(v) for v in values), (name, values)
    return values


def near(a, b, tolerance=.001):
    return abs(float(a)-float(b)) <= tolerance


def equal_vectors(a, b, tolerance=.001):
    return len(a) == len(b) and all(near(x, y, tolerance) for x, y in zip(a, b))


def compiled_float(text, parameter, expected, key):
    match = re.search(r'm_name = "' + re.escape(parameter) + r'"\s+m_flValue = ([\d.eE+-]+)', text)
    assert match and near(float(match[1]), expected), (key, 'wrong compiled float', parameter, expected)


def check_stage_asset(asset):
    """Check the stage contract and explicitly recorded authored layer ranges."""
    meta = asset['meta']
    rank = meta['rank']
    wanted = stage(rank)
    for key in ('rank', 'name', 'layers', 'footprint', 'deck_z', 'deck_size', 'clear_combat_size', 'float_preview_offset', 'review_xy'):
        assert meta[key] == wanted[key], (asset['name'], key, meta[key], wanted[key])
    assert asset['name'] == wanted['name'] and asset['label'] == wanted['label'], asset['name']
    assert not asset.get('emissive', False) and not meta.get('emissive', False), asset['name']
    assert asset['collision_count'] == asset['collision_hulls'] == len(asset['collision']) == rank, (asset['name'], 'collision count differs from counted layers')
    bounds = asset['bounds']
    assert len(bounds) == 2 and all(len(v) == 3 for v in bounds), asset['name']
    for axis, maximum in enumerate(FOOTPRINT):
        assert bounds[0][axis] >= -maximum/2-.04 and bounds[1][axis] <= maximum/2+.04, (asset['name'], 'outside centered footprint', bounds)
        assert 0 < bounds[1][axis]-bounds[0][axis] <= maximum+.04, (asset['name'], 'footprint too large', bounds)
    assert bounds[0][2] >= -.05 and bounds[1][2] >= meta['deck_z']-.4, (asset['name'], 'incorrect floor/deck extent')
    assert asset['triangles'] > 0 and asset['vertices'] > 0, asset['name']
    layer_bounds, layers = meta['layer_bounds'], meta['layer_geometry']
    assert len(layer_bounds) == len(layers) == rank, (asset['name'], 'recorded geometry layer count')
    last_vertex = last_face = 0
    for index, (bound, layer, collision) in enumerate(zip(layer_bounds, layers, asset['collision'])):
        width, depth = (FOOTPRINT[a]-2*index*LAYER_INSET for a in (0, 1))
        expected = [[-width/2, -depth/2, index*LAYER_HEIGHT], [width/2, depth/2, (index+1)*LAYER_HEIGHT]]
        assert all(equal_vectors(a, b) for a, b in zip(bound, expected)), (asset['name'], index, 'layer envelope')
        assert layer['index'] == index+1 and layer['bounds'] == bound, (asset['name'], index, 'layer range metadata')
        assert layer['material'] in PALETTE and layer['shape'] in ('masonry course', 'rounded solid cloud course'), (asset['name'], index, 'unexpected layer shape/material')
        observed = layer['actual_bounds']
        assert len(observed) == 2 and all(len(v) == 3 for v in observed), (asset['name'], index, 'missing measured layer bounds')
        for axis in range(3):
            assert expected[0][axis]-.04 <= observed[0][axis] < observed[1][axis] <= expected[1][axis]+.04, (asset['name'], index, 'measured layer leaves its envelope', observed)
        assert observed[1][2]-observed[0][2] >= LAYER_HEIGHT-.7, (asset['name'], index, 'layer is only a thin trim rather than a real course')
        assert observed[1][0]-observed[0][0] >= width-16 and observed[1][1]-observed[0][1] >= depth-16, (asset['name'], index, 'layer does not span the arena footprint')
        v0, v1 = layer['vertices']
        f0, f1 = layer['faces']
        assert 0 <= last_vertex <= v0 < v1 <= asset['vertices'], (asset['name'], index, 'empty/overlapping vertex ranges')
        assert 0 <= last_face <= f0 < f1 <= asset['triangles'], (asset['name'], index, 'empty/overlapping face ranges')
        last_vertex, last_face = v1, f1
        assert equal_vectors(collision['center'], [0, 0, (index+.5)*LAYER_HEIGHT]), (asset['name'], index, 'collision height')
        assert equal_vectors(collision['size'], [width, depth, LAYER_HEIGHT]), (asset['name'], index, 'collision layer size')
    cloud_fraction = meta['cloud_deck_area_fraction']
    assert 0 <= cloud_fraction <= 1, (asset['name'], 'invalid cloud coverage')
    if rank < 8:
        assert cloud_fraction == 0 and all(layer['shape'] == 'masonry course' for layer in layers), (asset['name'], 'cloud introduced before eighth rank')
    elif rank == 8:
        assert 0 < cloud_fraction < .75 and layers[0]['shape'] == 'rounded solid cloud course', (asset['name'], 'eighth-rank material transition missing')
    else:
        assert cloud_fraction > .7 and all(layer['shape'] == 'rounded solid cloud course' for layer in layers), (asset['name'], 'upper ranks must be real cloud decks')
        if rank == 10:
            assert cloud_fraction == 1, 'Tenth rank must have a cloud battle surface, not a stone deck with edge cloud decoration'
    return dict(rank=rank, name=asset['name'], layers=rank, footprint=list(FOOTPRINT), deck_z=meta['deck_z'],
                layer_geometry_ranges_checked=True, measured_layer_bounds_checked=True,
                collision_hulls=asset['collision_count'], cloud_deck_area_fraction=cloud_fraction)


def mesh_positions(text):
    """Read actual serialized world-mesh position streams in their write order."""
    streams = re.finditer(r'"name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*\[([^\]]*)\]', text)
    return [[[float(x) for x in match[1].split()] for match in re.finditer(r'"([^\"]+)"', stream[1])] for stream in streams]


def assert_support(points, placement):
    assert len(points) == 8, (placement['name'], 'support should be a closed box')
    actual = [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]]
    x, y, _ = placement['origin']
    w, d = placement['support_size']
    expected = [[x-w/2, y-d/2, placement['support_bottom']], [x+w/2, y+d/2, placement['support_top']]]
    assert all(equal_vectors(a, b) for a, b in zip(actual, expected)), (placement['name'], 'actual serialized support bounds', actual, expected)
    assert placement['support_top'] < placement['world_deck_z'], (placement['name'], 'support passes above deck')
    assert near(placement['world_deck_z']-placement['support_top'], .75), (placement['name'], 'wrong recessed support')
    assert near(placement['support_top']-placement['support_bottom'], 4), (placement['name'], 'wrong support thickness')


def check_review_spacing(layout):
    """Full arena footprints must fit the map and stay separate after resizing."""
    limits = [[-2048, -2048], [2048, 2048]]
    assert layout['review_bounds'] == limits, 'Unexpected review map limits'
    assert layout['columns'] == 2 and layout['rows'] == 5
    envelopes = []
    clearance = math.inf
    for placement in layout['placements']:
        assert placement['footprint'] == list(FOOTPRINT), (placement['name'], 'stale placement footprint')
        x, y = placement['origin'][:2]
        w, d = placement['footprint']
        low, high = [x-w/2, y-d/2], [x+w/2, y+d/2]
        assert all(limits[0][axis] <= low[axis] < high[axis] <= limits[1][axis] for axis in (0, 1)), (placement['name'], 'arena outside review map', low, high)
        for other_name, other_low, other_high in envelopes:
            overlap = all(low[axis] < other_high[axis] and other_low[axis] < high[axis] for axis in (0, 1))
            assert not overlap, (placement['name'], other_name, 'arena footprints overlap')
            gap = [max(low[axis]-other_high[axis], other_low[axis]-high[axis], 0) for axis in (0, 1)]
            clearance = min(clearance, math.hypot(*gap))
        envelopes.append((placement['name'], low, high))
    occupied = [[min(low[axis] for _, low, _ in envelopes) for axis in (0, 1)],
                [max(high[axis] for _, _, high in envelopes) for axis in (0, 1)]]
    assert all(equal_vectors(a, b) for a, b in zip(occupied, layout['occupied_bounds'])), 'Incorrect occupied bounds report'
    assert near(clearance, layout['min_footprint_clearance']), 'Incorrect arena clearance report'
    return dict(occupied_bounds=occupied, min_footprint_clearance=clearance, overlap=False, map_bounds=limits)


def check_navigation_mask(text, layout):
    """The serialized 64-unit grid must expand with each clear combat rectangle."""
    match = re.search(r'"gridnavFlags" "\w+_array"\s*\[([^\]]*)\]', text)
    assert match, 'Missing serialized navigation mask'
    flags = [int(value) for value in re.findall(r'"([^\"]+)"', match[1])]
    assert len(flags) == 64*64, 'Unexpected navigation mask size'
    per_rank = {str(p['rank']): 0 for p in layout['placements']}
    for iy in range(64):
        for ix in range(64):
            x, y = -2048+ix*64+32, -2048+iy*64+32
            arenas = [p for p in layout['placements'] if
                      abs(x-p['origin'][0]) < p['clear_combat_size'][0]/2 and
                      abs(y-p['origin'][1]) < p['clear_combat_size'][1]/2]
            assert len(arenas) <= 1, ('Overlapping combat regions', x, y)
            assert flags[iy*64+ix] == (0 if arenas else 1), ('Navigation mask differs from resized combat rectangles', x, y)
            if arenas:
                per_rank[str(arenas[0]['rank'])] += 1
    assert all(value > 0 for value in per_rank.values()), 'Arena with no open navigation cells'
    assert per_rank == {str(rank): int(count) for rank, count in layout['open_cells_by_rank'].items()}, 'Stale per-arena open-cell counts'
    assert sum(per_rank.values()) == layout['open_grid_cells'], 'Stale total open-cell count'
    return per_rank


def check_layout(assets, layout, map_meta):
    assert len(layout['placements']) == len(layout['markers']) == len(layout['prefabs']) == len(assets) == 10
    assert layout['footprint'] == list(FOOTPRINT) and layout['layer_height'] == LAYER_HEIGHT
    assert layout['review'] == 'ascension_arenas_review' and not layout['main_map_modified']
    map_path = 'maps/ascension_arenas_review.vmap'
    text = (SOURCE / map_path).read_text(encoding='utf-8-sig')
    installed_source(SOURCE / map_path, map_path)
    assert text.count('"classname" "string" "prop_static"') == 10, 'Review map must contain only ten authored arena models'
    assert text.count('"classname" "string" "env_global_light"') == 1
    assert 'info_particle_system' not in text and '"gridWidth" "int" "16"' in text
    refs = re.findall(r'"model" "string" "([^"]+)"', text)
    assert sorted(refs) == [f'models/{NAMESPACE}/arena_{i:02}.vmdl' for i in range(1, 11)], ('Unexpected model in review map', refs)
    positions = mesh_positions(text)
    assert len(positions) == 11, ('Ten deck supports plus one review backdrop expected', len(positions))
    assert max(p[2] for p in positions[-1]) == layout['base_z']-1, 'Review backdrop must stay beneath grounded arenas'
    spacing = check_review_spacing(layout)
    navigation_cells = check_navigation_mask(text, layout)
    for index, (asset, placement, marker, prefab) in enumerate(zip(assets, layout['placements'], layout['markers'], layout['prefabs'])):
        rank = index+1
        meta = asset['meta']
        assert placement['rank'] == rank and placement['name'] == asset['name'], 'Stage placement order'
        expected_stage = stage(rank)
        assert meta['review_xy'] == expected_stage['review_xy'], (asset['name'], 'stale specification arrangement')
        expected_origin = list(expected_stage['review_xy'])+[128+expected_stage['float_preview_offset']]
        assert equal_vectors(placement['origin'], expected_origin), (asset['name'], 'review arrangement')
        assert placement['deck_size'] == meta['deck_size'] and placement['clear_combat_size'] == meta['clear_combat_size']
        assert near(placement['world_deck_z'], expected_origin[2]+meta['deck_z'])
        assert placement['support_size'] == meta['deck_size'] and placement['collision_count'] == asset['collision_count']
        assert_support(positions[index], placement)
        assert marker['name'] == f'ascension_arena_{rank:02}_center'
        assert equal_vectors(marker['origin'], expected_origin[:2]+[placement['world_deck_z']+24])
        assert marker['name'] in text
        assert prefab['path'] == f'prefabs/ascension_arena_{rank:02}' and prefab['origin'] == [0, 0, 0]
        assert prefab['preview_offset_baked'] is False and prefab['placement']['origin'] == [0, 0, 0]
        assert prefab['placement']['footprint'] == list(FOOTPRINT)
        assert near(prefab['placement']['world_deck_z'], meta['deck_z'])
        prefab_path = 'maps/'+prefab['path']+'.vmap'
        installed_source(SOURCE / prefab_path, prefab_path)
        prefab_text = (SOURCE / prefab_path).read_text(encoding='utf-8-sig')
        assert prefab_text.count('"classname" "string" "prop_static"') == 1
        assert f'models/{NAMESPACE}/{asset["name"]}.vmdl' in prefab_text
        assert 'env_global_light' not in prefab_text and 'world_bounds' not in prefab_text and 'info_particle_system' not in prefab_text
        assert 'info_player_start' not in prefab_text and 'DotaTileGrid' not in prefab_text
        supports = mesh_positions(prefab_text)
        assert len(supports) == 1
        assert_support(supports[0], prefab['placement'])
        assert prefab['marker']['name'] in prefab_text
    assert map_meta['review'] == layout['review'] and map_meta['instances'] == map_meta['customAssets'] == 10
    assert map_meta['prefabs'] == [p['path'] for p in layout['prefabs']]
    assert map_meta['markers'] == [m['name'] for m in layout['markers']]
    assert map_meta['footprint'] == list(FOOTPRINT) and map_meta['occupiedBounds'] == layout['occupied_bounds']
    assert map_meta['reviewBounds'] == layout['review_bounds'] and near(map_meta['minFootprintClearance'], layout['min_footprint_clearance'])
    assert map_meta['openGridCells'] == layout['open_grid_cells']
    assert map_meta['emissiveEntities'] == 0 and not map_meta['mainMapModified']
    return dict(review_map=layout['review'], prefabs=10, supports=10, support_recess=.75,
                separate_deck_heights=True, footprint_spacing=spacing, open_cells_by_rank=navigation_cells,
                open_grid_cells=layout['open_grid_cells'], runtime_navigation_verified=False)


def main():
    assets = read_json(OUT / 'asset_manifest.json')
    materials = read_json(OUT / 'material_manifest.json')
    layout = read_json(OUT / 'layout.json')
    map_meta = read_json(OUT / 'map_manifest.json')
    assert len(assets) == 10 and [a['name'] for a in assets] == [f'arena_{i:02}' for i in range(1, 11)]
    assert {m['name'] for m in materials} == set(PALETTE) and len(materials) == len(PALETTE)
    blend = OUT / 'ascension_arenas.blend'
    assert blend.is_file() and blend.stat().st_size > 1024, 'Packed Blender source missing'
    model_checks = []
    for asset in assets:
        check = check_stage_asset(asset)
        text = dump(f'models/{NAMESPACE}/{asset["name"]}.vmdl_c')
        actual = [vector(text, 'm_vMinBounds'), vector(text, 'm_vMaxBounds')]
        error = max(abs(v-w) for row, wanted in zip(actual, asset['bounds']) for v, w in zip(row, wanted))
        assert error < .04, (asset['name'], 'compiled bounds/orientation/scale', error)
        assert '--- vmdl block PHYS' in text, (asset['name'], 'compiled collision missing')
        for material in asset['materials']:
            assert material.startswith(f'materials/{NAMESPACE}/') and material in text, (asset['name'], 'missing material dependency', material)
        vmdl = (SOURCE / f'models/{NAMESPACE}/{asset["name"]}.vmdl').read_text(encoding='utf-8-sig')
        assert vmdl.count('_class="PhysicsHullFile"') == asset['collision_count'], (asset['name'], 'source model collision count')
        check.update(bounds_error=error, compiled_physics=True, triangles=asset['triangles'])
        model_checks.append(check)
    for file in (SOURCE / 'models' / NAMESPACE).rglob('*'):
        if file.is_file() and file.suffix.lower() in ('.vmdl', '.fbx', '.obj'):
            installed_source(file, file.relative_to(SOURCE).as_posix())
    material_checks = []
    for material in materials:
        key = material['name']
        assert material['revision'] == REVISION and not material['emissive'], (key, 'material revision/emission')
        assert material['engine_reflectance_channel'] == 'linear R', (key, 'wrong scalar reflection contract')
        assert material['normal_std'] > .000001 and material['color_std'] > .001, (key, 'flat texture data')
        text = dump(f'materials/{NAMESPACE}/{key}.vmat_c')
        assert 'global_lit_simple' in text and 'F_NORMAL_MAP = 1' in text and 'F_SPECULAR = 1' in text, (key, 'shader features')
        for channel in ('normal', 'reflectance'):
            assert key+'_'+channel in text, (key, 'compiled texture missing', channel)
        specular = re.search(r'm_name = "g_tSpecular"\s+m_pValue = resource:"([^"]+)"', text)
        assert specular and f'/{key}_reflectance_' in specular[1], (key, 'reflection mask not bound to g_tSpecular')
        assert (ROOT / (specular[1]+'_c')).is_file(), (key, 'compiled reflection texture missing')
        assert 'F_FULLBRIGHT = 1' not in text and 'F_SELF_ILLUM = 1' not in text, (key, 'unexpected emission')
        for parameter, value in [('g_flSpecularIntensity', material['specular_intensity']), ('g_flBumpStrength', material['bump_strength']), ('g_flSpecularBloom', 0.)]:
            compiled_float(text, parameter, value, key)
        for suffix in ('.vmat', '_color.png', '_normal.png', '_reflectance.png', '_roughness.png', '_metallic.png'):
            relative = f'materials/{NAMESPACE}/{key}{suffix}'
            installed_source(SOURCE / relative, relative)
        material_checks.append(dict(name=key, shader='global_lit_simple.vfx', normal=True,
                                    specular_texture=specular[1], reflectance_channel='linear R',
                                    specular_intensity=material['specular_intensity'], emission=False))
    support_relative = f'materials/{NAMESPACE}/floor_support.vmat'
    installed_source(SOURCE / support_relative, support_relative)
    support = dump(support_relative+'_c')
    assert 'dota.nav.walkable = 1.0' in support and 'mapbuilder.nodraw = 1.0' in support, 'Support surface must be walkable and invisible'
    spatial = check_layout(assets, layout, map_meta)
    vpk_entries = verify_map_vpk(ROOT / 'maps/ascension_arenas_review.vpk')
    report = dict(status='PASS', revision=REVISION, namespace=NAMESPACE, custom_models=10,
                  material_sets=len(materials), prefab_count=10, footprint=list(FOOTPRINT),
                  layer_height=LAYER_HEIGHT, height_status='first modeling pass; adjustable after visual review',
                  source2_bounds_and_dependencies=model_checks, compiled_materials=material_checks,
                  spatial=spatial, compiled_map='ascension_arenas_review.vpk', vpk_crc_entries=vpk_entries,
                  packed_blender_source=blend.name, installed_sources_match=True, main_map_modified=False,
                  runtime_verified=False, runtime_note='Compiled assets and static deck supports checked; in-game appearance, movement and gameplay not claimed.')
    (OUT / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('ASCENSION_ARENAS_VERIFY_PASS', len(assets), 'models', len(materials), 'materials', len(layout['prefabs']), 'prefabs', flush=True)
    return report


if __name__ == '__main__':
    main()
