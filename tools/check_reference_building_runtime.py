"""Run targeted runtime regressions and retain reviewable validation output."""
import json
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/unique_buildings'
tests=['test_unique_building_models','test_farm_fixed_visual','test_reference_building_collision',
       'test_building_visual_service','test_tower_hero_visual_regression',
       'test_gold_mine_batch_upgrade_service','test_gold_mine_auto_upgrade_coordinator']
report=[]
for name in tests:
    result=subprocess.run(['lua',str(ROOT/'scripts/vscripts/tests'/(name+'.lua'))],cwd=ROOT,capture_output=True)
    output=(result.stdout+result.stderr).decode('utf-8',errors='replace')
    (OUT/(name+'.log')).write_text(output,encoding='utf-8')
    report.append(dict(test=name,status='PASS' if result.returncode==0 else 'FAIL',exit_code=result.returncode))
    print(name,report[-1]['status'])
(OUT/'runtime_verification.json').write_text(json.dumps(report,indent=2))
assert all(r['status']=='PASS' for r in report),report
print('REFERENCE_RUNTIME_CHECKS_PASS',len(report))
