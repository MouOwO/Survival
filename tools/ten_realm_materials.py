"""Independent, non-emissive surfaces for the ten approved island arenas.

Source 2 global_lit_simple uses linear reflectance.R and DirectX normals.
Roughness/metallic textures are explicit Blender preview inputs. Game water
is supplied separately by the island-water pipeline, not by this opaque VMAT.
"""
from pathlib import Path
import json
import math

import bpy
import numpy as np

from ten_realm_spec import NAMESPACE, PALETTE, REVISION
from gold_room_materials import maps_for as gold_maps, normal_from_height, png
from gold_room_materials import configure_blender as configure_gold_blender
from training_room_materials import timber_maps, theme_maps
from wall_surface_materials import SIZE, field

NS = NAMESPACE
MATERIAL_REVISION = REVISION + '_material_response_v1'
DOUBLE_SIDED = {'leaf', 'leaf_light', 'leaf_dark', 'flower', 'pink', 'pink_light',
                'teal', 'red_cloth', 'moss'}
FAMILIES = {
    'granular': {'sand', 'sand_wet', 'shell_sand', 'red_gravel'},
    'soil': {'forest_earth', 'peat', 'mud'},
    'sandstone': {'sandstone', 'sandstone_light', 'redstone', 'redstone_light'},
    'frozen': {'snow', 'ice'},
    'coral': {'coral', 'coral_light'},
    'volcanic': {'basalt', 'basalt_wet'},
    'layered_rock': {'schist', 'slate', 'slate_wet'},
    'mineral': {'quartz', 'amethyst'},
    'masonry': {'ivory', 'ivory_light', 'stone', 'stone_light', 'stone_cool', 'rock', 'rock_wet'},
    'bone': {'bone'},
    'matte_ground': {'mortar', 'moss'},
    'timber': {'wood', 'wood_light', 'wood_end', 'bark'},
    'foliage': {'leaf', 'leaf_light', 'leaf_dark', 'flower', 'pink', 'pink_light'},
    'metal': {'gold', 'bronze', 'iron'},
    'cloth': {'teal', 'red_cloth'},
    'water_preview': {'water', 'water_shallow', 'foam'},
}
TYPE = {key: family for family, keys in FAMILIES.items() for key in keys}


def _fields(seed, scales=(6, 25, 120)):
    rng = np.random.default_rng(seed)
    return rng, *(field(rng, cells) for cells in scales)


def _coords():
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
    return x, y


def _maps(color, height, rough, reflect, tile, metallic=0):
    """All channels follow the same marks; no baked directional illumination."""
    if np.isscalar(metallic):
        metallic = np.full_like(height, metallic)
    if np.isscalar(rough):
        rough = np.full_like(height, rough)
    if np.isscalar(reflect):
        reflect = np.full_like(height, reflect)
    return dict(color=np.clip(color, 0, 1), normal=normal_from_height(height, tile),
                roughness=np.clip(rough, 0, 1), reflectance=np.clip(reflect, 0, 1),
                metallic=np.clip(metallic, 0, 1))


def _tint(col, variation):
    return np.asarray(col, dtype=np.float32)[None, None, :] * variation[:, :, None]


def _scale_normal(normal, strength):
    n = normal * 2 - 1
    n[:, :, :2] *= strength
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * .5 + .5


def granular_maps(key, col):
    # Both sand variants have the same physical grain and ripple locations.
    rng, broad, medium, fine = _fields(91581, (5, 32, 170))
    x, y = _coords()
    ripple = .5 + .5*np.sin((y*7 + .32*np.sin(x*math.tau*2) + .18*(broad-.5))*math.tau)
    grain = np.clip((fine-.63)*3.6, 0, .7)
    pits = np.clip((.32-fine)*3.0, 0, .65)
    shell = key == 'shell_sand'
    gravel = key == 'red_gravel'
    wet = key == 'sand_wet'
    height = .13*(medium-.5) + .16*(fine-.5) + (.08 if shell else .22)*(ripple-.5)
    height += (.32 if shell else .13)*grain - .10*pits
    color = _tint(col, .95+.13*(broad-.5)+.08*(medium-.5)-.12*pits)
    color += grain[:, :, None]*np.asarray((.09, .08, .06))
    if gravel:
        chip = np.clip((medium-.52)*3.5, 0, .9)
        height = .45*(broad-.5)+.70*chip+.18*(fine-.5)-.24*pits
        color = _tint(col, .91+.18*broad+.15*chip-.18*pits)
    rough = .88+.07*pits-.055*grain
    reflect = .020+.015*grain-.008*pits
    if wet:
        rough = .30+.18*pits+.12*(1-broad)
        reflect = .16+.10*broad-.10*pits
        height *= .67
    return _maps(color, height, rough, reflect, 192), 1.12 if wet else .95, 1., 192


