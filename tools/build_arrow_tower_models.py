"""Build reference-inspired LV1-5 stone ballista towers; Blender 4.2 background."""
import bpy,bmesh,math,json,sys,random
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import reference_building_geometry as geom
import unique_building_detail as detail
import unique_building_bake as baking
OUT=ROOT/'output/tower_models_20260926'
MODELS=OUT/'source/models/survival_buildings';MATS=OUT/'source/materials/survival_buildings'
for p in [MODELS,MATS,OUT/'previews']:p.mkdir(parents=True,exist_ok=True)
geom.PALETTE.update(stone=(.32,.35,.34),limestone=(.47,.47,.40),ivory=(.62,.58,.44),basalt=(.13,.17,.18),wood=(.16,.085,.036),wood_light=(.28,.16,.065),slate=(.045,.16,.19),teal=(.07,.23,.25),brass=(.43,.26,.075),gold=(.76,.48,.12),blue=(.12,.44,.48),green=(.17,.24,.10),leaf=(.26,.32,.13),shadow=(.024,.028,.025))
bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
materials={}
for key,color in geom.PALETTE.items():
 m=bpy.data.materials.new('author_'+key);m.diffuse_color=(*color,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
 materials[key]=m
detail.prepare_materials(materials,geom.PALETTE,MATS,modeled_surfaces=True)
# Use the installed GPU when available; CPU fallback remains supported.
try:
 pref=bpy.context.preferences.addons['cycles'].preferences;pref.compute_device_type='CUDA';pref.get_devices()
 for device in pref.devices:device.use=device.type=='CUDA'
 if any(d.type=='CUDA' for d in pref.devices):scene.cycles.device='GPU'
except Exception:pass
scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.22,.24,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
bpy.ops.object.camera_add(location=(285,-390,300));camera=bpy.context.object;camera.data.type='ORTHO';scene.camera=camera
for loc,power,size in [((90,-190,350),1700000,210),((-200,-50,150),800000,160),((40,180,320),1800000,140)]:
 bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
 light.rotation_euler=(Vector((0,0,95))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=3000,location=(0,0,-.6));floor=bpy.context.object
floor_mat=bpy.data.materials.new('Slate preview ground');floor_mat.diffuse_color=(.07,.105,.105,1);floor.data.materials.append(floor_mat)
scene.render.resolution_x=850;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
manifest=[];finished=[]
def banner(k,x,y,top,length,width,angle=0):
 # Tapered hanging cloth, a geometric embroidered gold arrow crest.
 rot=Matrix.Rotation(angle,3,'Z')
 def pos(a,b,c):return Vector((x,y,top))+rot@Vector((a,b,c))
 verts=[pos(-width/2,0,0),pos(width/2,0,0),pos(width*.43,-.5,-length*.85),pos(0,-.8,-length),pos(-width*.43,-.5,-length*.85)]
 k.mesh(verts,[(0,1,2,3,4),(4,3,2,1,0)],'slate')
 for a,b in [(0,1),(1,2),(2,3),(3,4),(4,0)]:k.beam(verts[a]+Vector((0,-.35,0)),verts[b]+Vector((0,-.35,0)),.8,'gold')
 k.beam(pos(0,-1.2,-length*.2),pos(0,-1.2,-length*.72),1.2,'gold')
 for side in [-1,1]:
  k.beam(pos(0,-1.3,-length*.2),pos(side*width*.23,-1.3,-length*.40),1.4,'gold')
  k.beam(pos(0,-1.3,-length*.65),pos(side*width*.2,-1.3,-length*.52),1,'brass')
 k.beam(pos(-width*.65,0,2),pos(width*.65,0,2),1.7,'brass')
def make_tower(level):
 k=geom.Kit(9300+level);w=42+level*5;h=68+level*22;z0=12
 # Grounded dressed-stone footings, not a display disc.
 k.box((0,0,4),(w+29,w+29,8),'basalt',1.8)
 k.wall((0,0,8),w+22,w+22,10)
 k.box((0,0,19),(w+25,w+25,4),'limestone',.8)
 k.wall((0,0,z0+8),w,w,h-20)
 # Corner quoin towers and stepped buttresses become heavier each tier.
 for x in [-w/2,w/2]:
  for y in [-w/2,w/2]:
   if level==1:
    k.box((x,y,h*.58),(6,6,h*.84),'wood',.6)
    for zz in [30,h-10]:k.box((x,y,zz),(7.5,7.5,3),'brass',.5)
   else:
    for row in range(int((h-20)/13)):
     k.box((x,y,26+row*13),(10+(row%2)*2,10+(1-row%2)*2,12.4),'limestone',.6)
    k.box((x,y,33),(16+level,16+level,35),'stone',1)
    k.box((x,y,52),(18+level,18+level,4),'limestone',.6)
    if level>=4:
     k.box((x,y,72),(12+level,12+level,34),'stone',.8)
     k.box((x,y,90),(14+level,14+level,4),'ivory',.6)
 # Arrow slits, timber entrance and stepped threshold on the front.
 for side in [-1,1]:
  for height in ([h*.55] if level<3 else [h*.4,h*.7]):
   k.box((side*(w/2+1.7),0,height),(1,3,16),'shadow',0)
   for yy in [-3,3]:k.box((side*(w/2+2.2),yy,height),(2,2,18),'limestone',.3)
 k.box((0,-w/2-2,31),(14,1,23),'shadow',.4)
 for xx in [-5,-2.5,0,2.5,5]:k.box((xx,-w/2-2.8,31),(2.1,1.4,20),'wood',.2)
 for xx in [-9,9]:k.box((xx,-w/2-3,30),(4,4,26),'limestone',.4)
 k.box((0,-w/2-3,44),(22,4,5),'limestone',.7)
 for j in range(3):k.box((0,-w/2-7-j*4,10-j*2),(22+j*4,5,3),'stone',.5)
 banner(k,0,-w/2-3,h-7,h*.39,16+level*2)
 if level>=4:banner(k,w/2+3,0,h-8,h*.42,20,math.pi/2)
 # Corbels and platform, keeping the top silhouette different at each tier.
 deck=h+8;pw=w+18
 for side in [-1,1]:
  for q in [-.35,0,.35]:
   k.beam((side*w/2,q*w,h-10),(side*(pw/2-1),q*w,h+5),4,'wood_light' if level<3 else 'limestone')
   k.beam((q*w,side*w/2,h-10),(q*w,side*(pw/2-1),h+5),4,'wood_light' if level<3 else 'limestone')
 k.box((0,0,deck),(pw,pw,5),'wood' if level<3 else 'limestone',1)
 for j in range(9):k.box((0,(j-4)*pw/9,deck+3),(pw-5,pw/9-.6,1.5),'wood_light',.3)
 if level==1:
  for side in [-1,1]:
   for q in [-pw/2+3,pw/2-3]:k.box((side*(pw/2-2),q,deck+9),(3,3,15),'wood',.4)
   k.beam((side*(pw/2-2),-pw/2+2,deck+15),(side*(pw/2-2),pw/2-2,deck+15),2.5,'wood_light')
 elif level==2:
  # Four sloping slate roof skirts leave a central flat ballista platform.
  for side in [-1,1]:
   for row in range(3):
    t=row/3;nx=(pw*.60)*(1-t)+14*t;zz=deck-8+18*t
    for j in range(10):
     yy=(j-4.5)*pw/10
     k.box((side*nx,yy,zz),(pw*.18,pw/10-.4,2),'teal' if (row+j)%4==0 else 'slate',.4,Matrix.Rotation(side*-.53,3,'Y'))
     k.box((yy,side*nx,zz),(pw/10-.4,pw*.18,2),'slate',.4,Matrix.Rotation(side*.53,3,'X'))
  k.box((0,0,deck+13),(33,33,4),'wood_light',.8);deck+=15
 else:
  for side in [-1,1]:
   k.box((0,side*(pw/2-3),deck+7),(pw,7,11),'stone',.5)
   k.box((side*(pw/2-3),0,deck+7),(7,pw,11),'stone',.5)
   for j in range(5):
    q=(j-2)*(pw-8)/4
    k.box((q,side*(pw/2-3),deck+17),(10,9,12),'limestone',.8)
    if j not in (0,4):k.box((side*(pw/2-3),q,deck+17),(9,10,12),'limestone',.8)
  if level>=4:
   for side in [-1,1]:
    k.box((0,side*(pw/2+.7),deck-1),(pw,1.8,3),'gold',.2)
    k.box((side*(pw/2+.7),0,deck-1),(1.8,pw,3),'gold',.2)
 # Rotating spindle and detailed torsion ballista; all pieces are real geometry.
 tz=deck+20+(2 if level>=3 else 0);armspan=32+level*3
 k.cone((0,0,deck+8),11,9,12,'basalt',16);k.ring((0,0,deck+12),10,1.2,'brass',n=16)
 k.box((0,0,tz),(11,46+level*3,7),'wood',.7)
 for x in [-7,7]:k.beam((x,-26,tz+2),(x,27,tz+2),2,'brass' if level>=4 else 'wood_light')
 for x in [-12,12]:
  k.box((x,-11,tz+1),(9,11,16),'wood_light',.6)
  for zz in [-6,6]:k.box((x,-11,tz+zz),(10,12,2),'brass',.3)
  k.cone((x,-11,tz+2),2.5,2.5,18,'ivory',10)
 for side in [-1,1]:
  a=(side*8,-9,tz+4);b=(side*armspan*.68,-12,tz+6);c=(side*armspan,-23,tz+9)
  k.beam(a,b,3.8,'wood_light');k.beam(b,c,3,'brass' if level==5 else 'wood_light')
  k.beam(c,(0,17,tz+4),.65,'ivory')
  k.beam((side*10,15,tz-5),(side*17,24,tz-5),1.6,'basalt')
 # Bolt, broad metal spearhead, fletching and a rear crank.
 k.beam((0,17,tz+7),(0,-37,tz+7),1.2,'wood_light')
 k.mesh([(-3,-34,tz+7),(3,-34,tz+7),(0,-46,tz+7),(0,-36,tz+10),(0,-36,tz+5)],[(0,3,2),(3,1,2),(1,4,2),(4,0,2),(0,4,1,3)],'ivory')
 for side in [-1,1]:k.mesh([(0,18,tz+7),(side*4,23,tz+11),(side*4,14,tz+11),(0,10,tz+7)],[(0,1,2,3),(3,2,1,0)],'slate')
 k.beam((-14,21,tz-4),(14,21,tz-4),1.5,'basalt')
 for side in [-1,1]:k.beam((side*14,21,tz-4),(side*14,21,tz+2),1.8,'wood_light')
 if level==5:
  for x in [-w/2-10,w/2+10]:
   k.wall((x,w/2+5,10),13,13,h*.35)
   k.box((x,w/2+5,h*.35+13),(18,18,5),'limestone',.5)
   k.cone((x,w/2+5,h*.35+19),5,0,8,'brass',8)
 # Sparse grounded rubble/greenery, within the existing two-cell footprint.
 for i in range(12):
  a=k.rng.uniform(0,math.tau);r=(w+22)*.57
  k.rock((math.cos(a)*r,math.sin(a)*r,2),(k.rng.uniform(4,9),k.rng.uniform(4,8),5),'stone')
 for x,y in [(-w*.65,w*.48),(w*.58,-w*.53)]:
  for i in range(3):k.rock((x+i*2,y,3+i),(5,5,7),'green')
 return k,tz
for level in range(1,6):
 name=f'arrow_tower_lv{level:02}';print('TOWER_BUILD',name,flush=True)
 k,tz=make_tower(level)
 # Rotate the authored front -Y to the engine's +X forward; attachments agree.
 verts=[(-y,x,max(0,z)) for x,y,z in k.v]
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],k.f);data.update()
 o=bpy.data.objects.new(name,data);scene.collection.objects.link(o)
 for key in k.keys:data.materials.append(materials[key])
 for face,mat in zip(data.polygons,k.m):face.material_index=mat
 bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 detail.project_uv(o);tri=o.modifiers.new('Runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
 floor.hide_render=True;baking.bake(o,name,MATS,resolution=2048,color_gain=1.1,cavity_strength=.28)
 arm=baking.rig(o)
 # Source FBX import adds +90 degrees around Z; compensate on the export rig.
 arm.rotation_euler[2]=-math.pi/2
 # An explicit idle clip prevents engine reset-to-idle errors on static buildings.
 arm.animation_data_create();action=bpy.data.actions.new(name+'_idle');arm.animation_data.action=action
 bone=arm.pose.bones['root'];bone.location=(0,0,0);bone.keyframe_insert(data_path='location',frame=1);bone.keyframe_insert(data_path='location',frame=30)
 scene.frame_start=1;scene.frame_end=30;scene.frame_set(1)
 bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,add_leaf_bones=False)
 extent=math.ceil(max(abs(v[i]) for v in verts for i in (0,1)))+2
 height=max(v[2] for v in verts);material='materials/survival_buildings/'+name+'.vmat'
 nodes=[
  '{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'" filename="models/survival_buildings/'+name+'.fbx" import_scale=0.01}]}',
  '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[{from="'+material+'" to="'+material+'"}] use_global_default=false}]}',
  '{_class="BoneMarkupList" children=[] bone_cull_type="None"}',
  '{_class="HitboxSetList" children=[{_class="HitboxSet" name="default" children=[{_class="Hitbox" name="body" parent_bone="root" hitbox_mins=[-'+str(extent)+',-'+str(extent)+',0] hitbox_maxs=['+str(extent)+','+str(extent)+','+str(height)+'] surface_property="stone"}]}]}',
  '{_class="AttachmentList" children=[{_class="Attachment" name="attach_attack1" parent_bone="root" relative_origin=[46,0,'+str(tz+7)+'] relative_angles=[0,0,0]},{_class="Attachment" name="attach_hitloc" parent_bone="root" relative_origin=[0,0,'+str(height*.55)+'] relative_angles=[0,0,0]}]}',
  '{_class="AnimationList" children=[{_class="AnimFile" name="idle" activity_name="ACT_DOTA_IDLE" looping=true source_filename="models/survival_buildings/'+name+'.fbx" anim_name="'+name+'_rig|'+name+'_idle" import_scale=0.01}]}',
 ]
 (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
 manifest.append(dict(name=name,level=level,triangles=len(data.polygons),dimensions=list(o.dimensions),height=height,attack_origin=[46,0,tz+7],material=material,model='models/survival_buildings/'+name+'.vmdl',model_scale=.8,import_scale=.01))
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
 # Separate construction shell with the existing height-reveal UV convention.
 shell=o.copy();shell.data=o.data.copy();scene.collection.objects.link(shell);shell.name=name+'_flow'
 for loop in shell.data.loops:
  v=shell.data.vertices[loop.vertex_index].co;shell.data.uv_layers.active.data[loop.index].uv=((v.x+v.y*.32)/120+.5,1-(.05+.35*v.z/height))
 bpy.ops.object.select_all(action='DESELECT');shell.select_set(True);arm.select_set(True);bpy.context.view_layer.objects.active=shell
 bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'_flow.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
 bpy.data.objects.remove(shell,do_unlink=True)
 arm.rotation_euler[2]=0
 floor.hide_render=False;arm.hide_render=True
 scene.render.engine='CYCLES';scene.cycles.samples=32
 target=Vector((0,0,height*.48));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=310
 scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
 o.hide_render=True;o.hide_set(True);arm.hide_set(True);finished.append((o,arm))
 print('TOWER_COMPLETE',name,len(data.polygons),flush=True)
for i,(o,arm) in enumerate(finished):
 o.hide_render=False;o.hide_set(False);arm.hide_set(False);arm.location=(i*150,0,0)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'arrow_towers.blend'))
print('ALL_TOWER_MODELS_READY',flush=True)
