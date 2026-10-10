"""Offline ordinary-worker cap lifecycle; no production writes or Dota connection."""
from pathlib import Path
import argparse,json,sys,tempfile,subprocess,os,shutil
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--stage',type=Path);p.add_argument('--lua',default='C:/Program Files/lua/bin/lua5.1.exe');a=p.parse_args()
root=a.root.resolve();stage=(a.stage or root).resolve();sys.path.insert(0,str(root/'tools'))
from build_wave_monster_cosmetics import parse_kv
def value(v):
 if isinstance(v,dict): return '{'+','.join('['+json.dumps(k)+']='+value(x) for k,x in v.items())+'}'
 return json.dumps(v,ensure_ascii=False)
with tempfile.TemporaryDirectory(prefix='survival_worker_cap_tests_') as tmp:
 fixture=Path(tmp)/'native_kv.lua'
 allkv={}
 for path,key in [('scripts/npc/npc_units_custom.txt','DOTAUnits'),('scripts/npc/npc_abilities_custom.txt','DOTAAbilities')]:
  source=stage/path if (stage/path).is_file() else root/path
  allkv[path]=parse_kv(source.read_text(encoding='utf-8-sig'))[key]
 fixture.write_text('return '+value(allkv),encoding='utf-8')
 test=Path(__file__).with_suffix('.lua')
 subprocess.run([a.lua,str(test),str(stage),str(fixture)],cwd=root,check=True)
print('WORKER_NATIVE_ATTACK_CAP_SUITE_PASS; no production files written')
