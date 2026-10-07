"""Install only the main-city visual assets; preserve five levels and collision data."""
from pathlib import Path
import shutil,subprocess,json,re,hashlib
ROOT=Path(__file__).resolve().parents[1]
CONTENT=(ROOT/'../../../content/dota_addons/survival').resolve()
OUT=ROOT/'output/main_base_bunker_20260930'
SOURCE=OUT/'source'
NAME='main_base_bunker_v1'
MODELS='models/survival_buildings'
MATS='materials/survival_buildings'
manifest=json.loads((OUT/'manifest.json').read_text())
assert manifest['min_z']>=-.01 and 230<max(manifest['dimensions'][:2])<242
assert manifest['triangles']<65000
BACKUP=OUT/'before';BACKUP.mkdir(exist_ok=True)
def backup(file,kind,relative):
 if file.exists():
  dest=BACKUP/kind/relative;dest.parent.mkdir(parents=True,exist_ok=True)
  if not dest.exists():shutil.copy2(file,dest)

for level in range(1,6):
 alias=f'main_city_lv{level:02}'
 for suffix in ['', '_white_shell']:
  rel=Path(MODELS)/(alias+suffix+'.vmdl')
  old=CONTENT/rel;assert old.exists()
  backup(old,'content',rel);backup(ROOT/(str(rel)+'_c'),'game',Path(str(rel)+'_c'))
  original=(BACKUP/'content'/rel).read_text(encoding='utf-8')
  replacement=original.replace(f'{MODELS}/{alias}.fbx',f'{MODELS}/{NAME}.fbx').replace(f'{MODELS}/{alias}_flow.fbx',f'{MODELS}/{NAME}_flow.fbx').replace(f'{MATS}/{alias}.vmat',f'{MATS}/{NAME}.vmat').replace(alias+'_rig|'+alias+'_idle',NAME+'_rig|'+NAME+'_idle')
  assert NAME in replacement
  # Collision and selection boxes stay byte-identical to the old ModelDoc.
  if not suffix:
   for pattern in [r'_class="PhysicsHullFile"[^}]*',r'_class="Hitbox"[^}]*']:
    assert re.findall(pattern,original)==re.findall(pattern,replacement)
  (SOURCE/rel).write_text(replacement,encoding='utf-8')
# Keep a canonical authoring model; never assign its unprecached path in a live match.
canonical=(SOURCE/MODELS/'main_city_lv01.vmdl').read_text(encoding='utf-8')
(SOURCE/MODELS/(NAME+'.vmdl')).write_text(canonical,encoding='utf-8')
inputs=[p for p in SOURCE.rglob('*') if p.is_file()]
for p in inputs:
 rel=p.relative_to(SOURCE);target=CONTENT/rel;target.parent.mkdir(parents=True,exist_ok=True);backup(target,'content',rel)
 shutil.copy2(p,target)
compiler=(ROOT/'../../bin/win64/resourcecompiler.exe').resolve();game=(ROOT/'../../dota').resolve()
files=[SOURCE/MATS/(NAME+'.vmat'),SOURCE/MODELS/(NAME+'.vmdl')]+[SOURCE/MODELS/(f'main_city_lv{level:02}'+suffix+'.vmdl') for level in range(1,6) for suffix in ['', '_white_shell']]
results=[]
try:
 for p in files:
  rel=p.relative_to(SOURCE);r=subprocess.run([str(compiler),'-i',str(CONTENT/rel),'-game',str(game),'-f','-nop4'],capture_output=True,text=True,errors='replace',timeout=90)
  (OUT/(p.name+'.compile.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
  compiled=ROOT/(str(rel)+'_c')
  assert r.returncode==0 and '0 failed' in r.stdout and compiled.exists(),p.name+': '+r.stdout[-3500:]+r.stderr[-500:]
  results.append({'resource':str(rel),'compiled_bytes':compiled.stat().st_size,'sha256':hashlib.sha256(compiled.read_bytes()).hexdigest()});print('COMPILED',p.name,flush=True)
except Exception:
 # Restore original main-city resources on failure, while retaining new unused sources for diagnosis.
 for kind,destination in [('content',CONTENT),('game',ROOT)]:
  for p in (BACKUP/kind).rglob('*'):
   if p.is_file():shutil.copy2(p,destination/p.relative_to(BACKUP/kind))
 raise
(OUT/'installation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('MAIN_BASE_BUNKER_INSTALLED: five levels and five construction shells; unchanged collision/hitboxes/gameplay')
