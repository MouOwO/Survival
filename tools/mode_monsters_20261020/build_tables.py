"""Materialize reviewed video values and explicitly sourced estimates into CSV."""
from __future__ import annotations
import csv,json,math,statistics,sys
from collections import defaultdict
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_recorded_mode_configs import DIFFICULTIES,SOURCE,read_rows

FIELDS=('health','attack','war3_armor')
WAVES='data/csv/怪物与波次系统/rich_wave_definitions.csv'
MEMBERS='data/csv/挑战与奖励系统/rich_challenge_combat_profiles.csv'
VARIANTS='data/csv/怪物与波次系统/rich_wave_stat_variants.csv'
NEW_WAVES='data/csv/怪物与波次系统/recorded_mode_wave_definitions.csv'
NEW_MEMBERS='data/csv/挑战与奖励系统/recorded_mode_challenge_combat_profiles.csv'
NEW_VARIANTS='data/csv/怪物与波次系统/recorded_mode_wave_stat_variants.csv'

def layout(relative):
 with (ROOT/relative).open(encoding='utf-8-sig',newline='') as f:
  rows=list(csv.reader(f))
 return rows[0],rows[1:3]

def write(relative,rows,template=None,add_mode=False):
 headers,comments=layout(template or relative)
 if add_mode:
  headers=headers[:1]+['mode_id']+headers[1:]
  comments=[r[:1]+[('#模式ID' if i==0 else 'string')]+r[1:] for i,r in enumerate(comments)]
 with (ROOT/relative).open('w',encoding='utf8',newline='') as f:
  writer=csv.writer(f,lineterminator='\n');writer.writerow(headers);writer.writerows(comments)
  for row in rows:writer.writerow([row.get(k,'') for k in headers])

def numeric(value):
 value=float(value)
 return int(value) if value.is_integer() else value

def encode(value):
 def present(item):
  if isinstance(item,dict):return {k:present(v) for k,v in item.items() if v is not None}
  if isinstance(item,list):return [present(v) for v in item if v is not None]
  return item
 return json.dumps(present(value),ensure_ascii=False,separators=(',',':'),sort_keys=True)

