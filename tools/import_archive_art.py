"""Register completed generated artwork; never modify gameplay source tables.

Generated master PNGs are kept byte-identical. Each result has a per-item receipt.
The worklist is independent of the enabled runtime mapping, allowing safe resume.
"""
import csv
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BULK = ROOT / 'art/ui/development/remaining_ui_handoff_v1/bulk_art'
TABLE = ROOT / 'data/csv/存档系统/archive_item_icons.csv'

def main():
    with TABLE.open(encoding='utf-8-sig', newline='') as f:
        old = [r for r in csv.DictReader(f) if not next(iter(r.values()), '').startswith('#')]
    lookup = {(r['category_id'],r['item_id']):r for r in old}
    for row in lookup.values():
        if row.get('art_status') == 'trial':
            row['art_status'] = 'approved'
    work = json.loads((BULK/'prompts.json').read_text(encoding='utf-8'))
    for item in work:
        file = ROOT / 'panorama/src/images' / item['icon_path']
        if not file.exists():
            continue
        with Image.open(file) as im:
            if im.mode != 'RGBA' or im.getchannel('A').getextrema() != (0,255) or im.width != im.height:
                raise ValueError('Invalid transparent square artwork: '+str(file))
        # Resume adds missing rows only. A later hand-edited path, enabled flag,
        # display size or approval status belongs to the user's mapping table.
        if (item['category_id'],item['item_id']) in lookup:
            continue
        lookup[(item['category_id'],item['item_id'])] = dict(
            icon_id='archive_'+item['item_id']+'_v2', category_id=item['category_id'], item_id=item['item_id'],
            display_name=item['display_name'], source_table=item['source_table'], source_key=item['source_key'],
            icon_path=item['icon_path'], display_width=93,display_height=74,enabled=1,art_status='generated_review')
    fields=['icon_id','category_id','item_id','display_name','source_table','source_key','icon_path','display_width','display_height','enabled','art_status']
    with TABLE.open('w', encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fields,lineterminator='\n');writer.writeheader()
        writer.writerow(dict(zip(fields,['#中文表头:图标ID','分类ID','真实道具ID','名称','来源定义表','主键列','相对images资源路径','显示宽度','显示高度','启用','美术状态'])))
        writer.writerow(dict(zip(fields,['#types:string','string','string','string','string','string','string','number','number','boolean','string'])))
        for row in lookup.values():
            row['source_key']=row.get('source_key') or 'item_id'
            writer.writerow(row)
    status=[]
    for item in work:
        file=ROOT / 'panorama/src/images' / item['icon_path']
        status.append(dict(item_id=item['item_id'],category_id=item['category_id'],name=item['display_name'],
                           status='generated' if file.exists() else 'pending',path=item['icon_path']))
    (BULK/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(registered=len(lookup),generated=sum(x['status']=='generated' for x in status),total=len(status))))

if __name__ == '__main__': main()
