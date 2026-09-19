"""Render the existing component library after a material-only revision."""
import bpy
import json
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1] / 'output/gold_training_room'
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'gold_training_room.blend'))
scene = bpy.data.scenes['B01-B16 Modular Library']
bpy.context.window.scene = scene
assets = json.loads((OUT / 'asset_manifest.json').read_text(encoding='utf-8'))
objects = [scene.objects[a['name']] for a in assets]
native = scene.objects.get('B15_native_pine_preview')
labels = [o for o in scene.objects if o.type == 'FONT']
floor = scene.objects['Library backdrop']
cam = scene.camera
state = {o: (o.location.copy(), o.hide_render) for o in objects + [native, floor] + labels}
camera_state = (cam.location.copy(), cam.rotation_euler.copy(), cam.data.ortho_scale)
for o in objects + [native] + labels:
    o.hide_render = True
scene.cycles.samples = 24
scene.render.resolution_x, scene.render.resolution_y = 440, 400
for a, obj in zip(assets, objects):
    obj.location = (0, 0, 0)
    obj.hide_render = False
    bmin, bmax = (Vector(b) for b in a['bounds'])
    size, target = bmax - bmin, (bmax + bmin) * .5
    span = max(size)
    cam.location = target + Vector((span * 1.1, -span * 1.65, span * 1.25))
    if a['category'] == 'floor':
        cam.location = target + Vector((span * .6, -span * .8, span * 1.5))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = span * 1.65
    floor.location.z = bmin.z - .8
    scene.render.filepath = str(OUT / 'previews/components' / (a['name'] + '.png'))
    bpy.ops.render.render(write_still=True)
    obj.hide_render = True
    obj.location = state[obj][0]
for obj, (location, hidden) in state.items():
    obj.location, obj.hide_render = location, hidden
cam.location, cam.rotation_euler, cam.data.ortho_scale = camera_state
scene.render.resolution_x = scene.render.resolution_y = 1800
scene.render.filepath = str(OUT / 'previews/component_library.png')
bpy.ops.render.render(write_still=True)
print('GOLD_ROOM_CARDS_REFRESHED', len(assets), flush=True)
