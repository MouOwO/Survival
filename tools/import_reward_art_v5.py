"""Import reviewed reward PNGs, then update the single item-resource authority.

reward_art_v5.json remains an import receipt. Runtime views are generated only
from data/ui/item_resources.json; no legacy entries arrays are rewritten.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import struct

import build_item_resources

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'data/ui/item_resources.json'


def update_item_resources(root, assets, check=False):
    """Receipts carry explicit reward IDs; never infer identity from a URI/name."""
    document, resources, aliases = build_item_resources.load(root)
    changed = 0
    for identity, asset in assets.items():
        if asset['kind'] == 'pool':
            continue
        if not re.fullmatch(r'[A-Za-z0-9_-]+', identity):
            raise ValueError('Invalid reward resource ID: ' + identity)
        target = aliases.get(identity)
        if target is None:
            row = dict(id=identity, name=asset['name'], kind='image',
                       uri=asset['runtime_uri'], aliases=[])
            document['items'].append(row)
            resources[identity] = row
            aliases[identity] = identity
            changed += 1
        else:
            row = resources[target]
            if row['kind'] != 'image':
                raise ValueError('Reward art cannot replace specialized renderer: ' + identity)
            if row['uri'] != asset['runtime_uri']:
                row['uri'] = asset['runtime_uri']
                changed += 1
    if changed:
        if check:
            raise ValueError('Imported reward artwork differs from maintained resource table')
        document['items'].sort(key=lambda row: row['id'])
        (root / SOURCE).write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('receipts', type=Path)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    spec = json.loads((root / 'data/ui/reward_art_v5_prompts.json').read_text(encoding='utf-8'))
    raw = json.loads(args.receipts.read_text(encoding='utf-8-sig'))
    spec_by_id = {row['id']: row for row in spec}
    receipts = [{**spec_by_id[row['id']], **row} for row in raw]
    expected = set(spec_by_id)
    assert {row['id'] for row in receipts} == expected and len(receipts) == len(expected)
    folder = root / 'panorama/src/images/custom_game/reward_art_v5'
    template = (root / 'panorama/src/images/custom_game/archive_gpu_regular/head_v2_friend_01.vtex').read_text(encoding='utf-8')
    assets, imports = {}, []
    for row in receipts:
        if row.get('original_file'):
            source = Path(row['original_file'])
        else:
            match = re.search(r" as (C:\\[^\r\n]+?\.png) by default", row['output_hint'])
            assert match, 'Missing generated path: ' + row['id']
            source = Path(match.group(1))
        assert source.is_file() and 'generated_images' in source.parts
        blob = source.read_bytes()
        assert blob[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', blob[16:24])
        assert min(width, height) >= 512
        identity = row['id']
        assert re.fullmatch(r'[A-Za-z0-9_-]+', identity), 'Invalid resource ID'
        texture = template.replace('custom_game/archive_heads_v2/friend_01.png', 'custom_game/reward_art_v5/' + identity + '.png')
        if row['kind'] == 'pool':
            texture = texture.replace('"256"', '"1024"')
        imports.append((source, folder / (identity + '.png'), texture, folder / (identity + '.vtex')))
        assets[identity] = {'id': identity, 'name': row['name'], 'kind': row['kind'],
            'icon_path': 'custom_game/reward_art_v5/' + identity + '.png',
            'runtime_uri': 's2r://panorama/images/custom_game/reward_art_v5/' + identity + '.vtex',
            'source_width': width, 'source_height': height,
            'sha256': hashlib.sha256(blob).hexdigest(), 'original_file': str(source),
            'generator': 'built-in image_gen', 'prompt': row['prompt']}
    # Check mode validates receipts and identity bindings without copying assets.
    changed = update_item_resources(root, assets, check=args.check)
    if not args.check:
        folder.mkdir(parents=True, exist_ok=True)
        for source, target, texture, recipe in imports:
            shutil.copyfile(source, target)
            recipe.write_text(texture, encoding='utf-8')
        (root / 'data/ui/reward_art_v5.json').write_text(json.dumps(assets, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    result = build_item_resources.build(root=root, check=args.check)
    result.update(assets=len(assets), resource_updates=changed, receipt='data/ui/reward_art_v5.json')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
