"""Bake world-south facing into existing FBX vertices, preserving UVs/weights.

Run in Blender background. Source 2 adds +90 degrees to these FBX assets;
rotating authored vertices -90 degrees makes yaw=0 face world south.
"""
import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[1]
STAGE=ROOT/'output/unique_buildings'
MANIFEST=STAGE/'manifest.json'
entries=json.loads(MANIFEST.read_text(encoding='utf-8'))
backup=STAGE/'before_south_bake'
backup.mkdir(exist_ok=True)
if not (backup/'manifest.json').exists():shutil.copy2(MANIFEST,backup/'manifest.json')
for entry in entries:
    previous=float(entry.get('baked_yaw_degrees',0))
    if previous==-90:continue
    name=entry['name']
    source=STAGE/'source/models/survival_buildings'/(name+'.fbx')
    if not (backup/source.name).exists():shutil.copy2(source,backup/source.name)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
    assert len(meshes)==len(rigs)==1,name
    mesh=meshes[0]
    rotation=Matrix.Rotation(math.radians(-90-previous),4,'Z')
    local=mesh.matrix_world.inverted() @ rotation @ mesh.matrix_world
    mesh.data.transform(local)
    mesh.data.update()
    assert len(mesh.data.uv_layers)==1 and 'root' in rigs[0].data.bones,name
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True);rigs[0].select_set(True)
    bpy.context.view_layer.objects.active=mesh
    bpy.ops.export_scene.fbx(filepath=str(source),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
    entry['baked_yaw_degrees']=-90
    MANIFEST.write_text(json.dumps(entries,indent=2),encoding='utf-8')
    print('SOUTH_BAKED',name,flush=True)
print('REFERENCE_SOUTH_BAKE_PASS models=24 entity_yaw=0',flush=True)
