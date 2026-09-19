"""Ascension arena surfaces with the approved Source 2 reflection contract.

Run with Blender Python. Source normal maps are DirectX; configure_blender
flips green exactly once. Dota reads scalar linear reflectance.R, while
roughness and metallic images are explicitly Blender preview inputs.
"""
from pathlib import Path
import json
import math
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ascension_arena_spec import NAMESPACE, PALETTE, REVISION
from gold_room_materials import maps_for as gold_maps, png, normal_from_height
from gold_room_materials import configure_blender as configure_gold_blender
from training_room_materials import timber_maps, theme_maps
from wall_surface_materials import SIZE, field


FAMILY = {
    'earth': 'packed earth', 'earth_edge': 'packed earth edge', 'mortar': 'matte mortar',
    'wood': 'longitudinal wood grain', 'wood_light': 'exposed longitudinal wood grain',
    'wood_end': 'radial end grain', 'stone': 'weathered stone', 'stone_light': 'light weathered stone',
    'stone_dark': 'dark weathered stone', 'dressed_stone': 'dressed stone', 'ivory': 'ivory limestone',
    'jade': 'polished green jade', 'jade_light': 'pale jade', 'crystal': 'blue crystal',
    'mineral_stone': 'mineral stone', 'iron': 'forged iron', 'bronze': 'aged bronze',
    'gold': 'polished gold', 'silver': 'aged silver', 'moss': 'matte moss',
    'cloud': 'blue-white cloud billows', 'cloud_shadow': 'blue cloud shadows',
    'cloud_pearl': 'pearl cloud billows',
}


def scale_normal(normal, strength):
    n = normal * 2 - 1
    n[:, :, :2] *= strength
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * .5 + .5


def earth_maps(key, col):
    rng = np.random.default_rng(75612)
    broad, medium, fine = field(rng, 7), field(rng, 27), field(rng, 138)
    crack_field = field(rng, 13)
    crack = np.exp(-np.abs(crack_field - .505) / .010) * np.clip((.61 - broad) * 3.1, 0, .78)
    grain = np.clip((fine - .66) * 3.0, 0, .6)
    pit = np.clip((.32 - fine) * 3.5, 0, .65)
    color = np.asarray(col)[None, None, :] * (.91 + .19 * broad + .09 * (medium - .5) - .29 * crack - .065 * pit)[:, :, None]
    color += grain[:, :, None] * np.asarray((.082, .070, .050))
    height = .34 * (broad - .5) + .27 * (medium - .5) + .13 * (fine - .5) - .28 * crack - .10 * pit + .11 * grain
    return dict(color=np.clip(color, 0, 1), normal=normal_from_height(height, 192),
                roughness=np.clip(.87 + .065 * pit + .04 * broad, 0, .98),
                reflectance=.018 + .017 * broad - .008 * pit,
                metallic=np.zeros_like(broad)), .95, 1., 192


