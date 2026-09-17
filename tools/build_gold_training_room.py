"""Blender batch authoring: modular gold practice room, no emissive effects.

blender --background --python tools/build_gold_training_room.py
"""
import bpy,bmesh,json,math,random,sys,struct,zlib
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from gold_room_geometry import build_modules,PALETTE
from wall_surface_materials import surface_maps
OUT=ROOT/'output/gold_training_room';SOURCE=OUT/'source'
MODELS=SOURCE/'models/gold_training_room';MATS=SOURCE/'materials/gold_training_room'
for p in (OUT,MODELS,MATS,OUT/'previews'):p.mkdir(parents=True,exist_ok=True)
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.name='Gold Practice Room - assembled'
scene.unit_settings.system='NONE'
groups={}
for name in ('01 Paving','02 Enclosure','03 Functional landmarks','04 Edge planting','05 Ground','06 Native pine'):
    groups[name]=bpy.data.collections.new(name);scene.collection.children.link(groups[name])
library=bpy.data.scenes.new('B01-B16 Modular Library')
materials={};matmeta=[]

def png(path,pixels):
    a=np.uint8(np.clip(pixels,0,1)*255+.5)
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,c=a.shape
    def chunk(t,d):return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',w,h,8,2,0,0,0))+
                     chunk(b'IDAT',zlib.compress(b''.join(b'\x00'+row.tobytes()for row in a),6))+chunk(b'IEND',b''))

