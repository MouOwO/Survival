import csv,json,hashlib
from pathlib import Path
from PIL import Image
root=Path.cwd(); here=root/'art/ui/development/archive_polish_v1'; tables=root/'data/csv/存档系统'
def rows(file):
 return [r for r in csv.DictReader(file.open(encoding='utf-8-sig',newline='')) if r and not next(iter(r.values()),'').startswith('#')]
base=tables/'archive_item_icons.csv'; old=base.read_text(encoding='utf-8-sig'); audit=[]
for spec in json.loads((here/'prompts.json').read_text(encoding='utf-8')):
 path=root/'panorama/src/images/custom_game/archive_polish_v1'/f"{spec['id']}.png"
 with Image.open(path) as im:
  assert im.mode=='RGBA' and im.width==im.height and im.getchannel('A').getextrema()==(0,255),path
  audit.append(dict(id=spec['id'],name=spec['name'],path=path.relative_to(root).as_posix(),width=im.width,height=im.height,alpha=list(im.getchannel('A').getextrema()),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
existing={(r['category_id'],r['item_id']) for r in rows(base)}; additions=[]
for category,file in [('clear','archive_achievements.csv'),('endless','archive_endless_achievements.csv'),('work','archive_work_items.csv')]:
 for r in rows(tables/file):
  if category=='clear' and r['category_id']!='clear':continue
  key='item_id' if category=='work' else 'achievement_id'; id=r[key]
  if (category,id) in existing:continue
  art='achievement_shared' if category!='work' else json.loads((here/'work_themes.json').read_text())[id]
  additions.append([f'polish_{category}_{id}_v1',category,id,r['display_name'],file,key,f'custom_game/archive_polish_v1/{art}.png',93,74,1,'generated_v1'])
import io
stream=io.StringIO(newline='');writer=csv.writer(stream,lineterminator='\n');writer.writerows(additions)
base.write_text(old.rstrip()+'\n'+stream.getvalue(),encoding='utf-8')
(here/'art_audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
print('Mapped',len(additions),'real entries;',len(audit),'unique generated images')
