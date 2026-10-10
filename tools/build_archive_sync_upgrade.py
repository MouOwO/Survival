"""Build the reviewed archive sync on top of a verified production bundle.

Existing economic rules and recorded receipt versions remain immutable. Only
archive tables, additive statistics, and the shared archive integrations change.
"""
from __future__ import annotations
import argparse
import copy
import csv
import hashlib
import io
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, MODULES, PRESENTATION_CSV, read_csv
from archive_backend.config_compatibility import UPGRADE_COMMANDS
from archive_backend.service import FIELDS

NEW_FIELDS = {'starjoy_points_earned', 'starjoy_reward_level',
    'hero_execute_health_threshold_pct', 'vip_level', 'shop_paid_currency',
    'vip_recharge_total_fen'}
LEGACY_HASH = '288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7'

def immutable(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() != raw:
        raise ValueError('archive_sync_existing_file_changed:' + path.name)
    path.write_bytes(raw)

def build(baseline, database, destination, root=ROOT):
    oldraw = baseline['bundle_raw'].encode()
    previous = hashlib.sha256(oldraw).hexdigest()
    if previous != baseline['bundle']:
        raise ValueError('archive_sync_baseline_hash_mismatch')
    old = json.loads(oldraw)
    data = copy.deepcopy(old)
    for path in sorted((root / 'data/csv/存档系统').glob('*.csv')):
        if path.name in PRESENTATION_CSV:
            continue
        data['configs'][path.stem] = read_csv(path)
        data['csv_hashes'][path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes().replace(b'\r\n',b'\n')).hexdigest()
    current = read_csv(root / 'data/csv/玩家档案系统/player_gameplay_stats.csv')
    before = old['configs']['player_gameplay_stats']
    before_rows = {row['field_id']: row for row in before['rows']}
    current_rows = {row['field_id']: row for row in current['rows']}
    if current_rows.keys() - before_rows.keys() != NEW_FIELDS or before_rows.keys() - current_rows.keys():
        raise ValueError('archive_sync_stat_schema_changed')
    for field, row in before_rows.items():
        if any(row.get(key) != current_rows[field].get(key) for key in ('default_value','min_value','max_value','storage_type')):
            raise ValueError('archive_sync_existing_stat_bounds_changed:' + field)
    for field in NEW_FIELDS:
        if current_rows[field]['default_value'] != 0:
            raise ValueError('archive_sync_new_stat_default_nonzero')
    data['configs']['player_gameplay_stats'] = copy.deepcopy(before)
    data['configs']['player_gameplay_stats']['rows'].extend(current_rows[field] for field in sorted(NEW_FIELDS))
    # Preserve the deployed CSV byte content and append only the six new rows.
    deployed_csv = database['gameplay_stats_csv']
    if not deployed_csv.endswith('\n'):
        deployed_csv += '\n'
    local_lines = (root / 'data/csv/玩家档案系统/player_gameplay_stats.csv').read_text(encoding='utf-8-sig').splitlines()
    additions = []
    for line in local_lines:
        if not line or line.startswith('#'):
            continue
        if next(csv.reader([line]))[0] in NEW_FIELDS:
            additions.append(line)
    if len(additions) != len(NEW_FIELDS):
        raise ValueError('archive_sync_csv_rows_missing')
    stats_csv = (deployed_csv + '\n'.join(additions) + '\n').encode()
    stats_key = 'data/csv/玩家档案系统/player_gameplay_stats.csv'
    data['csv_hashes'][stats_key] = hashlib.sha256(stats_csv.replace(b'\r\n',b'\n')).hexdigest()
    for name in MODULES:
        data['sources']['systems/' + name + '.lua'] = (root / 'scripts/vscripts/systems' / (name + '.lua')).read_text(encoding='utf-8-sig')
    data['sources']['worker.lua'] = (root / 'server/archive_backend/worker.lua').read_text(encoding='utf-8-sig')
    aliases = set(old.get('compatible_config_hashes', {})) | {previous}
    if aliases != {LEGACY_HASH, previous}:
        raise ValueError('archive_sync_unknown_legacy_hash')
    data['compatible_config_hashes'] = {digest:{
        'commands':sorted(set(FIELDS) | {'lottery_snapshot'}),
        'upgrade_commands':sorted(UPGRADE_COMMANDS),
    } for digest in sorted(aliases)}
    changed_configs = sorted(k for k in data['configs'] if data['configs'][k] != old['configs'].get(k))
    if any(k != 'player_gameplay_stats' and not k.startswith('archive_') for k in changed_configs):
        raise ValueError('archive_sync_unrelated_economic_config_changed')
    changed_sources = sorted(k for k in data['sources'] if data['sources'][k] != old['sources'].get(k))
    raw = json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    digest = hashlib.sha256(raw).hexdigest()
    destination = Path(destination)
    bundles = destination / 'addon/server/bundles'
    for identity, encoded, content in ((previous,oldraw,old),(digest,raw,data)):
        for name, source in content['sources'].items():
            immutable(bundles / identity / name, source.encode())
        immutable(bundles / identity / 'bundle.json',encoded)
    immutable(bundles / 'current.json',json.dumps({'hash':digest,'protocol':1}).encode())
    for name in ('service.py','bundle.py','config_compatibility.py'):
        immutable(destination / 'backend/archive_backend' / name,(root / 'server/archive_backend' / name).read_bytes())
    immutable(destination / 'addon' / stats_key,stats_csv)
    Bundle(bundles / digest)
    return {'hash':digest,'previous_hash':previous,'legacy_hashes':sorted(aliases),
        'changed_configs':changed_configs,'changed_sources':changed_sources,
        'new_stat_fields':sorted(NEW_FIELDS),'existing_stat_rules_preserved':True,
        'commerce_lottery_configuration_preserved':True}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--database',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    result = build(json.loads(args.baseline.read_text(encoding='utf-8')),
        json.loads(args.database.read_text(encoding='utf-8')),args.output)
    print(json.dumps(result,sort_keys=True))
