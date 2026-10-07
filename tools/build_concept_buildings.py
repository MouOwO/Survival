"""Build approved village concepts into real Source 2 assets, keeping runtime IDs.
Blender 4.2 --background --python tools/build_concept_buildings.py -- [asset names]
"""
import bpy,bmesh,math,json,sys,re,shutil,os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from concept_building_geometry import ConceptKit,PALETTE
import unique_building_detail as detail
import unique_building_bake as baking
from build_building_flow_materials import REVEAL_STEPS
OUT=Path(os.environ.get('SURVIVAL_BUILD_OUTPUT',str(ROOT/'output/building_models_20260927')));MODELS=OUT/'source/models/survival_buildings';MATS=OUT/'source/materials/survival_buildings'
for p in [MODELS,MATS,OUT/'previews']:p.mkdir(parents=True,exist_ok=True)
jobs=[(f'main_city_lv{i:02}','city',i) for i in range(1,6)]
jobs += [(f'population_farm_lv{i:02}','farm',i) for i in range(1,6)]
jobs += [(f'gold_mine_lv{i:02}','mine',i) for i in range(1,11)]
jobs += [('research_lab','laboratory',False),('advanced_research_lab','laboratory',True),('hero_altar','altar',None),('challenge_arena','challenge',None)]
jobs += [(f'wall_lv{i:02}','defensive_wall',i) for i in range(1,11)]
jobs += [(f'archive_challenge_{i:02}','archive_challenge',i) for i in range(1,4)]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
selected=[j for j in jobs if not args or j[0] in args];assert selected
manifest=json.loads((OUT/'manifest.json').read_text()) if (OUT/'manifest.json').exists() else []
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
materials={}
for key,color in PALETTE.items():
 m=bpy.data.materials.new('author_'+key);m.diffuse_color=(*color,1);m.use_nodes=True
 m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*color,1);materials[key]=m
detail.prepare_materials(materials,PALETTE,MATS,modeled_surfaces=True)
try:
 pref=bpy.context.preferences.addons['cycles'].preferences;pref.compute_device_type='CUDA';pref.get_devices()
 for d in pref.devices:d.use=d.type=='CUDA'
 if any(d.type=='CUDA' for d in pref.devices):scene.cycles.device='GPU'
except Exception as e:print('GPU_FALLBACK',e,flush=True)
scene.world=bpy.data.worlds.new('Concept studio');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.19,.23,.25,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
bpy.ops.object.camera_add(location=(420,-560,420));camera=bpy.context.object;camera.data.type='ORTHO';scene.camera=camera
for loc,power,size in [((140,-300,550),2600000,300),((-350,-70,280),1300000,260),((80,330,460),2400000,220)]:
 bpy.ops.object.light_add(type='AREA',location=loc);lamp=bpy.context.object;lamp.data.energy=power;lamp.data.shape='DISK';lamp.data.size=size
 lamp.rotation_euler=(Vector((0,0,100))-lamp.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=6000,location=(0,0,-.7));floor=bpy.context.object
