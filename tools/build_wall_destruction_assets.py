"""Blender: faceted crystal fragment + finite wall charge / burst particles."""
import bpy
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_building_warp_particles import HEADER,kv,literal,cp,init
OUT=ROOT/'output/wall_destruction'
SOURCE=OUT/'source'
PARTICLES=SOURCE/'particles/survival_buildings'
MODELS=SOURCE/'models/survival_buildings'
MATERIALS=SOURCE/'materials/survival_buildings'
for p in (PARTICLES,MODELS,MATERIALS):p.mkdir(parents=True,exist_ok=True)

def random_float(lo,hi):
    return dict(m_nType='PF_TYPE_RANDOM_UNIFORM',m_flRandomMin=float(lo),m_flRandomMax=float(hi),m_nRandomMode='PF_RANDOM_MODE_CONSTANT')

def base(count,life,radius,texture='materials/particle/particle_glow_05.vtex',alpha=1.,colors=((115,185,255,255),(235,255,255,255))):
    return dict(_class='CParticleSystemDefinition',m_nMaxParticles=max(count,1),m_flConstantRadius=1.,m_ConstantColor=[255,255,255,255],
        m_BoundingBoxMin=[-1000.,-1000.,-600.],m_BoundingBoxMax=[1000.,1000.,1000.],
        m_Renderers=[dict(_class='C_OP_RenderSprites',m_vecTexturesInput=[dict(m_hTexture='resource:'+texture)],m_nOutputBlendMode='PARTICLE_OUTPUT_BLEND_MODE_ADD')],
        m_Initializers=[init(1,life if isinstance(life,dict) else literal(life)),init(3,radius if isinstance(radius,dict) else literal(radius)),init(7,literal(alpha)),
            init(4,random_float(0,360)),dict(_class='C_INIT_RandomColor',m_ColorMin=list(colors[0]),m_ColorMax=list(colors[1])),
            dict(_class='C_INIT_CreateWithinSphere',m_fRadiusMin=0.,m_fRadiusMax=0.)],
        m_Operators=[dict(_class='C_OP_FadeAndKill',m_flStartAlpha=1.,m_flStartFadeInTime=0.,m_flEndFadeInTime=0.,m_flStartFadeOutTime=.25,m_flEndFadeOutTime=1.)],
        m_Emitters=[dict(_class='C_OP_InstantaneousEmitter',m_flStartTime=literal(0),m_nParticlesToEmit=literal(count))],m_nBehaviorVersion=5)

def sphere(p,rmin,rmax,vmin=0,vmax=0):
    p['m_Initializers'][-1].update(m_fRadiusMin=float(rmin),m_fRadiusMax=float(rmax),m_fSpeedMin=float(vmin),m_fSpeedMax=float(vmax))

charge=base(1,1.,cp(0,1.5),alpha=.9)
charge['m_Operators'][0].update(m_flStartAlpha=0.,m_flEndFadeInTime=.85,m_flStartFadeOutTime=.95)
charge['m_Operators'].append(dict(_class='C_OP_InterpolateRadius',m_flStartScale=.12,m_flEndScale=1.0))
sparks=base(96,random_float(.18,.38),random_float(4,8),alpha=.9)
sphere(sparks,95,155,-260,-160)
sparks['m_Emitters']=[dict(_class='C_OP_ContinuousEmitter',m_flStartTime=literal(0),m_flEmissionDuration=literal(.86),m_flEmitRate=literal(95))]
sparks['m_Operators'].append(dict(_class='C_OP_BasicMovement'))
flash=base(1,.34,cp(0,3.5),alpha=1.,colors=((215,242,255,255),(255,255,255,255)))
flash['m_Operators'].append(dict(_class='C_OP_InterpolateRadius',m_flStartScale=.4,m_flEndScale=1.6))
ring=base(1,.65,cp(0,3.),'materials/particle/ring01.vtex',alpha=.9)
ring['m_Renderers'][0]['m_nOrientationType']='PARTICLE_ORIENTATION_WORLD_Z_ALIGNED'
ring['m_Operators'].append(dict(_class='C_OP_InterpolateRadius',m_flStartScale=.16,m_flEndScale=1.))
shards=base(44,random_float(.7,1.45),random_float(.65,1.7))
sphere(shards,12,65,240,470)
shards['m_Renderers']=[dict(_class='C_OP_RenderModels',m_ModelList=[dict(m_model='resource:models/survival_buildings/wall_death_shard.vmdl')],
    m_bOriginalModel=True,m_bOrientZ=True,m_bDisableShadows=True,m_nLOD=0)]
