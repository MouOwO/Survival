"""Audit installed concept meshes, shells, material refs and unchanged gameplay."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from build_wave_monster_cosmetics import parse_kv
OUT=ROOT/'output/building_models_20260927';ENGINE=ROOT.parents[2]
CONTENT=ENGINE/'content/dota_addons/survival';INFO=ENGINE/'game/bin/win64/resourceinfo.exe'

def dump(path,block):
 p=subprocess.run([str(INFO),'-i',str(path),'-b',block,'-maxelements','100'],capture_output=True,check=True)
 return re.sub(rb'\r+\n',b'\n',p.stdout).decode('utf-8',errors='replace')
def bounds(path):
 s=dump(path,'MDAT');values=[]
 for field in ['Min','Max']:
  m=re.search(r'm_v'+field+r'Bounds = \[([^\]]+)\]',s);assert m,path
  values.append([float(v) for v in m[1].split(',')])
 return values

def main():
 manifest=json.loads((OUT/'manifest.json').read_text());assert len(manifest)==34,len(manifest)
 names={a['name'] for a in manifest};assert len(names)==34
 before=json.loads((OUT/'before_hashes.json').read_text())
 # Gameplay, model IDs, levels, towers and shell registry must remain unchanged.
 checked=0
 for rel,sha in before.items():
  if rel.startswith(('data/csv/','scripts/vscripts/config/generated/')) or rel=='scripts/npc/npc_units_custom.txt' or '/arrow_tower_' in rel:
   assert hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==sha,('unexpected gameplay/tower change',rel);checked+=1
 old_portraits=parse_kv((OUT/'before/scripts/npc/portraits_custom.txt').read_text(encoding='utf-8'))['Portraits']
 portraits=parse_kv((ROOT/'scripts/npc/portraits_custom.txt').read_text(encoding='utf-8'))['Portraits']
 changed={'models/survival_buildings/'+name+'.vmdl' for name in names}
 assert old_portraits.keys()==portraits.keys()
 for model in portraits:
  if model not in changed:assert portraits[model]==old_portraits[model],('unrelated portrait',model)
 reports=[]
 for a in manifest:
  name=a['name'];model=ROOT/(a['model']+'_c');shell=ROOT/'models/survival_buildings'/(name+'_white_shell.vmdl_c')
  assert 0<a['triangles']<=65000,(name,a['triangles'])
  lo,hi=bounds(model);slo,shi=bounds(shell)
  for actual,expected in zip(lo+hi,slo+shi):assert abs(actual-expected)<.025,(name,'shell bounds')
  assert abs(lo[2])<.025 and abs(hi[2]-a['height'])<.03,(name,lo,hi,a['height'])
  assert abs(max(hi[i]-lo[i] for i in (0,1))-(248 if name.startswith('wall_') else 236))<.04,name
  seq=dump(model,'ASEQ');assert 'ACT_DOTA_IDLE' in seq and '"idle"' in seq,name
  data=dump(model,'DATA');assert '"root"' in data,name
  old=OUT/'before/models/survival_buildings'/(name+'.vmdl_c')
  phys=dump(model,'PHYS').split('--- vmdl block PHYS',1)[1].split('\n',1)[1]
  oldphys=dump(old,'PHYS').split('--- vmdl block PHYS',1)[1].split('\n',1)[1]
  # Root orientation is now identity; compare the actual symmetric hull shape,
  # not floating-point serialization or bone-local vertex ordering.
  for field in ['m_vMinBounds','m_vMaxBounds']:
   avalues=[float(x) for x in re.search(field+r' = \[([^\]]+)\]',phys)[1].split(',')]
   bvalues=[float(x) for x in re.search(field+r' = \[([^\]]+)\]',oldphys)[1].split(',')]
   assert all(abs(x-y)<.03 for x,y in zip(avalues,bvalues)),(name,'physics bounds changed')
  for field in ['m_flVolume','m_flSurfaceArea']:
   av=float(re.search(field+r' = ([0-9.]+)',phys)[1]);bv=float(re.search(field+r' = ([0-9.]+)',oldphys)[1])
   assert abs(av-bv)/max(1,bv)<.00001,(name,field)
  oldstage=ROOT/('output/reference_walls' if name.startswith('wall_') else 'output/unique_buildings')/'source/models/survival_buildings'
  assert (oldstage/(name+'_collision.obj')).read_bytes()==(OUT/'source/models/survival_buildings'/(name+'_collision.obj')).read_bytes(),name
  s=dump(ROOT/'materials/survival_buildings'/(name+'.vmat_c'),'DATA')
  for feature in ['F_NORMAL_MAP','F_SPECULAR']:
   assert re.search(r'm_name = "'+feature+r'"\s+m_nValue = 1',s),(name,feature)
  refs=set(re.findall(r'resource:"(materials/survival_buildings/[^"\r\n]+\.vtex)"',s))
  assert len(refs)>=3,(name,refs)
  for ref in refs:assert (ROOT/(ref+'_c')).exists(),ref
  for kind in ['models','materials']:
   for src in (OUT/'source'/kind/'survival_buildings').glob(name+'*'):
    rel=src.relative_to(OUT/'source');assert src.read_bytes()==(CONTENT/rel).read_bytes(),str(rel)
  for suffix in ['', '_white_shell']:
   log=(OUT/(name+suffix+'.compile.log')).read_text(encoding='utf-8-sig')
   assert '0 failed' in log and '1 failed' not in log,name
  # Geometric proof that the entire model fits the portrait, including tall spires.
  import math,itertools
  camera=portraits[a['model']]['cameras']['default']
  position=[float(x) for x in camera['PortraitPosition'].split()]
  pitch,yaw,_=[math.radians(float(x)) for x in camera['PortraitAngles'].split()]
  forward=[math.cos(pitch)*math.cos(yaw),math.cos(pitch)*math.sin(yaw),-math.sin(pitch)]
  right=[-math.sin(yaw),math.cos(yaw),0];up=[math.sin(pitch)*math.cos(yaw),math.sin(pitch)*math.sin(yaw),math.cos(pitch)]
  tangent=math.tan(math.radians(float(camera['PortraitFOV'])/2))
  dot=lambda u,v:sum(x*y for x,y in zip(u,v))
  for corner in itertools.product(*zip(lo,hi)):
   q=[c-p for c,p in zip(corner,position)];depth=dot(q,forward)
   assert depth>0 and abs(dot(q,right))<=depth*tangent and abs(dot(q,up))<=depth*tangent*.9,(name,'portrait clipping')
  reports.append(dict(name=name,triangles=a['triangles'],bounds=[lo,hi],shell_aligned=True,physics_preserved=True,idle=True,portrait_fits=True,material_textures=len(refs)))
 report=dict(status='PASS',models=34,construction_shells=34,unchanged_gameplay_and_tower_files=checked,unrelated_portraits_preserved=True,assets=reports,game_visual_acceptance='pending')
 (OUT/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print('CONCEPT_ASSET_VERIFICATION_PASS models=34 shells=34 gameplay_and_tower_files='+str(checked))
if __name__=='__main__':main()
