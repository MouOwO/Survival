"""Validate UI-only archive mappings against real item tables; never write rewards."""
import csv
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TABLES = ROOT / 'data/csv/存档系统'

def rows(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return [row for row in csv.DictReader(stream) if not next(iter(row.values()), '').startswith('#')]

def read_icons():
    result, seen = [], set()
    presentation_file = TABLES / 'archive_icon_presentation.csv'
    presentation = {(r['category_id'],r['item_id']):r for r in rows(presentation_file)} if presentation_file.exists() else {}
    for row in rows(TABLES / 'archive_item_icons.csv'):
        if row['enabled'] != '1':
            continue
        key = (row['category_id'], row['item_id'])
        if key in seen:
            raise ValueError(f'Duplicate archive icon mapping: {key}')
        seen.add(key)
        source = (TABLES / row['source_table']).resolve()
        if not source.is_relative_to((ROOT / 'data/csv').resolve()) or source.suffix != '.csv':
            raise ValueError('Source table must remain inside project CSV configuration')
        source_key = row.get('source_key') or 'item_id'
        if source_key not in ('item_id', 'fragment_id', 'reward_id', 'shop_entry_id', 'achievement_id', 'level_id'):
            raise ValueError('Unsupported item identity column')
        original = next((entry for entry in rows(source) if entry.get(source_key) == row['item_id']), None)
        if not original or original['display_name'] != row['display_name']:
            raise ValueError(f'Item missing or display name differs from real configuration: {key}')
        image_root = ROOT / 'panorama/src/images'
        file = (image_root / row['icon_path']).resolve()
        if not file.is_relative_to(image_root.resolve()):
            raise ValueError('Icon path escapes project images')
        with Image.open(file) as im:
            if im.mode != 'RGBA' or im.getchannel('A').getextrema() != (0, 255):
                raise ValueError(f'Icon requires real alpha and an opaque subject: {file}')
            if im.width != im.height:
                raise ValueError(f'Use a square icon canvas: {file}')
            bounds = im.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
            row.update(source_width=im.width, source_height=im.height, alpha_bounds=bounds)
        for field in ['display_width', 'display_height']:
            row[field] = int(row[field])
            if not 16 <= row[field] <= 256:
                raise ValueError('Invalid design dimensions')
        row.update(description=original.get('description') or original.get('source_method') or original.get('notes', ''),
                   quality=original.get('quality', ''), content_id=original.get('content_id', ''),
                   sha256=hashlib.sha256(file.read_bytes()).hexdigest())
        visual=presentation.get(key)
        if visual:
            import re
            color=visual['color']
            if color and not re.fullmatch(r'#[0-9a-fA-F]{6}',color):raise ValueError('Invalid UI color')
            row.update(tone=visual['tone'],tone_color=color,tint_icon=visual['tint_icon']=='1')
            if visual['portrait_width']:
                x,y,w=[float(visual[k]) for k in ('portrait_x','portrait_y','portrait_width')]
                h=w*row['display_height']/row['display_width']
                if not (0<=x<1 and 0<=y<1 and .3<=w<=1 and x+w<=1 and y+h<=1):raise ValueError('Portrait viewport outside master')
                row['portrait']=[x,y,w,h]
        result.append(row)
    return result

if __name__ == '__main__':
    print(json.dumps(read_icons(), ensure_ascii=True))
