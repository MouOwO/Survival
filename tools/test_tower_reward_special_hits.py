from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'output/python_test_runtime'))
from lupa.lua51 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
names=['test_tower_skill_tree_exclusion.lua','audit_vip_special_attacks.lua','test_tower_reward_special_hits.lua']
lua.execute('\n'.join((ROOT/'scripts/vscripts/tests'/name).read_text(encoding='utf-8-sig') for name in names))