def main():
 data=json.loads((ROOT/SOURCE).read_text(encoding='utf8'))
 observations=data['observations'];indexed=defaultdict(list)
 for obs in observations:indexed[(obs['mode_id'],obs['difficulty_id'])].append(obs)
 waves,members,variants=[read_rows(ROOT/p) for p in (WAVES,MEMBERS,VARIANTS)]
 ref_waves={(int(r['wave_number']),r['batch_id']):r for r in waves if r['difficulty_id']=='N3'}
 ref_members={r['member_id']:r for r in members if r['difficulty_id']=='N3'}
 ref_variants=[r for r in variants if r['difficulty_id']=='N3']
 wave_groups=defaultdict(list)
 for row in ref_waves.values():wave_groups[int(row['wave_number'])].append(row)
 pairs=[('rich','N4')]+[(m,d) for m,ds in DIFFICULTIES.items() for d in ds]
 calibration={};assignment=[]

 def normal_group(rows):
  rows=[r for r in rows if r.get('role') not in ('assault_boss','wave_leader','leader') and r.get('category') not in ('wave_boss','assault_boss')]
  if not rows:return []
  low=min(r['stats']['health'] for r in rows)
  return [r for r in rows if r['stats']['health']<=low*1.35]

 for mode,difficulty in pairs:
  observed=indexed[(mode,difficulty)];ratios={field:[] for field in FIELDS};refs=[]
  paired_ratios={field:[] for field in FIELDS};paired_refs=[]
  for number,templates in wave_groups.items():
   selected=normal_group([r for r in observed if r.get('wave_number')==number and r.get('category') in ('wave','wave_normal','wave_leader')])
   baseline=[r for r in templates if r['member_role']=='normal']
   if not selected or not baseline:continue
   # A wave can expose only a ranged/melee member. Medians across distinct waves
   # prevent one missing role or one switched panel from setting the whole mode.
   for field in FIELDS:
    seen=[r['stats'][field] for r in selected if r['stats'].get(field) is not None]
    if not seen:continue
    value=min(seen);reference=min(float(r[field]) for r in baseline)
    if value>0 and reference>0:ratios[field].append(value/reference)
   refs.extend(r['record_id'] for r in selected)
   all_regular=[r for r in observed if r.get('wave_number')==number and r.get('category') in ('wave','wave_normal','wave_leader') and r.get('role')!='assault_boss']
   paired=all_regular and min(r['stats']['health'] for r in all_regular)>0 and max(r['stats']['health'] for r in all_regular)>=min(r['stats']['health'] for r in all_regular)*1.75
   if paired:
    paired_refs.extend(r['record_id'] for r in selected)
    for field in FIELDS:
     seen=[r['stats'][field] for r in selected if r['stats'].get(field) is not None]
     reference=min(float(r[field]) for r in baseline)
     if seen and reference>0:paired_ratios[field].append(min(seen)/reference)
  if mode=='scourge' and len(paired_ratios['health'])>=2:
   ratios=paired_ratios;refs=paired_refs
  factors={field:statistics.median(values) if values else None for field,values in ratios.items()}
  calibration[(mode,difficulty)]={'wave_factors':factors,'wave_references':sorted(set(refs))}
  if mode=='scourge':
   segments={}
   for phase,minimum,maximum in [('early',1,10),('late',11,30)]:
    samples={f:[] for f in FIELDS};phase_refs=[]
    for number,templates in wave_groups.items():
     if not minimum<=number<=maximum:continue
     selected=normal_group([o for o in observed if o.get('wave_number')==number and o.get('category') in ('wave','wave_normal','wave_leader')])
     baseline=[t for t in templates if t['member_role']=='normal']
     if not selected or not baseline:continue
     phase_refs.extend(o['record_id'] for o in selected)
     for field in FIELDS:
      values=[o['stats'][field] for o in selected if o['stats'].get(field) is not None]
      if values:samples[field].append(min(values)/min(float(t[field]) for t in baseline))
    phase_factors={f:statistics.median(v) if v else factors[f] for f,v in samples.items()}
    if phase=='late':
     for field in ('health','war3_armor'):
      if paired_ratios[field]:phase_factors[field]=statistics.median(paired_ratios[field])
    # Matching only the weakest template misidentifies a sampled melee unit as
    # a ranged one. Fit attack against every existing same-wave normal model,
    # giving each wave one vote; use the median of the most-supported cluster.
    attack_candidates=defaultdict(list)
    for number,templates in wave_groups.items():
     if not minimum<=number<=maximum:continue
     selected=normal_group([o for o in observed if o.get('wave_number')==number and o.get('category') in ('wave','wave_normal','wave_leader')])
     for obs in selected:
      if obs['stats'].get('attack') is None:continue
      for template in templates:
       if template['member_role']=='normal' and float(template['attack'])>2:
        attack_candidates[number].append((obs['stats']['attack']-2)/(float(template['attack'])-2))
    candidates=[factor for values in attack_candidates.values() for factor in values if factor>0]
    if candidates:
     def support(factor):return sum(any(abs(math.log(value/factor))<.02 for value in values if value>0) for values in attack_candidates.values())
     fitted=max(candidates,key=lambda factor:(support(factor),-factor))
     phase_factors['attack']=statistics.median(factor for factor in candidates if abs(math.log(factor/fitted))<.02)
    segments[phase]={'factors':phase_factors,'references':sorted(set(phase_refs)) or sorted(set(refs))}
   calibration[(mode,difficulty)]['wave_segments']=segments
 # Entirely cropped cold N1 uses the existing N1/N2 relationship: the same
 # measured cold-N2-to-rich-N2 factor is applied to the pre-existing rich N1 row.
 for key,value in calibration.items():
  if not value['wave_references']:
   other=next((calibration[(key[0],d)] for d in DIFFICULTIES.get(key[0],()) if calibration[(key[0],d)]['wave_references']),None)
   assert other,'No calibration for mode '+key[0]
   value.update(wave_factors=dict(other['wave_factors']),wave_references=list(other['wave_references']),unobserved_difficulty=True)

 def complete_stats(reference,mode,difficulty,category,number=None,role=None):
  config=calibration[(mode,difficulty)];observed=indexed[(mode,difficulty)]
  missing_member_category=category!='wave' and not any(o.get('member_id') in ref_members for o in observed)
  if config.get('unobserved_difficulty') or missing_member_category:
   supported=[d for d in DIFFICULTIES[mode] if not calibration[(mode,d)].get('unobserved_difficulty') and (category=='wave' or any(o.get('member_id') in ref_members for o in indexed[(mode,d)]))]
   sibling=min(supported,key=lambda d:abs(int(d[1:])-int(difficulty[1:])))
   values,origins,_=complete_stats(reference,mode,sibling,category,number,role)
   catalog=waves if category=='wave' else members
   def same(row):return int(row['wave_number'])==number and row['batch_id']==reference['batch_id'] if category=='wave' else row['member_id']==reference['member_id']
   target=next(r for r in catalog if r['difficulty_id']==difficulty and same(r))
   source=next(r for r in catalog if r['difficulty_id']==sibling and same(r))
   output={};sources={}
   for field in FIELDS:
    factor=float(target[field])/float(source[field]);output[field]=max(0 if field=='war3_armor' else 1,math.floor(values[field]*factor+.5))
    refs=sorted({o['record_id'] for o in origins.values() if 'record_id' in o}|{ref for o in origins.values() for ref in o.get('reference_record_ids',[])})
    sources[field]={'method':'cross_difficulty_estimate','explanation':('The entire selected-stat panel is outside this recording; scale the sibling mode difficulty using the existing member-specific relationship.' if config.get('unobserved_difficulty') else 'No non-wave member was selected at this difficulty; scale the sibling difficulty final profile using the existing member-specific relationship.'),
      'input_value':values[field],'factor':factor,'rounding_quantum':1,'reference_record_ids':refs,
      'reference_difficulty_id':sibling,'reference_table':NEW_VARIANTS if category=='wave' and 'variant_index' in reference else NEW_WAVES if category=='wave' else NEW_MEMBERS,
      'ratio_reference_table':WAVES if category=='wave' else MEMBERS,
      'reference_wave_number':number,'reference_batch_id':reference.get('batch_id'),
      'reference_variant_index':reference.get('variant_index'),'reference_member_id':reference.get('member_id')}
   return output,sources,'estimated'
  is_wave=category=='wave';selected=[]
  segment=config.get('wave_segments',{}).get('early' if number and number<=10 else 'late') if is_wave else None
  wave_factors=segment['factors'] if segment else config['wave_factors']
  if is_wave:
   selected=[r for r in observed if r.get('wave_number')==number]
   bosses=[r for r in selected if r.get('role')=='assault_boss' or r.get('category') in ('wave_boss','assault_boss')]
   ordinary=[r for r in selected if r not in bosses]
   normals=normal_group(ordinary)
   if role=='assault_boss':selected=bosses
   elif role=='wave_leader':
    templates=[r for r in wave_groups[number] if r['member_role']=='normal']
    minimum=min((float(r['health']) for r in templates),default=0)*wave_factors['health']
    selected=[r for r in ordinary if r.get('role') in ('leader','wave_leader') or minimum and r['stats']['health']>=minimum*1.75]
   else:selected=normals
  else:selected=[r for r in observed if r.get('member_id')==reference['member_id']]
  factors=dict(wave_factors);references=list(segment['references'] if segment else config['wave_references'])
  for field,multiplier in reference.get('_factor_multiplier',{}).items():factors[field]*=multiplier
  input_row=reference
  if config.get('unobserved_difficulty') and is_wave:
   original=next((r for r in waves if r['difficulty_id']==difficulty and int(r['wave_number'])==number and r['batch_id']==reference['batch_id']),None)
   if original:input_row=original
   # Cold N2 factor above was fitted against rich N3. Convert it to the
   # corresponding existing rich N2 baseline before applying N1/N2 inheritance.
   source_difficulty='N2'
   base=next((r for r in waves if r['difficulty_id']==source_difficulty and int(r['wave_number'])==number and r['batch_id']==reference['batch_id']),None)
   if base:
    for field in FIELDS:factors[field]*=float(reference[field])/float(base[field])
  if not is_wave:
   # Non-wave combat has its own scale. A wave multiplier is never silently
   # reused as though it were an observed training-room or wilderness stat.
   by_field={f:[] for f in FIELDS};nonwave_refs=[]
   for obs in observed:
    other=ref_members.get(obs.get('member_id'))
    if other:
     nonwave_refs.append(obs['record_id'])
     for field in FIELDS:
      if float(other[field])>0 and obs['stats'].get(field) is not None:by_field[field].append(obs['stats'][field]/float(other[field]))
   if not nonwave_refs:
    sibling=next((indexed[(mode,d)] for d in DIFFICULTIES.get(mode,()) if any(o.get('member_id') in ref_members for o in indexed[(mode,d)])),[])
    for obs in sibling:
     other=ref_members.get(obs.get('member_id'))
     if other:
      nonwave_refs.append(obs['record_id'])
      for field in FIELDS:
       if float(other[field])>0 and obs['stats'].get(field) is not None:by_field[field].append(obs['stats'][field]/float(other[field]))
   factors={f:statistics.median(v) if v else 1 for f,v in by_field.items()};references=sorted(set(nonwave_refs))
   config['nonwave_factors']=factors;config['nonwave_references']=references
   if config.get('unobserved_difficulty'):
    original=next((r for r in members if r['difficulty_id']==difficulty and r['member_id']==reference['member_id']),None)
    sibling_base=next((r for r in members if r['difficulty_id']=='N2' and r['member_id']==reference['member_id']),None)
    if original and sibling_base:
     input_row=original
     for field in FIELDS:factors[field]*=float(reference[field])/float(sibling_base[field])
  predicted={f:max(0 if f=='war3_armor' else 1,math.floor(float(input_row[f])*factors[f]+.5)) for f in FIELDS}
  # A displayed leader ratio is mode-specific (e.g. scourge HP x2.5, same
  # attack), not assumed to equal rich's HP x10 / attack x4 design.
  if is_wave and role=='wave_leader':
   for field in FIELDS:
    adjustments=[]
    for n in wave_groups:
     allrows=[r for r in observed if r.get('wave_number')==n and r.get('category') in ('wave','wave_normal','wave_leader')]
     low=normal_group(allrows)
     high=[r for r in allrows if low and r['stats']['health']>=min(o['stats']['health'] for o in low)*1.75]
     templates=wave_groups[n];leaders=[t for t in templates if t['member_role']=='wave_leader'];normal=[t for t in templates if t['member_role']=='normal']
     if low and high and leaders and normal and float(normal[0][field])>0:
      highs=[o['stats'][field] for o in high if o['stats'].get(field) is not None]
      lows=[o['stats'][field] for o in low if o['stats'].get(field) is not None]
      if not highs or not lows:continue
      measured=statistics.median(highs)/max(statistics.median(lows),1)
      adjustments.append(measured)
    if adjustments:
     normal=next((r for r in wave_groups[number] if r['member_role']=='normal' and r['archetype_id']==reference.get('archetype_id')),next(r for r in wave_groups[number] if r['member_role']=='normal'))
     predicted[field]=max(0 if field=='war3_armor' else 1,math.floor(float(normal[field])*factors[field]*statistics.median(adjustments)+.5))
  weights={'health':2,'attack':1,'war3_armor':.35}
  def distance(obs):return sum(weights[f]*abs(math.log(max(obs['stats'][f],1)/max(predicted[f],1))) for f in FIELDS if obs['stats'].get(f) is not None)
  best=min(selected,key=distance) if selected else None
  # Keep an unobserved model variant's expected differences. Do not paint a
  # sampled melee member over every unobserved ranged member in the same wave.
  def close_field(obs,field,tolerance):
   value=obs['stats'].get(field)
   resolution=obs.get('display_resolution',{}).get(field,1)
   return value is not None and abs(value-predicted[field])<=max(resolution,predicted[field]*tolerance)
  unique_normal=is_wave and role=='normal' and sum(r['member_role']=='normal' for r in wave_groups[number])==1 and number<=3 and (mode!='scourge' or best and best['stats']['health']<=predicted['health']*1.35)
  exact_pattern=best and close_field(best,'health',.015) and close_field(best,'attack',.02)
  accepted=best if best and (not is_wave or role=='assault_boss' or unique_normal or exact_pattern) else None
  values={};origins={}
  for field in FIELDS:
   field_match=accepted and accepted['stats'].get(field) is not None
   if field_match and is_wave and field=='war3_armor' and role!='assault_boss':
    field_match=unique_normal or close_field(accepted,field,.025)
   if field_match:
    values[field]=accepted['stats'][field]
    origins[field]={'method':'video_panel','record_id':accepted['record_id'],
      'explanation':'Stable selected-unit panel; maximum HP after slash. Existing same-wave model/role assignment is inferred separately.',
      'assignment':'nearest_existing_model_role_stat_pattern' if is_wave else 'selected_member_name',
      'display_resolution':accepted.get('display_resolution',{}).get(field,1)}
   else:
    if is_wave and role=='assault_boss' and field=='war3_armor':
     # The recordings often select a boss after armor reduction has begun.
     # Preserve its raw display in observations, and mark the clean baseline
     # rounded from the calibrated curve as an estimate, never a measurement.
     predicted[field]=math.ceil(predicted[field]/100)*100
    values[field]=predicted[field]
    origins[field]={'method':'existing_curve_calibrated_estimate' if is_wave else 'nonwave_cross_member_estimate',
      'explanation':('No stable selected panel for this model/role; scale the existing independently authored reference row using the median of visible mode panels.' if is_wave else 'Room/material member was not selected; estimate from the mode\'s observed rebirth/member scale. This cross-category assumption is not a video measurement.'),
      'input_value':numeric(input_row[field]),'factor':factors[field],'rounding_quantum':1,
      'reference_record_ids':references,'reference_table':(VARIANTS if 'variant_index' in reference and not reference.get('_synthetic') else WAVES) if is_wave else MEMBERS,
      'reference_difficulty_id':input_row['difficulty_id'],
      'reference_wave_number':number,'reference_batch_id':reference.get('batch_id'),
      'reference_variant_index':reference.get('variant_index') if not reference.get('_synthetic') else None,
      'reference_member_id':reference.get('member_id')}
    if accepted:origins[field]['reference_record_ids']=sorted(set(references+[accepted['record_id']]))
    if field=='war3_armor' and is_wave and role=='assault_boss':origins[field]['explanation']+=' Boss armor is rounded up to the next 100 because the selected panel may already be debuffed.'
    # Leader adjustment is also captured as a reproducible final multiplier.
    if float(input_row[field])>0:origins[field]['factor']=predicted[field]/float(input_row[field])
  count=sum(origin['method']=='video_panel' for origin in origins.values())
  status='video_observed' if count==3 else 'mixed' if count else 'estimated'
  if accepted:assignment.append({'record_id':accepted['record_id'],'mode_id':mode,'difficulty_id':difficulty,'category':category,
      'wave_number':number,'batch_id':reference.get('batch_id'),'member_id':reference.get('member_id'),'member_role':role})
  return values,origins,status

 def apply(row,values,origins,status,is_wave):
  row=dict(row);row.update({f:numeric(values[f]) for f in FIELDS})
  ids=sorted({v['record_id'] for v in origins.values() if 'record_id' in v})
  row.update(data_status=status,data_source=SOURCE,source_difficulty_id=row['difficulty_id'],
      derivation_notes='录像实测与缺项推算分开记录；物品/英雄切换混合帧已排除；原有模型、数量、技能与奖励规则保留。')
  prefix='rich_' if is_wave else ''
  row[prefix+'field_sources']=encode(origins);row[prefix+'stats_source']='video' if status=='video_observed' else status
  row[prefix+'stats_estimated' if is_wave else 'estimated']='0' if status=='video_observed' else '1'
  row[prefix+'source_record_id']='|'.join(ids);row[prefix+'estimation_method']='' if status=='video_observed' else 'explicit_reference_row_calibration'
  if is_wave:row['rich_difficulty_scaled']='0';row['rich_reference_wave']=row['wave_number']
  else:row['evidence_status']='面板确认' if status=='video_observed' else '缺失推算';row['source']=SOURCE
  return row

 new_waves=[];new_members=[];new_variants=[];rich_waves=[];rich_members=[];rich_variants=[]
 for mode,difficulty in pairs:
  for template in [r for r in waves if r['difficulty_id']==difficulty]:
   number=int(template['wave_number']);reference=ref_waves[(number,template['batch_id'])]
   values,origins,status=complete_stats(reference,mode,difficulty,'wave',number,template['member_role'])
   row=apply(template,values,origins,status,True)
   if mode=='rich':rich_waves.append(row)
   else:row['wave_id']=f"{mode}_{difficulty.lower()}_wave_{number:02d}_{template['batch_id'].lower()}";row['mode_id']=mode;new_waves.append(row)
  for template in [r for r in members if r['difficulty_id']==difficulty]:
   reference=ref_members[template['member_id']]
   values,origins,status=complete_stats(reference,mode,difficulty,'member')
   row=apply(template,values,origins,status,False)
   if mode=='rich':rich_members.append(row)
   else:row['profile_id']=f"{mode}_{difficulty.lower()}_{template['member_id']}";row['mode_id']=mode;new_members.append(row)
  selected_variants=list(ref_variants)
  for reference in selected_variants:
   number=int(reference['wave_number']);values,origins,status=complete_stats(reference,mode,difficulty,'wave',number,'normal')
   row=dict(reference,difficulty_id=difficulty,variant_id=f"{mode}_{difficulty.lower()}_w{number:02d}_{reference['batch_id']}_v{reference['variant_index']}")
   row.update({f:numeric(values[f]) for f in FIELDS});row.update(estimated='0' if status=='video_observed' else '1',stats_source='video' if status=='video_observed' else status,
     source_record_id='|'.join(sorted({o['record_id'] for o in origins.values() if 'record_id' in o})),estimation_method='' if status=='video_observed' else 'explicit_reference_row_calibration',
     field_sources=encode(origins),data_status=status,data_source=SOURCE,source_difficulty_id=difficulty,
     derivation_notes='同一批次内按序循环，不增加怪物；比例沿用既有1:1设计，并非录像数量实测。'+('天灾前3波沿用同模型普通/高属性形态；低档缺项按已见同模式低高档比例推算。' if reference.get('_synthetic') else ''))
   if mode=='rich':rich_variants.append(row)
   else:row['mode_id']=mode;new_variants.append(row)
 write(NEW_WAVES,new_waves,WAVES,True);write(NEW_MEMBERS,new_members,MEMBERS,True);write(NEW_VARIANTS,new_variants,VARIANTS,True)
 write(WAVES,[r for r in waves if r['difficulty_id']!='N4']+rich_waves)
 write(MEMBERS,[r for r in members if r['difficulty_id']!='N4']+rich_members)
 write(VARIANTS,[r for r in variants if r['difficulty_id']!='N4']+rich_variants)
 coverage=[]
 for mode,category,rows in [('rich','wave',rich_waves),('rich','member',rich_members),('rich','variant',rich_variants),('', 'wave',new_waves),('', 'member',new_members),('', 'variant',new_variants)]:
  for row in rows:coverage.append(dict(mode_id=mode or row['mode_id'],difficulty_id=row['difficulty_id'],category=category,
    wave_number=row.get('wave_number',''),batch_id=row.get('batch_id',''),member_id=row.get('member_id',''),member_role=row.get('member_role',''),
    health=row['health'],attack=row['attack'],war3_armor=row['war3_armor'],data_status=row['data_status'],
    source_record_id=row.get('rich_source_record_id') or row.get('source_record_id',''),field_sources=row.get('rich_field_sources') or row.get('field_sources')))
 target=ROOT/'docs/balance/mode_monster_coverage_20261020.csv'
 with target.open('w',encoding='utf8',newline='') as f:
  writer=csv.DictWriter(f,fieldnames=list(coverage[0]),lineterminator='\n');writer.writeheader();writer.writerows(coverage)
 audit={'calibration':{m+':'+d:v for (m,d),v in calibration.items()},'assignments':assignment,'counts':{'wave_rows':len(new_waves),'member_rows':len(new_members),'variant_rows':len(new_variants),'rich_n4_wave_rows':len(rich_waves),'rich_n4_member_rows':len(rich_members)}}
 audit_path=ROOT/'output/mode_monsters_20261020/table_build_audit.json'
 audit_path.parent.mkdir(parents=True,exist_ok=True)
 audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf8')
 print(json.dumps(audit['counts']))

if __name__=='__main__':main()
