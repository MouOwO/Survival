"""Build the approved UR1/50-pity and cultivation unlock changes on the published WS4 bundle.

One operator-time O(bundle bytes) pass; no game, network or player operation.
The immutable parent and all unrelated configuration/source bytes are retained.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PARENT = '98761e2a9386174e696fada8efdc2fc6891365dc661215b576b5f90f02fc8fac'
CONFIGS = ('lottery_pool_definitions', 'lottery_quality_weights', 'lottery_pity_rules', 'lottery_pool_updates')
SOURCES = ('config/lottery_config.lua', 'systems/lottery_http_settlement.lua')
GOLD = ('cultivation', 'dragon_knight', 'summer')
CSV_PREFIX = 'data/csv/抽奖系统/'
sys.path.insert(0, str(ROOT))
from server.archive_backend.bundle import read_csv


def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(value): return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
def need(ok, code):
    if not ok: raise ValueError(code)


def derive(parent_raw, csv_files, source_files):
    need(sha(parent_raw) == PARENT, 'published_parent_changed')
    parent = json.loads(parent_raw)
    result = copy.deepcopy(parent)
    for key in CONFIGS:
        raw = csv_files[key]
        class Source:
            name = key
            def read_text(self, **kwargs): return raw.decode('utf-8-sig')
        candidate = read_csv(Source())
        original = parent['configs'][key]
        need(candidate['key'] == original['key'], 'configuration_key_changed')
        need([row for row in candidate['rows'] if row['pool_id'] == 'map'] ==
             [row for row in original['rows'] if row['pool_id'] == 'map'], 'map_configuration_changed')
        old = {row[original['key']]:row for row in original['rows']}
        for row in candidate['rows']:
            identity = row[candidate['key']]
            if identity not in old:
                need(key == 'lottery_pity_rules' and row['pool_id'] in GOLD and
                     identity == row['pool_id'] + '_ur_fifty' and row['threshold'] == 50 and
                     row['target_quality'] == 'ur' and row['trigger_mode'] == 'consecutive_misses' and
                     row['priority'] == 30 and row['enabled'] is True, 'unexpected_new_rule')
                continue
            prior = old[identity]
            allowed = {'description', 'notes'} if key == 'lottery_pool_definitions' else {'notes'}
            if key == 'lottery_pool_definitions' and row['pool_id'] == 'cultivation': allowed |= {'unlock_pool_id', 'unlock_draws'}
            if key == 'lottery_quality_weights': allowed |= {'weight'}
            if key == 'lottery_pool_updates': allowed |= {'title', 'summary', 'updated_at', 'single_draw_probabilities'}
            need({k:v for k,v in row.items() if k not in allowed} ==
                 {k:v for k,v in prior.items() if k not in allowed}, 'unrelated_configuration_change')
        need(set(old) <= {row[candidate['key']] for row in candidate['rows']}, 'configuration_row_deleted')
        for pool in GOLD:
            rows = [row for row in candidate['rows'] if row['pool_id'] == pool]
            if key == 'lottery_pool_definitions':
                need(len(rows) == 1 and rows[0]['ticket_content_id'] == 'special_lottery_ticket' and
                     rows[0]['single_cost'] == 1 and rows[0]['ten_cost'] == 10 and
                     rows[0].get('unlock_draws', 0) == 0 and not rows[0].get('unlock_pool_id') and
                     rows[0]['description'] == '金色抽奖券 · UR基础概率1% · 最多50抽必出UR · 十连保底SSR', 'gold_pool_contract_invalid')
            elif key == 'lottery_quality_weights':
                need({r['quality']:r['weight'] for r in rows} == {'n':0,'r':9350,'sr':400,'ssr':150,'ur':100}, 'gold_weights_invalid')
            elif key == 'lottery_pity_rules':
                need(len(rows) == 2 and {(r['target_quality'],r['threshold'],r['trigger_mode']) for r in rows} ==
                     {('ssr',10,'batch_only'),('ur',50,'consecutive_misses')}, 'gold_pity_invalid')
        result['configs'][key] = candidate
        result['csv_hashes'][CSV_PREFIX + key + '.csv'] = sha(raw)
    for name in SOURCES:
        raw = source_files[name]
        need(raw.decode('utf8') != parent['sources'][name], 'settlement_update_missing')
        result['sources'][name] = raw.decode('utf8')
    # Old rates must not authorize a new draw intent. Already prepared receipts
    # still recover against their own retained immutable bundle.
    result['compatible_config_hashes'][PARENT] = copy.deepcopy(result['compatible_config_hashes']['f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'])
    return canonical(result)


def build(revision, output):
    need(bool(re.fullmatch('[a-f0-9]{40}', revision or '')), 'immutable_source_required')
    def blob(name):
        raw = subprocess.check_output(['git', '--no-replace-objects', '-C', str(ROOT), 'show', revision + ':' + name]).replace(b'\r\n', b'\n')
        need(raw == (ROOT / name).read_bytes().replace(b'\r\n', b'\n'), 'source_worktree_drift')
        return raw
    csv_files = {key:blob(CSV_PREFIX + key + '.csv') for key in CONFIGS}
    source_files = {name:blob('scripts/vscripts/' + name) for name in SOURCES}
    parent_raw = (ROOT / 'server/bundles' / PARENT / 'bundle.json').read_bytes()
    raw = derive(parent_raw, csv_files, source_files)
    digest = sha(raw)
    output.mkdir(parents=True, exist_ok=False)
    directory = output / digest
    directory.mkdir()
    document = json.loads(raw)
    for name, text in document['sources'].items():
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf8', newline='\n')
    (directory / 'bundle.json').write_bytes(raw)
    receipt = dict(status='CULTIVATION_UNLOCK_BUNDLE_BUILT', recipe='gold-ur1-fifty-and-cultivation-unlock-v1',
                   source_revision=revision, source_sha256={**{CSV_PREFIX+k+'.csv':sha(v) for k,v in csv_files.items()}, **{'scripts/vscripts/'+k:sha(v) for k,v in source_files.items()}},
                   parent_bundle_hash=PARENT, candidate_bundle_hash=digest,
                   candidate_dir=str(directory.resolve()), changed_configs=list(CONFIGS), changed_sources=list(SOURCES),
                   unchanged_sources=len(document['sources'])-len(SOURCES), sdk_calls=0, player_writes=0)
    (output / 'candidate_receipt.json').write_bytes(canonical(receipt) + b'\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source_revision, args.output)))
