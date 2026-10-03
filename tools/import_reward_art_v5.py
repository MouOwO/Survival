"""Import independently generated reward art; leave item effects and costs unchanged."""
import csv, hashlib, json, re, shutil, struct, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=json.loads((ROOT/'data/ui/reward_art_v5_prompts.json').read_text(encoding='utf-8'))
raw=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
spec_by_id={r['id']:r for r in spec}
receipts=[{**spec_by_id[r['id']],**r} for r in raw]
expected={r['id'] for r in spec}
assert {r['id'] for r in receipts}==expected and len(receipts)==len(expected)
folder=ROOT/'panorama/src/images/custom_game/reward_art_v5'
folder.mkdir(parents=True,exist_ok=True)
template=(ROOT/'panorama/src/images/custom_game/archive_gpu_regular/head_v2_friend_01.vtex').read_text(encoding='utf-8')
assets={}
for row in receipts:
    if row.get('original_file'):
        source=Path(row['original_file'])
    else:
        match=re.search(r" as (C:\\[^\r\n]+?\.png) by default",row['output_hint'])
        assert match,'Missing generated path: '+row['id']
        source=Path(match.group(1))
    assert source.is_file() and 'generated_images' in source.parts
    blob=source.read_bytes();assert blob[:8]==b'\x89PNG\r\n\x1a\n'
    width,height=struct.unpack('>II',blob[16:24]);assert min(width,height)>=512
    identity=row['id'];shutil.copyfile(source,folder/(identity+'.png'))
    texture=template.replace('custom_game/archive_heads_v2/friend_01.png','custom_game/reward_art_v5/'+identity+'.png')
    if row['kind']=='pool':texture=texture.replace('"256"','"1024"')
    (folder/(identity+'.vtex')).write_text(texture,encoding='utf-8')
    assets[identity]={'id':identity,'name':row['name'],'kind':row['kind'],'icon_path':'custom_game/reward_art_v5/'+identity+'.png',
        'runtime_uri':'s2r://panorama/images/custom_game/reward_art_v5/'+identity+'.vtex','source_width':width,'source_height':height,
        'sha256':hashlib.sha256(blob).hexdigest(),'original_file':str(source),'generator':'built-in image_gen','prompt':row['prompt']}
p=next((ROOT/'data/csv').rglob('archive_item_icons.csv'))
with p.open(encoding='utf-8-sig',newline='') as f: reader=csv.DictReader(f);fields=reader.fieldnames;rows=list(reader)
updated=0
for row in rows:
    asset=assets.get(row.get('item_id'))
    if not asset:continue
    row.update(icon_path=asset['icon_path'],art_status='generated_reward_v5',display_width='84',display_height='84');updated+=1
with p.open('w',encoding='utf-8',newline='') as f: writer=csv.DictWriter(f,fields,lineterminator='\n');writer.writeheader();writer.writerows(rows)
for name in ['icons_remaining_5d5c1152eb.js','item_art_remaining_5d5c1152eb.js']:
    p=ROOT/'panorama/src/scripts/custom_game'/name;s=p.read_text(encoding='utf-8-sig');start=s.index('entries=')+len('entries=')
    entries,consumed=json.JSONDecoder().raw_decode(s[start:]);found=set()
    for row in entries:
        asset=assets.get(row.get('item_id'))
        if not asset:continue
        found.add(asset['id']);row.update({k:asset[k] for k in ['icon_path','runtime_uri','source_width','source_height','sha256']})
        row.update(small_runtime_uri=asset['runtime_uri'],display_width=84,display_height=84,art_status='generated_reward_v5')
        for key in ['portrait','tint_icon','tone_color','alpha_bounds']:row.pop(key,None)
    # Item presentation also includes any reward which is not listed as an archive card.
    if name.startswith('item_art'):
        for identity,asset in assets.items():
            if asset['kind']=='pool' or identity in found:continue
            entries.append(dict(asset,item_id=identity,display_name=asset['name'],content_id=identity,category_id='points',display_width=84,display_height=84,art_status='generated_reward_v5'))
    p.write_text(s[:start]+json.dumps(entries,ensure_ascii=False,separators=(',',':'))+s[start+consumed:],encoding='utf-8')
(ROOT/'data/ui/reward_art_v5.json').write_text(json.dumps(assets,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'assets':len(assets),'archive_mappings':updated,'item_art_entries':len(entries)},ensure_ascii=False))
