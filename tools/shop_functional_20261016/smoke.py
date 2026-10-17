"""Run the real bundled Lua settlement worker against isolated synthetic saves."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
NEW = ('video_p016', 'video_p028', 'video_p079', 'video_p147')
MARKERS = {'video_p016': 'commerce_p016', 'video_p028': 'commerce_p028',
           'video_p079': 'lottery_monkey_king', 'video_p147': 'commerce_p147'}
PRICES = {'video_p016': 29800, 'video_p028': 23800, 'video_p079': 5000,
          'video_p147': 5000, 'video_bundle_b003': 46560, 'video_p032': 8800}
DIRECT = {
    'video_p016': {'starjoy_points': 298},
    'video_p028': {'lumberjack_efficiency': 2, 'wood_per_second': 3,
                   'gold_per_second': 2, 'gold_mine_efficiency_pct': 10,
                   'gold_mine_build_cap': 1, 'starjoy_points': 238},
    'video_p079': {'map_level': 1, 'hero_attack_armor_reduction': 10,
                   'hero_basic_attack_growth': 10, 'hero_attribute_growth': 10,
                   'hero_attack_bonus_pct': 10, 'hero_attribute_bonus_pct': 10,
                   'hero_final_damage_bonus_pct': 10, 'starjoy_points': 200},
    'video_p147': {'hero_attack_armor_reduction': 25, 'hero_basic_attack_growth': 25,
                   'hero_attribute_growth': 25, 'hero_attack_bonus_pct': 25,
                   'hero_attribute_bonus_pct': 25, 'hero_final_damage_bonus_pct': 25,
                   'hero_attack_armor_reduction_pct': 8,
                   'hero_attack_attribute_efficiency_pct': 8},
}


def _bundle_file(path):
    path = Path(path)
    if path.is_file():
        return path
    direct = path / 'bundle.json'
    if direct.is_file():
        return direct
    found = list(path.rglob('bundle.json'))
    assert len(found) == 1, ('baseline_bundle_not_unique', str(path), len(found))
    return found[0]


def run_checks(bundle_path, lua_executable, baseline=None):
    bundle_file = _bundle_file(bundle_path)
    directory = bundle_file.parent
    configs = json.loads(bundle_file.read_bytes())['configs']
    products = {p['sku']: p for p in configs['commerce_catalog']['rows']}
    defaults = {r['field_id']: r['default_value'] for r in configs['player_gameplay_stats']['rows']}
    profile = {'schema_version': 1, 'account_id': 'functional-synthetic-no-database',
               'revision': 1, 'entitlements': {}, 'save': {
                   'gameplay_stats': dict(defaults, starjoy_points=37,
                       starjoy_points_earned=1000000, starjoy_reward_level=24,
                       hero_execute_health_threshold_pct=15),
                   'content_inventory': {'fixture_keep_item': 3},
                   'archive': {'fixture_keep_value': 123, 'commerce': {'balances': {
                       'shop_points': 1000000, 'shop_gold': 1000000, 'u_coin': 1000000}}}}}
    initial = copy.deepcopy(profile)
    checks, calls = [], 0

    def run(source, command):
        nonlocal calls
        payload = {'configs': configs, 'profile': source, 'command': command,
                   'has_pass': False, 'seed': 12345, 'server_time': 2000000000}
        process = subprocess.run([str(lua_executable), 'worker.lua'], cwd=directory,
            input=json.dumps(payload, ensure_ascii=False).encode('utf8'), capture_output=True,
            check=True, timeout=15, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        calls += 1
        return json.loads(process.stdout)

    def purchase(source, sku, **untrusted):
        return run(source, {'id': 'functional-smoke:' + sku, 'kind': 'commerce_purchase',
                           'sku': sku, 'request_id': 'functional-smoke-' + sku, **untrusted})

    def state(source, result):
        assert result.get('ok') is True, result
        after = copy.deepcopy(source)
        after['save'].update({key: result[key] for key in ('gameplay_stats', 'content_inventory', 'archive')})
        return after

    def snapshot(source):
        return run(source, {'id': 'functional-smoke:catalog', 'kind': 'commerce_catalog'})

    def verify_purchase(source, sku, result=None):
        result = result or purchase(source, sku)
        after = state(source, result)
        product, before = products[sku], source['save']
        assert product['enabled'] and product['price'] == PRICES.get(sku, product['price'])
        expected_inventory = copy.deepcopy(before['content_inventory'])
        expected_inventory[product['item_id']] = expected_inventory.get(product['item_id'], 0) + product.get('ownership_quantity', 1)
        for item, quantity in product['grants']['items'].items():
            expected_inventory[item] = expected_inventory.get(item, 0) + quantity
        assert after['save']['content_inventory'] == expected_inventory, ('inventory', sku)
        for field, amount in product['effects'].items():
            expected = before['gameplay_stats'].get(field, defaults[field]) + amount
            actual = after['save']['gameplay_stats'][field]
            assert abs(actual - expected) < 1e-7 * max(1, abs(expected)), (sku, field, actual, expected)
        starjoy = product['effects'].get('starjoy_points', 0)
        assert after['save']['gameplay_stats']['starjoy_points_earned'] == before['gameplay_stats']['starjoy_points_earned'] + starjoy
        assert after['save']['gameplay_stats']['starjoy_reward_level'] == 24
        expected_balances = dict(before['archive']['commerce']['balances'])
        expected_balances[product['currency']] -= product['price']
        assert after['save']['archive']['commerce']['balances'] == expected_balances, ('debit', sku)
        assert after['save']['archive']['fixture_keep_value'] == 123
        assert result['response']['price'] == product['price']
        assert result['response']['currency'] == product['currency']
        assert result['response']['balance'] == expected_balances[product['currency']]
        return after

    def denied_unchanged(source, sku, error):
        before = copy.deepcopy(source)
        denied = purchase(source, sku)
        assert denied.get('ok') is False and denied.get('error') == error, (sku, denied, error)
        assert not any(key in denied for key in ('archive', 'content_inventory', 'gameplay_stats'))
        assert source == before
        return denied

    assert len(products) == 129 and sum(bool(p['enabled']) for p in products.values()) == 126
    view = snapshot(profile)
    indexed = {p['sku']: p for p in view['products']}
    assert view['ok'] and len(indexed) == 126
    assert not any(p.get('currency') == 'shop_gold' for p in view['products'])
    for sku in (*NEW, 'video_bundle_b003'):
        assert indexed[sku]['enabled'], (sku, indexed[sku])
    checks.append('formal catalog129 / enabled126; four new functional products and complete newcomer pack listed; gold hidden')

    for sku, expected in DIRECT.items():
        p = products[sku]
        assert p['item_id'] == MARKERS[sku] and p['purchase_limit'] == 1
        for field, amount in expected.items():
            assert p['effects'].get(field) == amount, (sku, field, p['effects'].get(field), amount)
        if sku == 'video_p016':
            assert set(p['effects']) == {'starjoy_points'}, 'spatial aura must not become permanent global armor/regen'
        after = verify_purchase(profile, sku)
        denied_unchanged(after, sku, 'already_owned')
        row = next(p for p in snapshot(after)['products'] if p['sku'] == sku)
        assert not row['enabled'] and row['owned'] == 1 and row['disabled_reason'] == 'already_owned'
    checks.append('all four: authoritative cost, every static field, lifetime points, canonical marker, max1, and second-purchase rejection')

    # EX and per-match rerolls are entitlement-derived, so neither is copied
    # into persistent ordinary percentages or saved as a reusable reroll grant.
    ex = {f: value for f, value in products['video_p147']['effects'].items() if f not in DIRECT['video_p147']}
    assert not ex, ('unexpected_persisted_ex_or_other_fields', ex)
    assert not any('reroll' in key for key in products['video_p147']['effects'])
    checks.append('P147 persists exactly eight ordinary fields; independent EX8 and per-match rerolls derive from commerce_p147 ownership')

    bundle = products['video_bundle_b003']
    components = {p['sku']: p for p in bundle['grants']['components']}
    expected_components = {'video_p028', 'video_p020', 'video_p018', 'video_p032'}
    assert set(components) == expected_components and len(bundle['grants']['lines']) == 4
    assert bundle['effects']['starjoy_points'] == 662
    assert not bundle.get('bundle_pending') and not bundle.get('pending_members')
    total_effects = {}
    for sku in expected_components:
        component = components[sku]
        assert component['item_id'] == products[sku]['item_id'] and component['quantity'] == 1 and component['purchase_limit'] == 1
        assert bundle['grants']['items'][component['item_id']] == 1
        assert bundle['grants']['item_limits'][component['item_id']] == 1
        for field, amount in products[sku]['effects'].items():
            total_effects[field] = total_effects.get(field, 0) + amount
    assert bundle['effects'] == total_effects
    after_bundle = verify_purchase(profile, 'video_bundle_b003')
    assert after_bundle['save']['gameplay_stats']['starjoy_points'] == 37 + 662
    denied_unchanged(after_bundle, 'video_bundle_b003', 'already_owned')
    for sku in expected_components:
        denied_unchanged(after_bundle, sku, 'already_owned')
        after_single = verify_purchase(profile, sku)
        denied_unchanged(after_single, 'video_bundle_b003', 'component_already_owned')
    checks.append('newcomer pack grants four complete components and exact aggregated effects / starjoy662; all four single-pack conflicts block both purchase orders')

    lottery_owner = copy.deepcopy(profile)
    lottery_owner['save']['content_inventory']['lottery_monkey_king'] = 1
    denied_unchanged(lottery_owner, 'video_p079', 'already_owned')
    checks.append('P079 already obtained from lottery cannot be repurchased through the new marketplace SKU')

    for sku in (*NEW, 'video_bundle_b003'):
        poor = copy.deepcopy(profile)
        poor['save']['archive']['commerce']['balances'][products[sku]['currency']] = products[sku]['price'] - 1
        denied_unchanged(poor, sku, 'commerce_balance_insufficient')
    checks.append('every new purchase and newcomer bundle fails before any mutation when balance is insufficient')

    # Existing settlement ignores client-side quantities/prices/rewards; the
    # catalog owns all costs and grants, including the newly enabled bundle.
    for sku in ('video_p028', 'video_bundle_b003'):
        forged = purchase(profile, sku, price=1, quantity=99, effects={'gold_per_second': 999999},
                          item_id='forged', currency='shop_gold')
        verify_purchase(profile, sku, forged)
    checks.append('forged price/quantity/currency/reward cannot replace formal server-owned cost and complete grants')

    for sku in ('video_p037', 'video_p038'):
        denied_unchanged(profile, sku, 'shop_gold_not_open')
    assert not products['video_bundle_b005']['enabled']
    denied_unchanged(profile, 'video_bundle_b005', 'product_unavailable')
    checks.append('gold goods and unsupported cosmetic pack remain blocked')

    baseline_path = baseline
    if baseline_path is None:
        fallback = ROOT / 'design_refs/shop_functional_20261016/deployment/online_baseline/archive/addon/server/bundles'
        if fallback.exists():
            baseline_path = fallback
    compared = 0
    if baseline_path is not None:
        old = json.loads(_bundle_file(baseline_path).read_bytes())['configs']['commerce_catalog']['rows']
        for p in old:
            assert p['sku'] in products, ('old_product_removed', p['sku'])
            now = products[p['sku']]
            for key in ('price', 'currency', 'purchase_limit', 'item_id', 'ownership_quantity'):
                assert now.get(key) == p.get(key), ('old_price_or_identity_changed', p['sku'], key)
            compared += 1
        assert compared == 125
    else:
        # A standalone release may not include the workstation's baseline, but
        # critical existing formal prices are still independently asserted.
        for sku, price in {'video_p140': 588, 'video_p151': 5000, 'video_p032': 8800,
                           'video_p018': 8800, 'video_p020': 16800, 'video_p012': 29800}.items():
            assert products[sku]['price'] == price, (sku, products[sku]['price'], price)
    checks.append('existing prices, currencies, ownership limits and identities retained; baseline products compared=' + str(compared))
    assert profile == initial
    return {'status': 'PASS', 'cases': len(checks), 'checks': checks, 'native_worker_calls': calls,
            'formal_products': len(products), 'enabled_products': len(indexed), 'baseline_prices_compared': compared,
            'gateway_requests': 0, 'database_connections': 0, 'real_player_data': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--lua', default=shutil.which('lua5.1') or 'C:/Program Files/lua/bin/lua5.1.exe')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = run_checks(args.bundle, args.lua, args.baseline)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(json.dumps(result, ensure_ascii=False))
