"""Check trial tier grouping, generated configs and unchanged combat columns."""
from pathlib import Path
import csv,io,subprocess,sys,json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_configs

def parse(text):
 return list(csv.DictReader(line for line in text.splitlines() if line and not line.startswith('#')))
def previous(path):
 return subprocess.check_output(['git','show','HEAD:'+path.relative_to(ROOT).as_posix()],cwd=ROOT).decode('utf-8-sig')
report=[]
model_projectiles={}
for name in ['death','machine_gun','multi','frost','anti_air']:
 p=next((ROOT/'data/csv').rglob('tower_class_'+name+'.csv'))
 rows=parse(p.read_text(encoding='utf-8-sig')); old=parse(previous(p))
 assert len(rows)==len(old)==20
 stages={}
 for a,b in zip(old,rows):
  assert {k:v for k,v in a.items() if k not in ('projectile_model','model_name')}=={k:v for k,v in b.items() if k not in ('projectile_model','model_name')},'combat/config drift: '+b['record_id']
  stages.setdefault(b['stage_id'],[]).append(b['projectile_model'])
  model_projectiles[b['model_asset_id']]=b['projectile_model']
 assert [len(v) for v in stages.values()]==[5,5,10]
 assert all(len(set(v))==1 for v in stages.values()),'same tier must keep same projectile'
 assert len({v[0] for v in stages.values()})==3,'every tier must have distinct art'
 report.append({'route':name,'rows':20,'combat_columns_unchanged':True,'projectiles':[v[0] for v in stages.values()]})
# The linear skill changes only the particle reference; speed, width, targets,
# damage decay and cleanup clock remain byte-equivalent after normalization.
p=ROOT/'scripts/vscripts/systems/tower_special_skill_system.lua'
a=previous(p).replace('WAVE_OF_TERROR_PARTICLE','BURNING_ARROW_PARTICLE').replace('particles/econ/items/vengeful/vengeful_arcana/vengeful_arcana_wave_of_terror_v2.vpcf','particles/units/heroes/hero_clinkz/clinkz_searing_arrow_linear_proj.vpcf')
assert a.replace('\r\n','\n')==p.read_text(encoding='utf-8')
# Targeted regeneration must match committed-to-worktree Lua exactly.
check=ROOT/'output/tower_trial/config_check';check.mkdir(parents=True,exist_ok=True)
for name in ['tower_visual_profiles','asset_effects','tower_lightning_effects']+['tower_class_'+n for n in ['death','machine_gun','multi','frost','anti_air']]:
 p=next((ROOT/'data/csv').rglob(name+'.csv'));dest=check/(name+'.lua');build_configs.build(p,dest)
 assert dest.read_text(encoding='utf-8')==(ROOT/'scripts/vscripts/config/generated'/(name+'.lua')).read_text(encoding='utf-8')
profiles=parse(next((ROOT/'data/csv').rglob('tower_visual_profiles.csv')).read_text(encoding='utf-8'))
for row in profiles:
 if row['profile_id']=='ultimate':continue
 assert row['native_base'] and all(not row[k] for k in ['core','detail','detail_ssr','crown'])
ambient=parse(next((ROOT/'data/csv').rglob('asset_effects.csv')).read_text(encoding='utf-8'))
for row in ambient:
 if row['asset_id'] in model_projectiles and row['effect_role']=='attack_projectile':
  assert row['particle_path']==model_projectiles[row['asset_id']], 'asset override still uses old projectile: '+row['effect_key']
 if 'burning_wave' in row['effect_key']:
  assert row['particle_path']=='particles/units/heroes/hero_clinkz/clinkz_searing_arrow_linear_proj.vpcf'
assert all(row['enabled']=='0' for row in ambient if 'particles/units/heroes/hero_ancient_apparition/ancient_ice_vortex.vpcf' in row.values())
(ROOT/'output/tower_trial/config_contract.json').write_text(json.dumps({'status':'PASS','routes':report,'linear_skill_combat_unchanged':True,'generated_configs_match':True,'in_game_visual_verified':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('TOWER_TRIAL_CONFIG_PASS: 100 rows; five routes have 3 distinct tiers; combat columns and linear skill logic unchanged; generated configs match')
