"""Refresh the saved gold room without changing its models, placement or lights.

blender --background --python tools/refine_gold_room_materials.py
Before/after pairs are Cycles previews; engine verification is recorded separately.
"""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from gold_room_materials import build_materials, REVISION
OUT = ROOT / 'output/gold_training_room'
REVIEW = OUT / 'material_review'
REVIEW.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'gold_training_room.blend'))
scene = bpy.data.scenes['Gold Practice Room - assembled']
bpy.context.window.scene = scene
camera = scene.camera
original = (camera.location.copy(), camera.rotation_euler.copy(), camera.data.ortho_scale,
            scene.render.resolution_x, scene.render.resolution_y, scene.cycles.samples)


def shot(name, position, target, scale):
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = scale
    scene.render.resolution_x, scene.render.resolution_y = 1200, 900
    scene.cycles.samples = 40
    scene.render.filepath = str(REVIEW / f'{name}.png')
    bpy.ops.render.render(write_still=True)


views = [('stone_coin', (-420, -1860, 660), (-745, -1055, 70), 890),
         ('bronze_stone', (1300, -470, 780), (995, 15, 150), 780)]
first_revision = scene.get('surface_revision') != REVISION
if first_revision:
    for name, pos, target, scale in views:
        shot(name + '_before', pos, target, scale)
    (REVIEW / 'material_manifest_before.json').write_bytes((OUT / 'material_manifest.json').read_bytes())

materials, manifest = build_materials(OUT / 'source/materials/gold_training_room')
(OUT / 'material_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
for im in list(bpy.data.images):
    if im.users == 0 and 'gold_training_room' in im.filepath:
        bpy.data.images.remove(im)
scene['surface_revision'] = REVISION
for name, pos, target, scale in views:
    shot(name + '_after', pos, target, scale)

# Update the main page's established views with their original camera positions.
for name, pos, target, scale, res in [
    ('room_overview', (2600, -3700, 3500), (0, 90, 20), 3970, (1600, 1500)),
    ('room_top', (0, 50, 4500), (0, 50, 0), 3650, (1500, 1700)),
    ('entry_detail', (580, 410, 620), (0, 1110, 90), 1020, (1400, 1000)),
    ('stone_coin_detail', (-420, -1860, 660), (-745, -1055, 70), 980, (1400, 1000))]:
    camera.location = pos
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = scale
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = str(OUT / 'previews' / f'{name}.png')
    bpy.ops.render.render(write_still=True)

camera.location, camera.rotation_euler, camera.data.ortho_scale = original[:3]
scene.render.resolution_x, scene.render.resolution_y, scene.cycles.samples = original[3:]
bpy.ops.file.pack_all()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'gold_training_room.blend'))
(REVIEW / 'blender_review.json').write_text(json.dumps(dict(revision=REVISION,
    unchanged=['geometry', 'UV', 'placements', 'lighting', 'camera for each comparison'],
    comparisons=[dict(before=n + '_before.png', after=n + '_after.png') for n, *_ in views],
    renderer='Blender Cycles; not an in-game capture', emission=False), indent=2), encoding='utf-8')
print('GOLD_MATERIAL_REFINEMENT_COMPLETE', flush=True)
