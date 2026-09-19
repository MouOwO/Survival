"""Gold-room-only surfaces. Dota's simple shader has a scalar specular mask,
not a PBR roughness input; keep the Blender roughness separate and explicit.

Do not change wall_surface_materials: the other approved rooms use that module.
"""
import struct
import zlib
from pathlib import Path

import bpy
import numpy as np
from gold_room_geometry import PALETTE
from wall_surface_materials import SIZE, field, surface_maps

REVISION = 'gold_surface_response_v2'
STONE = {'stone', 'stone_light', 'stone_cool', 'rock'}
METAL = {'gold', 'bronze'}


def png(path, pixels):
    a = np.uint8(np.clip(pixels, 0, 1) * 255 + .5)
    if a.ndim == 2:
        a = np.repeat(a[:, :, None], 3, axis=2)
    h, w, _ = a.shape
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', w, h, 8, 2, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(b''.join(b'\x00' + row.tobytes() for row in a), 6)) + chunk(b'IEND', b''))


def normal_from_height(height, tile_width):
    """Height in Source units, image rows down: return a DirectX normal map."""
    scale = SIZE / (2 * tile_width)
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * scale
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * scale
    n = np.stack((-dx, -dy, np.ones_like(height)), axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * .5 + .5


def maps_for(key, col):
    source = 'wall_stone' if key in STONE else key
    color, normal, props = surface_maps(source, col, .22 if key == 'gold' else .60)
    # surface_maps differentiates top-down image rows too: already DirectX.
    # Both paths must flip G exactly once, at the Blender node, never here.
    rough = props[:, :, 0]
    if key == 'gold':
        color = np.clip(color * np.asarray([1.12, 1.22, 1.3]), 0, 1)
    if key.startswith('leaf') or key in ('flower', 'moss', 'teal', 'earth', 'mortar'):
        rough = np.full_like(rough, .90 if key == 'teal' else .84)
    reflectance = .018 + .30 * (1 - rough) ** 2
    metallic = np.full_like(rough, .55 if key in METAL else 0)
    intensity, bump = 1., 1.
    rng = np.random.default_rng(73109 + sum((i + 1) * ord(c) for i, c in enumerate(key)))
    broad, medium, fine = field(rng, 6), field(rng, 23), field(rng, 92)

    if key in STONE:
        # Broad worn faces + small mineral pits; relief is readable after mipmapping.
        # No painted lighting: normals and specular response follow the same surface.
        wear = np.clip((broad - .34) * 2.0, 0, 1)
        pit = np.clip((.35 - fine) * 3.7, 0, .7)
        vein = np.clip(1 - np.abs(medium - .45) / .016, 0, 1)
        cavity = np.clip(props[:, :, 2] * 1.1 + pit * .32, 0, 1)
        height = 1.65 * (broad - .5) + .83 * (medium - .5) + .19 * (fine - .5) - .35 * pit - .14 * vein
        normal = normal_from_height(height, 160)
        color = np.asarray(col)[None, None, :] * (.92 + .16 * (broad - .5) + .11 * (medium - .5) - .27 * cavity)[:, :, None]
        color += (.026 * wear - .018 * vein)[:, :, None]
        rough = np.clip(.78 - .22 * wear + .20 * cavity, .53, .90)
        reflectance = np.clip(.055 + .15 * wear - .055 * cavity, .035, .20)
        if key == 'rock':
            rough = np.clip(rough + .09, 0, .96)
            reflectance *= .65
        intensity, bump = 1.15, 1.
    elif key in METAL:
        # Tarnish is matte; exposed metal remains reflective. Never encode this
        # as RGB metal tint: global_lit_simple only samples reflectance.R.
        tarnish = np.clip((.60 - broad) * (3.2 if key == 'bronze' else 2.4), 0, .85)
        pits = np.clip((.30 - fine) * 3, 0, .55)
        polish = np.clip(1 - tarnish * 1.10 - pits * .30, .08, 1)
        base = np.asarray((.66, .49, .27) if key == 'bronze' else (.80, .63, .30))
        patina = np.asarray((.19, .32, .275) if key == 'bronze' else (.31, .245, .12))
        color = base[None, None, :] * (.92 + .16 * broad)[:, :, None]
        color = color * (1 - tarnish[:, :, None] * .76) + patina * tarnish[:, :, None] * .76
        # Short irregular tooling scratches, without repetitive full-length stripes.
        y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
        scratch = np.zeros_like(broad)
        for _ in range(75):
            cx, cy = rng.random(2)
            dist = np.abs(x - cx + (y - cy) * .24)
            line = np.clip(1 - dist / .0015, 0, 1) * np.clip(1 - np.abs(y - cy) / rng.uniform(.015, .09), 0, 1)
            scratch = np.maximum(scratch, line)
        color += scratch[:, :, None] * .045
        height = .19 * (medium - .5) + .036 * (fine - .5) - .09 * pits - .025 * scratch
        normal = normal_from_height(height, 75)
        rough = np.clip(.24 + .47 * tarnish + .16 * pits - .04 * scratch, .21, .79)
        reflectance = np.clip(.14 + (.57 if key == 'bronze' else .69) * polish, .12, .88)
        metallic = np.clip(.94 - .73 * tarnish, .15, .94)
        intensity, bump = (1.45 if key == 'bronze' else 1.65), 1.
    elif key == 'wood':
        n = normal * 2 - 1
        n[:, :, :2] *= 1.65
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        normal = n * .5 + .5
        rough = np.clip(rough - .08, .65, .93)
        reflectance = np.clip(.085 - .060 * props[:, :, 2] + .035 * broad, .018, .12)
    elif key == 'teal':
        # Fabric stays matte. Coarse folds, not shiny painted metal.
        height = .23 * (medium - .5) + .035 * (fine - .5)
        normal = normal_from_height(height, 90)
        rough = np.clip(.85 + .09 * broad, 0, .96)
        reflectance = .028 + .018 * broad
    return dict(color=np.clip(color, 0, 1), normal=normal, roughness=rough,
                reflectance=reflectance, metallic=metallic), intensity, bump


def configure_blender(mat, key, directory):
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    bs = nodes.new('ShaderNodeBsdfPrincipled')
    links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    for suffix, socket in [('color', 'Base Color'), ('roughness', 'Roughness'), ('metallic', 'Metallic')]:
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(str(directory / f'{key}_{suffix}.png'), check_existing=False)
        node.image.colorspace_settings.name = 'sRGB' if suffix == 'color' else 'Non-Color'
        links.new(node.outputs['Color'], bs.inputs[socket])
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(directory / f'{key}_normal.png'), check_existing=False)
    tex.image.colorspace_settings.name = 'Non-Color'
    separate, combine, invert = nodes.new('ShaderNodeSeparateColor'), nodes.new('ShaderNodeCombineColor'), nodes.new('ShaderNodeMath')
    invert.operation = 'SUBTRACT'
    invert.inputs[0].default_value = 1
    links.new(tex.outputs['Color'], separate.inputs[0])
    links.new(separate.outputs[0], combine.inputs[0])
    links.new(separate.outputs[2], combine.inputs[2])
    links.new(separate.outputs[1], invert.inputs[1])
    links.new(invert.outputs[0], combine.inputs[1])
    normal = nodes.new('ShaderNodeNormalMap')
    normal.uv_map = 'SurfaceUV'
    links.new(combine.outputs[0], normal.inputs['Color'])
    links.new(normal.outputs[0], bs.inputs['Normal'])
    mat.use_backface_culling = not (key.startswith('leaf') or key in ('teal', 'flower', 'moss'))
    mat['surface_revision'] = REVISION
    mat['engine_note'] = 'Source 2 scalar reflection mask; Blender roughness/metallic are preview parameters.'


