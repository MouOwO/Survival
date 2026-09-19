"""Blender round-trip audit of the exported runtime mesh, UV atlas and skin."""
import bpy
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/unique_buildings'
results=[]
for entry in json.loads((OUT/'manifest.json').read_text()):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(OUT/'source/models/survival_buildings'/(entry['name']+'.fbx')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
    assert len(meshes)==1 and len(rigs)==1,entry['name']
    mesh=meshes[0]
    assert 'root' in rigs[0].data.bones
    assert len(mesh.data.uv_layers)==1
    assert mesh.data.uv_layers[0].name=='BuildingAtlas'
    assert len(mesh.data.materials)==1
    assert len(mesh.data.uv_layers[0].data)==len(mesh.data.loops)
    assert all(v.groups and abs(sum(g.weight for g in v.groups)-1)<.001 for v in mesh.data.vertices)
    assert all(-.001 <= value <= 1.001 for corner in mesh.data.uv_layers[0].data for value in corner.uv)
    results.append(dict(name=entry['name'],vertices=len(mesh.data.vertices),uv='BuildingAtlas',root='root',status='PASS'))
(OUT/'fbx_verification.json').write_text(json.dumps(results,indent=2))
print('UNIQUE_BUILDING_FBX_PASS',len(results))
