"""Blender: copy shell mesh with height-coordinate UVs; normal models untouched."""
import bpy
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
STAGE=ROOT/'output/unique_buildings'
MODELS=STAGE/'source/models/survival_buildings'
entries=json.loads((STAGE/'manifest.json').read_text(encoding='utf-8'))
selected=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
for entry in entries:
    name=entry['name']
    if selected and name not in selected:continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(MODELS/(name+'.fbx')))
    mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    coords=[mesh.matrix_world@v.co for v in mesh.data.vertices]
    z0=min(v.z for v in coords);height=max(v.z for v in coords)-z0
    width=max(v.x for v in coords)-min(v.x for v in coords)
    uv=mesh.data.uv_layers.active
    for loop in mesh.data.loops:
        p=coords[loop.vertex_index]
        # Source 2 flips imported V. Runtime V therefore increases with height.
        uv.data[loop.index].uv=((p.x+p.y*.32)/width+.5,1-(.05+.35*(p.z-z0)/height))
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=mesh
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'_flow.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
    print('FLOW_HEIGHT_UV',name,'height',height,flush=True)
print('BUILDING_FLOW_MESHES_PASS',flush=True)
