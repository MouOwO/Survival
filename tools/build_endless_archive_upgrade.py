"""Build an additive endless update from a verified live release, without publishing.

The baseline export contains only backend source and its immutable bundle.
Keep all prices, defaults, lottery rules and pre-existing achievement rows.
"""
from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, read_csv


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('endless_upgrade_baseline_source_changed')
    return source.replace(before, after, 1)


def command_fields(source):
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name)
                and target.id == 'FIELDS' for target in node.targets):
            if not isinstance(node.value, ast.Dict):
                break
            result = {}
            for key, value in zip(node.value.keys, node.value.values):
                if not isinstance(key, ast.Constant) or not isinstance(key.value, str):
                    raise ValueError('endless_upgrade_fields_invalid')
                if isinstance(value, ast.Set):
                    result[key.value] = {ast.literal_eval(item) for item in value.elts}
                elif isinstance(value, ast.Call) and isinstance(value.func, ast.Name) \
                        and value.func.id == 'set' and not value.args and not value.keywords:
                    result[key.value] = set()
                else:
                    raise ValueError('endless_upgrade_fields_invalid')
            return result
    raise ValueError('endless_upgrade_fields_missing')


def patch_service(source):
    source = replace_once(source, 'from .bundle import Bundle\n',
                          'from .bundle import Bundle\nfrom .config_compatibility import accepts, upgrades\n')
    source = replace_once(source, '"endless": {"wave","difficulty"},',
                          '"endless": {"wave","difficulty"}, "endless_reconcile": set(),')
    source = replace_once(source,
        'if kind not in FIELDS or set(command)-FIELDS[kind]-{"id","kind"}:',
        'if not isinstance(kind, str) or kind not in FIELDS or set(command)-FIELDS[kind]-{"id","kind"}:')
    source = replace_once(source,
        '        if kind=="endless": c["id"]=match+":endless:"+str(c["wave"])\n',
        '        if kind=="endless": c["id"]=match+":endless:"+str(c["wave"])\n'
        '        if kind=="endless_reconcile": c["id"]=match+":endless_reconcile"\n')
    source = replace_once(source,
        '        if payload.get("config_hash")!=self.bundle.hash: return {"ok":False,"terminal":True,"error":"archive_config_mismatch","config_hash":self.bundle.hash}\n',
        '        requested_hash = payload.get("config_hash")\n'
        '        raw_command = payload.get("command")\n'
        '        kind = raw_command.get("kind") if isinstance(raw_command, dict) else None\n'
        '        if not accepts(self.bundle, requested_hash, kind): return {"ok":False,"terminal":True,"error":"archive_config_mismatch","config_hash":self.bundle.hash}\n')
    source = replace_once(source, '"p_hash":self.bundle.hash,"p_fingerprint":fingerprint,',
                          '"p_hash":requested_hash,"p_fingerprint":fingerprint,')
    source = replace_once(source, '            if version!=self.bundle.hash:\n',
        '            if version!=self.bundle.hash and not upgrades(self.bundle, version, command.get("kind")):\n')
    source = replace_once(source, '        if payload.get("config_hash")!=self.bundle.hash:\n',
        '        requested_hash = payload.get("config_hash")\n'
        '        if not accepts(self.bundle, requested_hash, "lottery_snapshot"):\n')
    return replace_once(source, '        projected["config_hash"]=self.bundle.hash\n',
                        '        projected["config_hash"]=requested_hash\n')


