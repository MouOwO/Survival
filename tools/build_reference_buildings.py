"""Build all 24 reference-led buildings and real-mesh previews in Blender.

blender --background --python tools/build_reference_buildings.py
Optional after --: asset names. Partial rebuilds preserve other finished assets.
"""
import bpy
import sys
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from reference_building_geometry import Kit, PALETTE
from sync_reference_building_config import SCALE
from reference_building_modeldoc import resize_modeldoc, MODEL_SOURCE_SCALE
import unique_building_detail as detail
import unique_building_bake as baking

OUT=ROOT/'output/unique_buildings'
MODELS=OUT/'source/models/survival_buildings'
MATS=OUT/'source/materials/survival_buildings'
for p in (MODELS,MATS,OUT/'previews'):p.mkdir(parents=True,exist_ok=True)
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
jobs=[(f'main_city_lv{i:02}', 'city',i) for i in range(1,6)]
jobs += [(f'population_farm_lv{i:02}','farm',i) for i in range(1,6)]
jobs += [(f'gold_mine_lv{i:02}','mine',i) for i in range(1,11)]
jobs += [('research_lab','laboratory',False),('advanced_research_lab','laboratory',True),('hero_altar','altar',None),('challenge_arena','challenge',None)]
all_jobs=list(jobs)
previous=[]
if args:
    jobs=[j for j in jobs if j[0] in args]
    if (OUT/'manifest.json').exists():previous=json.loads((OUT/'manifest.json').read_text())
assert jobs,'No matching assets'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.name='Radiant reference village - 24 variants'
materials={}
for key,color in PALETTE.items():
    m=bpy.data.materials.new('author_'+key);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=.78
    materials[key]=m
