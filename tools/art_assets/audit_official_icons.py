from pathlib import Path
import struct,re,csv,json,importlib.util
r=Path.cwd();vpk=r.parents[1]/'dota/pak01_dir.vpk'
def official_paths():
 with vpk.open('rb') as f:
  sig,ver,size=struct.unpack('<III',f.read(12));assert sig==0x55aa1234
  f.seek(28 if ver==2 else 12);data=f.read(size)
 i=0;paths=set()
 def z():
  nonlocal i
  j=data.index(0,i);s=data[i:j].decode();i=j+1;return s
 while (ext:=z()):
  while (folder:=z()):
   while (name:=z()):
    _,pre,_,_,_,_=struct.unpack_from('<IHHIIH',data,i);i+=18+pre
    paths.add((folder+'/' if folder!=' ' else '')+name+'.'+ext)
 return paths
paths=official_paths()
def valid(t,ability=False):
 return 'panorama/images/spellicons/'+t+'_png.vtex_c' in paths or (not ability and 'panorama/images/items/'+t.removeprefix('item_')+'_png.vtex_c' in paths)
result={'official_vpk':str(vpk),'missing':[],'hidden_without_icon':[],'counts':{}}
for p in (r/'scripts/npc').glob('*.txt'):
 if not ('abilities' in p.name or 'items' in p.name):continue
 s=p.read_text(encoding='utf8');tokens=re.findall(r'"[^"\n]*"|[{}]',re.sub(r'//[^\n]*','',s));depth=0;count=0
 for i,t in enumerate(tokens):
  if t=='{':
   depth+=1
   if depth==2:name=tokens[i-1].strip('"');start=i
  elif t=='}':
   if depth==2:
    b=tokens[start:i];tex=b[b.index('"AbilityTextureName"')+1].strip('"') if '"AbilityTextureName"' in b else ''
    if not tex and any('HIDDEN' in v for v in b):result['hidden_without_icon'].append(name)
    elif not valid(tex,'items' not in p.name):result['missing'].append({'id':name,'icon':tex,'file':p.name})
    count+=1
   depth-=1
 result['counts'][p.name]=count
for p in (r/'data/csv').rglob('*.csv'):
 if p.name not in ['hero_skill_definitions.csv','rogue_reward_rules.csv','item_definitions.csv','weapon_definitions.csv','research_lab_abilities.csv','technology_definitions.csv']:continue
 for row in csv.DictReader(p.open(encoding='utf-8-sig',newline='')):
  if str(next(iter(row.values()))).startswith('#'):continue
  for k,v in row.items():
   if k and 'icon' in k and v and not valid(v):result['missing'].append({'id':next(iter(row.values())),'icon':v,'file':p.name})
(r/'tools/art_assets/official_icon_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(result,ensure_ascii=False,indent=2));assert not result['missing']