def write_immutable(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() != content:
        raise ValueError('endless_upgrade_existing_file_changed')
    path.write_bytes(content)


def build(baseline, destination, root=ROOT):
    raw_before = baseline['bundle_raw'].encode('utf-8')
    previous = hashlib.sha256(raw_before).hexdigest()
    if previous != baseline['bundle']:
        raise ValueError('endless_upgrade_baseline_hash_mismatch')
    old = json.loads(raw_before)
    data = copy.deepcopy(old)
    csv = root / 'data/csv/存档系统/archive_endless_achievements.csv'
    milestones = read_csv(csv)
    prior = old['configs']['archive_endless_achievements']
    prior_ids = {row['achievement_id']: row for row in prior['rows']}
    current_ids = {row['achievement_id']: row for row in milestones['rows']}
    if len(prior_ids) != 50 or len(current_ids) != 82 \
            or any(current_ids.get(key) != row for key, row in prior_ids.items()):
        raise ValueError('endless_upgrade_prior_rewards_changed')
    fields = {row['field_id'] for row in data['configs']['player_gameplay_stats']['rows']}
    if any(field not in fields for row in milestones['rows'] for field in row['effect_ids']):
        raise ValueError('endless_upgrade_stat_schema_missing')
    data['configs']['archive_endless_achievements'] = milestones
    csv_keys = [key for key in data['csv_hashes'] if key.endswith('/archive_endless_achievements.csv')]
    if len(csv_keys) != 1:
        raise ValueError('endless_upgrade_csv_missing')
    data['csv_hashes'][csv_keys[0]] = hashlib.sha256(csv.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    source = data['sources']['systems/archive_settlement.lua']
    start = source.index('        for _, item in ipairs(require("config/generated/archive_endless_achievements").rows) do')
    end = source.index('    elseif command.kind == "challenge" then', start)
    source = source[:start] + (
        '        require("systems/archive_endless_rewards").reconcile(archive, stats, apply_effects)\n'
        '    elseif command.kind == "endless_reconcile" then\n'
        '        -- Award only from trusted saved server progress, without client counts.\n'
        '        require("systems/archive_endless_rewards").reconcile(archive, stats, apply_effects)\n'
    ) + source[end:]
    data['sources']['systems/archive_settlement.lua'] = source
    data['sources']['systems/archive_endless_rewards.lua'] = (
        root / 'scripts/vscripts/systems/archive_endless_rewards.lua').read_text(encoding='utf-8-sig').replace('\r\n', '\n')
    # The database keeps the original request hash for replay identity. Only
    # these additive endless operations may use the current settlement code.
    data['compatible_config_hashes'] = {previous: {
        'commands': sorted(set(command_fields(baseline['service_source'])) | {'endless_reconcile', 'lottery_snapshot'}),
        'upgrade_commands': ['endless', 'endless_reconcile'],
    }}
    for name, config in old['configs'].items():
        if name != 'archive_endless_achievements' and data['configs'][name] != config:
            raise ValueError('endless_upgrade_unrelated_config_changed')
    for name, text in old['sources'].items():
        if name != 'systems/archive_settlement.lua' and data['sources'][name] != text:
            raise ValueError('endless_upgrade_unrelated_source_changed')
    raw = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    digest = hashlib.sha256(raw).hexdigest()
    destination = Path(destination)
    bundle_root = destination / 'addon/server/bundles'
    for identity, encoded, contents in ((previous, raw_before, old), (digest, raw, data)):
        for name, text in contents['sources'].items():
            write_immutable(bundle_root / identity / name, text.encode())
        write_immutable(bundle_root / identity / 'bundle.json', encoded)
    write_immutable(bundle_root / 'current.json', json.dumps({'hash': digest, 'protocol': 1}).encode())
    backend = destination / 'backend/archive_backend'
    write_immutable(backend / 'service.py', patch_service(baseline['service_source']).encode())
    loader = replace_once(baseline['bundle_loader'], '        data=json.loads(raw);self.configs=data["configs"]\n',
        '        data=json.loads(raw);self.configs=data["configs"]\n'
        '        from .config_compatibility import parse\n'
        '        self.compatible_config_hashes = parse(data)\n')
    write_immutable(backend / 'bundle.py', loader.encode())
    write_immutable(backend / 'config_compatibility.py', (root / 'server/archive_backend/config_compatibility.py').read_bytes())
    Bundle(bundle_root / digest)
    return {'hash': digest, 'previous_hash': previous, 'milestones': len(current_ids),
            'changed_configs': ['archive_endless_achievements'],
            'changed_sources': ['systems/archive_settlement.lua', 'systems/archive_endless_rewards.lua']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = build(json.loads(args.baseline.read_text(encoding='utf-8')), args.output)
    print(json.dumps(result, sort_keys=True))
