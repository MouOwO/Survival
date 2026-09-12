"""Build a resumable art-only worklist from enabled project configuration."""
import csv
import json
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / 'data/csv'
OUT = ROOT / 'art/ui/development/remaining_ui_handoff_v1/bulk_art'

def rows(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        return [r for r in csv.DictReader(f) if not next(iter(r.values()), '').startswith('#') and r.get('enabled', '1') == '1']

def main():
    result = []
    sources = [
        ('points', '抽奖系统/lottery_item_definitions.csv', 'item_id'),
        ('points', '存档系统/archive_daily_items.csv', 'item_id'),
        ('fragment', '存档系统/archive_fragment_definitions.csv', 'fragment_id'),
        ('pet', '存档系统/archive_cage_items.csv', 'item_id'),
        ('social', '存档系统/archive_social_items.csv', 'item_id'),
        ('fishing', '存档系统/archive_fishing_items.csv', 'reward_id'),
        ('building', '存档系统/archive_building_items.csv', 'item_id'),
        ('shop', '商店系统/shop_entries.csv', 'shop_entry_id'),
    ]
    for category, source, key in sources:
        for row in rows(CSV / source):
            if category == 'shop' and row['server_action'] != 'grant_content':
                continue  # Challenge and rebirth controls are not purchasable item art.
            actual = row['pool_id'] if category == 'social' else category
            item_id = row[key]
            result.append(dict(category_id=actual, item_id=item_id, display_name=row['display_name'],
                source_table='../'+source, source_key=key, content_id=row.get('content_id', ''),
                description=row.get('description') or row.get('source_method') or row.get('notes', ''),
                quality=row.get('quality', ''), icon_path='custom_game/archive_items_v2/'+item_id+'.png',
                display_width=93, display_height=74, status='pending'))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'worklist.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'total':len(result), 'categories':dict(Counter(x['category_id'] for x in result)),
                      'names':{c:[x['display_name'] for x in result if x['category_id']==c] for c in dict(Counter(x['category_id'] for x in result))}}, ensure_ascii=False))

if __name__ == '__main__':
    main()
