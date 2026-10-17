"""Isolated checks: never invokes the reward PNG import or changes the real table."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
OUT = ROOT / 'design_refs/item_resources_20261016/audit'


def module(name):
    path = ROOT / 'tools' / (name + '.py')
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rejects(fn):
    try:
        fn()
    except (ValueError, AssertionError):
        return
    raise AssertionError('expected_rejection')


def main():
    master = ROOT / 'data/ui/item_resources.json'
    before = digest(master)
    commerce = module('build_commerce_product_art')
    rewards = module('import_reward_art_v5')
    checks = []
    with tempfile.TemporaryDirectory(prefix='survival-item-resource-generators-') as work:
        root = Path(work)
        path = root / 'data/ui/item_resources.json'
        path.parent.mkdir(parents=True)
        data = {'schema_version': 1, 'items': [
            {'id': 'lottery_muramasa', 'name': 'Muramasa', 'kind': 'image',
             'uri': 'file://{images}/items/yasha.png', 'aliases': ['video_p042', 'commerce_p042']},
            {'id': 'commerce_p151', 'name': 'Spirit', 'kind': 'image',
             'uri': 's2r://panorama/images/custom_game/commerce_art_v1/spirit_katana.vtex',
             'aliases': ['video_p151', 'commerce_spirit_katana']},
            {'id': 'vip_medal_01', 'name': 'VIP1', 'kind': 'vip', 'vip_level': 1,
             'uri': 'file://{images}/custom_game/topnav_reference_v2/vip.svg', 'aliases': []},
        ]}
        path.write_text(json.dumps(data), encoding='utf-8')
        original = path.read_bytes()
        assert commerce.update_resource(root, 'video_p042', 'lottery_muramasa',
                                        data['items'][0]['uri'], check=True) is False
        assert path.read_bytes() == original
        checks.append('commerce_unchanged_check_no_write')
        rejects(lambda: commerce.update_resource(root, 'video_p151', 'lottery_muramasa',
                                                  data['items'][0]['uri']))
        rejects(lambda: commerce.update_resource(root, 'video_p042', 'lottery_muramasa',
                                                  'https://example.com/unreviewed.png'))
        rejects(lambda: commerce.update_resource(root, 'video_p042', 'lottery_muramasa',
                                                  'file://{images}/items/rapier.png', check=True))
        assert path.read_bytes() == original
        checks.append('commerce_wrong_identity_unsafe_uri_and_check_diff_rejected')
        assert commerce.update_resource(root, 'video_p042', 'lottery_muramasa',
                                        's2r://panorama/images/custom_game/reward_art_v5/lottery_muramasa.vtex')
        changed = json.loads(path.read_bytes())
        assert changed['items'][1] == data['items'][1]
        assert changed['items'][0]['aliases'] == data['items'][0]['aliases']
        checks.append('commerce_explicit_update_preserves_other_items_and_aliases')
        assets = {
            'lottery_muramasa': {'kind': 'item', 'name': 'Muramasa',
                                'runtime_uri': 'file://{images}/items/yasha.png'},
            'new_exact_reward': {'kind': 'item', 'name': 'New',
                                 'runtime_uri': 'file://{images}/items/rapier.png'},
            'pool_example': {'kind': 'pool', 'name': 'Pool',
                             'runtime_uri': 'file://{images}/items/recipe.png'},
        }
        snapshot = path.read_bytes()
        rejects(lambda: rewards.update_item_resources(root, assets, check=True))
        assert path.read_bytes() == snapshot
        checks.append('reward_check_no_write')
        assert rewards.update_item_resources(root, assets) == 2
        result = json.loads(path.read_bytes())
        by_id = {row['id']: row for row in result['items']}
        assert by_id['commerce_p151'] == data['items'][1]
        assert by_id['lottery_muramasa']['uri'] == assets['lottery_muramasa']['runtime_uri']
        assert 'new_exact_reward' in by_id and 'pool_example' not in by_id
        assert by_id['lottery_muramasa']['aliases'] == data['items'][0]['aliases']
        checks.append('reward_exact_ids_only_and_pool_excluded')
        snapshot = path.read_bytes()
        rejects(lambda: rewards.update_item_resources(root, {
            'vip_medal_01': {'kind': 'item', 'name': 'Wrong', 'runtime_uri': 'file://{images}/items/yasha.png'}}))
        assert path.read_bytes() == snapshot
        checks.append('reward_specialized_renderer_preserved')
    assert digest(master) == before, 'production_master_changed'
    checks.append('production_master_unchanged')
    checks.append('both_tools_import_safely_and_parse_without_running_asset_import')
    result = {'status': 'PASS', 'groups': len(checks), 'checks': checks,
              'production_master_sha256': before, 'asset_import_executed': False,
              'files': {name: digest(ROOT / 'tools' / name) for name in
                        ['build_commerce_product_art.py', 'import_reward_art_v5.py']}}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'generator_compatibility.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
