"""Blender: ten reference wall meshes, baked atlases, collision, flow shells and previews.

blender --background --python tools/build_reference_walls.py -- [wall_lv01 ...]
Normal assets use 0.01 FBX import, scale 1.0 and fit a 4x4, 256-unit footprint.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from reference_wall_geometry import WallKit, PALETTE, NAMES
import unique_building_detail as detail
import unique_building_bake as baking
from wall_asset_spec import HEIGHT_MULTIPLIER, WEATHERING
from wall_surface_materials import make_materials, project_surfaces

OUT=ROOT/'output/reference_walls'
MODELS=OUT/'source/models/survival_buildings'
MATS=OUT/'source/materials/survival_buildings'
for p in (MODELS,MATS,OUT/'previews'):p.mkdir(parents=True,exist_ok=True)
selected=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
jobs=[(f'wall_lv{i:02}',i) for i in range(1,11) if not selected or f'wall_lv{i:02}' in selected]
assert jobs,'No matching wall names'
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8')) if (OUT/'manifest.json').exists() else []
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.world=bpy.data.worlds.new('Wall preview daylight');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.4,.43,.48,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
bpy.ops.object.camera_add(location=(340,-440,355));camera=bpy.context.object;scene.camera=camera;camera.data.type='ORTHO'
for loc,power,size in [((80,-330,450),1800000,220),((-320,-50,230),950000,250),((120,350,380),1300000,190)]:
    bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.size=size
    light.rotation_euler=(Vector((0,0,65))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=22000,location=(0,0,-.4));floor=bpy.context.object;floor.name='Preview ground only'
ground=bpy.data.materials.new('Neutral ground');ground.diffuse_color=(.22,.215,.20,1);floor.data.materials.append(ground)
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
for name,stage in jobs:
    print('WALL_BUILD',name,flush=True)
    k=WallKit(92700+stage).wall(stage)
    width=max(max(p[a] for p in k.v)-min(p[a] for p in k.v) for a in (0,1))
    factor=248/width
    base_height=max(max(0,z)*factor for x,y,z in k.v)
    verts=[(x*factor,y*factor,max(0,z)*factor*HEIGHT_MULTIPLIER) for x,y,z in k.v]
    used_keys=[key for i,key in enumerate(k.keys) if i in k.m or key=='wood_end']
    stage_materials_before=set(bpy.data.materials)
    stage_images_before=set(bpy.data.images)
    materials=make_materials({key:PALETTE[key] for key in used_keys},stage,base_height*HEIGHT_MULTIPLIER)
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],k.f);data.update()
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj)
    for key in used_keys:data.materials.append(materials[key])
    for face,mat in zip(data.polygons,k.m):face.material_index=used_keys.index(k.keys[mat])
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
    detail.project_uv(obj)
    project_surfaces(obj,k.surface_parts,stage)
    triangulate=obj.modifiers.new('Runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=triangulate.name)
    floor.hide_render=True
    baking.bake(obj,name,MATS,resolution=2048,color_gain=1.0,cavity_strength=.50,atlas_margin=.0015)
    rig=baking.rig(obj)
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
    height=float(obj.dimensions.z)
    # A separate copy keeps the artist atlas and the height-mask UVs independent.
    uv=obj.data.uv_layers.active
    saved=[tuple(v.uv) for v in uv.data]
    for loop in obj.data.loops:
        p=obj.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=((p.x+p.y*.32)/248+.5,1-(.05+.35*p.z/height))
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'_flow.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
    for loop,value in zip(uv.data,saved):loop.uv=value
    physics_height=min(118,base_height*.73)*HEIGHT_MULTIPLIER
    hv=[(x,y,z) for z in (0,physics_height) for x,y in [(-122,-122),(122,-122),(122,122),(-122,122)]]
    hf=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    (MODELS/(name+'_collision.obj')).write_text('\n'.join(['o '+name+'_collision']+['v %.5f %.5f %.5f'%(x,z,-y) for x,y,z in hv]+['f '+' '.join(str(i+1) for i in face) for face in hf])+'\n',encoding='utf-8')
    sets=[]
    for label,r,top in [('default',124,height),('select_low',124,min(height,125*HEIGHT_MULTIPLIER)),('select_high',113,height)]:
        sets.append('{_class="HitboxSet" name="'+label+'" children=[{_class="Hitbox" name="root" parent_bone="root" hitbox_mins=[-'+str(r)+',-'+str(r)+',0] hitbox_maxs=['+str(r)+','+str(r)+','+str(top)+'] surface_property="stone" translation_only=false group_id=0}]}')
    mat='materials/survival_buildings/'+name+'.vmat'
    nodes=[
      '{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'" filename="models/survival_buildings/'+name+'.fbx" import_scale=0.01}]}',
      '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[{from="'+mat+'" to="'+mat+'"}] use_global_default=false}]}',
      '{_class="HitboxSetList" children=['+','.join(sets)+']}',
      '{_class="BoneMarkupList" children=[] bone_cull_type="None"}',
      '{_class="PhysicsShapeList" children=[{_class="PhysicsHullFile" name="wall_body" filename="models/survival_buildings/'+name+'_collision.obj" parent_bone="root" surface_prop="stone" collision_tags="solid" import_scale=1.0}]}',
    ]
    (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    manifest=[a for a in manifest if a['name']!=name]
    manifest.append(dict(name=name,stage=stage,display_name=NAMES[stage-1]+'城墙',dimensions=list(obj.dimensions),triangles=len(data.polygons),texture_resolution=2048,footprint=[4,4],runtime_scale=1,import_scale=.01,baked_yaw_degrees=0,collision_half_width=122,collision_height=physics_height,height_multiplier=HEIGHT_MULTIPLIER,original_height=base_height,weathering=WEATHERING[stage-1],revision=2))
    manifest.sort(key=lambda a:a['stage'])
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    floor.hide_render=False;rig.hide_render=True
    target=Vector((0,0,height*.51))
    camera.location=target+Vector((410,-530,390))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=max(620,height*1.55)
    scene.render.engine='CYCLES';scene.cycles.samples=24
    scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+'.blend')))
    print('WALL_COMPLETE',name,'triangles',len(data.polygons),'height',height,flush=True)
    bpy.data.objects.remove(obj,do_unlink=True);bpy.data.objects.remove(rig,do_unlink=True)
    for material in set(bpy.data.materials)-stage_materials_before:bpy.data.materials.remove(material,do_unlink=True)
    for im in set(bpy.data.images)-stage_images_before:bpy.data.images.remove(im,do_unlink=True)
print('REFERENCE_WALLS_COMPLETE',len(jobs),flush=True)