print('GOLD_ROOM materials',flush=True)
for key,col in PALETTE.items():
    source_key='wall_stone' if key.startswith('stone') or key=='rock' else key
    color,normal,props=surface_maps(source_key,col,.22 if key=='gold' else .60)
    if key=='gold':color=np.clip(color*np.asarray([1.12,1.22,1.3]),0,1)
    rough=props[:,:,0]
    if key.startswith('leaf') or key in ('flower','moss','teal','earth','mortar'):
        rough=np.full_like(rough,.84 if key!='teal' else .90)
    normal_dx=normal.copy();normal_dx[:,:,1]=1-normal_dx[:,:,1]
    reflectance=.018+.30*(1-rough)**2
    for suffix,p in [('color',color),('normal',normal_dx),('roughness',rough),('reflectance',reflectance)]:png(MATS/(key+'_'+suffix+'.png'),p)
    canonical='materials/gold_training_room/'+key+'.vmat'
    mat=bpy.data.materials.new(canonical);mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF');nodes=mat.node_tree.nodes;links=mat.node_tree.links
    for suffix,socket in [('color','Base Color'),('roughness','Roughness')]:
        n=nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(MATS/(key+'_'+suffix+'.png')))
        if suffix!='color':n.image.colorspace_settings.name='Non-Color'
        links.new(n.outputs['Color'],bs.inputs[socket])
    n=nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(MATS/(key+'_normal.png')));n.image.colorspace_settings.name='Non-Color'
    sep=nodes.new('ShaderNodeSeparateColor');combine=nodes.new('ShaderNodeCombineColor');invert=nodes.new('ShaderNodeMath')
    invert.operation='SUBTRACT';invert.inputs[0].default_value=1
    links.new(n.outputs['Color'],sep.inputs[0]);links.new(sep.outputs[0],combine.inputs[0]);links.new(sep.outputs[2],combine.inputs[2]);links.new(sep.outputs[1],invert.inputs[1]);links.new(invert.outputs[0],combine.inputs[1])
    nm=nodes.new('ShaderNodeNormalMap');links.new(combine.outputs[0],nm.inputs['Color']);links.new(nm.outputs[0],bs.inputs['Normal'])
    bs.inputs['Metallic'].default_value=.55 if key in ('gold','bronze') else 0
    two_sided=key.startswith('leaf') or key in ('teal','flower','moss')
    mat.use_backface_culling=not two_sided
    text='"Layer0"\n{\n"shader" "global_lit_simple.vfx"\n"F_NORMAL_MAP" "1"\n"F_SPECULAR" "1"\n'
    if two_sided:text+='"F_RENDER_BACKFACES" "1"\n'
    for channel,suffix in [('Color','color'),('Normal','normal'),('Reflectance','reflectance')]:
        text+='"Texture'+channel+'" "materials/gold_training_room/'+key+'_'+suffix+'.png"\n'
    text+='"g_vColorTint" "[1 1 1 0]"\n}\n'
    (MATS/(key+'.vmat')).write_text(text,encoding='utf-8');materials[key]=mat
    matmeta.append(dict(name=key,size=1024,color_std=float(np.std(color)),normal_std=float(np.std(normal[:,:,:2])),roughness_mean=float(np.mean(rough)),emissive=False))

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
    return '{_class="PhysicsHullFile" name="hull_'+str(index)+'" filename="models/gold_training_room/'+file+'" surface_prop="stone" collision_tags="solid" import_scale=1.0}'

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
        key=k.keys[face.material_index];tile=160 if key.startswith('stone')or key=='rock'else 90 if key in ('teal','wood')else 75
        for li in face.loop_indices:
            p=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(p[other[0]]/tile,p[other[1]]/tile)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.material_slot_remove_unused()
    me.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
    me.transform(Matrix.Rotation(math.pi/2,4,'Z'))
    matpaths=[m.name for m in me.materials]
    nodes=['{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/gold_training_room/'+name+'.fbx" import_scale=0.01}]}',
           '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+','.join('{from="'+m+'" to="'+m+'"}'for m in matpaths)+'] use_global_default=false}]}']
    if job['collision']:nodes.append('{_class="PhysicsShapeList" children=['+','.join(collision_file(name,i,s)for i,s in enumerate(job['collision']))+']}')
    (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    bound=[[min(v.co[i]for v in me.vertices)for i in range(3)],[max(v.co[i]for v in me.vertices)for i in range(3)]]
    manifest.append(dict(name=name,label=job['label'],category=job['category'],triangles=len(me.polygons),vertices=len(me.vertices),bounds=bound,materials=matpaths,collision_hulls=len(job['collision']),import_scale=.01,pivot='module origin, Z=0 walking plane or bottom',emissive=False))
    obj['component']=job['label'];obj['native_resource']=False
    scene.collection.objects.unlink(obj);library.collection.objects.link(obj)
    obj.location=((index%6)*430,(index//6)*480,0)
    objects[name]=obj
    print('GOLD_ROOM module',name,len(me.polygons),flush=True)

placements=[];rng=random.Random(20260916)
def place(name,x,y,z=0,yaw=0,scale=1,group=None):
    base=objects[name];obj=bpy.data.objects.new(name+'__'+str(len(placements)),base.data)
    if group is None:
        cat=next(a['category']for a in manifest if a['name']==name)
        group={'floor':'01 Paving','wall':'02 Enclosure','feature':'03 Functional landmarks','nature':'04 Edge planting','terrain':'05 Ground'}[cat]
    groups[group].objects.link(obj);obj.location=(x,y,z);obj.rotation_euler.z=math.radians(yaw);obj.scale=(scale,)*3
    placements.append(dict(name=name,origin=[x,y,z],yaw=yaw,scale=scale,native=False,group=group))
    return obj

place('room_earth_base',0,0)
for row in range(9):
    for col in range(8):
        name='b02_floor_worn' if rng.random()<.17 else rng.choice(['b01_floor_a','b01_floor_b'])
        place(name,-896+col*256,-1024+row*256,yaw=rng.choice([0,90,180,270]))
# Behind the square floor, a paved shallow niche remains under the curved wall.
place('b01_niche_floor',0,1152)
for x in range(-768,769,256):place('b03_wall_256',x,-1152)
for x in (-1024,1024):
    for y in range(-896,897,256):place('b03_wall_256',x,y,yaw=90)
for sign in (-1,1):
    for x in (512,768):place('b03_wall_256',x*sign,1152)
    place('b03_wall_128',320*sign,1152)
for x,y,angle in ((-1024,-1152,0),(1024,-1152,90),(1024,1152,180),(-1024,1152,270)):
    place('b05_corner',x,y,yaw=angle);place('b04_pillar',x,y)
for angle in (-60,0,60):place('b06_arc_60',0,1152,yaw=angle)
for x,y in ((-256,1152),(256,1152),(-384,-1152),(384,-1152),(-1024,-512),(-1024,512),(1024,-512),(1024,512)):
    place('b04_pillar_coin' if abs(y)==1152 else 'b04_pillar',x,y)
place('b07_teleport_base',0,1096)
place('b08_spawn_inlay',0,-140)
for x in (-448,448):place('b16_banner',x,1117,18)
place('b09_coin_stele',-720,-1204,-8);place('b09_coin_relief',-720,-1204,-8)
for x,y,z,scale in ((-1024,0,176,1),(1024,0,176,1),(-226,1120,176,.6),(226,1120,176,.6)):
    place('b10_brazier_plinth',x,y,z,scale=scale)
    place('b10_bronze_bowl',x,y,z+66*scale,scale=scale)

clusters=[(-1080,-1180,1.05),(1130,-1150,1.20),(-1060,1200,.98),(1060,1230,1.25),(-1110,710,.65),(1160,-720,.65)]
for x,y,scale in clusters:
    place('b11_rock_1',x,y,-15,rng.randrange(360),scale)
    for dx,dy,s in ((95,-50,.9),(-60,95,.6),(100,72,.6)):
        place('b11_rock_2',x+dx*scale,y+dy*scale,-15,rng.randrange(360),s*scale)
    for j in range(12):
        a=rng.random()*math.tau;r=rng.uniform(95,190)*scale;xx=x+math.cos(a)*r;yy=y+math.sin(a)*r
        if abs(xx)<970 and -1080<yy<1120:continue
        place(rng.choice(['b13_fern','b14_shrub','b14_shrub_flowers']),xx,yy,-13,rng.randrange(360),rng.uniform(1.15,1.65))
    place('b12_rubble',x-50,y-110,-13,rng.randrange(360),scale)
for side in range(4):
    for i in range(55):
        if side<2:x=(-1 if side==0 else 1)*rng.uniform(1060,1240);y=rng.uniform(-1160,1300)
        else:x=rng.uniform(-1040,1040);y=(-1 if side==2 else 1)*rng.uniform(1190,1370)
        if side==3 and abs(x)<330:continue
        name=rng.choice(['b13_grass_small','b13_grass_large','b13_fern','b14_shrub','b14_shrub_flowers'])
        place(name,x,y,-13,rng.randrange(360),rng.uniform(1.15,1.85))
        if i%3==0:place('b12_rubble',x,y,-14,rng.randrange(360),rng.uniform(.35,.8))
        if i%4==0:place('b12_ground_patch',x,y,-13,rng.randrange(360),1.1)
# Sparse inner foot vegetation leaves the battle and spawn areas unobstructed.
for i in range(28):
    if i<16:x=rng.choice([-980,980]);y=rng.uniform(-1080,1100)
    else:x=rng.uniform(-910,910);y=rng.choice([-1104,1104])
    if y>1000 and abs(x)<350:continue
    place('b13_grass_small',x,y,0,rng.randrange(360),.55)
for i in range(18):
    x=rng.uniform(-940,940);y=rng.choice([-1126,1126]);o=place('b16_moss_patch',x,y,25,rng.randrange(360),rng.uniform(.6,1.1));o.rotation_euler.x=math.pi/2
    placements[-1]['pitch']=90

# Reuse the game's native pine, with a locally extracted preview-only glTF.
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(OUT/'native_preview/tree_pine01.glb'))
imported=list(set(bpy.data.objects)-before);meshes=[o for o in imported if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();pine=bpy.context.object
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
height=max(v.co.z for v in pine.data.vertices)-min(v.co.z for v in pine.data.vertices)
pine.data.transform(Matrix.Scale(414.546313/height,4))
pine.name='B15_native_pine_preview';pine.location=(0,0,0)
for c in list(pine.users_collection):c.objects.unlink(pine)
library.collection.objects.link(pine);pine.location=(0,2500,0)
pine['native_resource']='models/props_foliage/tree_pine01.vmdl'
for o in imported:
    if o!=pine and o.name in bpy.data.objects:bpy.data.objects.remove(o,do_unlink=True)
for x,y,s,angle in ((890,1440,1.2,25),(-1210,940,.85,144)):
    o=bpy.data.objects.new('Native pine',pine.data);groups['06 Native pine'].objects.link(o);o.location=(x,y,-9);o.scale=(s,s,s);o.rotation_euler.z=math.radians(angle)
    placements.append(dict(name='models/props_foliage/tree_pine01.vmdl',origin=[x,y,-9],yaw=angle,scale=s,native=True,group='06 Native pine'))

markers=[dict(name='challenge_02_entry',origin=[0,1096,24],role='teleport arrival'),dict(name='challenge_02_home',origin=[0,900,24],role='room home')]
for i in range(8):
    a=i*math.tau/8;markers.append(dict(name=f'challenge_02_spawn_{i+1:02d}',origin=[round(340*math.cos(a),3),round(-140+340*math.sin(a),3),24],role='monster spawn'))
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
scene['purpose']='Independent gold practice-room art sample; no emission. Component pivots in Source units.'
scene['walkable_interior']='2048 x 2304; central point (0,-140); arrival (0,1096); Z=0.'
scene['native_asset']='models/props_foliage/tree_pine01.vmdl (preview glTF only; runtime references original)'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.clip_end=30000
(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'material_manifest.json').write_text(json.dumps(matmeta,indent=2),encoding='utf-8')
(OUT/'room_layout.json').write_text(json.dumps(dict(interior=[2048,2304],floor_z=0,wall_height=176,placements=placements,markers=markers,native_models=['models/props_foliage/tree_pine01.vmdl'],emissive=False),ensure_ascii=False,indent=2),encoding='utf-8')
shot('room_overview',(2600,-3700,3500),(0,90,20),3970)
shot('room_top',(0,50,4500),(0,50,0),3650,(1500,1700))
shot('entry_detail',(580,410,620),(0,1110,90),1020,(1400,1000))
shot('stone_coin_detail',(-420,-1860,660),(-745,-1055,70),980,(1400,1000))
camera.location=(2600,-3700,3500);camera.rotation_euler=(Vector((0,90,20))-camera.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=3970
scene.render.resolution_x=1600;scene.render.resolution_y=1500
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'gold_training_room.blend'))
print('GOLD_ROOM_COMPLETE',len(manifest),'modules',len(placements),'instances',flush=True)
