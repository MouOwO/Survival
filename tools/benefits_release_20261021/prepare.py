"""Build a reviewable benefits candidate by applying only recorded task deltas.

No deployment, active pointers, database or game config is changed by this file.
The online immutable bundle/backend remain the base; existing dirty edits are
never copied wholesale. Conflicting three-way merges stop for review.
"""
from __future__ import annotations
import argparse
import ast
import copy
import csv
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / 'tmp/benefits_20261021'
OUT = TASK / 'release_candidate'
BASE = TASK / 'online_baseline'
sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def write(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)


def text(path):
    return path.read_text(encoding='utf-8-sig').replace('\r\n', '\n')


def merge(parent, before, after, name):
    if before == after:
        return parent
    if parent == before:
        return after
    with tempfile.TemporaryDirectory(prefix='benefits-merge-', dir=TASK) as directory:
        files = [Path(directory) / item for item in ('online', 'before', 'task')]
        for path, source in zip(files, (parent, before, after)):
            path.write_text(source, encoding='utf-8', newline='\n')
        result = subprocess.run(['git', '-c', 'core.safecrlf=false', 'merge-file', '-p', *map(str, files)],
                                cwd=ROOT, capture_output=True)
    raw = result.stdout.decode('utf-8')
    if result.returncode:
        write(OUT / 'conflicts' / name, raw.encode())
        raise ValueError('task_delta_conflict:' + name)
    return raw


def load_csv(path):
    lines = text(path).splitlines()
    header = next(csv.reader([lines[0]]))
    types = next(line[7:].split(',') for line in lines if line.startswith('#types:'))
    assert len(header) == len(types), 'csv_types_invalid'
    rows = []
    for source in csv.DictReader(line for line in lines if not line.startswith('#')):
        row = {}
        for key, kind in zip(header, types):
            value = (source[key] or '').strip()
            if not value:
                continue
            if kind == 'number':
                value = float(value)
                if value.is_integer(): value = int(value)
            elif kind == 'boolean':
                assert value.lower() in {'1','0','true','false','yes','no','on','off'}, 'csv_boolean_invalid'
                value = value.lower() in {'1','true','yes','on'}
            elif kind == 'list':
                value = [item.strip() for item in value.split('|' if '|' in value else ',') if item.strip()]
            row[key] = value
        rows.append(row)
    return {'key': header[0], 'rows': rows}


def table_delta(parent, before, after, name):
    if before is None:
        assert parent is None, 'new_table_already_online:' + name
        return copy.deepcopy(after)
    assert parent is not None and parent['key'] == before['key'] == after['key'], 'table_key_changed:' + name
    result = copy.deepcopy(parent)
    key = result['key']
    current = {row[key]: row for row in result['rows']}
    old = {row[key]: row for row in before['rows']}
    new = {row[key]: row for row in after['rows']}
    for identity in old.keys() | new.keys():
        if old.get(identity) == new.get(identity): continue
        if identity not in old:
            assert identity not in current, 'table_add_conflict:' + name
            current[identity] = copy.deepcopy(new[identity])
        elif identity not in new:
            assert current.get(identity) == old[identity], 'table_delete_conflict:' + name
            del current[identity]
        else:
            assert identity in current, 'table_row_missing:' + name
            for field in old[identity].keys() | new[identity].keys():
                if old[identity].get(field) == new[identity].get(field): continue
                assert current[identity].get(field) == old[identity].get(field), 'table_field_conflict:' + name + ':' + str(identity) + ':' + field
                if field in new[identity]: current[identity][field] = copy.deepcopy(new[identity][field])
                else: current[identity].pop(field, None)
    order = [row[key] for row in result['rows'] if row[key] in current]
    order += [row[key] for row in after['rows'] if row[key] not in order]
    result['rows'] = [current[identity] for identity in order]
    return result


def dump_csv(configuration, template):
    lines = text(template).splitlines()
    header = next(csv.reader([lines[0]]))
    types = next(line[7:].split(',') for line in lines if line.startswith('#types:'))
    stream = io.StringIO(newline='')
    writer = csv.writer(stream, lineterminator='\n')
    writer.writerow(header); stream.write('#types:' + ','.join(types) + '\n')
    for row in configuration['rows']:
        values = []
        for field, kind in zip(header, types):
            value = row.get(field, '')
            if kind == 'list' and isinstance(value, list): value = '|'.join(map(str, value))
            if isinstance(value, bool): value = '1' if value else '0'
            values.append(value)
        writer.writerow(values)
    return stream.getvalue().encode()