detail.prepare_materials(materials,PALETTE,MATS,modeled_surfaces=True)
scene.world=bpy.data.worlds.new('Neutral warm daylight');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.36,.40,.44,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7
bpy.ops.object.camera_add(location=(190,-280,210));camera=bpy.context.object
camera.data.type='ORTHO';scene.camera=camera
for loc,power,size in [((30,-160,230),850000,150),((-170,-40,160),500000,160),((90,140,230),700000,120)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object
    o.data.energy=power;o.data.size=size;o.rotation_euler=(Vector((0,0,35))-o.location).to_track_quat('-Z','Y').to_euler()
floor_mat=bpy.data.materials.new('Preview neutral ground');floor_mat.diffuse_color=(.22,.235,.21,1)
bpy.ops.mesh.primitive_plane_add(size=2000,location=(0,0,-.25));floor=bpy.context.object;floor.name='Preview only ground';floor.data.materials.append(floor_mat)
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
selected={j[0] for j in jobs}
manifest=[a for a in previous if a['name'] not in selected];objects=[]
header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
for index,(name,kind,level) in enumerate(jobs):
    print('BUILD_REFERENCE',index+1,len(jobs),name,flush=True)
    k=Kit(906160+next(i for i,j in enumerate(all_jobs) if j[0]==name))
    if level is None:getattr(k,kind)()
    else:getattr(k,kind)(level)
    # Equal nominal footprint across building types. One uniform transform, never
    # stretching individual axes; runtime applies the configured uniform scale.
    extent=[max(v[i] for v in k.v)-min(v[i] for v in k.v) for i in range(3)]
    scale=118/max(extent[:2])
    cx=(min(v[0] for v in k.v)+max(v[0] for v in k.v))/2
    cy=(min(v[1] for v in k.v)+max(v[1] for v in k.v))/2
    # Flatten only below-ground rock/root vertices. Translating every vertex up
    # by the lowest rock would leave mine entrances and timber feet floating.
    # Bake -90 degrees into the source geometry; imported models face world -Y
    # at entity yaw=0, including their very first visible frame.
    vertices=[((y-cy)*scale,-(x-cx)*scale,max(0,z)*scale) for x,y,z in k.v]
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],k.f);data.update()
    o=bpy.data.objects.new(name,data);scene.collection.objects.link(o)
    for key in k.keys:data.materials.append(materials[key])
    for face,mat in zip(data.polygons,k.m):face.material_index=mat
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
    detail.project_uv(o)
    mod=o.modifiers.new('Runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
    floor.hide_render=True
    baking.bake(o,name,MATS,resolution=2048)
    arm=baking.rig(o)
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
    arm.hide_render=True;arm.hide_set(True)
    height=float(o.dimensions.z);sets=[]
    for set_name,r,top in [('default',59,height),('select_low',59,min(height,100)),('select_high',43,min(height,78))]:
        sets.append('{_class="HitboxSet" name="'+set_name+'" children=[{_class="Hitbox" name="root" parent_bone="root" hitbox_mins=[-'+str(r)+',-'+str(r)+',0] hitbox_maxs=['+str(r)+','+str(r)+','+str(top)+'] surface_property="default" translation_only=false group_id=0}]}')
    # A simple eight-sided closed convex collider, independent of roof detail.
    # ModelDoc reads OBJ as Y-up. Encode (x,z,-y); compiled hulls are then
    # Z-up and grounded, in Source units (no FBX centimetre conversion).
    hull_height=min(52,height*.7);hull_radius=48 if kind=='city' else 42
    hv=[(hull_radius*math.cos(i*math.tau/8),hull_radius*math.sin(i*math.tau/8),z) for z in (0,hull_height) for i in range(8)]
    hf=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    (MODELS/(name+'_collision.obj')).write_text('\n'.join(['o '+name+'_collision']+['v %.5f %.5f %.5f'%(x,z,-y) for x,y,z in hv]+['f '+' '.join(str(i+1) for i in f) for f in hf])+'\n')
    material='materials/survival_buildings/'+name+'.vmat'
    nodes=[
        '{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'" filename="models/survival_buildings/'+name+'.fbx" import_scale=0.01}]}',
        '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[{from="'+material+'" to="'+material+'"}] use_global_default=false}]}',
        '{_class="HitboxSetList" children=['+','.join(sets)+']}',
        '{_class="BoneMarkupList" children=[] bone_cull_type="None"}',
        '{_class="PhysicsShapeList" children=[{_class="PhysicsHullFile" name="building_body" filename="models/survival_buildings/'+name+'_collision.obj" parent_bone="root" surface_prop="stone" collision_tags="solid" import_scale=1.0}]}',
    ]
    (MODELS/(name+'.vmdl')).write_text(resize_modeldoc(header+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}'))
    manifest.append(dict(name=name,revision=4,family=kind,stage=level,triangles=len(o.data.polygons),dimensions=list(o.dimensions),minimum=[min(v.co[i] for v in data.vertices) for i in range(3)],materials=[material],uv_layers=1,texture_resolution=2048,root_bone='root',selection_sets=['default','select_low','select_high'],baseplate=False,runtime_scale=float(SCALE),collision_radius=hull_radius,collision_height=hull_height))
    manifest.sort(key=lambda a:next(i for i,j in enumerate(all_jobs) if j[0]==a['name']))
    next(a for a in manifest if a['name']==name)['model_source_scale']=MODEL_SOURCE_SCALE
    next(a for a in manifest if a['name']==name)['baked_yaw_degrees']=-90
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
    floor.hide_render=False
    scene.render.engine='CYCLES';scene.cycles.samples=32
    target=Vector((0,0,height*.44));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=max(161,height*1.47)
    scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
    o.hide_render=True;o.hide_set(True);objects.append((o,arm))
    print('REFERENCE_ASSET_COMPLETE',name,'triangles',len(o.data.polygons),flush=True)
if args and (OUT/'survival_buildings.blend').exists():
    keep={a['name'] for a in previous if a['name'] not in selected}
    with bpy.data.libraries.load(str(OUT/'survival_buildings.blend'),link=False) as (src,dst):
        dst.objects=[name for name in src.objects if name in keep or name.removesuffix('_rig') in keep]
    for obj in dst.objects:
        if obj is not None:scene.collection.objects.link(obj)
    for obj in dst.objects:
        if obj is not None and obj.name in keep:objects.append((obj,obj.parent))
objects.sort(key=lambda pair:next(i for i,j in enumerate(all_jobs) if j[0]==pair[0].name))
for i,(o,arm) in enumerate(objects):
    arm.hide_set(False);o.hide_set(False);o.hide_render=False
    arm.location=((i%5)*165,(i//5)*185,0)
if args:
    # Blender protects files used as an append library even after local copies
    # are made. Save a complete temporary scene, then replace the old source.
    staged_blend=OUT/'survival_buildings_rebuilt.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend))
    staged_blend.replace(OUT/'survival_buildings.blend')
else:
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'survival_buildings.blend'))
print('REFERENCE_BUILDINGS_COMPLETE',len(manifest),flush=True)
