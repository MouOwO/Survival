"""Read-only independent resource-table coverage audit; writes evidence only."""
from pathlib import Path
import csv
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/item_resources_20261016/audit'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def rows(rel):
    with (ROOT / rel).open(encoding='utf-8-sig', newline='') as handle:
        return [row for row in csv.DictReader(handle)
                if row and not str(next(iter(row.values()), '')).startswith('#')
                and row.get('enabled', '1') not in {'0', 'false'}]

def js_array(rel, token):
    text = (ROOT / rel).read_text(encoding='utf-8-sig')
    at = text.index(token) + len(token)
    return json.JSONDecoder().raw_decode(text[at:])[0]

def main():
    master = ROOT / 'data/ui/item_resources.json'
    document = json.loads(master.read_text(encoding='utf-8-sig'))
    items = document['items']
    index, collisions = {}, []
    for row in items:
        for key in [row['id']] + row.get('aliases', []):
            if key in index and index[key]['id'] != row['id']:
                collisions.append({'alias': key, 'first': index[key]['id'], 'second': row['id']})
            index[key] = row

    archive = 'data/csv/存档系统/'
    configs = {
        'commerce': ('data/csv/商城兑换系统/commerce_products.csv', 'sku'),
        'lottery': ('data/csv/抽奖系统/lottery_item_definitions.csv', 'item_id'),
        'content_catalog': ('data/csv/物品系统/content_catalog.csv', 'content_id'),
        'shop_entries': ('data/csv/商店系统/shop_entries.csv', 'shop_entry_id'),
        'item_definitions': ('data/csv/物品系统/item_definitions.csv', 'content_id'),
        'weapon_definitions': ('data/csv/物品系统/weapon_definitions.csv', 'content_id'),
        'treasure_rogue_cards': ('data/csv/肉鸽奖励系统/rogue_reward_cards.csv', 'card_id'),
        'shadow': (archive + 'archive_shadow_items.csv', 'item_id'),
        'clear': (archive + 'archive_achievements.csv', 'achievement_id'),
        'cage': (archive + 'archive_cage_items.csv', 'item_id'),
        'work': (archive + 'archive_work_items.csv', 'item_id'),
        'welfare': (archive + 'archive_welfare_rewards.csv', 'achievement_id'),
        'building': (archive + 'archive_building_items.csv', 'item_id'),
        'fishing': (archive + 'archive_fishing_items.csv', 'reward_id'),
        'social': (archive + 'archive_social_items.csv', 'item_id'),
        'fragment': (archive + 'archive_fragment_definitions.csv', 'fragment_id'),
        'map_level': (archive + 'archive_map_levels.csv', 'level_id'),
        'endless': (archive + 'archive_endless_achievements.csv', 'achievement_id'),
        'boss': (archive + 'archive_boss_achievements.csv', 'achievement_id'),
        'daily': (archive + 'archive_daily_items.csv', 'item_id'),
        'starjoy': (archive + 'archive_starjoy_levels.csv', 'tier_id'),
        'vip': (archive + 'archive_vip_rewards.csv', 'reward_id'),
        'title': (archive + 'archive_titles.csv', 'title_id'),
    }
    old_art = js_array('panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js', 'entries=')
    old_icons = rows(archive + 'archive_item_icons.csv')
    old_index = {}
    for row in old_art + old_icons:
        old_index.setdefault(row['item_id'], row)
    coverage = {}
    for category, (file, field) in configs.items():
        definitions = rows(file)
        missing = []
        for row in definitions:
            key = row[field]
            if key in index:
                continue
            candidate = old_index.get(key, {})
            # These are exact same-ID sources; no fuzzy names or URI-inferred aliases.
            current = candidate.get('runtime_uri') or candidate.get('icon_path') or row.get('icon') or row.get('icon_name')
            missing.append({'id': key, 'name': row.get('display_name') or row.get('name'),
                            'current_icon_candidate': current,
                            'exact_candidate_source': 'existing_same_id_icon' if candidate else 'formal_row',
                            'content_id': row.get('content_id'), 'ownership_id': row.get('ownership_id')})
        coverage[category] = {'file': file, 'id_field': field, 'total': len(definitions),
                              'covered': len(definitions) - len(missing), 'missing': missing}

    art_manifest = json.loads((ROOT / 'data/ui/commerce_product_art_v1.json').read_text(encoding='utf-8-sig'))
    products = rows('data/csv/商城兑换系统/commerce_products.csv')
    products_by_sku = {row['sku']: row for row in products}
    explicit_aliases = []
    for row in art_manifest['products']:
        formal = products_by_sku.get(row['sku'], {})
        explicit_aliases.append({'sku': row['sku'], 'business_ownership_id': formal.get('ownership_id'),
                                 'resource_id': row['item_id'], 'uri': row['runtime_uri'],
                                 'identity_rule': 'presentation_alias_only_do_not_merge_inventory'})
    targets = {key: index.get(key) for key in ['video_p042', 'commerce_p042', 'lottery_muramasa',
                                               'video_p151', 'commerce_p151', 'commerce_spirit_katana']}
    critical = {
        'P042_alias_present': all(targets[k] for k in ['video_p042', 'commerce_p042', 'lottery_muramasa']),
        'P042_shared_art': len({targets[k]['uri'] for k in ['video_p042', 'commerce_p042', 'lottery_muramasa'] if targets[k]}) == 1,
        'P151_alias_present': all(targets[k] for k in ['video_p151', 'commerce_p151', 'commerce_spirit_katana']),
        'P151_shared_art': len({targets[k]['uri'] for k in ['video_p151', 'commerce_p151', 'commerce_spirit_katana'] if targets[k]}) == 1,
        'P042_P151_different': bool(targets['lottery_muramasa'] and targets['commerce_spirit_katana'] and targets['lottery_muramasa']['uri'] != targets['commerce_spirit_katana']['uri']),
        'no_alias_collision': not collisions,
    }
    local_assets, native_assets, missing_assets = 0, 0, []
    for row in items:
        uri = row['uri']
        if uri.startswith('s2r://'):
            resource = ROOT / (uri[len('s2r://'):] + '_c')
        elif uri.startswith('file://{images}/custom_game/'):
            resource = ROOT / 'panorama/src/images' / uri[len('file://{images}/'):]
        else:
            native_assets += 1
            continue
        if resource.is_file():
            local_assets += 1
        else:
            missing_assets.append({'id': row['id'], 'uri': uri})
    critical['all_local_assets_exist'] = not missing_assets
    critical['all_formal_ids_covered'] = all(not group['missing'] for group in coverage.values())
    result = {'status': 'PASS' if all(critical.values()) else 'FAIL',
              'master': 'data/ui/item_resources.json', 'master_sha256': sha(master),
              'resource_count': len(items), 'addressable_keys': len(index), 'alias_collisions': collisions,
              'critical': critical, 'critical_targets': targets, 'coverage': coverage,
              'asset_existence': {'local_present': local_assets, 'native_vpk_or_game': native_assets,
                                  'missing_local_assets': missing_assets},
              'explicit_commerce_presentation_aliases': explicit_aliases,
              'notes': ['P042 and lottery_muramasa share art but retain distinct formal ownership markers.',
                        'P151 remains commerce_spirit_katana despite the old commerce CSV borrowing the Muramasa icon.',
                        'Coverage reports exact formal IDs only; shop wrapper rows may resolve through their explicit content_id.',
                        'This tool never writes production data or player saves.']}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'resource_coverage.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': result['status'], 'resources': len(items), 'addressable_keys': len(index),
                      'critical': critical, 'coverage': {k: [v['covered'], v['total']] for k, v in coverage.items()}}, ensure_ascii=False))

if __name__ == '__main__':
    main()
