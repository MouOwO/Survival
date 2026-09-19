"""Blender batch authoring: modular gold practice room, no emissive effects.

blender --background --python tools/build_main_island.py
"""
import bpy,bmesh,json,math,random,sys,struct,zlib
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from main_island_geometry import build_modules,PALETTE
from wall_surface_materials import surface_maps
OUT=ROOT/'output/main_island';SOURCE=OUT/'source'
MODELS=SOURCE/'models/main_island';MATS=SOURCE/'materials/main_island'
for p in (OUT,MODELS,MATS,OUT/'previews'):p.mkdir(parents=True,exist_ok=True)
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.name='Cross Main Island - assembled'
scene.unit_settings.system='NONE'
groups={}
for name in ('01 Platforms and paths','02 Shoreline','03 Boundary walls','04 Flags','05 Edge planting','06 Water','07 Markers'):
    groups[name]=bpy.data.collections.new(name);scene.collection.children.link(groups[name])
library=bpy.data.scenes.new('M01-M18 Modular Library')
materials={};matmeta=[]

def png(path,pixels):
    a=np.uint8(np.clip(pixels,0,1)*255+.5)
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,c=a.shape
    def chunk(t,d):return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',w,h,8,2,0,0,0))+
                     chunk(b'IDAT',zlib.compress(b''.join(b'\x00'+row.tobytes()for row in a),6))+chunk(b'IEND',b''))

def water_maps():
    from wall_surface_materials import field
    rng=np.random.default_rng(72);noise=field(rng,12)
    color=np.zeros((1024,1024,3));color[:]=(.055,.24,.30)
    color*= (.96+.08*noise)[:,:,None]
    # Recombine a native directional water normal with the new deep-blue color.
    # Reflections describe waves; broad painted bright spots do not.
    im=bpy.data.images.load(str(ROOT/'output/survival_world_v2/source_materials/water_river_oil_normal.png'))
    im.colorspace_settings.name='Non-Color';im.scale(1024,1024)
    normal=np.asarray(im.pixels[:],dtype=np.float32).reshape(1024,1024,4)[::-1,:,:3].copy()
    normal[:,:,1]=1-normal[:,:,1];bpy.data.images.remove(im)
    xy=(normal[:,:,:2]*2-1)*.22
    normal[:,:,:2]=xy*.5+.5
    normal[:,:,2]=np.sqrt(np.maximum(0,1-np.sum(xy*xy,axis=2)))*.5+.5
    props=np.zeros_like(color);props[:,:,0]=.28
    return color,normal,props

