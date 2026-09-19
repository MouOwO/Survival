"""Run the presentation regressions and retain logs for the final handoff."""
import json
import shutil
import subprocess
from pathlib import Path
from build_building_warp_particles import PARTICLE_NAMES, MATERIAL
from build_building_flow_materials import REVEAL_SECONDS
from verify_building_white_shells import verify as verify_white_shells

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/building_presentation'
tests=['test_unique_building_models','test_farm_fixed_visual','test_reference_building_collision',
       'test_building_visual_service','test_tower_hero_visual_regression',
       'test_gold_mine_batch_upgrade_service','test_gold_mine_auto_upgrade_coordinator',
       'test_building_grid_alignment','test_grid_placement_collision','test_tower_rebuild_after_death',
       'test_building_construction_visual_service','test_building_upgrade_process',
       'test_building_white_shell']
results=[]
for name in tests:
    run=subprocess.run(['lua',str(ROOT/'scripts/vscripts/tests'/(name+'.lua'))],cwd=ROOT,capture_output=True)
    (OUT/(name+'.log')).write_bytes(run.stdout+run.stderr)
    results.append(dict(test=name,status='PASS' if run.returncode==0 else 'FAIL'))
    print(name,results[-1]['status'])
for relative in [MATERIAL]+['particles/survival_buildings/'+name+'.vpcf' for name in PARTICLE_NAMES]:
    source=OUT/'source'/relative
    compiled=ROOT/(relative+'_c')
    assert compiled.is_file() and compiled.stat().st_mtime>=source.stat().st_mtime,source
    assert '0 failed' in (OUT/(source.name+'.compile.log')).read_text(encoding='utf-8',errors='replace'),source
js=OUT/'source/panorama/scripts/custom_game/survival_grid_placement.js'
subprocess.run(['node','--check',str(js)],cwd=ROOT,check=True)
shell=shutil.which('pwsh') or shutil.which('powershell')
assert shell, 'PowerShell is required for the compiled texture pixel audit'
subprocess.run([shell,'-NoProfile','-File',str(ROOT/'tools/test_building_white_material.ps1')],cwd=ROOT,check=True)
white_material=json.loads((OUT/'white_material_verification.json').read_text(encoding='utf-8-sig'))
subprocess.run([shell,'-NoProfile','-File',str(ROOT/'tools/test_building_flow_material.ps1')],cwd=ROOT,check=True)
flow_material=json.loads((OUT/'flow_material_verification.json').read_text(encoding='utf-8-sig'))
white_shells=verify_white_shells()
report=dict(status='PASS' if all(r['status']=='PASS' for r in results) else 'FAIL',
            model_yaw=0,baked_yaw_degrees=-90,model_scale=1.0,model_source_scale=2.0,footprint=[2,2],world_footprint=128,
            particle_sources=len(PARTICLE_NAMES),effect='iridescent_top_down_reveal',
            reveal_seconds=REVEAL_SECONDS,white_material=white_material,flow_material=flow_material,white_shells=white_shells,
            workshop_verified=False,tests=results)
(OUT/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert report['status']=='PASS'
print('BUILDING_PRESENTATION_PASS tests=13 white_shells=24 effect=iridescent_top_down_reveal')