def soil_maps(key, col):
    _, broad, medium, fine = _fields(91633, (7, 28, 142))
    x, y = _coords()
    crack = np.exp(-np.abs(medium-.49)/.013)*np.clip((.59-broad)*3, 0, .75)
    fibre = (.5+.5*np.sin((x*31+y*5+medium*.13)*math.tau))**14
    leaf_bits = np.clip((field(np.random.default_rng(619), 43)-.64)*4, 0, .8)
    damp = np.clip((.58-broad)*2.3, 0, .85)
    height = .34*(broad-.5)+.23*(medium-.5)+.13*(fine-.5)-.32*crack+.10*leaf_bits
    color = _tint(col, .93+.16*(broad-.5)+.10*(medium-.5)-.22*crack)
    if key != 'forest_earth':
        height += .085*fibre
        color += fibre[:, :, None]*np.asarray((.020, .018, .009))
    else:
        color += leaf_bits[:, :, None]*np.asarray((.08, .035, .005))
    rough = np.clip(.88-.12*damp+.08*crack, .65, .96)
    reflect = .025+.045*damp-.012*crack
    if key == 'mud':
        height *= .72
        rough = .32+.32*(1-damp)+.08*crack
        reflect = .07+.18*damp-.035*crack
    elif key == 'peat':
        rough -= .07*damp
        reflect += .045*damp
    return _maps(color, height, rough, reflect, 192), 1.05, 1., 192


def sandstone_maps(key, col):
    red = key.startswith('redstone')
    _, broad, medium, fine = _fields(37229 if red else 37211, (6, 25, 124))
    x, y = _coords()
    warp = y + .018*np.sin(x*math.tau*2) + .010*(broad-.5)
    stratum = .5+.5*np.sin(warp*math.tau*(17 if red else 25)+.18*medium)
    ledge = stratum**12
    pit = np.clip((.34-fine)*3.4, 0, .72)
    fissure = np.exp(-np.abs(medium-.465)/.012)*np.clip((.57-broad)*3, 0, .7)
    height = .82*(broad-.5)+.36*(medium-.5)+.08*(fine-.5)-.32*pit-.31*fissure
    height += (.20 if red else .10)*(stratum-.5)-.10*ledge
    color = _tint(col, .97+.17*(broad-.5)+.07*(stratum-.5)-.23*pit-.20*fissure)
    if red:
        color += (stratum-.5)[:, :, None]*np.asarray((.033, .008, -.003))
    rough = .77+.14*pit+.08*fissure-.085*broad
    reflect = .035+.06*broad-.025*pit-.016*fissure
    return _maps(color, height, rough, reflect, 160), 1.05, 1., 160


def frozen_maps(key, col):
    _, broad, medium, fine = _fields(55119, (5, 25, 144))
    x, y = _coords()
    if key == 'snow':
        wind = .5+.5*np.sin((y*5+.15*np.sin(x*math.tau*2)+.09*medium)*math.tau)
        compressed = np.clip((broad-.48)*2.4, 0, .8)
        color = _tint(col, .99+.040*(broad-.5)+.018*(medium-.5))
        height = .21*(broad-.5)+.055*(wind-.5)+.048*(fine-.5)
        rough = .80-.15*compressed+.05*(1-fine)
        reflect = .055+.07*compressed+.018*fine
        return _maps(color, height, rough, reflect, 192), 1.10, 1., 192
    crack = np.exp(-np.abs(medium-.52)/.010)*np.clip((.70-broad)*2, 0, .85)
    frost = np.clip((.44-broad)*3, 0, .60)
    bubbles = np.clip((fine-.72)*4, 0, .65)
    color = _tint(col, .89+.21*broad)
    color = color*(1-frost[:, :, None]*.40)+np.asarray((.73,.82,.84))*frost[:, :, None]*.40
    color += (crack*.07+bubbles*.025)[:, :, None]
    height = .065*(broad-.5)+.018*(fine-.5)-.035*crack+.020*frost
    return _maps(color, height, .14+.35*frost+.11*crack,
                 .35-.18*frost-.12*crack, 128), 1.35, 1., 128