def cloud_maps(key, col):
    """Scalloped billows and readable curled ribbons, independent from stone."""
    rng = np.random.default_rng(93184)
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
    broad, medium, fine = field(rng, 5), field(rng, 13), field(rng, 54)
    # Keep middle-sized contours visible at gameplay scale. The earlier broad
    # Gaussian field blurred into a smooth slab after mipmapping and denoising.
    xx = x + .018 * np.sin(y * math.tau * 2) + .018 * (broad - .5)
    yy = y + .012 * np.sin(x * math.tau * 3) + .013 * (medium - .5)
    mask, billow, shoulder = np.zeros_like(x), np.zeros_like(x), np.zeros_like(x)
    for _ in range(32):
        cx, cy = rng.random(2)
        rx, ry = rng.uniform(.062, .11), rng.uniform(.039, .073)
        for lx, ly, size in ((0, 0, 1), (-.050, -.007, .64), (.052, .005, .75),
                             (-.024, .030, .58), (.031, .028, .50)):
            dx = (xx - cx - lx + .5) % 1 - .5
            dy = (yy - cy - ly + .5) % 1 - .5
            radius = np.sqrt((dx / (rx * size)) ** 2 + (dy / (ry * size)) ** 2)
            edge = np.clip((1.03 - radius) / .18, 0, 1)
            edge = edge * edge * (3 - 2 * edge)
            mask = np.maximum(mask, edge)
            billow = np.maximum(billow, np.clip(1 - radius * radius, 0, 1) ** .65)
            shoulder = np.maximum(shoulder, np.exp(-((radius - .83) / .10) ** 2) * edge)
    curl, curl_under = np.zeros_like(x), np.zeros_like(x)
    for index, (cx, cy) in enumerate(((.16, .22), (.61, .58), (.32, .82), (.82, .13), (.80, .86), (.07, .55))):
        dx, dy = (xx - cx + .5) % 1 - .5, (yy - cy + .5) % 1 - .5
        radius = np.sqrt(dx * dx + dy * dy)
        angle = np.arctan2(dy, dx) + index * .6
        distance = np.ones_like(x)
        for turn in (-1, 0, 1):
            spiral_radius = .014 + .015 * (angle + math.pi + turn * math.tau)
            distance = np.minimum(distance, np.where(spiral_radius > 0, np.abs(radius - spiral_radius), 1))
        fade = np.clip((.137 - radius) / .036, 0, 1)
        curl = np.maximum(curl, np.exp(-(distance / .0052) ** 2) * fade)
        curl_under = np.maximum(curl_under, np.exp(-(distance / .0135) ** 2) * fade)
    # These are blue/pearl pigments, not baked light or emissive white. Surface
    # shading still comes from the scene lights, slight relief and reflection.
    low = np.asarray(col) * np.asarray((.79, .84, .935))
    high = np.minimum(np.asarray(col) * np.asarray((1.075, 1.04, 1.00)), .985)
    if key == 'cloud_pearl':
        low = np.asarray((.76, .805, .915))
        high = np.asarray((.985, .978, .958))
    white = np.clip(.45 * mask + .58 * billow + .065 * shoulder, 0, 1)
    color = low[None, None, :] * (1 - white[:, :, None]) + high[None, None, :] * white[:, :, None]
    # A pale blue under-ribbon and narrow cream curl preserve the reference's
    # painted cloud motif. They are pigment, never a glow or particle layer.
    blue = low * np.asarray((.99, .975, 1.025))
    color = color * (1 - .30 * curl_under[:, :, None]) + blue * (.30 * curl_under[:, :, None])
    cream = np.minimum(high + np.asarray((.018, .012, .0)), .99)
    color = color * (1 - .82 * curl[:, :, None]) + cream * (.82 * curl[:, :, None])
    color += (.005 * (medium - .5))[:, :, None]
    height = .19 * billow + .105 * curl + .033 * shoulder + .017 * (medium - .5) + .005 * (fine - .5)
    roughness = np.clip(.62 - .12 * white + .022 * (fine - .5), .45, .65)
    reflectance = .105 + .08 * white + .023 * curl
    if key == 'cloud_pearl':
        roughness -= .035
        reflectance += .035
    return dict(color=np.clip(color, 0, .99), normal=normal_from_height(height, 350),
                roughness=roughness, reflectance=reflectance, metallic=np.zeros_like(x)), 1.22, 1., 350


def arena_maps(key, col):
    if key in ('earth', 'earth_edge'):
        return earth_maps(key, col)
    if key.startswith('cloud'):
        return cloud_maps(key, col)
    if key in ('wood', 'wood_light', 'wood_end'):
        maps, intensity, bump = timber_maps(key, col)
        return maps, intensity, bump, 112
    if key in ('jade', 'jade_light', 'crystal', 'mineral_stone'):
        maps, intensity, bump = theme_maps('attribute', 'mineral', col)
        if key == 'mineral_stone':
            stone, _, _ = gold_maps('stone', col)
            maps['color'] = maps['color'] * .68 + stone['color'] * .32
            maps['normal'] = stone['normal']
            maps['roughness'] = np.clip(maps['roughness'] + .18, .44, .83)
            maps['reflectance'] *= .68
            return maps, 1.3, bump, 160
        if key == 'crystal':
            maps['roughness'] = np.clip(maps['roughness'] - .05, .20, .58)
            maps['reflectance'] = np.clip(maps['reflectance'] * 1.16, 0, .60)
            maps['normal'] = scale_normal(maps['normal'], .75)
        return maps, intensity, bump, 95
    if key in ('iron', 'silver'):
        maps, intensity, bump = theme_maps('attribute', 'iron' if key == 'iron' else 'metal_light', col)
        return maps, intensity, bump, 95
    if key in ('stone', 'stone_light', 'stone_dark', 'dressed_stone', 'ivory'):
        maps, intensity, bump = gold_maps('stone_light' if key in ('stone_light', 'ivory') else 'stone', col)
        if key in ('dressed_stone', 'ivory'):
            maps['normal'] = scale_normal(maps['normal'], .65 if key == 'dressed_stone' else .46)
            maps['roughness'] = np.clip(maps['roughness'] - .09, .43, .88)
            maps['reflectance'] = np.clip(maps['reflectance'] * 1.16, .035, .25)
        return maps, intensity, bump, 160
    maps, intensity, bump = gold_maps(key, col)
    if key in ('bronze', 'gold'):
        base = np.asarray((.66, .49, .27) if key == 'bronze' else (.80, .63, .30))
        maps['color'] = np.clip(maps['color'] * (np.asarray(col) / base)[None, None, :], 0, 1)
    return maps, intensity, bump, 75


