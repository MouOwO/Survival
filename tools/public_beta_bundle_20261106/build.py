"""Derive a narrow immutable public-beta bundle without switching any pointer.

Build-only costs: O(B + N) once, where B is the parent bundle/source byte count
and N is the 20 existing benefit tiers. Runtime rules retain direct tier lookup;
this tool adds no polling, HTTP, database, native or gameplay calls.
"""
from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import Bundle, read_csv
from archive_backend.config_compatibility import parse

CSV = 'data/csv/存档系统/archive_benefit_rewards.csv'
LUA = 'scripts/vscripts/systems/archive_benefit_rewards.lua'
SERVICE = 'server/archive_backend/service.py'
SOURCE_NAME = 'systems/archive_benefit_rewards.lua'
RULE = {'reward_id': 'public_beta_login', 'track': 'public_beta_login',
        'period': 'day', 'metric': 'minutes', 'required': 0,
        'base_item_ids': ['special_lottery_ticket'], 'base_counts': ['2'],
        'enabled': True, 'monthly_only': False, 'auto_claim': False,
        'starts_at': 0, 'ends_at': 0}


def need(ok, code):
    if not ok:
        raise ValueError(code)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode('utf8')


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def git_blob(revision, path):
    need(bool(re.fullmatch('[0-9a-f]{40}', revision)), 'immutable_source_revision_required')
    raw = subprocess.check_output(['git', '--no-replace-objects', '-C', str(ROOT),
                                   'show', revision + ':' + path])
    return raw.replace(b'\r\n', b'\n')


def commands_from_service(raw):
    tree = ast.parse(raw)
    values = [node.value for node in tree.body if isinstance(node, ast.Assign)
              and any(isinstance(target, ast.Name) and target.id == 'FIELDS'
                      for target in node.targets)]
    need(len(values) == 1 and isinstance(values[0], ast.Dict), 'command_fields_source_required')
    names = [ast.literal_eval(key) for key in values[0].keys]
    need(names and all(isinstance(name, str) and re.fullmatch('[a-z_]+', name)
                       for name in names), 'command_names_invalid')
    return sorted(names)


def narrow_source(parent, source):
    """Reject changes beyond the reviewed public-beta query and activity gate."""
    constant = 'local PUBLIC_BETA_TIER = "public_beta_login"\n'
    begin = 'local function active(row, timestamp)\n'
    end = 'local function event_time(command)\n'
    gate = '    if not active(row, timestamp) then return false,"活动尚未开始或已结束" end\n'
    need(source.count(constant) == source.count(begin) == source.count(end)
         == source.count(gate) == 1, 'public_beta_source_anchors_invalid')
    first, last = source.index(begin), source.index(end)
    need(first < last and 'function M.public_beta_snapshot(' in source[first:last],
         'public_beta_snapshot_required')
    stripped = (source[:first] + source[last:]).replace(constant, '', 1).replace(gate, '', 1)
    need(stripped == parent, 'unrelated_benefit_source_change')


def derive(parent, parent_hash, source_revision, csv_config, csv_sha, lua_source,
           lua_sha, command_names, service_sha):
    need(digest(canonical(parent)) == parent_hash, 'canonical_parent_hash_mismatch')
    original = parent['configs']['archive_benefit_rewards']
    need(original['key'] == csv_config['key'] == 'reward_id', 'benefit_key_changed')
    old = {row['reward_id']: row for row in original['rows']}
    new = {row['reward_id']: row for row in csv_config['rows']}
    need(len(old) == len(original['rows']) and len(new) == len(csv_config['rows']),
         'duplicate_benefit_tier')
    need('public_beta_login' not in old and set(new) == set(old) | {'public_beta_login'},
         'exact_one_public_beta_tier_required')
    need(all(new[key] == row for key, row in old.items()), 'existing_benefit_rule_changed')
    need(new['public_beta_login'] == RULE, 'approved_public_beta_rule_required')
    narrow_source(parent['sources'][SOURCE_NAME], lua_source)
    need(digest(lua_source.encode('utf8')) == lua_sha, 'benefit_source_pin_mismatch')
    result = copy.deepcopy(parent)
    # Preserve ordering and exact values of every old tier.
    result['configs']['archive_benefit_rewards']['rows'].append(copy.deepcopy(RULE))
    result['sources'][SOURCE_NAME] = lua_source
    result['csv_hashes'][CSV] = csv_sha
    rules = result.setdefault('compatible_config_hashes', {})
    need(parent_hash not in rules, 'parent_compatibility_already_present')
    # No benefit reducer upgrade: old sessions keep their recorded rules and
    # completed receipts. The new client must explicitly bind the new hash.
    rules[parent_hash] = {'commands': sorted(command_names), 'upgrade_commands': []}
    parse(result)
    result['public_beta_delivery'] = {
        'recipe': 'public-beta-tier-only-v1', 'parent_hash': parent_hash,
        'source_revision': source_revision,
        'source_sha256': {CSV: csv_sha, LUA: lua_sha, SERVICE: service_sha},
        'changed_configs': ['archive_benefit_rewards'],
        'changed_sources': [SOURCE_NAME], 'new_tier': 'public_beta_login',
        'client_binding_required': True,
    }
    return result


def prepare(parent_directory, source_revision):
    bundle = Bundle(Path(parent_directory))
    parent_raw = (bundle.directory / 'bundle.json').read_bytes()
    parent = json.loads(parent_raw)
    csv_raw = git_blob(source_revision, CSV)
    lua_raw = git_blob(source_revision, LUA)
    service_raw = git_blob(source_revision, SERVICE)
    with tempfile.TemporaryDirectory(prefix='public-beta-csv-') as directory:
        path = Path(directory) / 'archive_benefit_rewards.csv'
        path.write_bytes(csv_raw)
        config = read_csv(path)
    result = derive(parent, bundle.hash, source_revision, config, digest(csv_raw),
                    lua_raw.decode('utf8'), digest(lua_raw),
                    commands_from_service(service_raw), digest(service_raw))
    return result


def write_candidate(document, output):
    raw = canonical(document)
    checksum = digest(raw)
    root = Path(output).resolve()
    directory = root / checksum
    need(not directory.exists(), 'exclusive_candidate_directory_required')
    directory.mkdir(parents=True)
    for name, source in document['sources'].items():
        relative = PurePosixPath(name)
        need(not relative.is_absolute() and '..' not in relative.parts,
             'bundle_source_path_invalid')
        target = directory / name
        need(target.resolve().is_relative_to(directory), 'bundle_source_outside_candidate')
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('x', encoding='utf8', newline='\n') as stream:
            stream.write(source)
    with (directory / 'bundle.json').open('xb') as stream:
        stream.write(raw)
    verified = Bundle(directory)
    need(verified.hash == checksum, 'new_bundle_verification_failed')
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parent', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    need(not args.report.exists(), 'exclusive_report_required')
    document = prepare(args.parent, args.source_revision)
    directory = write_candidate(document, args.output)
    report = dict(status='IMMUTABLE_PUBLIC_BETA_CANDIDATE_NOT_DEPLOYED',
                  bundle_hash=directory.name, directory=str(directory),
                  binding=document['public_beta_delivery'],
                  existing_tiers_unchanged=True, game_config_written=False,
                  current_pointer_written=False, deployed=False,
                  http_requests=0, database_writes=0)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open('x', encoding='utf8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
