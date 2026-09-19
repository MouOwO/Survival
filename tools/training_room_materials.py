"""Theme surfaces using the approved gold-room normal/specular export contract.

Wood fibres run along texture V; wood_end is a separate radial cut surface.
Source 2 uses a linear scalar reflectance mask. Roughness and metallic PNGs
are explicitly Blender preview inputs, not unsupported Dota shader inputs.
"""
from pathlib import Path
import math
import bpy
import numpy as np
from gold_room_geometry import PALETTE as GOLD_PALETTE
from gold_room_materials import maps_for, png, normal_from_height, configure_blender
from wall_surface_materials import SIZE, field

REVISION = 'themed_training_surfaces_v1'
THEMES = {
    'wood': dict(namespace='wood_training_room', title='木材练功房', challenge='01',
                 description='暖色旧木板、顺纹木梁、端面年轮、哑光树皮与磨亮铁箍'),
    'attribute': dict(namespace='attribute_training_room', title='属性练功房', challenge='03',
                      description='浅冷石灰岩、翠玉矿物、三瓣生长纹与克制的银铜嵌件'),
    'greater_attribute': dict(namespace='greater_attribute_training_room', title='大属性练功房', challenge='04',
                              description='深色矿石、蓝紫切面晶体、浅色石缘与分层金银嵌件'),
}


def palette(theme):
    p = dict(GOLD_PALETTE)
    if theme == 'wood':
        p.update(stone=(.59,.57,.48), stone_light=(.69,.65,.54), stone_cool=(.53,.56,.49),
                 wood=(.49,.345,.205), wood_light=(.62,.46,.28), wood_end=(.66,.49,.30),
                 bark=(.31,.25,.18), iron=(.30,.335,.32), teal=(.245,.355,.23),
                 bronze=(.54,.43,.25), earth=(.37,.29,.19))
    else:
        p.update(mineral=(.25,.49,.405), mineral_dark=(.12,.28,.26), metal_light=(.64,.69,.67))
        if theme == 'attribute':
            p.update(stone=(.67,.70,.66), stone_light=(.77,.78,.68), stone_cool=(.54,.61,.59),
                     rock=(.50,.57,.52), mortar=(.30,.35,.32), teal=(.16,.39,.34))
        else:
            p.update(stone=(.40,.43,.48), stone_light=(.72,.72,.67), stone_cool=(.35,.395,.445),
                     rock=(.38,.405,.44), mortar=(.245,.265,.29), teal=(.26,.255,.38),
                     mineral=(.38,.32,.60), mineral_dark=(.17,.315,.44), metal_light=(.73,.735,.67),
                     earth=(.30,.285,.27))
    return p


def timber_maps(key, col):
    rng = np.random.default_rng(61873 + sum(ord(c)*(i+1) for i,c in enumerate(key)))
    y,x = np.mgrid[0:SIZE,0:SIZE].astype(np.float32) / SIZE
    broad,medium,fine = field(rng,5),field(rng,22),field(rng,100)
    # Periodic bends in growth rings, with grain drawn around each knot.
    warp = x + .011*np.sin(y*math.tau*2) + .025*(broad-.5)
    knot = np.zeros_like(x)
    for cx,cy,rx,ry in ((.26,.33,.08,.17),(.72,.78,.055,.12)):
        dx,dy = (x-cx+.5)%1-.5,(y-cy+.5)%1-.5
        r = np.sqrt((dx/rx)**2+(dy/ry)**2)
        knot = np.maximum(knot,np.exp(-r*r*3.5))
        warp += .045*np.sin(np.arctan2(dy/ry,dx/rx))*np.exp(-r*1.2)
    growth = (.5+.5*np.sin(warp*math.tau*13+.35*np.sin(y*math.tau*4)))**8
    fibres = (.5+.5*np.sin(warp*math.tau*55+medium*.7))**18
    split = np.zeros_like(x)
    for _ in range(23):
        cx,cy = rng.random(2)
        dy = (y-cy+.5)%1-.5
        path = cx+.0025*np.sin(y*math.tau*4)+.004*(broad-.5)
        dx = (x-path+.5)%1-.5
        split = np.maximum(split,np.clip(1-np.abs(dx)/rng.uniform(.001,.0032),0,1)*
                           np.clip(1-np.abs(dy)/rng.uniform(.035,.22),0,1))
    cut = key == 'wood_end'
    bark = key == 'bark'
    if cut:
        radius = np.sqrt(((x-.5)*1.06)**2+((y-.5)*.93)**2)
        growth = (.5+.5*np.sin(radius*math.tau*20+medium*.7))**8
        angle = np.arctan2(y-.5,x-.5)
        split = np.clip(1-np.abs(np.sin(angle*3+.38))/.028,0,1)*(radius>.20)
        knot = np.exp(-radius*radius*140)
        fibres *= .15
    cavity = np.clip(growth*.37+fibres*.14+split*.9+knot*.70,0,1)
    polish = np.clip((broad-.30)*1.5,0,.85)*(1-cavity)
    height = .20*(medium-.5)+.07*(fine-.5)-.33*growth-.17*fibres-.78*split-.45*knot
    if bark:
        height = 1.1*(broad-.5)+.36*(medium-.5)-1.5*growth-.80*split
        cavity = np.clip(cavity*1.25,0,1)
    color = np.asarray(col)[None,None,:]*(.91+.19*broad+.12*(medium-.5)-.45*cavity)[:,:,None]
    # Pale exposed fibres and grey-brown weathered regions remain correlated
    # with rough, unpolished areas, not painted directional illumination.
    grey = np.clip((.45-broad)*1.7,0,.35)*(1-knot)
    color = color*(1-grey[:,:,None]) + np.asarray((.43,.395,.33))*grey[:,:,None]
    rough = np.clip(.80-.28*polish+.18*cavity+( .10 if bark else 0),.51,.97)
    reflect = np.clip(.035+.15*polish-.035*cavity,.015,.17)
    if bark: reflect *= .5
    return dict(color=np.clip(color,0,1),normal=normal_from_height(height,112),roughness=rough,
                reflectance=reflect,metallic=np.zeros_like(x)),1.30,1.0