def configure_blender(mat, key, destination):
    configure_gold_blender(mat, key, Path(destination))
    mat['surface_revision'] = REVISION
    mat['surface_family'] = FAMILY[key]
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            node.inputs['Emission Strength'].default_value = 0


def write_materials(destination: Path) -> list[dict]:
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    assert set(FAMILY) == set(PALETTE), 'Every palette key requires an explicit surface-family mapping'
    manifest = []
    for key, col in PALETTE.items():
        maps, intensity, bump, tile = arena_maps(key, col)
        assert set(maps) == {'color', 'normal', 'roughness', 'reflectance', 'metallic'}, key
        for suffix, pixels in maps.items():
            assert pixels.shape[:2] == (SIZE, SIZE) and np.isfinite(pixels).all(), (key, suffix)
            assert pixels.min() >= 0 and pixels.max() <= 1, (key, suffix, float(pixels.min()), float(pixels.max()))
            png(destination / f'{key}_{suffix}.png', pixels)
        entries = [('shader', 'global_lit_simple.vfx'), ('F_NORMAL_MAP', '1'), ('F_SPECULAR', '1'),
                   ('g_flSpecularIntensity', f'{intensity:.6f}'), ('g_flBumpStrength', f'{bump:.6f}'),
                   ('g_flSpecularBloom', '0.000000'), ('g_vColorTint', '[1 1 1 0]')]
        if key == 'moss':
            entries.append(('F_RENDER_BACKFACES', '1'))
        entries += [(f'Texture{channel}', f'materials/{NAMESPACE}/{key}_{suffix}.png')
                    for channel, suffix in [('Color', 'color'), ('Normal', 'normal'), ('Reflectance', 'reflectance')]]
        (destination / f'{key}.vmat').write_text('"Layer0"\n{\n' + ''.join(f'    "{k}" "{v}"\n' for k, v in entries) + '}\n', encoding='utf-8')
        manifest.append(dict(name=key, revision=REVISION, size=SIZE, surface_family=FAMILY[key], recommended_uv_tile=tile,
                             color_std=float(np.std(maps['color'])), normal_std=float(np.std(maps['normal'][:, :, :2])),
                             roughness_mean=float(np.mean(maps['roughness'])), reflectance_mean=float(np.mean(maps['reflectance'])),
                             reflectance_std=float(np.std(maps['reflectance'])), specular_intensity=intensity, bump_strength=bump,
                             emissive=False, engine_shader='global_lit_simple.vfx', engine_reflectance_channel='linear R',
                             normal_convention='DirectX; flip G once in Blender only',
                             roughness_use='Blender preview only; Dota simple shader has no roughness input'))
        print('ASCENSION_MATERIAL', key, FAMILY[key], flush=True)
    out = destination.parents[2] if destination.name == NAMESPACE and destination.parent.name == 'materials' and destination.parent.parent.name == 'source' else destination
    (out / 'material_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return manifest


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    manifest = write_materials(root / f'output/{NAMESPACE}/source/materials/{NAMESPACE}')
    print('ASCENSION_MATERIALS_COMPLETE', len(manifest), 'non-emissive materials', flush=True)