def coral_maps(key, col):
    _, broad, medium, fine = _fields(68323, (7, 36, 138))
    pore = np.clip((.36-medium)*4.5, 0, .95)
    pinhole = np.clip((.28-fine)*3.8, 0, .65)
    fossil = np.exp(-np.abs(field(np.random.default_rng(68324), 12)-.53)/.026)
    height = .53*(broad-.5)+.16*(fine-.5)-.75*pore-.22*pinhole+.075*fossil
    color = _tint(col, .99+.10*(broad-.5)-.24*pore-.10*pinhole)
    color += fossil[:, :, None]*np.asarray((.026,.022,.012))
    rough = .71+.20*pore+.12*pinhole-.07*fossil
    reflect = .075-.055*pore-.030*pinhole+.018*fossil
    return _maps(color, height, rough, reflect, 160), 1.05, 1., 160


def volcanic_maps(key, col):
    _, broad, medium, fine = _fields(77517, (7, 24, 130))
    fissure = np.exp(-np.abs(medium-.48)/.016)
    pit = np.clip((.35-fine)*4, 0, .8)
    worn = np.clip((broad-.38)*1.8, 0, .9)*(1-fissure)
    height = .75*(broad-.5)+.36*(medium-.5)+.075*(fine-.5)-.52*fissure-.31*pit
    color = _tint(col, 1.00+.20*(broad-.5)-.22*fissure-.13*pit)
    rough = .72+.16*pit+.10*fissure-.17*worn
    reflect = .045+.10*worn-.030*pit-.020*fissure
    if key == 'basalt_wet':
        rough = .22+.24*pit+.23*fissure
        reflect = .22+.10*worn-.15*pit-.15*fissure
        height *= .84
    return _maps(color, height, rough, reflect, 160), 1.25 if key.endswith('wet') else 1.10, 1., 160


def layered_rock_maps(key, col):
    _, broad, medium, fine = _fields(84721, (6, 26, 102))
    x, y = _coords()
    lamina = (.5+.5*np.sin((y*21+x*3+.025*np.sin(x*math.tau*2))*math.tau))**9
    vein = np.exp(-np.abs(medium-.485)/.015)
    pit = np.clip((.29-fine)*3, 0, .7)
    height = .55*(broad-.5)+.19*(medium-.5)-.11*lamina-.16*vein-.13*pit
    color = _tint(col, .97+.18*(broad-.5)-.06*lamina-.08*pit)
    color += vein[:, :, None]*(.044 if key == 'schist' else .021)
    rough = .64+.12*lamina+.10*pit-.12*broad
    reflect = .070+.095*broad-.035*lamina-.040*pit
    if key == 'slate_wet':
        rough = .25+.22*lamina+.13*pit
        reflect = .20+.10*broad-.10*lamina-.08*pit
        height *= .80
    return _maps(color, height, rough, reflect, 160), 1.20, 1., 160


def mineral_maps(key, col):
    maps, _, _ = theme_maps('greater_attribute', 'mineral', col)
    _, broad, medium, fine = _fields(24739, (5, 19, 100))
    vein = np.exp(-np.abs(medium-.49)/.016)
    inclusion = np.clip((.39-broad)*2.5, 0, .75)
    maps['color'] = _tint(col, .95+.18*(broad-.5))
    maps['color'] += vein[:, :, None]*(.035 if key == 'amethyst' else .060)
    maps['normal'] = normal_from_height(.11*(broad-.5)+.035*(fine-.5)-.025*vein, 95)
    maps['roughness'] = np.clip(.20+.29*inclusion+.12*vein, .18, .65)
    maps['reflectance'] = np.clip(.36-.19*inclusion-.12*vein, .11, .40)
    maps['metallic'] = np.zeros_like(broad)
    return maps, 1.4, 1., 95


