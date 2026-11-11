"""Verify the prepared immutable bundle using synthetic Lua workers only."""
import copy
import hashlib
import json
import shutil
import subprocess

PARENT = '98761e2a9386174e696fada8efdc2fc6891365dc661215b576b5f90f02fc8fac'
CONFIGS = {'lottery_pool_definitions', 'lottery_quality_weights', 'lottery_pity_rules', 'lottery_pool_updates'}
SOURCES = {'config/lottery_config.lua', 'systems/lottery_http_settlement.lua'}
GOLD = ('cultivation', 'dragon_knight', 'summer')


def need(ok, code):
    if not ok: raise RuntimeError(code)


def run(old, new, bundle_hash):
    parent_dir = old / 'addon/server/bundles' / PARENT
    directory = new / 'addon/server/bundles' / bundle_hash
    parent = json.loads((parent_dir / 'bundle.json').read_bytes())
    raw = (directory / 'bundle.json').read_bytes()
    need(hashlib.sha256(raw).hexdigest() == bundle_hash, 'candidate_bundle_changed')
    candidate = json.loads(raw)
    need(set(candidate['configs']) == set(parent['configs']), 'configuration_set_changed')
    need({k for k in parent['configs'] if parent['configs'][k] != candidate['configs'][k]} == CONFIGS,
         'configuration_scope_changed')
    need(set(candidate['sources']) == set(parent['sources']) and
         {k for k in parent['sources'] if parent['sources'][k] != candidate['sources'][k]} == SOURCES,
         'source_scope_changed')
    for key in CONFIGS:
        need([r for r in candidate['configs'][key]['rows'] if r['pool_id'] == 'map'] ==
             [r for r in parent['configs'][key]['rows'] if r['pool_id'] == 'map'], 'map_rules_changed')
    lua = shutil.which('lua5.1') or shutil.which('lua')
    need(lua is not None, 'actual_lua_required')
    vectors = 0

    def worker(document, path, profile, count, pool, seed=0):
        nonlocal vectors
        payload = dict(profile=profile, configs=document['configs'], seed=seed, has_pass=False,
                       command=dict(kind='lottery_draw', id='synthetic:ur50', request_id='synthetic_ur50',
                                    count=count, pool_id=pool))
        result = subprocess.run([lua, 'worker.lua'], cwd=path,
            input=json.dumps(payload).encode('ascii'), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10, check=True)
        vectors += 1
        return json.loads(result.stdout)

    def profile(pool, start):
        return dict(account_id='synthetic', save=dict(gameplay_stats={}, content_inventory={
            'lottery_ticket':100, 'special_lottery_ticket':100}, archive=dict(lottery_state=dict(pools={
                pool:dict(draws=10000, pity_counts={pool+'_ur_fifty':start}),
                'unrelated':dict(draws=17, pity_counts=dict(untouched=12))}))))

    for pool in GOLD:
        defs = [r for r in candidate['configs']['lottery_pool_definitions']['rows'] if r['pool_id'] == pool]
        need(len(defs) == 1 and defs[0].get('unlock_draws',0) == 0 and
             not defs[0].get('unlock_pool_id') and defs[0]['ticket_content_id'] == 'special_lottery_ticket'
             and defs[0]['single_cost'] == 1 and defs[0]['ten_cost'] == 10, 'gold_cost_or_unlock_invalid')
        weights = {r['quality']:r['weight'] for r in candidate['configs']['lottery_quality_weights']['rows'] if r['pool_id'] == pool}
        need(weights == dict(n=0,r=9350,sr=400,ssr=150,ur=100), 'gold_weights_invalid')
        for start in range(50):
            for count in (1,10):
                p = profile(pool,start)
                before = copy.deepcopy(p)
                result = worker(candidate,directory,p,count,pool)
                need(result.get('ok') is True and p == before, 'synthetic_draw_failed')
                qualities = [r['quality'] for r in result['response']['results']]
                need(qualities.count('ur') == int(start+count >= 50), 'ur_deadline_failed')
                need(count != 10 or 'ssr' in qualities, 'ssr_ten_guarantee_failed')
                saved = result['archive']['lottery_state']['pools']
                need(saved[pool]['pity_counts'][pool+'_ur_fifty'] == (start+count)%50,
                     'ur_counter_invalid')
                need(saved['unrelated'] == p['save']['archive']['lottery_state']['pools']['unrelated'],
                     'other_pool_counter_changed')
                need(result['content_inventory']['special_lottery_ticket'] == 100-count and
                     result['content_inventory']['lottery_ticket'] == 100, 'wrong_ticket_debit')
                if start == 40 and count == 10: need(qualities[-2:] == ['ssr','ur'], 'last_slot_collision')
        natural = worker(candidate,directory,profile(pool,0),10,pool,67)
        need(natural['response']['results'][5]['quality'] == 'ur' and
             natural['archive']['lottery_state']['pools'][pool]['pity_counts'][pool+'_ur_fifty'] == 4,
             'natural_ur_reset_failed')
        poor = profile(pool,49);poor['save']['content_inventory']['special_lottery_ticket'] = 0
        failed = worker(candidate,directory,poor,1,pool)
        need(failed.get('ok') is False and failed.get('error') == 'lottery_ticket_insufficient' and
             'archive' not in failed, 'failed_draw_changed_state')
    # Exact result/state parity for the unchanged map pool, using both actual
    # immutable workers. No normalization may hide a map behavior change.
    for seed in (0,1,67,555):
        for count in (1,10):
            p = profile('map',0)
            need(worker(parent,parent_dir,p,count,'map',seed) ==
                 worker(candidate,directory,p,count,'map',seed), 'map_settlement_parity_failed')
    manifest = json.loads((new / 'release_manifest.json').read_bytes())
    changed = manifest['lottery_rates_changed_files']
    need(len(changed) == 36 and changed == sorted(changed), 'overlay_scope_invalid')
    return dict(ok=True,status='ACTUAL_WS4_PREPARED_GOLD_UR1_FIFTY_PASS',
                real_lua_vectors=vectors,changed_files=changed,gold_pools_verified=3,map_unchanged=True,
                exact_ssr_guarantee=True,ur50_guarantee=True,cultivation_gate_removed=True,
                rpc_calls=0,database_writes=0,real_player_data_used=False)
