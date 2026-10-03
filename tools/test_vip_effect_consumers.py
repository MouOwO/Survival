from pathlib import Path
import sys,json
sys.path.insert(0,'output/python_test_runtime')
from lupa.lua51 import LuaRuntime
p=Path('scripts/vscripts/tests/test_vip_effect_consumers.lua');p.write_text(p.read_text(encoding='utf-8-sig'),encoding='utf-8')
source=Path('scripts/vscripts/tests/test_reward_effect_audit.lua').read_text(encoding='utf-8')
source+='\nrequire("tests/test_vip_effect_consumers")({check=check,near=near,private=private,set=set,unit=unit,hero=hero,bus=bus,ev=ev,totals=totals})'
lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(source)
results=json.loads(lua.eval('require("core/json_encoder").encode')(lua.globals().AUDIT_RESULTS))
Path('output/vip_rewards_20261003/consumer_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
failed=[r for r in results if not r['ok']]
print('VIP_CONSUMERS',sum(r['name'].startswith('vip_') and r['ok'] for r in results),'KNOWN_OTHER_FAILURES',[r['name'] for r in failed])
if any(r['name'].startswith('vip_') for r in failed):raise SystemExit(1)
