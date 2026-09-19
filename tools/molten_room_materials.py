"""Molten Core surface response: porous basalt, aged copper and cooled crust.

Source 2 global_lit_simple uses a linear scalar reflection mask, not PBR
roughness. The roughness/metallic maps are retained for the packed Blender file.
"""
from pathlib import Path
import bpy
import numpy as np
from molten_room_geometry import PALETTE
from molten_surface_materials import mineral_cells
from wall_surface_materials import SIZE, field
from gold_room_materials import png, normal_from_height

REVISION = 'molten_surface_response_v2'
STONE = {k for k in PALETTE if k.startswith('stone')} | {'rock', 'charred'}
METAL = {'bronze', 'copper', 'iron', 'patina'}


def maps_for(key, col):
    rng = np.random.default_rng(19631 + sum((i + 1) * ord(c) for i, c in enumerate(key)))
    broad, medium, fine = field(rng, 6), field(rng, 25), field(rng, 96)
    color = np.asarray(col)[None, None, :] * (.86 + .23 * broad)[:, :, None]
    rough = .86 + .10 * broad
    reflectance = .022 + .026 * broad
    metallic = np.zeros_like(broad)
    height = .17 * (medium - .5) + .035 * (fine - .5)
    intensity, tile = 1., 90
    if key in STONE:
        seam, tone = mineral_cells(9160 + sum(ord(c) for c in key), 6)
        pores = np.clip((.37 - fine) * 3.5, 0, .72)
        worn = np.clip((broad - .29) * 1.85, 0, 1)
        cavity = np.clip(seam * .72 + pores * .45, 0, 1)
        # Large cleaved planes and small volcanic pores react differently to
        # light; cracks are narrow, with no orange paint or baked highlights.
        height = 1.42 * (broad - .5) + .84 * (medium - .5) + .20 * (fine - .5) + .18 * tone - .30 * seam - .37 * pores
        color *= (.93 + .16 * tone + .10 * (medium - .5) - .18 * cavity)[:, :, None]
        rough = np.clip(.84 - .23 * worn + .18 * cavity, .56, .97)
        reflectance = np.clip(.042 + .135 * worn - .042 * cavity, .023, .18)
        if key in ('charred', 'stone_scorched'):
            soot = np.clip((.64 - broad) * 2.1, 0, .9)
            color *= (1 - .20 * soot)[:, :, None]
            rough = np.clip(rough + .13 * soot, 0, .99)
            reflectance *= 1 - .72 * soot
        if key == 'rock':
            rough = np.clip(rough + .055, 0, .97)
            reflectance *= .78
        intensity, tile = 1.18, 192
    elif key in METAL:
        patina = np.clip((.62 - broad) * 2.7, 0, .93)
        if key == 'patina':
            patina = np.clip(.26 + patina, 0, .98)
        pit = np.clip((.32 - fine) * 3.4, 0, .6)
        polish = np.clip(1 - patina * .98 - pit * .38, .045, 1)
        exposed = {'bronze': (.54, .355, .215), 'copper': (.71, .465, .295),
                   'patina': (.52, .355, .225), 'iron': (.29, .315, .32)}[key]
        oxide = (.115, .23, .215) if key != 'iron' else (.13, .11, .09)
        color = np.asarray(exposed)[None, None, :] * (.91 + .16 * broad)[:, :, None]
        color = color * (1 - patina[:, :, None] * .86) + np.asarray(oxide) * patina[:, :, None] * .86
        y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
        scratch = np.zeros_like(broad)
        for _ in range(68):
            cx, cy = rng.random(2)
            line = np.clip(1 - np.abs(x - cx + (y - cy) * .27) / .0017, 0, 1)
            line *= np.clip(1 - np.abs(y - cy) / rng.uniform(.012, .09), 0, 1)
            scratch = np.maximum(scratch, line)
        color += (.035 * scratch - .028 * pit)[:, :, None]
        height = .21 * (medium - .5) + .045 * (fine - .5) - .11 * pit - .027 * scratch
        rough = np.clip(.255 + .46 * patina + .17 * pit - .035 * scratch, .22, .88)
        reflectance = np.clip(.09 + .65 * polish, .08, .80)
        metallic = np.clip(.94 - .80 * patina, .10, .94)
        intensity = 1.48 if key == 'copper' else 1.36
        if key == 'iron':
            # Forged iron remains darker and rougher than polished copper.
            height += .24 * (broad - .5) - .06 * pit
            rough = np.clip(rough + .12, 0, .93)
            reflectance *= .70
            intensity = 1.18
    elif key == 'lava':
        seam, tone = mineral_cells(8196, 8)
        crack = np.clip(seam * 1.45, 0, 1)
        glass = np.clip((broad - .31) * 1.8, 0, 1)
        crust = np.asarray((.155, .145, .135))[None, None, :] * (.81 + .32 * tone)[:, :, None]
        color = crust * (1 - crack[:, :, None]) + np.asarray(col)[None, None, :] * crack[:, :, None] * .85
        height = .72 * (medium - .5) + .24 * tone - .58 * crack + .13 * (fine - .5)
        rough = np.clip(.82 - .26 * glass + .12 * crack, .54, .94)
        reflectance = np.clip(.052 + .16 * glass - .055 * crack, .023, .21)
        intensity, tile = 1.12, 256
    elif key in ('ash', 'earth', 'mortar'):
        # Powdery surfaces have broad diffuse response, never metallic sheen.
        color *= (.87 + .23 * medium)[:, :, None]
        height = .30 * (medium - .5) + .085 * (fine - .5)
        rough = .94 + .045 * broad
        reflectance = .012 + .012 * broad
        intensity = .85
    elif key == 'teal':
        height = .25 * (medium - .5) + .04 * (fine - .5)
        rough = .85 + .10 * broad
        reflectance = .022 + .018 * broad
    return dict(color=np.clip(color, .008, .88), normal=normal_from_height(height, tile),
                roughness=rough, reflectance=reflectance, metallic=metallic), intensity


