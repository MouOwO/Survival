from pathlib import Path
import json,re,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_concept_buildings import ROOT,CONTENT,dump,bounds
stage=ROOT/'output/wall_models_named_20260927'
manifest=json.loads((stage/'manifest.json').read_text())
assert len(manifest)==9 and 'wall_lv03' not in {a['name'] for a in manifest}
report=[]
for a in manifest:
 name=a['name'];model=ROOT/(a['model']+'_c');shell=ROOT/'models/survival_buildings'/(name+'_white_shell.vmdl_c')
 lo,hi=bounds(model);slo,shi=bounds(shell)
 assert all(abs(x-y)<.04 for x,y in zip(lo+hi,slo+shi)),(name,'shell')
 assert abs(max(hi[i]-lo[i] for i in [0,1])-248)<.04,(name,'footprint')
 assert 0<a['triangles']<=65000
 assert 'ACT_DOTA_IDLE' in dump(model,'ASEQ')
 old=stage/'before/models/survival_buildings'/(name+'.vmdl_c')
 physics=dump(model,'PHYS');previous=dump(old,'PHYS')
 for field in ['m_vMinBounds','m_vMaxBounds']:
  x=[float(v) for v in re.search(field+r' = \[([^\]]+)\]',physics)[1].split(',')]
  y=[float(v) for v in re.search(field+r' = \[([^\]]+)\]',previous)[1].split(',')]
  assert all(abs(u-v)<.03 for u,v in zip(x,y)),(name,'collision bounds')
 for field in ['m_flVolume','m_flSurfaceArea']:
  x=float(re.search(field+r' = ([0-9.]+)',physics)[1]);y=float(re.search(field+r' = ([0-9.]+)',previous)[1])
  assert abs(x-y)/max(1,y)<.00001,(name,'collision geometry')
 material=dump(ROOT/'materials/survival_buildings'/(name+'.vmat_c'),'DATA')
 refs=set(re.findall(r'resource:"(materials/survival_buildings/[^"\r\n]+\.vtex)"',material));assert len(refs)>=3
 for ref in refs:assert (ROOT/(ref+'_c')).exists(),ref
 for kind in ['models','materials']:
  for src in (stage/'source'/kind/'survival_buildings').glob(name+'*'):
   assert src.read_bytes()==(CONTENT/src.relative_to(stage/'source')).read_bytes(),src
 for suffix in ['', '_white_shell']:
  assert '0 failed' in (stage/(name+suffix+'.compile.log')).read_text(encoding='utf-8-sig')
 report.append({'name':name,'triangles':a['triangles'],'collision_preserved':True,'shell_aligned':True,'textures':len(refs)})
(stage/'verification.json').write_text(json.dumps({'status':'PASS','models':9,'preserved_stage':'wall_lv03','assets':report},indent=2),encoding='utf-8')
print('NAMED_WALLS_PASS: 9 models + 9 construction shells, unchanged collision/footprint, valid animation/materials, content/runtime synced; stone wall preserved')