def masonry_maps(key, col):
    source = 'rock' if key in ('rock','rock_wet') else 'stone_light' if key.endswith('light') else 'stone'
    maps, intensity, bump = gold_maps(source, col)
    if key in ('ivory','ivory_light'):
        maps['normal'] = _scale_normal(maps['normal'], .53)
        maps['roughness'] = np.clip(maps['roughness']-.08, .46, .88)
        maps['reflectance'] = np.clip(maps['reflectance']*1.13, .04, .24)
    if key == 'rock_wet':
        _, wet, _, _ = _fields(17329)
        maps['normal'] = _scale_normal(maps['normal'], .84)
        maps['roughness'] = np.clip(.28+.21*(1-wet)+.10*maps['roughness'], .25, .65)
        maps['reflectance'] = np.clip(.18+.11*wet, .10, .33)
        intensity = 1.2
    return maps, intensity, bump, 160


def soft_maps(key, col):
    _, broad, medium, fine = _fields(16199, (6, 28, 108))
    x, y = _coords()
    family = TYPE[key]
    if family == 'cloth':
        weave = np.sin(x*math.tau*96)*np.sin(y*math.tau*96)
        height = .10*(medium-.5)+.018*weave
        return _maps(_tint(col,.96+.13*(broad-.5)+.03*weave),height,
                     .87+.05*broad,.027+.017*broad,90),1.,1.,90
    if family == 'foliage':
        petal = key in ('flower','pink','pink_light')
        vein = np.exp(-np.abs(x-.5)/.022)
        vein += .35*np.exp(-np.abs(np.sin((y*8+np.abs(x-.5)*3)*math.tau))/.10)
        height = .048*vein+.045*(broad-.5)+.008*(fine-.5)
        color = _tint(col,.98+.12*(broad-.5)-.035*vein)
        return _maps(color,height,.69+.10*broad if petal else .53+.17*broad,
                     .025+.023*broad if petal else .045+.055*broad,90),1.,1.,90
    if key == 'bone':
        pore = np.clip((.31-fine)*3.5,0,.65)
        height=.14*(medium-.5)+.025*(fine-.5)-.10*pore
        return _maps(_tint(col,.97+.10*(broad-.5)-.12*pore),height,
                     .59+.19*pore,.07+.05*broad-.045*pore,95),1.05,1.,95
    moss = key == 'moss'
    height=(.28 if moss else .13)*(medium-.5)+.075*(fine-.5)
    color=_tint(col,.95+.20*(broad-.5)+.07*(medium-.5))
    return _maps(color,height,.92-.05*broad,.016+.012*broad,90 if moss else 160),1.,1.,90 if moss else 160


def water_maps(key, col):
    _, broad, medium, fine = _fields(62489, (5, 24, 90))
    x,y = _coords()
    waves = np.sin((x*6+y*3+.035*np.sin(y*math.tau*3))*math.tau)
    waves += .40*np.sin((y*13-x*5+.015*medium)*math.tau)
    height=.085*waves+.065*(medium-.5)+.010*(fine-.5)
    color=_tint(col,.95+.13*(broad-.5))
    if key == 'foam':
        return _maps(color,height*.4,.66+.08*broad,.065+.025*broad,192),1.,1.,192
    return _maps(color,height,.17+.07*broad,.34+.08*broad,256),1.2,1.,256


def realm_maps(key, col=None):
    """Return (five channel arrays, spec intensity, bump strength, world UV tile)."""
    if col is None:
        col=PALETTE[key]
    family=TYPE[key]
    generators={'granular':granular_maps,'soil':soil_maps,'sandstone':sandstone_maps,
                'frozen':frozen_maps,'coral':coral_maps,'volcanic':volcanic_maps,
                'layered_rock':layered_rock_maps,'mineral':mineral_maps,'masonry':masonry_maps,
                'bone':soft_maps,'matte_ground':soft_maps,'foliage':soft_maps,
                'cloth':soft_maps,'water_preview':water_maps}
    if family in generators:
        return generators[family](key,col)
    if family == 'timber':
        maps,intensity,bump=timber_maps(key,col)
        return maps,intensity,bump,112
    if key == 'iron':
        maps,intensity,bump=theme_maps('attribute','iron',col)
    else:
        maps,intensity,bump=gold_maps(key,col)
        base=np.asarray((.80,.63,.30) if key=='gold' else (.66,.49,.27))
        maps['color']=np.clip(maps['color']*(np.asarray(col)/base)[None,None,:],0,1)
    return maps,intensity,bump,75 if key!='iron' else 95


