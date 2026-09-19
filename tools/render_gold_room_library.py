"""Render component cards and prepare a readable Blender asset-library scene."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/gold_training_room'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'gold_training_room.blend'))
room=bpy.data.scenes['Gold Practice Room - assembled'];scene=bpy.data.scenes['B01-B16 Modular Library']
bpy.context.window.scene=scene
assets=json.loads((OUT/'asset_manifest.json').read_text(encoding='utf-8'))
objects=[scene.objects[a['name']]for a in assets]
for o in objects:o.hide_render=True
native=scene.objects.get('B15_native_pine_preview');native.hide_render=True
camdata=bpy.data.cameras.new('Library camera');cam=bpy.data.objects.new('Library camera',camdata);scene.collection.objects.link(cam);scene.camera=cam;camdata.type='ORTHO';camdata.clip_end=25000
scene.render.resolution_x=440;scene.render.resolution_y=400;scene.cycles.samples=12
scene.render.film_transparent=False
bpy.ops.mesh.primitive_plane_add(size=20000,location=(0,0,-32));floor=bpy.context.object;floor.name='Library backdrop'
mat=bpy.data.materials.new('Library neutral background');mat.diffuse_color=(.24,.23,.21,1);floor.data.materials.append(mat)
dest=OUT/'previews/components';dest.mkdir(parents=True,exist_ok=True)
for i,a in enumerate(assets):
    o=objects[i];o.location=(0,0,0);o.hide_render=False
    bmin,bmax=a['bounds'];size=Vector(bmax)-Vector(bmin);target=(Vector(bmin)+Vector(bmax))*.5
    span=max(size);cam.location=target+Vector((span*1.1,-span*1.65,span*1.25))
    if a['category']=='floor':cam.location=target+Vector((span*.6,-span*.8,span*1.5))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=span*1.65
    floor.location.z=bmin[2]-.8
    scene.render.filepath=str(dest/(a['name']+'.png'));bpy.ops.render.render(write_still=True)
    o.hide_render=True;o.location=((i%6)*700,(i//6)*700,0)
    print('GOLD_ROOM_CARD',a['name'],flush=True)
for o in objects:o.hide_render=False
native.hide_render=False;native.location=(0,3500,0)
floor.location.z=-30
for i,a in enumerate(assets):
    if a['name']=='room_earth_base':objects[i].hide_render=True;objects[i].hide_set(True);continue
    label=bpy.data.curves.new(a['name']+'_label','FONT');label.body=a['name'];label.size=25;label.align_x='CENTER'
    ob=bpy.data.objects.new(a['name']+'_label',label);scene.collection.objects.link(ob);ob.location=((i%6)*700,(i//6)*700-210,2)
    lm=bpy.data.materials.get('Library label ink')or bpy.data.materials.new('Library label ink');lm.diffuse_color=(.055,.055,.04,1);label.materials.append(lm)
cam.location=(1800,1500,6000);cam.rotation_euler=(0,0,0);cam.rotation_euler=(Vector((1800,1500,0))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.ortho_scale=4500
scene.render.resolution_x=1800;scene.render.resolution_y=1800;scene.render.filepath=str(OUT/'previews/component_library.png');bpy.ops.render.render(write_still=True)
bpy.context.window.scene=room
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.clip_end=30000
            region=area.spaces.active.region_3d
            region.view_perspective='ORTHO'
            region.view_location=Vector((0,120,0))
            region.view_rotation=room.camera.rotation_euler.to_quaternion()
            region.view_distance=4200
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'gold_training_room.blend'))
print('GOLD_ROOM_LIBRARY_COMPLETE',len(assets),flush=True)