def baseline_for(name, manifests):
    if name == 'server/archive_backend/daily_limits.py':
        corrected = TASK / 'root_before' / name
        assert corrected.is_file(), 'corrected_daily_limits_baseline_required'
        return text(corrected)
    choices = []
    for directory, manifest in manifests:
        entry = manifest.get(name)
        if entry is None: continue
        exists = entry.get('exists', True) if isinstance(entry, dict) else True
        if exists:
            path = directory / name
            assert path.is_file(), 'task_baseline_missing:' + name
            choices.append(text(path))
    assert not choices or all(value == choices[0] for value in choices), 'task_baselines_disagree:' + name
    return choices[0] if choices else None


def bundle_module_delta(parent,before,after):
    def node(source):
        return next(item for item in ast.parse(source).body if isinstance(item,ast.Assign)
                    and any(isinstance(target,ast.Name) and target.id=='MODULES' for target in item.targets))
    def replace(source,item,value):
        lines=source.splitlines(keepends=True)
        return ''.join(lines[:item.lineno-1])+value+''.join(lines[item.end_lineno:])
    old,new,online=node(before),node(after),node(parent)
    assert replace(before,old,'')==replace(after,new,''),'unexpected_bundle_builder_task_delta'
    old_values,new_values,values=map(lambda item:ast.literal_eval(item.value),(old,new,online))
    assert set(old_values)<=set(new_values),'worker_module_removed'
    values=tuple(values)+tuple(value for value in new_values if value not in old_values and value not in values)
    return replace(parent,online,'MODULES = '+repr(values)+'\n')


def commerce_delta(parent, manifests):
    sys.path.insert(0, str(ROOT / 'server'))
    from payment_backend.csv_catalog import SOURCES
    from payment_backend.ucoin_catalog import COMMERCE_TABLES
    from payment_backend.commerce_bundles import compile_commerce
    path = 'server/payment_backend/commerce_bundles.py'
    source = baseline_for(path, manifests)
    assert source is not None, 'commerce_compiler_baseline_missing'
    import types
    old = types.ModuleType('payment_backend.benefits_before_commerce_bundles')
    old.__package__ = 'payment_backend'
    exec(compile(source, 'benefits_before_commerce_bundles.py', 'exec'), old.__dict__)
    def compile_one(before):
        def read(relative):
            original = baseline_for(relative, manifests) if before else None
            return original if original is not None else text(ROOT / relative)
        tables = {name: read('data/csv/商城兑换系统/' + name + '.csv') for name in COMMERCE_TABLES}
        references = {name: read('data/csv/' + name) for name in SOURCES}
        category = read('data/csv/商城支付系统/payment_categories.csv')
        return {'key': 'sku', 'rows': (old.compile_commerce if before else compile_commerce)(tables, references, category)['products']}
    return table_delta(parent, compile_one(True), compile_one(False), 'commerce_catalog')


