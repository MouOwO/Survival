"""Install individually generated portrait masters and explicit 256px game textures.
No reward IDs or gameplay data are modified. Input: built-in imagegen receipts JSON.
"""
import csv, hashlib, json, re, shutil, struct, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
receipts=json.loads(Path(sys.argv[1]).read_text(encoding='utf8'))
expected={f'{group}_{i:02}' for group in ('friend','ex') for i in range(1,41)}
assert len(receipts)==80 and {r['id'] for r in receipts}==expected, 'Require all 80 distinct character receipts'
masters=ROOT/'panorama/src/images/custom_game/archive_portraits_v3'
textures=ROOT/'panorama/src/images/custom_game/archive_gpu_regular'
masters.mkdir(parents=True,exist_ok=True)
template=(textures/'head_v2_friend_01.vtex').read_text(encoding='utf8')
results={}
for row in receipts:
    identity=row['id']
    match=re.search(r' as (C:\\[^\r\n]+?\.png) by default',row['output_hint'])
    assert match, 'Missing built-in image path for '+identity
    source=Path(match.group(1))
    assert source.is_file() and 'generated_images' in source.parts
    blob=source.read_bytes(); assert blob[:8]==b'\x89PNG\r\n\x1a\n', identity
    width,height=struct.unpack('>II',blob[16:24])
    assert min(width,height)>=512, 'Master too small: '+identity
    target=masters/(identity+'.png');shutil.copyfile(source,target)
    texture=template.replace('custom_game/archive_heads_v2/friend_01.png','custom_game/archive_portraits_v3/'+identity+'.png')
    (textures/('head_v3_'+identity+'.vtex')).write_text(texture,encoding='utf8')
    results[identity]={'id':identity,'icon_path':'custom_game/archive_portraits_v3/'+identity+'.png',
        'runtime_uri':'s2r://panorama/images/custom_game/archive_gpu_regular/head_v3_'+identity+'.vtex',
        'source_width':width,'source_height':height,'sha256':hashlib.sha256(blob).hexdigest(),
        'prompt':row['prompt'],'generator':'built-in image_gen','original_file':str(source)}
# Update only visual rows, keeping the original identity/name and effect mappings.
path=next((ROOT/'data/csv').rglob('archive_item_icons.csv'))
with path.open(encoding='utf-8-sig',newline='') as stream:
    reader=csv.DictReader(stream);fields=reader.fieldnames;rows=list(reader)
for row in rows:
    new=results.get(row.get('item_id'))
    if not new:continue
    row.update(icon_id='archive_'+new['id']+'_v3',icon_path=new['icon_path'],display_width='96',display_height='96',art_status='generated_portrait_v3')
with path.open('w',encoding='utf8',newline='') as stream:
    writer=csv.DictWriter(stream,fields,lineterminator='\n');writer.writeheader();writer.writerows(rows)
# This production wrapper contains the active catalog; do not rebuild unrelated art.
path=ROOT/'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js'
source=path.read_text(encoding='utf8');start=source.index('entries=')+len('entries=')
entries,consumed=json.JSONDecoder().raw_decode(source[start:]);updated=0
artifacts=json.loads((ROOT/'data/ui/archive_artifact_icons.json').read_text(encoding='utf8'))
for row in entries:
    identity=row.get('item_id');new=results.get(identity)
    if new:
        row.update({k:new[k] for k in ('icon_path','runtime_uri','source_width','source_height','sha256')})
        row.update(small_runtime_uri=new['runtime_uri'],display_width=96,display_height=96,art_status='generated_portrait_v3')
        row.pop('portrait',None);updated+=1
    elif identity in artifacts:
        row.update(artifacts[identity]);row.update(art_status='valve_shop',display_width=168,display_height=122)
assert updated==80
path.write_text(source[:start]+json.dumps(entries,ensure_ascii=False,separators=(',',':'))+source[start+consumed:],encoding='utf8')
(ROOT/'data/ui/archive_portraits_v3.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('ARCHIVE_PORTRAITS_V3_IMPORTED: 80 untouched masters, 80 separate 256px BGRA textures, 80 identity mappings; official artifacts retained')