def build_materials(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    materials, manifest = {}, []
    for key, col in PALETTE.items():
        maps, intensity, bump = maps_for(key, col)
        for suffix, pixels in maps.items():
            png(directory / f'{key}_{suffix}.png', pixels)
        canonical = f'materials/gold_training_room/{key}.vmat'
        mat = bpy.data.materials.get(canonical) or bpy.data.materials.new(canonical)
        configure_blender(mat, key, directory)
        materials[key] = mat
        entries = [('shader', 'global_lit_simple.vfx'), ('F_NORMAL_MAP', '1'), ('F_SPECULAR', '1'),
                   ('g_flSpecularIntensity', f'{intensity:.6f}'), ('g_flBumpStrength', f'{bump:.6f}'),
                   ('g_flSpecularBloom', '0.000000'), ('g_vColorTint', '[1 1 1 0]')]
        if not mat.use_backface_culling:
            entries.append(('F_RENDER_BACKFACES', '1'))
        for channel, suffix in [('Color', 'color'), ('Normal', 'normal'), ('Reflectance', 'reflectance')]:
            entries.append((f'Texture{channel}', f'materials/gold_training_room/{key}_{suffix}.png'))
        (directory / f'{key}.vmat').write_text('"Layer0"\n{\n' + ''.join(f'    "{k}" "{v}"\n' for k, v in entries) + '}\n', encoding='utf-8')
        manifest.append(dict(name=key, revision=REVISION, size=SIZE, color_std=float(np.std(maps['color'])),
                             normal_std=float(np.std(maps['normal'][:, :, :2])), roughness_mean=float(np.mean(maps['roughness'])),
                             reflectance_mean=float(np.mean(maps['reflectance'])), reflectance_std=float(np.std(maps['reflectance'])),
                             specular_intensity=intensity, bump_strength=bump, emissive=False,
                             engine_shader='global_lit_simple.vfx', engine_reflectance_channel='linear R',
                             roughness_use='Blender preview; Dota simple shader has no roughness input'))
        print('GOLD_MATERIAL', key, flush=True)
    return materials, manifest
