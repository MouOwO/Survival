"""Read-only probe of the prepared WS4 lottery bundle; no account or RPC calls."""
import hashlib
import json

PARENT_BUNDLE = 'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
GOLD_POOLS = ('cultivation', 'dragon_knight', 'summer')
CHANGED_CONFIGS = {'lottery_quality_weights', 'lottery_pity_rules',
                   'lottery_pool_definitions', 'lottery_pool_updates'}


def need(ok, code):
    if not ok: raise RuntimeError(code)


def rows(bundle, key, pool):
    return [row for row in bundle['configs'][key]['rows'] if row['pool_id'] == pool]


def run(old, new, bundle_hash):
    parent = json.loads((old / 'addon/server/bundles' / PARENT_BUNDLE / 'bundle.json').read_bytes())
    raw = (new / 'addon/server/bundles' / bundle_hash / 'bundle.json').read_bytes()
    need(hashlib.sha256(raw).hexdigest() == bundle_hash, 'candidate_bundle_changed')
    candidate = json.loads(raw)
    need(set(candidate['configs']) == set(parent['configs']), 'lottery_config_set_changed')
    need({key for key in parent['configs'] if parent['configs'][key] != candidate['configs'][key]}
         == CHANGED_CONFIGS, 'lottery_config_scope_changed')
    need({key for key in parent['sources'] if parent['sources'][key] != candidate['sources'][key]}
         == {'systems/lottery_http_settlement.lua'}, 'lottery_source_scope_changed')
    need('item.quality==guarantee' in candidate['sources']['systems/lottery_http_settlement.lua'],
         'exact_ssr_guarantee_missing')
    for key in ('lottery_quality_weights', 'lottery_pity_rules', 'lottery_pool_definitions'):
        need(rows(parent, key, 'map') == rows(candidate, key, 'map'), 'map_pool_changed')
    for pool in GOLD_POOLS:
        weights = {row['quality']: row['weight'] for row in rows(candidate, 'lottery_quality_weights', pool)}
        need(weights == {'n': 0, 'r': 9150, 'sr': 400, 'ssr': 150, 'ur': 300},
             'gold_pool_weights_invalid')
        pity = [row for row in rows(candidate, 'lottery_pity_rules', pool) if row['enabled']]
        need(len(pity) == 1 and pity[0]['target_quality'] == 'ssr' and
             pity[0]['trigger_mode'] == 'batch_only' and pity[0]['threshold'] == 10,
             'gold_pool_ten_pity_invalid')
        definitions = rows(candidate, 'lottery_pool_definitions', pool)
        need(len(definitions) == 1 and '十连保底SSR' in definitions[0]['description'],
             'gold_pool_advertised_pity_invalid')
    alias = candidate['compatible_config_hashes'][PARENT_BUNDLE]
    need('lottery_draw' not in alias['commands'] and 'lottery_read' not in alias['commands'],
         'stale_client_draw_not_blocked')
    manifest = json.loads((new / 'release_manifest.json').read_bytes())
    changed = manifest['lottery_rates_changed_files']
    need(len(changed) == 36 and changed == sorted(changed), 'lottery_overlay_file_set_invalid')
    return dict(ok=True, status='ACTUAL_WS4_PREPARED_LOTTERY_RATES_PASS',
                changed_files=changed, gold_pools_verified=3, map_unchanged=True,
                exact_ssr_guarantee=True, old_client_draw_blocked=True,
                rpc_calls=0, database_writes=0, real_player_data_used=False)
