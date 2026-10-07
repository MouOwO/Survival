from pathlib import Path
import sys,json
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'output/python_test_runtime'))
from lupa.lua51 import LuaRuntime
out=ROOT/'output/vip_effect_audit_20261003';out.mkdir(exist_ok=True,parents=True)
ctx='{check=check,near=near,private=private,set=set,unit=unit,hero=hero,bus=bus,ev=ev,totals=totals}'
for name in ['test_vip_audit_extra.lua','audit_vip_special_attacks.lua']:
 p=ROOT/'scripts/vscripts/tests'/name;p.write_text(p.read_text(encoding='utf-8-sig'),encoding='utf-8')
lua=LuaRuntime(unpack_returned_tuples=True)
source=(ROOT/'scripts/vscripts/tests/test_reward_effect_audit.lua').read_text(encoding='utf-8')
for name in ['test_starjoy_effect_consumers','test_vip_effect_consumers','test_vip_audit_extra']:
 source+='\nrequire("tests/'+name+'")('+ctx+')'
lua.execute(source)
checks=json.loads(lua.eval('require("core/json_encoder").encode')(lua.globals().AUDIT_RESULTS))
(out/'consumer_checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
special=LuaRuntime(unpack_returned_tuples=True)
special.execute((ROOT/'scripts/vscripts/tests/test_tower_skill_tree_exclusion.lua').read_text(encoding='utf-8')+'\n'+(ROOT/'scripts/vscripts/tests/audit_vip_special_attacks.lua').read_text(encoding='utf-8'))
rows=json.loads(special.eval('require("core/json_encoder").encode')(special.globals().VIP_SPECIAL_AUDIT))
(out/'special_attack_checks.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
print('CONSUMER CHECKS',len(checks),'PASSED',sum(r['ok'] for r in checks))
for r in rows:print('PASS' if r['ok'] else 'ISSUE',r['id'],r['actual'],'expected',r['expected'])
