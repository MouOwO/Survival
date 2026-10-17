"""One-time exact-ID completion of the new resource authority; no business data writes."""
from pathlib import Path
import json
import re

from audit_resources import ROOT, OUT, rows, js_array, sha


def main():
    path = ROOT / 'data/ui/item_resources.json'
    document = json.loads(path.read_text(encoding='utf-8-sig'))
    items = document['items']
    index = {key: row for row in items for key in [row['id']] + row.get('aliases', [])}
    additions, aliases = [], []

    def add(key, name, uri, kind='image', **metadata):
        if key in index:
            return index[key]
        row = dict(id=key, name=name, kind=kind, uri=uri, aliases=[], **metadata)
        items.append(row)
        index[key] = row
        additions.append({'id': key, 'uri': uri, 'kind': kind})
        return row

    def alias(key, target):
        if key in index:
            assert index[key] is index[target], (key, target)
            return
        index[target].setdefault('aliases', []).append(key)
        index[key] = index[target]
        aliases.append({'alias': key, 'target': target})

    for sku, semantic in [
        ('video_p151', 'commerce_spirit_katana'),
        ('video_p016', 'commerce_titan_shield'),
        ('video_p028', 'commerce_master_foreman'),
        ('video_p147', 'commerce_lament_seed'),
        ('video_p110', 'commerce_swift_winch'),
        ('video_p001', 'special_lottery_ticket'),
    ]:
        alias(semantic, sku)

    # Legacy renderer has forty wife rows that the old item-art list omitted.
    for row in js_array('panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js', 'entries='):
        if row['item_id'] not in index:
            uri = row.get('runtime_uri') or 'file://{images}/' + row['icon_path']
            add(row['item_id'], row['display_name'], uri,
                category=row.get('category_id'), quality=str(row.get('quality', '')).lower(),
                source='icons_remaining_same_id', original_uri='file://{images}/' + row['icon_path'])

    # The server's existing welfare renderer supplies icon_style=seal, mapped to this art.
    for row in rows('data/csv/存档系统/archive_welfare_rewards.csv'):
        add(row['achievement_id'], row['display_name'],
            'file://{images}/custom_game/archive_handoff_v1/art_01.png',
            category='gift', source='archive_welfare_rewards.rows seal -> handoff art_01')

    # These banners use an existing layered renderer. A static URI is metadata only.
    for row in rows('data/csv/存档系统/archive_titles.csv'):
        add(row['title_id'], row['display_name'], row['icon'], kind='layered_title',
            category='titles', source='archive_titles.csv')

    catalog = {row['content_id']: row for row in rows('data/csv/物品系统/content_catalog.csv')}
    for key, row in catalog.items():
        if key not in index and row.get('icon', '').startswith('item_'):
            icon = row['icon'][5:]
            add(key, row['name'], 'file://{images}/items/' + icon + '.png',
                native_type='item', native_name=icon, source='content_catalog.csv exact content_id')

    # Building unit_name is the exact content_catalog ID; texture comes from its formal build ability.
    abilities = (ROOT / 'scripts/npc/npc_abilities_custom.txt').read_text(encoding='utf-8-sig')
    for row in rows('data/csv/建筑与工人系统/building_definitions.csv'):
        key = row['unit_name']
        if key in index or key not in catalog:
            continue
        match = re.search(r'"' + re.escape(row['builder_ability']) + r'"\s*\{([^{}]*)\}', abilities)
        assert match, key
        texture = re.search(r'"AbilityTextureName"\s*"([^"]+)"', match[1])
        assert texture, key
        add(key, row['name'], 'file://{images}/spellicons/' + texture[1] + '.png',
            native_type='ability', native_name=texture[1],
            source='building_definitions.unit_name -> builder_ability -> AbilityTextureName')

    # The existing lottery header/draw-button art uses this ticket. IDs remain separate currencies.
    add('lottery_ticket', catalog['lottery_ticket']['name'],
        's2r://panorama/images/custom_game/lottery_handoff_v1/ticket_illustrated_png.vtex',
        source='lottery_handoff_bb9968eef7.css current LHTicket and LHDrawTicket')

    for row in items:
        row['aliases'] = sorted(set(row.get('aliases', [])))
    document['items'] = sorted(items, key=lambda row: row['id'])
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    OUT.mkdir(parents=True, exist_ok=True)
    evidence = {'added_resource_count': len(additions), 'added_alias_count': len(aliases),
                'final_resource_count': len(items), 'final_sha256': sha(path),
                'additions': additions, 'aliases': aliases,
                'notes': ['Only data/ui/item_resources.json changed in production sources.',
                          'All aliases are presentation-only; no ownership or gameplay changes.',
                          'Layered titles deliberately retain their original renderer.']}
    (OUT / 'master_completion.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: evidence[key] for key in ['added_resource_count', 'added_alias_count', 'final_resource_count', 'final_sha256']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
