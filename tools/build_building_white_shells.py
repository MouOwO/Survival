"""Build explicit white building render meshes; no CP model lookup or hitboxes."""
import json
from pathlib import Path
from build_building_flow_materials import REVEAL_STEPS

ROOT=Path(__file__).resolve().parents[1]
STAGE=ROOT/'output/unique_buildings'
MODELS=STAGE/'source/models/survival_buildings'
manifest=json.loads((STAGE/'manifest.json').read_text(encoding='utf-8'))
for entry in manifest:entry['_stage']=STAGE
wall_stage=ROOT/'output/reference_walls'
if (wall_stage/'manifest.json').exists():
    walls=json.loads((wall_stage/'manifest.json').read_text(encoding='utf-8'))
    for entry in walls:entry['_stage']=wall_stage
    manifest+=walls
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
registry=['-- Generated from output/unique_buildings/manifest.json by build_building_white_shells.py.','return {']
for entry in manifest:
    name=entry['name']
    target_models=entry['_stage']/'source/models/survival_buildings'
    import_scale=entry.get('import_scale',.02)
    material='materials/survival_buildings/'+name+'.vmat'
    groups=['{_class="DefaultMaterialGroup" remaps=[{from="'+material+'" to="materials/survival_buildings/build_flow_00.vmat"}] use_global_default=false}']
    for step in range(1,REVEAL_STEPS+1):
        groups.append('{_class="MaterialGroup" name="reveal_%02d" remaps=[{from="materials/survival_buildings/build_flow_00.vmat" to="materials/survival_buildings/build_flow_%02d.vmat"}]}'%(step,step))
    nodes=[
        '{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'_white_shell" filename="models/survival_buildings/'+name+'_flow.fbx" import_scale='+str(import_scale)+'}]}',
        '{_class="MaterialGroupList" children=['+','.join(groups)+']}',
        '{_class="BoneMarkupList" children=[] bone_cull_type="None"}',
    ]
    path=target_models/(name+'_white_shell.vmdl')
    text=HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}'
    if not path.exists() or path.read_text(encoding='utf-8')!=text:
        path.write_text(text,encoding='utf-8')
    registry.append('    ["models/survival_buildings/'+name+'.vmdl"] = "models/survival_buildings/'+name+'_white_shell.vmdl",')
registry.append('}')
(ROOT/'scripts/vscripts/config/generated/building_white_shells.lua').write_text('\n'.join(registry)+'\n',encoding='utf-8')
print(f'BUILDING_WHITE_SHELL_SOURCES models={len(manifest)} no_hitboxes no_physics')
