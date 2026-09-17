import bpy, os, json, math
from mathutils import Vector
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','xianxia_kit','detail_pass')
os.makedirs(os.path.join(OUT,'previews'),exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,'xianxia_detail_modules.blend'))
manifest=json.load(open(os.path.join(OUT,'asset_manifest.json')))
library=next(s for s in reversed(list(bpy.data.scenes))if s.name.startswith('Xianxia detail and junction modules'))
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
for a in [a for a in manifest if a['name']=='t08_stair_cheek']:
    o=instance(a['name']);lo,hi=map(Vector,a['bounds']);c=(lo+hi)/2;size=max((hi-lo));camera.location=c+Vector((1,-1.5,1.25))*size;aim(camera,c);camera.data.ortho_scale=size*1.65
    scene.render.filepath=os.path.join(OUT,'previews',a['name']+'.png');bpy.ops.render.render(write_still=True);bpy.data.objects.remove(o,do_unlink=True)
    with open(os.path.join(OUT,'render_status.json'),'w')as f:json.dump({'last':a['name']},f)

