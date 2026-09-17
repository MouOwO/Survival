import bpy, math, random, json, os
from mathutils import Vector
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','survival_world_v2','source_models')
os.makedirs(OUT,exist_ok=True)
scene=bpy.data.scenes.new('Cultivation cloud sea assets')
bpy.context.window.scene=scene
def material(name,color):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs[0].default_value=(*color,1);bs.inputs[2].default_value=.86
    return m
stone=material('cultivation_stone',(.66,.69,.65))
wood=material('cultivation_wood',(.26,.15,.095))
roof=material('cultivation_roof',(.095,.24,.25))
trim=material('cultivation_trim',(.57,.40,.16))
cloud=material('cultivation_cloud',(.87,.91,.94))
assets=[]
def box(name,loc,scale,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat);return o
def beam(name,a,b,r,mat,vertices=8):
    d=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=d.length,location=(Vector(a)+Vector(b))/2);o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(mat);return o
def combine_export(name,objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    tri=o.modifiers.new('Export triangulation','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=tri.name)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    # Source 2 modeldoc import_scale controls final raw game units.
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,name+'.fbx'),use_selection=True,object_types={'MESH'},apply_unit_scale=True,global_scale=1,axis_forward='-Y',axis_up='Z',add_leaf_bones=False,bake_anim=False)
    deps=bpy.context.evaluated_depsgraph_get();ev=o.evaluated_get(deps);me=ev.to_mesh()
    bounds=[list(min(v.co[i] for v in me.vertices) for i in range(3)),list(max(v.co[i] for v in me.vertices) for i in range(3))]
    with open(os.path.join(OUT,name+'.json'),'w')as f:json.dump({'vertices':[list(v.co)for v in me.vertices],'triangles':[list(p.vertices)for p in me.polygons],'materials':[m.name for m in o.data.materials],'materialIndices':[p.material_index for p in me.polygons]},f)
    assets.append({'name':name,'bounds':bounds,'triangles':len(me.polygons),'materials':[m.name for m in o.data.materials]});ev.to_mesh_clear();return o
# An open pavilion: raised pale-stone plinth, four posts, open railings,
# swept hip roof, visible teal tile courses, brass ridge and finial.
parts=[]
for z,w,h in [(12,460,24),(32,420,16),(49,390,18)]:parts.append(box('Pavilion stone plinth',(0,0,z),(w,w,h),stone))
for x in [-152,152]:
    for y in [-152,152]:
        parts.append(box('Column stone foot',(x,y,71),(45,45,24),stone));parts.append(beam('Cedar column',(x,y,80),(x,y,330),12,wood,12))
        parts.append(box('Bracket block',(x,y,310),(60,60,26),wood))
for x in [-154,154]:parts.append(box('Top beam',(x,0,329),(24,346,28),wood))
for y in [-154,154]:parts.append(box('Top beam',(0,y,329),(346,24,28),wood))
for y in [-167,167]:
    for x in [-117,117]:parts.append(box('Open rail',(x,y,125),(65,13,15),wood));parts.append(box('Rail post',(x,y,99),(12,12,74),wood))
def roofpoint(t,u,side):
    # t=0 eave, t=1 upper hip. Flared corners make a recognizable swept roof.
    w=244*(1-t)+32*t;z=345+125*t+39*(1-t)**5+21*abs(u)**5*(1-t)
    x=u*w;y=-w
    for _ in range(side):x,y=-y,x
    return (x,y,z)
for side in range(4):
    vv=[roofpoint(i/8,j/8*2-1,side)for i in range(9)for j in range(9)]
    ff=[(i*9+j,i*9+j+1,(i+1)*9+j+1,(i+1)*9+j)for i in range(8)for j in range(8)]
    me=bpy.data.meshes.new('Swept teal roof');me.from_pydata(vv,[],ff);me.materials.append(roof);o=bpy.data.objects.new('Swept teal roof',me);scene.collection.objects.link(o);parts.append(o)
    for j in range(13):
        u=j/12*2-1
        for i in range(8):parts.append(beam('Rounded roof tile',roofpoint(i/8,u,side),roofpoint((i+1)/8,u,side),2.8,roof,6))
    for i in range(8):parts.append(beam('Curved corner trim',roofpoint(i/8,1,side),roofpoint((i+1)/8,1,side),4.4,trim,8))
parts.append(box('Ridge crown',(0,0,473),(68,68,12),roof));parts.append(beam('Finial',(0,0,479),(0,0,524),6,trim,10))
pavilion=combine_export('cultivation_pavilion',parts)
# Rounded three-dimensional cloud cores. Metaball union avoids visible seams
# between intersecting spheres; soft particle fringes are added in the game.
for variant in range(2):
    rng=random.Random(910+variant);meta=bpy.data.metaballs.new('Cloud lobes');meta.resolution=48;meta.render_resolution=48;meta.threshold=.62
    o=bpy.data.objects.new('Cloud core',meta);scene.collection.objects.link(o)
    for i in range(15):
        e=meta.elements.new();e.co=((i%5-2)*240+rng.uniform(-70,70),(i//5-1)*210+rng.uniform(-60,60),rng.uniform(-75,80));e.radius=rng.uniform(230,355)
    for i in range(5):
        e=meta.elements.new();e.co=(rng.uniform(-480,480),rng.uniform(-210,210),rng.uniform(160,270));e.radius=rng.uniform(190,280)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');o=bpy.context.object
    o.data.materials.append(cloud)
    for p in o.data.polygons:p.use_smooth=True
    smooth=o.modifiers.new('Soft cloud surface','SMOOTH');smooth.factor=.9;smooth.iterations=3;bpy.ops.object.modifier_apply(modifier=smooth.name)
    combine_export('cultivation_cloud_'+str(variant),[o])
with open(os.path.join(OUT,'cultivation_assets.json'),'w')as f:json.dump(assets,f,indent=2)
# Stage the assets without touching the user's previous scene.
pavilion.location=(0,-1350,0)
for i,o in enumerate([o for o in scene.objects if o.name.startswith('cultivation_cloud_')]):o.location=(i*1800-900,700,0)
scene.world=bpy.data.worlds.new('Cloudsea asset world');scene.world.use_nodes=True;next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.2,.26,.32,1)
data=bpy.data.lights.new('Studio sun','SUN');data.energy=2;sun=bpy.data.objects.new('Studio sun',data);scene.collection.objects.link(sun);sun.rotation_euler=(.4,-.6,-.4)
camdata=bpy.data.cameras.new('Asset camera');cam=bpy.data.objects.new('Asset camera',camdata);scene.collection.objects.link(cam);cam.location=(3000,-4200,3000);cam.rotation_euler=(Vector((0,0,120))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=4200;camdata.clip_end=20000;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.region_3d.view_distance=3600;area.spaces.active.region_3d.view_location=(0,0,100);area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion();area.spaces.active.clip_end=20000;area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'cultivation_assets.blend'))
print(json.dumps(assets))