def theme_maps(theme,key,col):
    if key in ('wood','wood_light','wood_end','bark'):
        return timber_maps(key,col)
    if key in ('mineral','mineral_dark','metal_light','iron'):
        rng=np.random.default_rng(8203+sum(ord(c)*(i+1) for i,c in enumerate(key)))
        broad,medium,fine=field(rng,5),field(rng,21),field(rng,84)
        metal=key in ('metal_light','iron')
        vein=np.clip(1-np.abs(medium-.51)/.018,0,1)
        pit=np.clip((.33-fine)*3,0,.55)
        tarnish=np.clip((.56-broad)*2.8,0,.8)
        if metal:
            color=np.asarray(col)[None,None,:]*(.88+.2*broad)[:,:,None]
            tint=np.asarray((.36,.28,.19) if key=='iron' else (.31,.34,.32))
            color=color*(1-tarnish[:,:,None]*.6)+tint*tarnish[:,:,None]*.6
            height=.15*(medium-.5)+.035*(fine-.5)-.11*pit
            rough=np.clip(.26+.40*tarnish+.14*pit,.24,.83)
            reflect=np.clip(.57-.40*tarnish-.15*pit,.10,.68)
            metallic=np.clip(.9-.55*tarnish,.25,.9)
            intensity=1.45
        else:
            # Stone mineral inclusions: broad, polished faces and dull veins.
            color=np.asarray(col)[None,None,:]*(.79+.30*broad+.14*(medium-.5))[:,:,None]
            color+=vein[:,:,None]*.07
            height=.24*(broad-.5)+.075*(medium-.5)-.035*vein
            rough=np.clip(.27+.21*tarnish+.14*vein,.25,.65)
            reflect=np.clip(.29+.18*broad-.19*vein-.1*pit,.10,.52)
            metallic=np.zeros_like(broad)
            intensity=1.5
        return dict(color=np.clip(color,0,1),normal=normal_from_height(height,95),roughness=rough,
                    reflectance=reflect,metallic=metallic),intensity,1.0
    maps,intensity,bump=maps_for(key,col)
    if key in ('gold','bronze'):
        # Gold's fixed metal base is intentional. Wood uses fewer bright metals;
        # the other themes use the same controlled polished/tarnished response.
        if theme=='wood':
            maps['color']*=.88
            maps['reflectance']*=.82
            intensity=1.3
    if theme=='greater_attribute' and key=='stone_cool':
        maps['roughness']=np.clip(maps['roughness']-.08,.42,.90)
        maps['reflectance']=np.clip(maps['reflectance']*1.30,.035,.24)
    return maps,intensity,bump


def build_materials(theme,directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    ns=THEMES[theme]['namespace'];materials={};manifest=[]
    for key,col in palette(theme).items():
        maps,intensity,bump=theme_maps(theme,key,col)
        for suffix,pixels in maps.items():png(directory/f'{key}_{suffix}.png',pixels)
        canonical=f'materials/{ns}/{key}.vmat'
        mat=bpy.data.materials.new(canonical)
        configure_blender(mat,key,directory)
        mat['surface_revision']=REVISION;mat['theme']=theme
        materials[key]=mat
        entries=[('shader','global_lit_simple.vfx'),('F_NORMAL_MAP','1'),('F_SPECULAR','1'),
                 ('g_flSpecularIntensity',f'{intensity:.6f}'),('g_flBumpStrength',f'{bump:.6f}'),
                 ('g_flSpecularBloom','0.000000'),('g_vColorTint','[1 1 1 0]')]
        if not mat.use_backface_culling:entries.append(('F_RENDER_BACKFACES','1'))
        entries += [(f'Texture{channel}',f'materials/{ns}/{key}_{suffix}.png') for channel,suffix in
                    [('Color','color'),('Normal','normal'),('Reflectance','reflectance')]]
        (directory/f'{key}.vmat').write_text('"Layer0"\n{\n'+''.join(f'    "{k}" "{v}"\n' for k,v in entries)+'}\n',encoding='utf-8')
        manifest.append(dict(name=key,theme=theme,revision=REVISION,size=SIZE,color_std=float(np.std(maps['color'])),
                             normal_std=float(np.std(maps['normal'][:,:,:2])),roughness_mean=float(np.mean(maps['roughness'])),
                             reflectance_mean=float(np.mean(maps['reflectance'])),reflectance_std=float(np.std(maps['reflectance'])),
                             specular_intensity=intensity,bump_strength=bump,emissive=False,
                             engine_shader='global_lit_simple.vfx',engine_reflectance_channel='linear R',
                             roughness_use='Blender preview only; Dota simple shader has no roughness input'))
        print('THEME_MATERIAL',theme,key,flush=True)
    return materials,manifest