print('MAIN_ISLAND materials',flush=True)
for key,col in PALETTE.items():
    source_key='wall_stone' if key.startswith('stone') or key.startswith('rock') else key
    color,normal,props=surface_maps(source_key,col,.24 if key=='gold' else .40 if key.startswith('stone') else .65)
    if key=='water':
        color,normal,props=water_maps()
    if key=='gold':color=np.clip(color*np.asarray([1.12,1.22,1.3]),0,1)
    rough=props[:,:,0]
    if key.startswith('leaf') or key in ('flower','moss','teal','earth','mortar'):
        rough=np.full_like(rough,.84 if key!='teal' else .90)
    normal_dx=normal.copy();normal_dx[:,:,1]=1-normal_dx[:,:,1]
    reflectance=.018+.30*(1-rough)**2
    for suffix,p in [('color',color),('normal',normal_dx),('roughness',rough),('reflectance',reflectance)]:png(MATS/(key+'_'+suffix+'.png'),p)
    canonical='materials/main_island/'+key+'.vmat'
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
    if key=='water':
        bs.inputs['IOR'].default_value=1.333
        bs.inputs['Metallic'].default_value=.25
    two_sided=key.startswith('leaf') or key in ('teal','blue_cloth','ochre_cloth','rose_cloth','flower','moss') or key.startswith('pink')
    mat.use_backface_culling=not two_sided
    text='"Layer0"\n{\n"shader" "global_lit_simple.vfx"\n"F_NORMAL_MAP" "1"\n"F_SPECULAR" "1"\n'
    if two_sided:text+='"F_RENDER_BACKFACES" "1"\n'
    for channel,suffix in [('Color','color'),('Normal','normal'),('Reflectance','reflectance')]:
        text+='"Texture'+channel+'" "materials/main_island/'+key+'_'+suffix+'.png"\n'
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
    return '{_class="PhysicsHullFile" name="hull_'+str(index)+'" filename="models/main_island/'+file+'" surface_prop="stone" collision_tags="solid" import_scale=1.0}'

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
        key=k.keys[face.material_index];tile=210 if key.startswith('stone') or key.startswith('rock') else 512 if key=='water' else 150 if 'cloth' in key or key in ('teal','wood') else 85
        for li in face.loop_indices:
            p=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(p[other[0]]/tile,p[other[1]]/tile)
            if name=='m12_vortex_surface':
                a=1.8*max(0,1-math.hypot(p.x,p.y)/1600)**2
                uv.data[li].uv=((p.x*math.cos(a)-p.y*math.sin(a))/512,(p.x*math.sin(a)+p.y*math.cos(a))/512)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.material_slot_remove_unused()
    me.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
    me.transform(Matrix.Rotation(math.pi/2,4,'Z'))
    matpaths=[m.name for m in me.materials]
    nodes=['{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/main_island/'+name+'.fbx" import_scale=0.01}]}',
           '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+','.join('{from="'+m+'" to="'+m+'"}'for m in matpaths)+'] use_global_default=false}]}']
    if job['collision']:nodes.append('{_class="PhysicsShapeList" children=['+','.join(collision_file(name,i,s)for i,s in enumerate(job['collision']))+']}')
    (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    bound=[[min(v.co[i]for v in me.vertices)for i in range(3)],[max(v.co[i]for v in me.vertices)for i in range(3)]]
    manifest.append(dict(name=name,label=job['label'],category=job['category'],triangles=len(me.polygons),vertices=len(me.vertices),bounds=bound,materials=matpaths,collision_hulls=len(job['collision']),import_scale=.01,pivot='module origin, Z=0 walking plane or bottom',emissive=False))
    obj['component']=job['label'];obj['native_resource']=False
    scene.collection.objects.unlink(obj);library.collection.objects.link(obj)
    obj.location=((index%6)*430,(index//6)*480,0)
    objects[name]=obj
    print('MAIN_ISLAND module',name,len(me.polygons),flush=True)

# The structural kit shares the gold room's mesh/material pipeline, but the
# island layout and water are authored independently. Existing room files stay intact.
from main_island_geometry import PLATFORM,OUTER_EDGE,INNER_EDGE,arm_parts,FLOOR_Z,WATER_Z
placements=[];rng=random.Random(20260917);supports=[];shore_segments=[]
def rotate(x,y,q):
    a=q*math.pi/2;return (round(x*math.cos(a)-y*math.sin(a),6),round(x*math.sin(a)+y*math.cos(a),6))
def place(name,x,y,z=640,yaw=0,scale=1,group='01 Platforms and paths',q=0):
    base=objects[name];o=bpy.data.objects.new(name+'__'+str(len(placements)),base.data)
    groups[group].objects.link(o);xy=rotate(x,y,q);o.location=(*xy,z);o.rotation_euler.z=math.radians(yaw+q*90)
    o.scale=(scale,)*3 if isinstance(scale,(float,int))else scale
    o['module']=name;o['quadrant']=q
    placements.append(dict(name=name,origin=list(o.location),yaw=yaw+q*90,scale=list(o.scale),native=False,group=group,quadrant=q))
    return o
def edge(a,b,name,group,q,z=640,inset=0,spacing=256):
    d=Vector((b[0]-a[0],b[1]-a[1]));L=d.length;tangent=d/L;normal=Vector((-tangent.y,tangent.x));count=math.ceil(L/spacing)
    for i in range(count):
        p=Vector(a)+d*((i+.5)/count)+normal*inset
        place(name,*p,z,math.degrees(math.atan2(d.y,d.x)),(L/count/256,1,1),group,q)
    return tangent,normal,L

colors=['teal','blue_cloth','ochre_cloth','rose_cloth']
for q in range(4):
    place('m01_player_platform',0,3584,q=q)
    for side in(-1,1):place('m02_arm_'+('left'if side<0 else'right'),0,0,q=q)
    for poly in [PLATFORM,*arm_parts(-1),*arm_parts(1)]:
        supports.append(dict(polygon=[rotate(x,y,q)for x,y in poly],top=639.1,bottom=155,role='platform'))
    place('m03_stair_treads',0,2304,396,q=q)
    for side in(-1,1):place('m03_stair_cheek_'+('left'if side<0 else'right'),side*326,2304,396,q=q)
    for i in range(16):
        supports.append(dict(polygon=[rotate(x,y,q)for x,y in [(-288,2304+i*32),(288,2304+i*32),(288,2336+i*32),(-288,2336+i*32)]],top=396+(i+1)*244/16-.6,bottom=320,role='stairs'))
    # A submerged approach continues through the central cross. The water
    # surface stays visual; a separate bed provides movement for enemies.
    for a,b in zip(OUTER_EDGE,OUTER_EDGE[1:]):
        t,n,L=edge(a,b,'m09_cliff_'+rng.choice(['straight','bulge','recess']),'02 Shoreline',q)
        edge(a,b,'m08_coping_straight','02 Shoreline',q)
        edge(a,b,'m13_lowwall_256','03 Boundary walls',q,inset=64)
        edge(a,b,'m11_shore_foam','06 Water',q,z=401.5,inset=-115)
        shore_segments.append(dict(a=rotate(*a,q),b=rotate(*b,q),outer=True))
        for i in range(max(1,round(L/640))+1):
            p=Vector(a)+(Vector(b)-Vector(a))*i/max(1,round(L/640))+n*64
            place('m13_short_post',*p,640,group='03 Boundary walls',q=q)
        # Continuous sparse border, with taller clusters only near the corners.
        for i in range(max(1,int(L/145))):
            p=Vector(a)+(Vector(b)-Vector(a))*(i+.5)/max(1,int(L/145))+n*rng.uniform(120,205)
            for j in range(2):
                plant=rng.choice(['grass','fern','shrub','flowers','flowers'])
                place('m17_'+plant,p.x+rng.uniform(-40,40),p.y+rng.uniform(-40,40),641,rng.randrange(360),rng.uniform(1,1.65),'05 Edge planting',q)
            place('m10_transition_dry',p.x,p.y,641,rng.randrange(360),.7,'05 Edge planting',q)
    for side in(-1,1):
        points=[(side*x,y)for x,y in INNER_EDGE]+[(side*320,2816)]
        if side>0:points=points[::-1]
        for a,b in zip(points,points[1:]):
            edge(a,b,'m04_inner_bank_256','02 Shoreline',q,inset=20)
            edge(a,b,'m11_shore_foam','06 Water',q,z=401.5,inset=-70)
            shore_segments.append(dict(a=rotate(*a,q),b=rotate(*b,q),outer=False))
        for x,y in [(side*1260,4400),(side*1440,2910),(side*1040,4660)]:
            for j in range(3):place('m15_rock_'+str(j+1),x+rng.uniform(-80,80),y+rng.uniform(-80,80),635,rng.randrange(360),rng.uniform(.8,1.25),'05 Edge planting',q)
        x,y=side*1090,4410
        place('m14_banner_post',x,y,640,0,1.2,'04 Flags',q)
        place('m14_flag_'+colors[q],x,y,640,0,1.2,'04 Flags',q)
    place('m16_cherry_'+str(q%2+1),-1260,3980,640,18+q*12,1.35,'05 Edge planting',q)
    place('m16_cherry_'+str((q+1)%2+1),1280,3220,640,73,1.05,'05 Edge planting',q)

# Native pine is reused as in the gold room; the preview GLB is not a new game asset.
pinefile=ROOT/'output/gold_training_room/native_preview/tree_pine01.glb'
before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(pinefile));imported=list(set(bpy.data.objects)-before)
meshes=[o for o in imported if o.type=='MESH'];bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();pine=bpy.context.object;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
height=max(v.co.z for v in pine.data.vertices)-min(v.co.z for v in pine.data.vertices);pine.data.transform(Matrix.Scale(414.546313/height,4))
for c in list(pine.users_collection):c.objects.unlink(pine)
library.collection.objects.link(pine);pine.name='M16 Native pine preview';pine.location=(0,5000,0)
for o in imported:
    if o!=pine and o.name in bpy.data.objects:bpy.data.objects.remove(o,do_unlink=True)
for q in range(4):
    for x,y,s in [(1310,4050,1.65),(-1220,4650,1.3)]:
        o=bpy.data.objects.new('Native pine',pine.data);groups['05 Edge planting'].objects.link(o);o.location=(*rotate(x,y,q),633);o.rotation_euler.z=q*1.32;o.scale=(s,)*3
        placements.append(dict(name='models/props_foliage/tree_pine01.vmdl',origin=list(o.location),yaw=math.degrees(o.rotation_euler.z),scale=[s]*3,native=True,group='05 Edge planting',quadrant=q))

# A tiled mesh is only the Blender preview. Hammer gets a non-solid water mesh
# with the existing, verified multiblend wave shader and these custom textures.
o=place('m12_water_tile',0,0,400,scale=(32,32,1),group='06 Water');o['preview_only']=True;placements.pop()
o.data=o.data.copy()
for uv in o.data.uv_layers.active.data:uv.uv*=32
place('m12_vortex_surface',0,0,400.7,group='06 Water')

markers=[]
for q in range(4):
    for suffix,xy,z in [('builder_spawn',(0,3456),665),('gate',(0,2848),664),('attack_entry',(0,2100),420)]:
        name=f'main_island_player_{q+1}_{suffix}';origin=[*rotate(*xy,q),z];markers.append(dict(name=name,origin=origin))
        e=bpy.data.objects.new(name,None);groups['07 Markers'].objects.link(e);e.location=origin;e.empty_display_size=90

def lighting(sc):
    sc.world=bpy.data.worlds.new(sc.name+' daylight');sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.56,.64,.71,1);sc.world.node_tree.nodes['Background'].inputs[1].default_value=.65
    ld=bpy.data.lights.new('Afternoon sunlight','SUN');ld.energy=2.5;ld.angle=.20
    lo=bpy.data.objects.new('Afternoon sunlight',ld);sc.collection.objects.link(lo);lo.rotation_euler=(.4,-.65,-.40)
    sc.render.engine='CYCLES';sc.cycles.samples=20;sc.cycles.use_denoising=True;sc.view_settings.view_transform='AgX'
    sc.render.resolution_percentage=100
lighting(scene);lighting(library)
camdata=bpy.data.cameras.new('Island overview');camera=bpy.data.objects.new('Island overview',camdata);scene.collection.objects.link(camera);scene.camera=camera;camdata.type='ORTHO';camdata.clip_end=60000
def shot(name,position,target,scale,resolution=(1700,1700)):
    camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=scale
    scene.render.resolution_x,scene.render.resolution_y=resolution;scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)

