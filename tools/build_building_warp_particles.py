"""Stable white building silhouette, followed by a single smooth reveal.

CP0 = origin; CP1 = (footprint radius, height, duration).
CP2 = (entity scale, yaw in degrees, reserved); CP3 = actual model entity.
One model particle per phase; no repeated emitters, rings, noise or cloak shader.
"""
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT/'output/building_presentation/source'
OUT = STAGE/'particles/survival_buildings'
HEADER = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->\n'
PARTICLE_NAMES = ('white_build_channel', 'white_build_reveal')
MATERIAL = 'materials/survival_buildings/build_white_glow.vmat'
WHITE_TEXTURE = 'materials/survival_buildings/build_white_glow_color.png'
REVEAL_SECONDS = .9


def literal(value):
    return dict(m_nType='PF_TYPE_LITERAL', m_flLiteralValue=float(value))


def cp(component, factor=1, point=1):
    return dict(m_nType='PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint=point,
                m_nVectorComponent=component, m_nMapType='PF_MAP_TYPE_MULT', m_flMultFactor=float(factor))


def init(field, value):
    return dict(_class='C_INIT_InitFloat', m_nOutputField=field, m_InputValue=value)


def silhouette(reveal=False):
    # Slight expansion avoids coplanar surfaces fighting during the reveal.
    # Fullbright alpha blending covers the real model, then fades once.
    operators = [dict(_class='C_OP_Decay')]
    if reveal:
        operators = [dict(_class='C_OP_FadeAndKill', m_flStartAlpha=1.,
                         m_flStartFadeInTime=0., m_flEndFadeInTime=0.,
                         m_flStartFadeOutTime=.05, m_flEndFadeOutTime=1.)]
    else:
        operators.append(dict(_class='C_OP_FadeInSimple', m_flFadeInTime=.08,
                              m_bProportional=False))
    return dict(_class='CParticleSystemDefinition', m_nMaxParticles=1,
        m_flConstantRadius=1., m_ConstantColor=[255,255,255,255],
        m_BoundingBoxMin=[-512.,-512.,-16.], m_BoundingBoxMax=[512.,512.,1200.],
        m_Emitters=[dict(_class='C_OP_InstantaneousEmitter', m_flStartTime=literal(0),
                        m_nParticlesToEmit=literal(1))],
        # Headroom for the server completion tick; channel is destroyed at
        # commit/cancel and never cycles on its own.
        m_Initializers=[init(1,literal(REVEAL_SECONDS) if reveal else cp(2,2)),
            init(3,cp(0,1.006,point=2)), init(12,cp(1,point=2)), init(7,literal(1)),
            dict(_class='C_INIT_CreateWithinSphere',m_fRadiusMin=0.,m_fRadiusMax=0.)],
        m_Operators=operators,
        m_Renderers=[dict(_class='C_OP_RenderModels',m_ActivityName='ACT_DOTA_IDLE',
            m_ModelList=[dict(m_model='resource:models/development/invisiblebox.vmdl')],
            m_bOrientZ=True,m_bDisableShadows=True,m_bOriginalModel=True,m_nLOD=0,
            m_bForceLoopingAnimation=True,m_bForceDrawInterlevedWithSiblings=True,
            m_hOverrideMaterial='resource:'+MATERIAL,
            m_modelInput=dict(m_nType='PM_TYPE_CONTROL_POINT',m_nControlPoint=3))],
        m_nBehaviorVersion=5)


def kv(value, depth=0):
    if isinstance(value,dict):
        return '{\n'+''.join('    '*(depth+1)+k+' = '+kv(v,depth+1)+'\n' for k,v in value.items())+'    '*depth+'}'
    if isinstance(value,list):return '[ '+', '.join(kv(v,depth) for v in value)+' ]'
    if isinstance(value,str) and value.startswith('resource:'):return 'resource:'+json.dumps(value[9:])
    return json.dumps(value)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    for name,reveal in zip(PARTICLE_NAMES,(False,True)):
        (OUT/(name+'.vpcf')).write_text(HEADER+kv(silhouette(reveal))+'\n',encoding='utf-8')
    material=STAGE/MATERIAL
    material.parent.mkdir(parents=True,exist_ok=True)
    # Supply actual opaque-white pixels. The material compiler interpreted the
    # old inline TextureColor [1 1 1 1] as near-black texture data (RGBA 0,1,0,255).
    # This tiny constant shader input is independent of artist-authored textures.
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    size=8
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))
    png+=chunk(b'IDAT',zlib.compress((b'\0'+b'\xff'*(size*4))*size))+chunk(b'IEND',b'')
    (STAGE/WHITE_TEXTURE).write_bytes(png)
    material.write_text('''"Layer0"
{
    "shader" "global_lit_simple.vfx"
    "F_FULLBRIGHT" "1"
    "F_TRANSLUCENT" "1"
    "F_ADDITIVE_BLEND" "0"
    "F_SPECULAR" "0"
    "F_NORMAL_MAP" "0"
    "TextureColor" "materials/survival_buildings/build_white_glow_color.png"
    "g_vColorTint" "[1 1 1 1]"
    "g_flOverbrightFactor" "3.0"
    "g_flOpacityScale" "1.0"
}
''',encoding='utf-8')
    print('BUILDING_WHITE_REVEAL_SOURCES particles=2 material=1 opaque_white_texture=1 fade_seconds=0.9')


if __name__=='__main__':main()