def build(owner_files):
    baseline = json.loads((BASE / 'baseline.json').read_bytes())
    raw = (BASE / 'bundle.json').read_bytes()
    assert sha(raw) == baseline['archive_bundle'], 'online_bundle_digest_invalid'
    parent = json.loads(raw); candidate = copy.deepcopy(parent)
    manifests = [(TASK / name, json.loads((TASK / name / 'manifest.json').read_bytes()))
                 for name in ('backend_before', 'items_before')]
    files = sorted(set(owner_files)); changed_sources = []; changed_configs = []; changed_python = []
    backend = OUT / 'backend'
    for path in (BASE / 'backend').rglob('*.py'):
        relative = path.relative_to(BASE / 'backend')
        write(backend / relative, path.read_bytes())
    for name in files:
        source = ROOT / name
        assert source.is_file(), 'owner_file_missing:' + name
        before = baseline_for(name, manifests)
        after = text(source)
        if (name.startswith('server/archive_backend/') or name.startswith('server/fishing_api_overrides/')) and name.endswith('.py'):
            relative = name.removeprefix('server/').replace('fishing_api_overrides/', 'fishing_api/')
            online_path = BASE / 'backend' / relative
            online = text(online_path) if online_path.is_file() else ''
            if name.startswith('server/fishing_api_overrides/'):
                # This canonical override is authored directly from the pinned
                # online source; a separate original is preserved by its owner.
                before = online
            if not online_path.is_file():
                assert before is None, 'new_python_module_already_in_baseline:' + name
                updated = after
            else:
                assert before is not None, 'python_baseline_missing:' + name
                updated = bundle_module_delta(online,before,after) if name=='server/archive_backend/bundle.py' else merge(online, before, after, name)
            ast.parse(updated)
            write(backend / relative, updated.encode())
            if updated != online: changed_python.append('backend/' + relative)
        elif name.startswith('scripts/vscripts/'):
            relative = name.removeprefix('scripts/vscripts/')
            if relative not in parent['sources']:
                # Only new modules explicitly loaded by the worker may be added.
                if relative not in {'systems/archive_benefit_rewards.lua', 'systems/archive_stackable_items.lua'}: continue
                assert before is None, 'new_worker_module_baseline_exists:' + name
                updated = after
            else:
                assert before is not None, 'lua_baseline_missing:' + name
                updated = merge(parent['sources'][relative], before, after, name)
            if updated != parent['sources'].get(relative):
                candidate['sources'][relative] = updated; changed_sources.append(relative)
        elif name.startswith('data/csv/') and name.endswith('.csv'):
            key = source.stem
            if key not in parent['configs'] and key not in {'archive_benefit_rewards', 'archive_stackable_items'}: continue
            before_config = None
            if before is not None:
                for directory, manifest in manifests:
                    if name in manifest and (directory / name).is_file():
                        before_config = load_csv(directory / name); break
            updated = table_delta(parent['configs'].get(key), before_config, load_csv(source), key)
            if updated != parent['configs'].get(key):
                candidate['configs'][key] = updated; changed_configs.append(key)
                csv_raw = dump_csv(updated, source)
                write(OUT / 'csv' / name, csv_raw)
                candidate['csv_hashes'][name] = sha(csv_raw)
    updated_commerce = commerce_delta(parent['configs']['commerce_catalog'], manifests)
    if updated_commerce != parent['configs']['commerce_catalog']:
        candidate['configs']['commerce_catalog'] = updated_commerce; changed_configs.append('commerce_catalog')
    # This is an offline compiler only. Payment source/process/catalog/order
    # rows are not overlaid or restarted by this archive publication.
    # Existing hashes keep their existing compatibility commands; old clients do
    # not receive the newly introduced benefit_claim command via an alias.
    aliases = candidate.setdefault('compatible_config_hashes', {})
    old_commands = sorted({kind for rule in aliases.values() for kind in rule['commands']})
    aliases.setdefault(baseline['archive_bundle'], {'commands': old_commands, 'upgrade_commands': []})
    raw = canonical(candidate); digest = sha(raw)
    directory = OUT / 'bundles' / digest
    write(directory / 'bundle.json', raw)
    for name, value in candidate['sources'].items(): write(directory / name, value.encode())
    disabled = copy.deepcopy(candidate)
    for row in disabled['configs']['archive_benefit_rewards']['rows']: row['enabled'] = False
    disabled['compatible_config_hashes'][digest] = {'commands': old_commands, 'upgrade_commands': []}
    disabled_raw = canonical(disabled); disabled_hash = sha(disabled_raw)
    rollback_directory = OUT / 'bundles' / disabled_hash
    write(rollback_directory / 'bundle.json', disabled_raw)
    for name, value in disabled['sources'].items(): write(rollback_directory / name, value.encode())
    # Only this reviewed pair shares byte-identical lottery configs/reducers.
    # Keep all historical guard pairs and permit in-flight receipts across a
    # safe benefits shutdown without admitting older unique-item reducers.
    unique_path=backend/'archive_backend/unique_points.py'
    source=text(unique_path)
    marker='def legacy_lottery_error(current_hash, recorded_hash, kind):'
    assert source.count(marker)==1 and 'IDENTICAL_LOTTERY_UPDATES' in source,'unique_compatibility_anchor_changed'
    proof_pairs={(digest,disabled_hash),(disabled_hash,digest)}
    addition='# Exact reviewed safe-shutdown pair: only benefit enabled flags/client alias differ.\nIDENTICAL_LOTTERY_UPDATES = IDENTICAL_LOTTERY_UPDATES | frozenset('+repr(proof_pairs)+')\n\n\n'
    source=source.replace(marker,addition+marker,1);ast.parse(source);write(unique_path,source.encode())
    report = dict(parent_release=baseline['archive_release'], parent_bundle=baseline['archive_bundle'],
        candidate_hash=digest, rollback_hash=disabled_hash, changed_sources=changed_sources,
        changed_configs=changed_configs, changed_python=changed_python, owner_files=files,
        backend_directory=str(backend), bundle_directory=str(directory), rollback_directory=str(rollback_directory),
        rollback_keeps_stackable=True, payment_files_changed=False)
    write(OUT / 'report.json', canonical(report))
    print(json.dumps(report, ensure_ascii=False))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owner-files', type=Path, required=True)
    args = parser.parse_args()
    build(json.loads(args.owner_files.read_bytes()))
