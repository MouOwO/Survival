"""One-time preserve display rarity/category metadata from exact formal identities."""
from pathlib import Path
import json
import re
ROOT=Path(__file__).resolve().parents[2]
p=ROOT/'data/ui/item_resources.json'
data=json.loads(p.read_bytes());index={}
for row in data['items']:
    for key in [row['id'],*row['aliases']]:index[key]=row
for name in ['item_art_remaining_5d5c1152eb.js','icons_remaining_5d5c1152eb.js']:
    source=(ROOT/'design_refs/item_resources_20261016/baseline_generator/panorama/src/scripts/custom_game'/name).read_text(encoding='utf-8-sig')
    match=re.search(r'\bentries\s*=\s*',source)
    for old in json.JSONDecoder().raw_decode(source[match.end():])[0]:
        row=index.get(old['item_id'])
        if row:
            for field in ['quality','category_id']:
                if old.get(field):row[field]=old[field]
current=json.loads((ROOT/'server/bundles/current.json').read_bytes())['hash']
cfg=json.loads((ROOT/'server/bundles'/current/'bundle.json').read_bytes())['configs']
for old in cfg['lottery_item_definitions']['rows']:
    row=index.get(old['item_id'])
    if row and old.get('quality'):row['quality']=old['quality']
for row in data['items']:
    if row.get('category_id')=='endless':row['kind']='endless_emblem'
p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'items':len(data['items']),'quality':sum(bool(r.get('quality')) for r in data['items'])}))