shards['m_Initializers'].append(init(12,random_float(0,360)))
shards['m_Operators']+=[dict(_class='C_OP_BasicMovement',m_Gravity=[0.,0.,-460.]),
    dict(_class='C_OP_RampScalarLinearSimple',m_nField=4,m_Rate=2.6),dict(_class='C_OP_InterpolateRadius',m_flStartScale=1.,m_flEndScale=.25)]
dust=base(28,random_float(.4,.9),random_float(10,32),alpha=.24)
sphere(dust,20,70,90,230)
dust['m_Operators']+=[dict(_class='C_OP_BasicMovement',m_Gravity=[0.,0.,-110.]),dict(_class='C_OP_InterpolateRadius',m_flStartScale=.7,m_flEndScale=2.3)]
for name,p in [('charge',charge),('sparks',sparks),('flash',flash),('ring',ring),('shards',shards),('dust',dust)]:
    (PARTICLES/('wall_death_'+name+'.vpcf')).write_text(HEADER+kv(p)+'\n',encoding='utf-8')

# Small real 3D crystal fragments; facets keep their shape while spinning.
bpy.ops.wm.read_factory_settings(use_empty=True)
mesh=bpy.data.meshes.new('Crystal debris')
mesh.from_pydata([(0,0,16),(0,0,-11),(-5,0,1),(0,-4,1),(6,0,1),(0,5,1)],[],
    [(0,2,3),(0,3,4),(0,4,5),(0,5,2),(1,3,2),(1,4,3),(1,5,4),(1,2,5)])
mesh.update();obj=bpy.data.objects.new('wall_death_shard',mesh);bpy.context.collection.objects.link(obj)
for name,color in [('deep',(.09,.32,.60)),('cyan',(.18,.76,.94)),('white',(.78,.96,1.))]:
    matname='materials/survival_buildings/wall_death_'+name+'.vmat'
    mat=bpy.data.materials.new(matname);mat.diffuse_color=(*color,1);mesh.materials.append(mat)
    (MATERIALS/('wall_death_'+name+'.vmat')).write_text('"Layer0"\n{\n"shader" "global_lit_simple.vfx"\n"F_FULLBRIGHT" "1"\n"F_SPECULAR" "0"\n"TextureColor" "materials/survival_buildings/build_white_glow_color.png"\n"g_vColorTint" "['+' '.join(str(v) for v in color)+' 1]"\n"g_flOverbrightFactor" "1.4"\n}\n',encoding='utf-8')
for i,face in enumerate(mesh.polygons):face.material_index=i%3
bpy.context.view_layer.objects.active=obj;obj.select_set(True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project();bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.export_scene.fbx(filepath=str(MODELS/'wall_death_shard.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
model_header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
(MODELS/'wall_death_shard.vmdl').write_text(model_header+'{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/survival_buildings/wall_death_shard.fbx" import_scale=0.01}]}]}}',encoding='utf-8')
profiles=json.loads((ROOT/'output/reference_walls/manifest.json').read_text(encoding='utf-8'))
registry=['-- Generated wall render heights for the death effect; gameplay bounds are separate.','return {']
for wall in profiles:registry.append('    ["models/survival_buildings/'+wall['name']+'.vmdl"] = '+str(round(wall['dimensions'][2],4))+',')
registry.append('}')
(ROOT/'scripts/vscripts/config/generated/wall_destruction_models.lua').write_text('\n'.join(registry)+'\n',encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps(dict(particles=6,fragment_model='wall_death_shard',fragment_triangles=8,shake_seconds=1.,burst_seconds=.34,fragment_max_lifetime=1.45,cleanup_seconds=2.6),indent=2),encoding='utf-8')
print('WALL_DESTRUCTION_SOURCES particles=6 model=1 materials=3 heights=10')
