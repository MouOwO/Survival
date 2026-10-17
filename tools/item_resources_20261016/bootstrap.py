"""One-time migration from captured presentation tables into the maintained registry.

This is not the normal build. It refuses to overwrite an existing authority.
Normal generation reads only data/ui/item_resources.json.
"""
from pathlib import Path
import csv
import hashlib
import io
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/item_resources_20261016'
TARGET = ROOT / 'data/ui/item_resources.json'


def extract(file, pattern):
    text = (ROOT / file).read_text(encoding='utf-8-sig')
    match = re.search(pattern, text)
    assert match, 'missing_source:' + file
    return json.JSONDecoder().raw_decode(text[match.end():])[0]


def csv_rows(file):
    return [r for r in csv.DictReader(io.StringIO((ROOT / file).read_text(encoding='utf-8-sig')))
            if not str(next(iter(r.values()), '')).startswith('#')]


def main():
    assert not TARGET.exists(), 'authority_already_exists_use_build_item_resources'
    OUT.mkdir(parents=True, exist_ok=True)
    entries, priorities, decisions = {}, {}, []

    def put(identity, uri, name='', priority=0, aliases=(), **extra):
        assert identity and isinstance(uri, str), identity
        if not uri.startswith(('file://', 's2r://')):
            uri = 'file://{images}/' + uri
        old = entries.get(identity)
        if old and priorities[identity] > priority:
            return
        if old and old['uri'] != uri:
            decisions.append({'id': identity, 'previous': old['uri'], 'selected': uri})
        merged = set(aliases) | set(old.get('aliases', []) if old else [])
        merged.discard(identity)
        entries[identity] = {'id': identity, 'name': name or (old or {}).get('name', identity),
            'kind': extra.pop('kind', 'image'), 'uri': uri, 'aliases': sorted(merged), **extra}
        priorities[identity] = priority

    native = extract('panorama/src/scripts/custom_game/native_ui_icons.js', r'\bvar icons\s*=\s*')
    for identity, row in native.items():
        put(identity, row['uri'], priority=30, aliases=['shop_' + identity],
            native_type=row['type'], native_name=row['name'])
    art = extract('panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js', r'\bentries\s*=\s*')
    for row in art:
        put(row['item_id'], row.get('runtime_uri') or row['icon_path'], row.get('display_name', ''),
            priority=60 if row['item_id'].startswith('lottery_') else 20,
            aliases=[row['content_id']] if row.get('content_id') else [])
    bindings = json.loads((ROOT / 'data/ui/archive_v10_icon_bindings.json').read_bytes())['bindings']
    for row in bindings:
        # Dedicated reward art already superseded the old archive-only native copies.
        if row['category'] == 'points' and row['id'] in entries:
            continue
        put(row['id'], row['uri'], row['name'], priority=50, source_size=row['source_size'])
    v10 = extract('panorama/src/scripts/custom_game/archive_v10_data.js', r'ArchiveV10Data\s*=\s*')
    for identity, info in v10.get('shadow_icons', {}).items():
        uri = info.get('file') or info.get('uri') if isinstance(info, dict) else info
        if uri:
            put(identity, uri, priority=90)
    # The latest collection revision uses full-resolution transparent portraits.
    for identity in list(entries):
        if re.fullmatch(r'(?:friend|ex|wife)_\d+', identity):
            path = ROOT / 'panorama/src/images/custom_game/compact_portraits_v5' / (identity + '.png')
            if path.is_file():
                put(identity, 'file://{images}/custom_game/compact_portraits_v5/' + identity + '.png',
                    priority=95)
    current = json.loads((ROOT / 'server/bundles/current.json').read_bytes())['hash']
    configs = json.loads((ROOT / 'server/bundles' / current / 'bundle.json').read_bytes())['configs']
    products = {r['sku']: r for r in configs['commerce_catalog']['rows']}
    cash = json.loads((ROOT / 'design_refs/shop_functional_20261016/release_v2/payment_catalog.json').read_bytes())['products']
    products.update({r['sku']: r for r in cash if r['sku'] not in products})
    manifest = json.loads((ROOT / 'data/ui/commerce_product_art_v1.json').read_bytes())
    for row in manifest['products']:
        sku = row['sku']
        product = products[sku]
        marker = product['item_id']
        identity = row['item_id'] if row['item_id'].startswith('lottery_') else marker
        if sku.startswith('video_bundle_vip_'):
            identity = 'vip_package_' + sku[-2:]
        aliases = {sku, marker}
        if product.get('source_id'):
            aliases.add(product['source_id'])
        # SKU is explicit. Never infer identity from a borrowed historical icon.
        put(identity, row['runtime_uri'], row['name'], priority=100, aliases=aliases)
    for row in configs['archive_starjoy_levels']['rows']:
        put(row['tier_id'], 'file://{images}/custom_game/starjoy_v1/starjoy.png', row['display_name'], priority=100)
    for row in configs['archive_vip_rewards']['rows']:
        if not row.get('enabled'):
            continue
        if row['reward_id'] == 'vip_little_jacket':
            put(row['reward_id'], 'file://{images}/custom_game/commerce_jade_v1/gift_light.png',
                row['display_name'], priority=110)
        else:
            put(row['reward_id'], 'file://{images}/custom_game/topnav_reference_v2/vip.svg',
                row['display_name'], priority=110, kind='vip', vip_level=row['level'])
    # Formal aliases are resource aliases only; inventory markers remain unchanged.
    for alias, identity in {'challenge_synthesis_gem': 'material_synthesis_gem',
        'lottery_flame_crystal': 'lottery_nature_crystal', 'lottery_burst_crystal': 'lottery_bombardment_crystal'}.items():
        if identity in entries:
            entries[identity]['aliases'] = sorted(set(entries[identity]['aliases']) | {alias})
            entries.pop(alias, None)
    for identity, row in entries.items():
        row['aliases'] = [alias for alias in row['aliases'] if alias not in entries]
    registry = {'schema_version': 1,
        'scope': 'Single maintained item presentation authority. Aliases select artwork only and never change ownership, price, effects, rewards or quantities.',
        'items': sorted(entries.values(), key=lambda row: row['id'])}
    TARGET.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (OUT / 'bootstrap.json').write_text(json.dumps({'status': 'MIGRATED', 'items': len(entries),
        'native': len(native), 'previous_item_art': len(art), 'commerce': len(manifest['products']),
        'authority_sha256': hashlib.sha256(TARGET.read_bytes()).hexdigest(), 'replaced_conflicts': decisions},
        ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'MIGRATED', 'items': len(entries), 'commerce': len(manifest['products'])}))


if __name__ == '__main__':
    main()