def configure_blender(mat, key, directory):
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out, bs = nodes.new('ShaderNodeOutputMaterial'), nodes.new('ShaderNodeBsdfPrincipled')
    links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    bs.inputs['Emission Strength'].default_value = 0
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
    mat.use_backface_culling = key != 'teal'
    mat['surface_revision'] = REVISION
    mat['engine_note'] = 'Source 2 scalar reflection; Blender roughness/metallic preview parameters.'


def build_materials(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    materials, manifest = {}, []
    for key, col in PALETTE.items():
        maps, intensity = maps_for(key, col)
        for suffix, pixels in maps.items():
            png(directory / f'{key}_{suffix}.png', pixels)
        canonical = f'materials/molten_core_room/{key}.vmat'
        mat = bpy.data.materials.get(canonical) or bpy.data.materials.new(canonical)
        configure_blender(mat, key, directory)
        materials[key] = mat
        entries = [('shader', 'global_lit_simple.vfx'), ('F_NORMAL_MAP', '1'), ('F_SPECULAR', '1'),
                   ('g_flSpecularIntensity', f'{intensity:.6f}'), ('g_flBumpStrength', '1.000000'),
                   ('g_flSpecularBloom', '0.000000'), ('g_vColorTint', '[1 1 1 0]')]
        if key == 'teal':
            entries.append(('F_RENDER_BACKFACES', '1'))
        for channel, suffix in [('Color', 'color'), ('Normal', 'normal'), ('Reflectance', 'reflectance')]:
            entries.append((f'Texture{channel}', f'materials/molten_core_room/{key}_{suffix}.png'))
        (directory / f'{key}.vmat').write_text('"Layer0"\n{\n' + ''.join(f'    "{k}" "{v}"\n' for k, v in entries) + '}\n', encoding='utf-8')
        manifest.append(dict(name=key, revision=REVISION, size=SIZE, color_std=float(np.std(maps['color'])),
                             normal_std=float(np.std(maps['normal'][:, :, :2])), roughness_mean=float(np.mean(maps['roughness'])),
                             reflectance_mean=float(np.mean(maps['reflectance'])), reflectance_std=float(np.std(maps['reflectance'])),
                             specular_intensity=intensity, bump_strength=1., emissive=False,
                             engine_shader='global_lit_simple.vfx', engine_reflectance_channel='linear R',
                             roughness_use='Blender preview; Dota simple shader has no roughness input'))
        print('MOLTEN_MATERIAL', key, flush=True)
    return materials, manifest
