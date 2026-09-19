"""Blender batch authoring: modular Molten Core room, no emissive effects.

blender --background --python tools/build_molten_core_room.py
"""
import bpy,bmesh,json,math,random,sys,struct,zlib
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from molten_room_geometry import build_modules,PALETTE
from molten_room_materials import build_materials, REVISION
OUT=ROOT/'output/molten_core_room';SOURCE=OUT/'source'
MODELS=SOURCE/'models/molten_core_room';MATS=SOURCE/'materials/molten_core_room'
for p in (OUT,MODELS,MATS,OUT/'previews'):p.mkdir(parents=True,exist_ok=True)
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.name='Molten Core Room - assembled'
scene.unit_settings.system='NONE'
groups={}
for name in ('01 Paving','02 Enclosure','03 Functional landmarks','04 Exterior details','05 Ground','06 Lava channels'):
    groups[name]=bpy.data.collections.new(name);scene.collection.children.link(groups[name])
library=bpy.data.scenes.new('F01-F16 Modular Library')
print('MOLTEN_ROOM materials',flush=True)
materials,matmeta=build_materials(MATS)
scene['surface_revision']=REVISION

def collision_file(name,index,shape):
    if 'vertices' in shape:v=shape['vertices']
    else:
        c=shape['center'];s=shape['size'];v=[(c[0]+x*s[0]/2,c[1]+y*s[1]/2,c[2]+z*s[2]/2)
            for z in (-1,1) for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    faces=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    file=f'{name}_collision_{index}.obj'
    # Source 2 imports these files with +90 yaw. Pre-rotate both visual and
    # physical geometry so Hammer yaw=0 matches the authored Blender module.
    (MODELS/file).write_text('\n'.join(['o collision']+['v %.6f %.6f %.6f'%(y,z,x)for x,y,z in v]+['f '+' '.join(str(i+1)for i in f)for f in faces])+'\n')
    return '{_class="PhysicsHullFile" name="hull_'+str(index)+'" filename="models/molten_core_room/'+file+'" surface_prop="stone" collision_tags="solid" import_scale=1.0}'

objects={};manifest=[]
for index,job in enumerate(build_modules()):
    name=job['name'];k=job['kit'];me=bpy.data.meshes.new(name);me.from_pydata(k.v,[],k.f);me.update()
    obj=bpy.data.objects.new(name,me);scene.collection.objects.link(obj)
    for m in materials.values():me.materials.append(m)
    for f,mi in zip(me.polygons,k.m):f.material_index=mi
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001);bm.to_mesh(me);bm.free();me.update()
    uv=me.uv_layers.new(name='SurfaceUV')
    for face in me.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i]));other=[i for i in range(3)if i!=axis]
        key=k.keys[face.material_index];tile=192 if key.startswith('stone')or key in ('rock','charred')else 256 if key=='lava'else 90
        for li in face.loop_indices:
            p=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(p[other[0]]/tile,p[other[1]]/tile)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.material_slot_remove_unused()
    me.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
    me.transform(Matrix.Rotation(math.pi/2,4,'Z'))
    matpaths=[m.name for m in me.materials]
    nodes=['{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/molten_core_room/'+name+'.fbx" import_scale=0.01}]}',
           '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+','.join('{from="'+m+'" to="'+m+'"}'for m in matpaths)+'] use_global_default=false}]}']
    if job['collision']:nodes.append('{_class="PhysicsShapeList" children=['+','.join(collision_file(name,i,s)for i,s in enumerate(job['collision']))+']}')
    (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    bound=[[min(v.co[i]for v in me.vertices)for i in range(3)],[max(v.co[i]for v in me.vertices)for i in range(3)]]
    manifest.append(dict(name=name,label=job['label'],category=job['category'],triangles=len(me.polygons),vertices=len(me.vertices),bounds=bound,materials=matpaths,collision_hulls=len(job['collision']),import_scale=.01,pivot='module origin, Z=0 walking plane or bottom',emissive=False))
    obj['component']=job['label'];obj['native_resource']=False
    scene.collection.objects.unlink(obj);library.collection.objects.link(obj)
    obj.location=((index%6)*430,(index//6)*480,0)
    objects[name]=obj
    print('MOLTEN_ROOM module',name,len(me.polygons),flush=True)

placements=[];rng=random.Random(20260918)
def place(name,x,y,z=0,yaw=0,scale=1,group=None):
    base=objects[name];obj=bpy.data.objects.new(name+'__'+str(len(placements)),base.data)
    if group is None:
        cat=next(a['category']for a in manifest if a['name']==name)
        group={'floor':'01 Paving','wall':'02 Enclosure','feature':'03 Functional landmarks','exterior':'04 Exterior details','terrain':'05 Ground'}[cat]
    groups[group].objects.link(obj);obj.location=(x,y,z);obj.rotation_euler.z=math.radians(yaw);obj.scale=(scale,)*3
    placements.append(dict(name=name,origin=[x,y,z],yaw=yaw,scale=scale,native=False,group=group))
    return obj

def post(x,y):
    place('f04_pillar_body',x,y);place('f04_pillar_cap',x,y,214)

place('room_ash_base',0,0)
for row in range(9):
    for col in range(8):
        edge=col in(0,7)or row in(0,8)
        name='f02_floor_scorched'if edge and rng.random()<.78 else rng.choice(['f01_floor_a','f01_floor_b'])
        place(name,-896+col*256,-1024+row*256,yaw=rng.choice([0,90,180,270]))
place('f01_niche_floor',0,1152)
for x in range(-768,769,256):place('f03_wall_256',x,-1152)
for x in(-1024,1024):
    for y in range(-896,897,256):place('f03_wall_256',x,y,yaw=90)
for sign in(-1,1):
    for x in(512,768):place('f03_wall_256',x*sign,1152)
    place('f03_wall_128',320*sign,1152)
for x,y,angle in((-1024,-1152,0),(1024,-1152,90),(1024,1152,180),(-1024,1152,270)):
    place('f05_corner',x,y,yaw=angle);post(x,y)
for angle in(-60,0,60):place('f06_arc_60',0,1152,yaw=angle)
for angle in(60,120):
    a=math.radians(angle);post(259*math.cos(a),1152+259*math.sin(a))
for x,y in((-256,1152),(256,1152),(-384,-1152),(384,-1152),(-1024,-512),(-1024,512),(1024,-512),(1024,512)):
    post(x,y)
place('f07_portal_ring',0,1096);place('f07_portal_inlay',0,1096)
place('f08_spawn_inlay',0,-140)
for x in(-360,360):place('f16_banner',x,1108,20)
place('f11_fire_stele',0,-1190,-4);place('f11_flame_emblem',0,-1190,-4)
for x,y,z,s in((-1024,0,180,1.25),(1024,0,180,1.25),(-220,1130,180,.7),(220,1130,180,.7)):
    place('f10_brazier_bracket',x,y,z,scale=s);place('f10_brazier_bowl',x,y,z+38*s,scale=s)
# Connected channels remain outside the sealed fighting floor. Surfaces and
# troughs are separate meshes and carry no particle, light or emission.
for x in(-1104,1104):
    for y in range(-1024,1025,256):
        place('f09_trough_straight',x,y,-8,yaw=90,group='06 Lava channels')
        place('f09_lava_straight',x,y,-8,yaw=90,group='06 Lava channels')
for x in range(-896,897,256):
    place('f09_trough_straight',x,-1232,-8,group='06 Lava channels');place('f09_lava_straight',x,-1232,-8,group='06 Lava channels')
# L-shaped corner sockets connect the lower rail to both side rails.
for x,angle in((-1104,270),(1104,0)):
    place('f09_trough_corner',x,-1232,-8,yaw=angle,group='06 Lava channels')
    place('f09_lava_corner',x,-1232,-8,yaw=angle,group='06 Lava channels')
for x in(-1104,1104):
    place('f09_trough_end',x,1280,-8,yaw=90,group='06 Lava channels');place('f09_lava_straight',x,1280,-8,yaw=90,group='06 Lava channels')
# Dominant volcanic outcrops occupy corners; rubble follows the outside foot.
for x,y,s in((-1260,-1340,1.20),(1250,-1350,1.05),(-1250,1320,1.2),(1250,1360,1.3)):
    place('f12_rock_1',x,y,-18,rng.randrange(360),s)
    for dx,dy,ss in((-95,52,.85),(100,-65,.78),(35,90,.65)):
        place('f12_rock_2',x+dx,y+dy,-18,rng.randrange(360),ss*s)
    place('f12_rock_4',x-80,y-115,-18,rng.randrange(360),s)
for side in range(4):
    for i in range(24):
        if side<2:x=(-1 if side==0 else 1)*rng.uniform(1170,1280);y=rng.uniform(-1150,1290)
        else:x=rng.uniform(-1020,1020);y=(-1 if side==2 else 1)*rng.uniform(1280,1380)
        if side==3 and abs(x)<355:continue
        place('f14_rubble',x,y,-14,rng.randrange(360),rng.uniform(.5,1.2))
        place('f14_ash_patch',x,y,-14.15,rng.randrange(360),rng.uniform(.9,1.6))
        if i%5==0:place('f12_rock_3',x,y,-16,rng.randrange(360),rng.uniform(.7,1.3))
# Ash marks at the interior foot stay outside the combat rectangle.
for i in range(22):
    x=rng.choice([-981,981]);y=rng.uniform(-1070,1020)
    place('f14_ash_patch',x,y,.01,rng.randrange(360),.40)
markers=[dict(name='challenge_07_entry',origin=[0,1096,24],role='teleport arrival'),dict(name='challenge_07_home',origin=[0,900,24],role='room home')]
markers.append(dict(name='challenge_07_boss_spawn',origin=[0,-140,24],role='existing challenge configuration spawn'))
for i in range(10):
    a=i*math.tau/10;markers.append(dict(name=f'challenge_07_spawn_{i+1:02d}',origin=[round(365*math.cos(a),3),round(-140+365*math.sin(a),3),24],role='monster spawn'))
for m in markers:
    e=bpy.data.objects.new(m['name'],None);groups['03 Functional landmarks'].objects.link(e);e.location=m['origin'];e.empty_display_type='PLAIN_AXES';e.empty_display_size=36;e['role']=m['role']

def lighting(sc):
    sc.world=bpy.data.worlds.new(sc.name+' daylight');sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.58,.62,1)
    sc.world.node_tree.nodes['Background'].inputs[1].default_value=.65
    ld=bpy.data.lights.new('Warm daylight','SUN');ld.energy=2.4;ld.angle=.22
    lo=bpy.data.objects.new('Warm daylight',ld);sc.collection.objects.link(lo);lo.rotation_euler=(.40,-.65,-.40)
    sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True
    sc.render.resolution_x=1600;sc.render.resolution_y=1500;sc.render.resolution_percentage=100
    sc.view_settings.view_transform='AgX'
lighting(scene);lighting(library)
camdata=bpy.data.cameras.new('Room overview');camera=bpy.data.objects.new('Room overview',camdata);scene.collection.objects.link(camera);scene.camera=camera;camdata.type='ORTHO';camdata.clip_end=25000
def shot(name,position,target,ortho,resolution=(1600,1500)):
    camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=ortho
    scene.render.resolution_x,scene.render.resolution_y=resolution
    scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)

groundmesh=bpy.data.meshes.new('Preview studio ground');groundmesh.from_pydata([(-20000,-20000,-29),(20000,-20000,-29),(20000,20000,-29),(-20000,20000,-29)],[],[(0,1,2,3)])
ground=bpy.data.objects.new('Preview backdrop (not exported)',groundmesh);scene.collection.objects.link(ground)
gm=bpy.data.materials.new('Warm neutral preview background');gm.diffuse_color=(.24,.225,.205,1);groundmesh.materials.append(gm)
scene['purpose']='Independent Molten Core challenge-room sample. All materials non-emissive; no fire or particles.'
scene['walkable_interior']='2048 x 2304; central point (0,-140); arrival (0,1096); Z=0.'

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.clip_end=30000
(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'material_manifest.json').write_text(json.dumps(matmeta,indent=2),encoding='utf-8')
(OUT/'room_layout.json').write_text(json.dumps(dict(interior=[2048,2304],floor_z=0,wall_height=186,placements=placements,markers=markers,native_models=[],emissive=False),ensure_ascii=False,indent=2),encoding='utf-8')
shot('room_overview',(2600,-3700,3500),(0,90,20),4300)
shot('room_top',(0,50,4500),(0,50,0),3650,(1500,1700))
shot('entry_detail',(580,410,620),(0,1110,90),1020,(1400,1000))
shot('wall_corner_detail',(-1740,-1760,620),(-1000,-1080,65),970,(1400,1100))
shot('fire_stele_detail',(270,-1730,350),(0,-1160,90),560,(1100,1000))
camera.location=(2600,-3700,3500);camera.rotation_euler=(Vector((0,90,20))-camera.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=4300
scene.render.resolution_x=1600;scene.render.resolution_y=1500
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'molten_core_room.blend'))
print('MOLTEN_ROOM_COMPLETE',len(manifest),'modules',len(placements),'instances',flush=True)