floor_mat=bpy.data.materials.new('Preview ground');floor_mat.diffuse_color=(.065,.095,.10,1);floor.data.materials.append(floor_mat)
scene.render.resolution_x=850;scene.render.resolution_y=850;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
base_images=set(bpy.data.images);base_materials=set(bpy.data.materials)
for index,(name,kind,level) in enumerate(selected):
 print('CONCEPT_BUILD',index+1,len(selected),name,flush=True)
 k=ConceptKit(927000+next(i for i,j in enumerate(jobs) if j[0]==name))
 getattr(k,kind)(*(() if level is None else (level,)))
 width=248 if kind=='defensive_wall' else (210 if kind=='archive_challenge' else 236)
 lo=[min(v[a] for v in k.v) for a in (0,1)];hi=[max(v[a] for v in k.v) for a in (0,1)]
 factor=width/max(b-a for a,b in zip(lo,hi));center=[(a+b)/2 for a,b in zip(lo,hi)]
 verts=[((x-center[0])*factor,(y-center[1])*factor,max(0,z)*factor) for x,y,z in k.v]
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],k.f);data.update()
 obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj)
 for key in k.keys:data.materials.append(materials[key])
 for f,mat in zip(data.polygons,k.m):f.material_index=mat
 bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
 detail.project_uv(obj);tri=obj.modifiers.new('Runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
 # Cap dense stonework so eight-player towns do not multiply decorative triangles.
 if len(obj.data.polygons)>65000:
  dec=obj.modifiers.new('Decorative triangle budget','DECIMATE');dec.ratio=64000/len(obj.data.polygons)
  bpy.ops.object.modifier_apply(modifier=dec.name)
  tri=obj.modifiers.new('Final runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
 floor.hide_render=True;baking.bake(obj,name,MATS,resolution=2048,color_gain=1.1,cavity_strength=.30)
 rig=baking.rig(obj);rig.rotation_euler[2]=-math.pi/2
 rig.animation_data_create();action=bpy.data.actions.new(name+'_idle');rig.animation_data.action=action
 bone=rig.pose.bones['root'];bone.location=(0,0,0)
 for frame in [1,30]:bone.keyframe_insert(data_path='location',frame=frame)
 scene.frame_start=1;scene.frame_end=30;scene.frame_set(1)
 bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,add_leaf_bones=False)
 height=max(v[2] for v in verts);material='materials/survival_buildings/'+name+'.vmat'
 oldstage=ROOT/('output/reference_walls' if kind=='defensive_wall' else 'output/unique_buildings')/'source/models/survival_buildings'
 template='challenge_arena' if kind=='archive_challenge' else name
 oldtext=(oldstage/(template+'.vmdl')).read_text(encoding='utf-8-sig')
 physics=re.search(r'\{_class="PhysicsShapeList" children=\[\{[^{}]+\}\]\}',oldtext).group(0).replace(template+'_collision',name+'_collision')
 shutil.copy2(oldstage/(template+'_collision.obj'),MODELS/(name+'_collision.obj'))
 radius=width/2;sets=[]
 for label,r,top in [('default',radius,height),('select_low',radius,min(height,180)),('select_high',radius*.80,height)]:
  sets.append('{_class="HitboxSet" name="'+label+'" children=[{_class="Hitbox" name="body" parent_bone="root" hitbox_mins=[-'+str(r)+',-'+str(r)+',0] hitbox_maxs=['+str(r)+','+str(r)+','+str(height if label=="default" else top)+'] surface_property="stone"}]}')
 nodes=[
 '{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'" filename="models/survival_buildings/'+name+'.fbx" import_scale=0.01}]}',
 '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[{from="'+material+'" to="'+material+'"}] use_global_default=false}]}',
 '{_class="BoneMarkupList" children=[] bone_cull_type="None"}',
 '{_class="HitboxSetList" children=['+','.join(sets)+']}',physics,
 '{_class="AttachmentList" children=[{_class="Attachment" name="attach_hitloc" parent_bone="root" relative_origin=[0,0,'+str(height*.5)+'] relative_angles=[0,0,0]}]}',
 '{_class="AnimationList" children=[{_class="AnimFile" name="idle" activity_name="ACT_DOTA_IDLE" looping=true source_filename="models/survival_buildings/'+name+'.fbx" anim_name="'+name+'_rig|'+name+'_idle" import_scale=0.01}]}']
 (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
 uv=obj.data.uv_layers.active;saved=[tuple(v.uv) for v in uv.data]
 for loop in obj.data.loops:
  p=obj.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=((p.x+p.y*.32)/width+.5,1-(.05+.35*p.z/height))
 bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'_flow.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
 for loop,value in zip(uv.data,saved):loop.uv=value
 groups=['{_class="DefaultMaterialGroup" remaps=[{from="'+material+'" to="materials/survival_buildings/build_flow_00.vmat"}] use_global_default=false}']
 for step in range(1,REVEAL_STEPS+1):groups.append('{_class="MaterialGroup" name="reveal_%02d" remaps=[{from="materials/survival_buildings/build_flow_00.vmat" to="materials/survival_buildings/build_flow_%02d.vmat"}]}'%(step,step))
 shell='{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'_white_shell" filename="models/survival_buildings/'+name+'_flow.fbx" import_scale=0.01}]},{_class="MaterialGroupList" children=['+','.join(groups)+']},{_class="BoneMarkupList" children=[] bone_cull_type="None"}]}}'
 (MODELS/(name+'_white_shell.vmdl')).write_text(HEADER+shell,encoding='utf-8')
 entry=dict(name=name,family=kind,stage=level,triangles=len(data.polygons),dimensions=[hi-lo for lo,hi in zip([min(v[a] for v in verts) for a in range(3)],[max(v[a] for v in verts) for a in range(3)])],height=height,model='models/survival_buildings/'+name+'.vmdl',runtime_scale=1,import_scale=.01,texture_resolution=2048,front='-Y',collision_preserved=True,revision='concept_20260927')
 manifest=[a for a in manifest if a['name']!=name]+[entry];manifest.sort(key=lambda a:next(i for i,j in enumerate(jobs) if j[0]==a['name']))
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 rig.rotation_euler[2]=0;rig.hide_render=True;floor.hide_render=False
 target=Vector((0,0,height*.43));camera.location=target+Vector((390,-530,360));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=max(355,height*1.40)
 scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+'.blend')))
 print('CONCEPT_COMPLETE',name,len(data.polygons),'height',height,flush=True)
 bpy.data.objects.remove(obj,do_unlink=True);bpy.data.objects.remove(rig,do_unlink=True)
 for m in set(bpy.data.materials)-base_materials:bpy.data.materials.remove(m,do_unlink=True)
 for im in set(bpy.data.images)-base_images:bpy.data.images.remove(im,do_unlink=True)
print('CONCEPT_BUILD_COMPLETE',len(selected),flush=True)
