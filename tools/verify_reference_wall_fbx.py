"""Blender round-trip of wall selection skin, atlas and height-mask coordinates."""
import bpy
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from wall_asset_spec import HEIGHT_MULTIPLIER
OUT=ROOT/'output/reference_walls'
result=[]
for entry in json.loads((OUT/'manifest.json').read_text(encoding='utf-8')):
    original=None
    for suffix in ('','_flow'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(OUT/'source/models/survival_buildings'/(entry['name']+suffix+'.fbx')))
        meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
        assert len(meshes)==1 and len(rigs)==1 and 'root' in rigs[0].data.bones
        mesh=meshes[0];assert len(mesh.data.materials)==1 and len(mesh.data.uv_layers)==1
        assert all(v.groups and abs(sum(g.weight for g in v.groups)-1)<.001 for v in mesh.data.vertices)
        coords=[mesh.matrix_world@v.co for v in mesh.data.vertices]
        height=max(p.z for p in coords)-min(p.z for p in coords)
        assert abs(height-entry['original_height']*HEIGHT_MULTIPLIER)<.001,(entry['name'],'height')
        if not suffix:
            original=coords
            assert all(-.001<=n<=1.001 for corner in mesh.data.uv_layers[0].data for n in corner.uv)
        else:
            assert len(coords)==len(original) and all((a-b).length<.0001 for a,b in zip(coords,original))
            lo=min(p.z for p in coords);height=max(p.z for p in coords)-lo
            for loop in mesh.data.loops:
                v=mesh.data.uv_layers[0].data[loop.index].uv.y
                expected=1-(.05+.35*(coords[loop.vertex_index].z-lo)/height)
                assert abs(v-expected)<.0001,(entry['name'],v,expected)
    result.append(dict(name=entry['name'],root='root',atlas_uv_layers=1,height_multiplier=HEIGHT_MULTIPLIER,flow_matches_geometry=True,linear_height_uv=True))
(OUT/'fbx_verification.json').write_text(json.dumps(dict(status='PASS',models=result),indent=2),encoding='utf-8')
print('REFERENCE_WALL_FBX_PASS models=10 skins=10 height_uvs=10')
