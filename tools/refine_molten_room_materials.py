"""Material-only refresh of the saved Molten Core scene; no mesh/light changes."""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from molten_room_materials import build_materials, REVISION
OUT = ROOT / 'output/molten_core_room'
REVIEW = OUT / 'material_review'
REVIEW.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'molten_core_room.blend'))
scene = bpy.data.scenes['Molten Core Room - assembled']
bpy.context.window.scene = scene
camera = scene.camera
original = (camera.location.copy(), camera.rotation_euler.copy(), camera.data.ortho_scale,
            scene.render.resolution_x, scene.render.resolution_y, scene.cycles.samples,
            scene.render.filepath, scene.render.resolution_percentage)


def shot(path, position, target, scale, res=(1100, 825)):
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = scale
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.cycles.samples = 32
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


views = [('basalt_copper', (-1740, -1760, 620), (-1000, -1080, 65), 970),
         ('forged_brazier', (1370, -500, 540), (1035, 0, 180), 620)]
if scene.get('surface_revision') != REVISION:
    for name, pos, target, scale in views:
        shot(REVIEW / (name + '_before.png'), pos, target, scale)
    (REVIEW / 'material_manifest_before.json').write_bytes((OUT / 'material_manifest.json').read_bytes())

materials, manifest = build_materials(OUT / 'source/materials/molten_core_room')
(OUT / 'material_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
for im in list(bpy.data.images):
    if im.users == 0 and 'molten_core_room' in im.filepath:
        bpy.data.images.remove(im)
scene['surface_revision'] = REVISION
for name, pos, target, scale in views:
    shot(REVIEW / (name + '_after.png'), pos, target, scale)
shot(OUT / 'previews/room_overview.png', (2600, -3700, 3500), (0, 90, 20), 4300, (1500, 1400))
camera.location, camera.rotation_euler, camera.data.ortho_scale = original[:3]
scene.render.resolution_x, scene.render.resolution_y, scene.cycles.samples = original[3:6]
scene.render.filepath, scene.render.resolution_percentage = original[6:]
bpy.ops.file.pack_all()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'molten_core_room.blend'))
(REVIEW / 'blender_review.json').write_text(json.dumps(dict(revision=REVISION,
    unchanged=['geometry', 'UV', 'placements', 'lighting', 'camera for each comparison'],
    comparisons=[dict(before=n + '_before.png', after=n + '_after.png') for n, *_ in views],
    renderer='Blender Cycles; not an in-game capture', emission=False), indent=2), encoding='utf-8')
cards = ''.join('<section><h2>' + title + '</h2><div><figure><img src="' + name + '_before.png"><figcaption>修改前</figcaption></figure><figure><img src="' + name + '_after.png"><figcaption>修改后</figcaption></figure></div></section>' for name, title in [('basalt_copper', '玄武岩、氧化铜与冷却熔岩'), ('forged_brazier', '锻铁火盆与磨亮铜饰')])
(REVIEW / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>熔火核心材质打磨</title><style>body{background:#1b2022;color:#e9e5df;font:16px system-ui;margin:28px}h1{font-size:26px}div{display:flex;gap:16px}figure{margin:0;flex:1}img{width:100%;display:block}figcaption{padding:10px}section{margin:30px 0}</style><h1>熔火核心 · 材质打磨</h1><p>Blender Cycles 同相机、同光照对比。玄武岩断面与孔隙、焦灰哑光、旧铜与锻铁的反光差异；没有自发光和粒子。并非游戏截图。</p>' + cards + '<h2>完整房间</h2><img src="../previews/room_overview.png">', encoding='utf-8')
print('MOLTEN_MATERIAL_REFINEMENT_COMPLETE', flush=True)