(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'material_manifest.json').write_text(json.dumps(matmeta,indent=2),encoding='utf-8')
layout=dict(pivot=[0,0,0],integration_translation=[-1152,2688,0],platform_z=640,water_z=400,extent=4864,stair_width=576,stair_run=512,placements=placements,supports=supports,shore_segments=shore_segments,markers=markers,native_models=['models/props_foliage/tree_pine01.vmdl'])
(OUT/'island_layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
shot('island_overview',(3000,-13500,17600),(0,80,440),12500)
shot('island_top',(0,0,19000),(0,0,0),11200)
shot('player_platform',(4300,-700,6400),(0,3370,520),5250,(1700,1250))
shot('shore_detail',(-2300,5900,2400),(-1150,4450,460),1900,(1500,1200))
shot('stair_detail',(1100,1100,1900),(0,2540,510),2000,(1500,1200))
camera.location=(3000,-13500,17600);camera.rotation_euler=(Vector((0,80,440))-camera.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=12500
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            s=area.spaces.active;s.clip_end=60000;s.region_3d.view_distance=14000;s.region_3d.view_location=(0,0,440);s.region_3d.view_rotation=camera.rotation_euler.to_quaternion();s.region_3d.view_perspective='ORTHO'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'main_island.blend'))
print('MAIN_ISLAND_COMPLETE',len(manifest),'modules',len(placements),'instances',flush=True)
