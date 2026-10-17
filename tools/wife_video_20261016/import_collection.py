"""Import manually reviewed local-video tooltips without replacing old rewards.

The user chose to display the two non-stat effects as pending adaptation,
excluded from drawing. No substitute gameplay field, card or skin is invented.
"""
from __future__ import annotations

import copy
import csv
import io
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from build_configs import build
from collection_rarity_config import ensure_collection_rarity, quality_for_index

REFERENCE = ROOT / 'data/reference/wife_tooltips_20261016.json'
CSV = ROOT / 'data/csv/存档系统'


def read(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return [{key: value or '' for key, value in row.items()} for row in csv.DictReader(stream)]


def ensure_availability_columns():
    path = CSV / 'archive_social_items.csv'
    raw = path.read_bytes()
    lines = raw.splitlines(keepends=True)
    header = lines[0].decode('utf-8-sig').strip()
    if header.endswith(',draw_enabled,availability_note'):
        return
    assert header == 'item_id,pool_id,display_name,max_owned,quality,description,effect_ids,effect_values,enabled'
    for index, line in enumerate(lines):
        if index == 0 or line.startswith(b'#types:'):
            suffix = b',draw_enabled,availability_note' if index == 0 else b',boolean,string'
            ending = b'\r\n' if line.endswith(b'\r\n') else b'\n'
            lines[index] = line.rstrip(b'\r\n') + suffix + ending
    # All existing data rows remain byte-for-byte unchanged. Their missing
    # optional cells mean the historical default (participates in drawing).
    path.write_bytes(b''.join(lines))


def append_verified(path, additions):
    original = path.read_bytes()
    rows = read(path)
    fields = list(rows[0])
    key = fields[0]
    index = {r[key]: r for r in rows}
    fresh = []
    for row in additions:
        assert set(row) == set(fields), (path.name, row[key])
        if row[key] in index:
            assert index[row[key]] == row, ('existing row differs', row[key])
        else:
            fresh.append(row)
    if fresh:
        text = io.StringIO(newline='')
        writer = csv.DictWriter(text, fields, lineterminator='\n')
        writer.writerows(fresh)
        path.write_bytes(original + (b'' if original.endswith(b'\n') else b'\n') + text.getvalue().encode())
    assert path.read_bytes().startswith(original), 'existing CSV bytes changed'


def main():
    reference = json.loads(REFERENCE.read_text(encoding='utf-8'))
    assert reference['user_rules']['special_policy'].startswith('两项保留原文')
    ensure_availability_columns()
    ensure_collection_rarity(CSV)
    source = read(CSV / 'archive_social_items.csv')
    templates = {r['item_id']: r for r in source}
    schema = {r['field_id'] for r in read(ROOT / 'data/csv/玩家档案系统/player_gameplay_stats.csv')}
    icons_path = ROOT / 'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js'
    script = icons_path.read_text(encoding='utf-8')
    start = script.index('entries=') + len('entries=')
    entries, length = json.JSONDecoder().raw_decode(script[start:])
    existing_icons = {r['item_id']: r for r in entries}
    icon_csv = {r['item_id']: r for r in read(CSV / 'archive_item_icons.csv')}
    wife_art_path = ROOT / 'data/ui/wife_portraits_v1.json'
    wife_art = json.loads(wife_art_path.read_text(encoding='utf-8'))['items'] if wife_art_path.exists() else {}
    added_items, added_icons, added_entries = [], [], []
    for item in reference['items']:
        special = 'special' in item
        if not special:
            assert item['field'] in schema, item['field']
        ident = f"wife_{item['index']:02}"
        source_id = f"ex_{item['index']:02}"
        row = dict(templates[source_id])
        quality = quality_for_index(item['index'])
        row.update(item_id=ident, pool_id='wife', display_name=item['name'], quality=quality,
                   description=item['tooltip'], effect_ids='' if special else item['field'],
                   effect_values='' if special else str(item['value']),
                   draw_enabled='0' if special else '',
                   availability_note='待适配，暂不参与抽取，不消耗玫瑰' if special else '')
        added_items.append(row)
        art = dict(icon_csv[source_id])
        art.update(icon_id='archive_' + ident + '_v1', item_id=ident, category_id='wife',
                   display_name=item['name'], art_status='reused_portrait_v3')
        if wife_art:
            portrait = wife_art[ident]
            assert portrait['id'] == ident and portrait['display_name'] == item['name']
            art.update(icon_path=portrait['icon_path'], art_status='generated_wife_portrait_v1')
        added_icons.append(art)
        entry = copy.deepcopy(existing_icons.get(ident, existing_icons[source_id]))
        entry.update(art)
        entry.update(display_width=96, display_height=96, description=item['tooltip'],
                     quality=quality, reused_from=source_id)
        if wife_art:
            for key in ('source_width','source_height','alpha_bounds','sha256','runtime_uri'):
                entry[key] = portrait[key]
            entry['small_runtime_uri'] = portrait['runtime_uri']
            entry.pop('reused_from', None)
        if ident in existing_icons:
            assert existing_icons[ident] == entry, ident
        else:
            added_entries.append(entry)
    append_verified(CSV / 'archive_social_items.csv', added_items)
    append_verified(CSV / 'archive_item_icons.csv', added_icons)
    build(CSV / 'archive_social_items.csv', ROOT / 'scripts/vscripts/config/generated/archive_social_items.lua')
    build(CSV / 'archive_social_rules.csv', ROOT / 'scripts/vscripts/config/generated/archive_social_rules.lua')
    if added_entries:
        entries.extend(added_entries)
        script = script[:start] + json.dumps(entries, ensure_ascii=False, separators=(',', ':')) + script[start+length:]
    script = script.replace("ex:'我的前女友',beast:", "ex:'我的前女友',wife:'我的老婆',beast:")
    script = script.replace("social=category==='friend'||category==='ex'||category==='beast';",
                            "social=category==='friend'||category==='ex'||category==='wife'||category==='beast';")
    if script != icons_path.read_text(encoding='utf-8'):
        icons_path.write_text(script, encoding='utf-8', newline='')
    print(json.dumps({'status':'IMPORTED', 'collection_items':len(added_items), 'numeric_items':sum('field' in i for i in reference['items']),
                      'special_items_pending':[i['index'] for i in reference['items'] if 'special' in i],
                      'portrait_manifest':'wife_portraits_v1' if wife_art else 'archive_portraits_v3',
                      'portrait_rows':len(added_items)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