def configure_blender(mat, key, destination):
    configure_gold_blender(mat,key,Path(destination))
    mat.use_backface_culling=key not in DOUBLE_SIDED
    mat['surface_revision']=MATERIAL_REVISION
    mat['surface_family']=TYPE[key]
    mat['namespace']=NS
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            node.inputs['Emission Strength'].default_value=0
            if key in ('water','water_shallow','ice'):
                node.inputs['IOR'].default_value=1.333 if key!='ice' else 1.31
                node.inputs['Coat Weight'].default_value=.18 if key=='ice' else .24
                node.inputs['Coat Roughness'].default_value=.12
                # Surface-only preview. Real refraction/water shader is separate.
                node.inputs['Transmission Weight'].default_value=0
    if key in ('water','water_shallow','foam'):
        mat['engine_note']='Blender surface preview; replace with island water shader in the game map.'


def write_materials(destination):
    destination=Path(destination)
    destination.mkdir(parents=True,exist_ok=True)
    assert set(TYPE)==set(PALETTE),'Every palette key requires an explicit material family'
    manifest=[]
    for key,col in PALETTE.items():
        maps,intensity,bump,tile=realm_maps(key,col)
        assert set(maps)=={'color','normal','roughness','reflectance','metallic'},key
        files={}
        for suffix,pixels in maps.items():
            assert pixels.shape[:2]==(SIZE,SIZE) and np.isfinite(pixels).all(),(key,suffix)
            assert pixels.min()>=0 and pixels.max()<=1,(key,suffix)
            files[suffix]=f'{key}_{suffix}.png'
            png(destination/files[suffix],pixels)
        entries=[('shader','global_lit_simple.vfx'),('F_NORMAL_MAP','1'),('F_SPECULAR','1'),
                 ('g_flSpecularIntensity',f'{intensity:.6f}'),('g_flBumpStrength',f'{bump:.6f}'),
                 ('g_flSpecularBloom','0.000000'),('g_vColorTint','[1 1 1 0]')]
        if key in DOUBLE_SIDED:
            entries.append(('F_RENDER_BACKFACES','1'))
        entries.extend((f'Texture{channel}',f'materials/{NS}/{key}_{suffix}.png') for channel,suffix in
                       [('Color','color'),('Normal','normal'),('Reflectance','reflectance')])
        files['vmat']=f'{key}.vmat'
        (destination/files['vmat']).write_text('"Layer0"\n{\n'+''.join(f'    "{k}" "{v}"\n' for k,v in entries)+'}\n',encoding='utf-8')
        manifest.append(dict(name=key,revision=MATERIAL_REVISION,type=TYPE[key],surface_family=TYPE[key],
            size=SIZE,recommended_uv_tile=tile,files=files,material=f'materials/{NS}/{key}.vmat',
            specular_intensity=intensity,bump_strength=bump,double_sided=key in DOUBLE_SIDED,emissive=False,
            color_std=float(np.std(maps['color'])),normal_std=float(np.std(maps['normal'][:,:,:2])),
            roughness_mean=float(np.mean(maps['roughness'])),roughness_range=[float(maps['roughness'].min()),float(maps['roughness'].max())],
            reflectance_mean=float(np.mean(maps['reflectance'])),reflectance_std=float(np.std(maps['reflectance'])),
            metallic_mean=float(np.mean(maps['metallic'])),engine_shader='global_lit_simple.vfx',
            engine_reflectance_channel='linear R',normal_convention='DirectX; Blender flips G exactly once',
            roughness_use='Blender preview only; global_lit_simple has no roughness input',
            engine_water_override=key in ('water','water_shallow','foam')))
        print('TEN_REALM_MATERIAL',key,TYPE[key],flush=True)
    (destination/'material_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    return manifest
