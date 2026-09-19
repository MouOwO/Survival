import bpy, os, json, math
from mathutils import Vector
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','xianxia_kit')
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,'xianxia_library.blend'))
manifest=json.load(open(os.path.join(OUT,'asset_manifest.json')))
library=next(s for s in reversed(list(bpy.data.scenes))if s.name.startswith('Xianxia modular asset library')and len(s.objects)>=26)
scene=bpy.data.scenes.new('Xianxia component studio');bpy.context.window.scene=scene
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='HIP';prefs.get_devices()
for d in prefs.devices:d.use=d.type=='HIP' and '9070' in d.name
if any(d.use for d in prefs.devices):scene.cycles.device='GPU'
scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=False
scene.view_settings.view_transform='AgX';scene.world=bpy.data.worlds.new('Morning studio');scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.32,.40,.45,1);bg.inputs[1].default_value=.7
sun=bpy.data.lights.new('Soft morning sun','SUN');sun.energy=2.4;sun.angle=.35;sun.color=(1,.94,.83)
so=bpy.data.objects.new('Soft morning sun',sun);scene.collection.objects.link(so);so.rotation_euler=(.4,-.45,-.3)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
camera=bpy.data.objects.new('Asset camera',bpy.data.cameras.new('Asset camera'));scene.collection.objects.link(camera);camera.data.type='ORTHO';scene.camera=camera;camera.data.clip_end=50000
for name,loc,energy,size,color in [('Morning key',(-800,-1000,1800),1900000,1200,(1,.91,.77)),('Sky fill',(800,500,1300),1200000,1000,(.71,.84,1))]:
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=color;o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;aim(o,(0,0,0))
for im in bpy.data.images:
    if im.source=='FILE':
        try:im.reload()
        except:pass
def instance(name,pos=(0,0,0),angle=0,scale=1):
    src=next(o for o in library.objects if o.name.split('.')[0]==name);o=src.copy();o.data=src.data;scene.collection.objects.link(o);o.location=pos;o.rotation_euler[2]=angle;o.scale=(scale,)*3;return o
for a in manifest:
    o=instance(a['name']);lo,hi=map(Vector,a['bounds']);c=(lo+hi)/2;size=max((hi-lo));camera.location=c+Vector((1,-1.5,1.25))*size;aim(camera,c);camera.data.ortho_scale=size*1.65
    scene.render.filepath=os.path.join(OUT,'previews',a['name']+'.png');bpy.ops.render.render(write_still=True);bpy.data.objects.remove(o,do_unlink=True)
    with open(os.path.join(OUT,'render_status.json'),'w')as f:json.dump({'last':a['name']},f)
# Small playable-looking assembly, with actual sockets and no decoration in the entry.
for x in [-768,-256,256,768]:instance('t01_shore_straight',(x,-512,256));instance('t01_shore_straight',(x,512,256),math.pi)
for y in [-224,224]:
 for x,a in [(-960,-math.pi/2),(960,math.pi/2)]:
  side=instance('t01_shore_straight',(x,y,256),a);side.scale.x=.875
# Continuous supported floor; transition pieces occur only beside planting pockets.
bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,131));floor=bpy.context.object;floor.name='Continuous platform foundation';floor.dimensions=(1792,896,248)
floor.data.materials.append(next(m for m in library.objects[0].data.materials if 'xx_stone' in m.name))
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
uv=floor.data.uv_layers.active
for p in floor.data.polygons:
 axis=max(range(3),key=lambda i:abs(p.normal[i]));axes=[i for i in range(3)if i!=axis]
 for li in p.loop_indices:
  v=floor.data.vertices[floor.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]/256,v[axes[1]]/256)
for x,y,a in [(800,350,0),(-820,350,math.pi),(820,-350,math.pi/2)]:instance('t05_transition_broken',(x,y,256),a)
instance('t04_stairs',(0,-704,256));instance('a02_gateway',(0,-470,260),0,.85)
instance('a01_pavilion',(-640,230,264),0,.8)
instance('v01_pine_0',(780,370,265),.8);instance('v02_peach_0',(-870,370,265),-.2,.85)
instance('v02_peach_1',(810,-380,265),.6,.8)
for x in [-768,-512,512,768]:instance('t06_rail_straight',(x,-550,256))
for x,y in [(-720,-470),(740,480),(940,200),(-940,20)]:instance('v03_rock_1',(x,y,256));instance('v03_fern',(x+55,y+16,256))
instance('a03_censer',(-490,310,310),0,.8)
camera.location=(2600,-3400,3300);aim(camera,(0,0,220));camera.data.ortho_scale=2900
scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.cycles.samples=48
scene.render.filepath=os.path.join(OUT,'previews','assembly.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'xianxia_assembly.blend'))
json.dump({'complete':True,'models':len(manifest)},open(os.path.join(OUT,'render_status.json'),'w'))
