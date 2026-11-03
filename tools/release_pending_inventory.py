"""Read-only Workshop pending inventory; never an upload or publication claim.

One invocation indexes both Git trees O(N), unions every retained deferral, and
streams only pending/bound blobs up to explicit byte budgets. There is no
watcher, game timer, SDK, network, journal write, Git mutation, or deletion.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONTENT = Path('D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival')
BASELINE = ROOT/'tools/shared_boss_portrait_release_20261101/source_baseline_0104.json'
BASELINE_SHA256 = '3a60ddab9a93b58fa936e789f1a9d2008d39ed7eca9545487e1f40bf32219ee3'
PLAN = ROOT/'output/lottery_redemption_release_20261103/plan_v01.json'
PLAN_SHA256 = '40a011eef4b98b2173de3718a5eb33a5f0aa27cc020e4eb71ee6ee404b8a6d59'
PARENT_MANIFEST = Path('D:/Survival_发布候选/20261101_ws4_five_account_admission_v01_view/_release_manifest.json')
BASELINE_REGISTRY = ROOT/'output/release_baselines/registry.json'
RUNTIME_ROOTS = frozenset(('scripts', 'panorama', 'materials', 'models', 'particles',
                           'sounds', 'soundevents', 'resource', 'maps', 'data', 'art'))
COMPILED_SUFFIXES = frozenset(('.vjs_c', '.vcss_c', '.vxml_c', '.vtex_c', '.vsvg_c', '.vmdl_c',
                               '.vpcf_c', '.vsnd_c', '.vmat_c', '.vsndevts_c', '.vpk'))
POINTER = re.compile(rb'version https://git-lfs.github.com/spec/v1\r?\n'
                     rb'oid sha256:([a-f0-9]{64})\r?\nsize ([0-9]{1,16})\r?\n?\Z')
SHA256 = re.compile(r'[a-f0-9]{64}\Z')
OID = re.compile(r'[a-f0-9]{40,64}\Z')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def relevant(path):
    parts = PurePosixPath(path).parts
    return (path == 'addoninfo.txt' or bool(parts and parts[0] in RUNTIME_ROOTS)) and not any(
        part in {'tests', '__pycache__', 'node_modules'} or part.startswith('.') for part in parts)


def _entry(value):
    return (value.get('mode'), value.get('kind'), value.get('oid')) if value else None


def _deferred(values):
    if isinstance(values, dict):
        values = values.values()
    return list(values or ())


def pending_source_keys(baseline_inventory, head_inventory, *deferrals):
    """Git differences are insufficient: unchanged-OID deferrals are included."""
    keys = set()
    for role in ('game', 'content'):
        old, current = baseline_inventory.get(role, {}), head_inventory.get(role, {})
        keys.update((role, path) for path in set(old) | set(current)
                    if relevant(path) and _entry(old.get(path)) != _entry(current.get(path)))
    for group in deferrals:
        keys.update((row['repo'], row['path']) for row in _deferred(group))
    return keys


def _resource(role, path, parent_rows):
    """Return a candidate mapping, not proof of compilation or production fit."""
    suffix = PurePosixPath(path).suffix.lower()
    if role == 'game':
        if path.startswith('panorama/src/') and suffix == '.svg':
            return str(PurePosixPath(path.replace('panorama/src/', 'panorama/', 1)).with_suffix('.vsvg_c')), 'author'
        if path.startswith('panorama/src/') and suffix in {'.js', '.css', '.xml'}:
            output = path.replace('panorama/src/', 'panorama/', 1)
            return str(PurePosixPath(output).with_suffix({'.js': '.vjs_c', '.css': '.vcss_c', '.xml': '.vxml_c'}[suffix])), 'author'
        if path in parent_rows or (PurePosixPath(path).parts[0] not in {'data', 'art'}
                                   and suffix in COMPILED_SUFFIXES | {'.lua', '.txt', '.gameevents'}):
            return path, 'compiled' if suffix in COMPILED_SUFFIXES else 'identity'
        if path == 'addoninfo.txt':
            return path, 'identity'
    if role == 'content':
        if path.startswith('panorama/') and suffix == '.svg':
            return str(PurePosixPath(path).with_suffix('.vsvg_c')), 'author'
        if path.startswith('panorama/') and suffix in {'.js', '.css', '.xml'}:
            return str(PurePosixPath(path).with_suffix({'.js': '.vjs_c', '.css': '.vcss_c', '.xml': '.vxml_c'}[suffix])), 'author'
        if path.startswith('maps/') and suffix == '.vmap':
            return str(PurePosixPath(path).with_suffix('.vpk')), 'author'
        if suffix in {'.vmat', '.vmdl', '.vpcf', '.vsndevts'}:
            return path + '_c', 'author'
    return None, 'unknown'


def classify_inventory(*, baseline_inventory, head_inventory, parent_manifest,
                       deferred_sources=(), deferred_unpublished_sources=(),
                       blob_facts=None, bindings=(), dirty=(), production_resources=()):
    """Pure conservative classification. Facts contain hashes, never raw bytes.

    bindings: {resource, output:{repo,path}, inputs:[{repo,path,sha256}],
               artifact_sha256}. A valid binding proves bytes, not publication.
    """
    facts = blob_facts or {}
    parent_rows = {row['path']: row for row in parent_manifest.get('files', ())}
    history = {}
    for label, values in (('historical', deferred_sources), ('unpublished0201', deferred_unpublished_sources)):
        for item in _deferred(values):
            history.setdefault((item['repo'], item['path']), []).append(label)
    by_source = {}
    for binding in bindings:
        for item in list(binding.get('inputs', ())) + [binding['output']]:
            by_source.setdefault((item['repo'], item['path']), []).append(binding)
    production = set(production_resources) | {'addoninfo.txt'}
    for row in _deferred(deferred_sources):
        if any(word in str(row.get('original_classification', '')) for word in ('PRODUCTION_OVERRIDE', 'ADMISSION_THREE_BLOCK')):
            production.add(row['path'])
    rows = []
    for role, path in sorted(pending_source_keys(baseline_inventory, head_inventory,
                                                deferred_sources, deferred_unpublished_sources)):
        old = baseline_inventory.get(role, {}).get(path)
        current = head_inventory.get(role, {}).get(path)
        fact = facts.get(role + ':' + path, {})
        resource, kind = _resource(role, path, parent_rows)
        candidates = by_source.get((role, path), ())
        binding = candidates[0] if len(candidates) == 1 else None
        if binding:
            resource = binding['resource']
        parent = parent_rows.get(resource)
        output_fact = fact
        binding_valid = False
        if binding:
            output = binding['output']
            output_fact = facts.get(output['repo'] + ':' + output['path'], {})
            binding_valid = bool(binding.get('inputs')) and all(
                SHA256.fullmatch(str(source.get('sha256', ''))) and
                facts.get(source['repo'] + ':' + source['path'], {}).get('sha256') == source['sha256']
                for source in binding.get('inputs', ())) and bool(SHA256.fullmatch(str(binding.get('artifact_sha256', '')))) and output_fact.get('sha256') == binding.get('artifact_sha256')
        status, blocking = 'UNMAPPED_SOURCE_PENDING', True
        if current is None:
            status = 'RUNTIME_REMOVAL_PENDING' if resource in parent_rows else 'SOURCE_REMOVED_REQUIRES_RUNTIME_DECISION'
        elif current.get('kind') != 'blob' or current.get('mode') not in {'100644', '100755'}:
            status = 'NON_REGULAR_GIT_ENTRY'
        elif fact.get('hash_state') not in (None, 'VERIFIED'):
            status = str(fact['hash_state'])
        elif resource in production:
            status = 'PRODUCTION_TRANSFORM_REQUIRED'
        elif path.startswith('scripts/vscripts/config/generated/') and not binding:
            status = 'GENERATED_BINDING_REQUIRED'
        elif kind == 'author' and not binding_valid:
            status = 'UNCOMPILED_BINDING_REQUIRED'
        elif (kind == 'compiled' or binding) and not binding_valid:
            status = 'UNBOUND_COMPILED_ARTIFACT'
        elif resource and (kind == 'identity' or binding_valid):
            digest = output_fact.get('sha256')
            if not SHA256.fullmatch(str(digest or '')):
                status = 'HASH_UNAVAILABLE'
            elif parent and parent['sha256'] == digest:
                if (role, path) in history:
                    status = 'HISTORICAL_REVIEW_REQUIRED_PARENT_BYTES_MATCH'
                else:
                    status, blocking = 'PARENT_BYTES_MATCH', False
            else:
                status, blocking = ('PENDING_RUNTIME_UPDATE' if parent else 'PENDING_RUNTIME_ADD'), False
        rows.append(dict(source=dict(repo=role, path=path, head_oid=(current or {}).get('oid'),
                                     baseline_oid=(old or {}).get('oid')),
                         resource=resource, status=status, blocking=blocking,
                         history=history.get((role, path), []),
                         requires_review=bool(history.get((role, path))),
                         candidate=dict(sha256=output_fact.get('sha256'), bytes=output_fact.get('bytes'),
                                        git_sha256=fact.get('git_sha256'), lfs=output_fact.get('lfs', False),
                                        lfs_declared_sha256=output_fact.get('lfs_declared_sha256')),
                         parent_sha256=parent.get('sha256') if parent else None))
    dirty_rows = [{**row, 'runtime_related': relevant(row['path']),
                   'status': 'DIRTY_LOCAL_RUNTIME' if relevant(row['path']) else 'DIRTY_NON_WORKSHOP_PATH',
                   'copied_or_hashed': False} for row in dirty]
    statuses = dict(sorted(Counter(row['status'] for row in rows).items()))
    pending = [row for row in rows if row['status'] != 'PARENT_BYTES_MATCH']
    blocked = [row for row in rows if row['blocking']]
    runtime_dirty = sum(row['runtime_related'] for row in dirty_rows)
    return dict(schema=1, kind='READ_ONLY_ALL_PENDING_WORKSHOP_INVENTORY',
                publication_status='LOCAL_INVENTORY_ONLY_NO_PUBLICATION_CLAIM', rows=rows, dirty=dirty_rows,
                counts=dict(rows=len(rows), pending=len(pending), blocking=len(blocked),
                            historical_sources=len(history), dirty_total=len(dirty_rows), dirty_runtime=runtime_dirty,
                            pending_resources=len({row['resource'] for row in pending if row['resource']}), by_status=statuses),
                ready_for_full_build=not blocked and not runtime_dirty, ready_for_publication=False)


def parse_lfs_pointer(raw):
    match = POINTER.fullmatch(raw)
    return (match[1].decode('ascii'), int(match[2])) if match else None


class HashBudget:
    def __init__(self, total=256 * 1024 * 1024, per_blob=64 * 1024 * 1024):
        self.total, self.per_blob, self.used = total, per_blob, 0

    def reserve(self, size):
        if size > self.per_blob or self.used + size > self.total:
            return False
        self.used += size
        return True


def _git(root, *args, counts):
    counts['git_processes'] += 1
    result = subprocess.run(['git', '-c', 'safe.directory=' + root.resolve().as_posix(),
                             '--no-replace-objects', '-C', str(root), *args], capture_output=True,
                            timeout=30, env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})
    if result.returncode:
        raise RuntimeError('read_only_git_command_failed')
    if len(result.stdout) > 32 * 1024 * 1024:
        raise RuntimeError('git_metadata_budget_exceeded')
    return result.stdout


def git_tree(root, counts, revision='HEAD'):
    raw = _git(root, 'ls-tree', '-rlz', '--full-tree', revision, counts=counts)
    counts['git_tree_calls'] += 1
    tree = {}
    for item in raw.split(b'\0'):
        if not item:
            continue
        header, name = item.split(b'\t', 1)
        mode, kind, oid, size = header.decode('ascii').split()
        path = name.decode('utf8')
        if path in tree or path.startswith('/') or '\\' in path or '..' in PurePosixPath(path).parts:
            raise RuntimeError('unsafe_git_tree_path')
        tree[path] = dict(mode=mode, kind=kind, oid=oid, bytes=int(size) if size.isdigit() else None)
    return tree


def git_dirty(root, role, counts):
    parts = _git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all', counts=counts).split(b'\0')
    rows, index = [], 0
    while index < len(parts):
        item = parts[index]; index += 1
        if not item:
            continue
        status, path = item[:2].decode('ascii'), item[3:].decode('utf8')
        row = dict(repo=role, path=path, change=status)
        if 'R' in status or 'C' in status:
            row['original_path'] = parts[index].decode('utf8'); index += 1
        rows.append(row)
    return rows


def _read_exact(stream, count):
    chunks = []
    while count:
        chunk = stream.read(min(count, 65536))
        if not chunk:
            raise RuntimeError('git_batch_truncated')
        chunks.append(chunk); count -= len(chunk)
    return b''.join(chunks)


def read_git_facts(root, tree, paths, budget, counts):
    """One cat-file process per repo, bounded streaming; never invokes LFS fetch."""
    common = Path(_git(root, 'rev-parse', '--git-common-dir', counts=counts).decode('utf8').strip())
    if not common.is_absolute():
        common = root / common
    lfs_root = (common / 'lfs/objects').resolve()
    args = ['git', '-c', 'safe.directory=' + root.resolve().as_posix(), '--no-replace-objects',
            '-C', str(root), 'cat-file', '--batch']
    counts['git_processes'] += 1; counts['git_fact_batches'] += 1
    proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})
    result, by_oid = {}, {}
    try:
        for path in sorted(paths):
            entry = tree.get(path)
            if not entry or entry.get('kind') != 'blob' or entry.get('mode') not in {'100644', '100755'}:
                continue
            oid, size = entry['oid'], entry.get('bytes')
            if not OID.fullmatch(oid) or not isinstance(size, int):
                raise RuntimeError('invalid_git_blob_metadata')
            if oid in by_oid:
                result[path] = by_oid[oid]; continue
            if not budget.reserve(size):
                fact = dict(hash_state='HASH_BUDGET_EXCEEDED', bytes=size, sha256=None)
                counts['hash_budget_skips'] += 1
                result[path] = by_oid[oid] = fact; continue
            proc.stdin.write((oid + '\n').encode('ascii')); proc.stdin.flush()
            header = proc.stdout.readline(256).decode('ascii').strip().split()
            if header != [oid, 'blob', str(size)]:
                raise RuntimeError('git_batch_object_mismatch')
            counts['git_blob_requests'] += 1
            prefix = _read_exact(proc.stdout, min(size, 512))
            digest = hashlib.sha256(prefix); remaining = size - len(prefix)
            while remaining:
                chunk = _read_exact(proc.stdout, min(remaining, 65536)); digest.update(chunk); remaining -= len(chunk)
            if proc.stdout.read(1) != b'\n':
                raise RuntimeError('git_batch_delimiter_missing')
            counts['git_bytes_streamed'] += size
            fact = dict(hash_state='VERIFIED', git_sha256=digest.hexdigest(), sha256=digest.hexdigest(), bytes=size, lfs=False)
            pointer = parse_lfs_pointer(prefix) if size <= 512 else None
            if pointer:
                lfs_oid, real_size = pointer
                fact.update(lfs=True, lfs_declared_sha256=lfs_oid, sha256=None, bytes=real_size)
                target = lfs_root / lfs_oid[:2] / lfs_oid[2:4] / lfs_oid
                if not target.is_file() or target.is_symlink() or not target.resolve().is_relative_to(lfs_root):
                    fact['hash_state'] = 'LFS_OBJECT_MISSING'
                elif target.stat().st_size != real_size:
                    fact['hash_state'] = 'LFS_OBJECT_SIZE_MISMATCH'
                elif not budget.reserve(real_size):
                    fact['hash_state'] = 'HASH_BUDGET_EXCEEDED'; counts['hash_budget_skips'] += 1
                else:
                    with target.open('rb') as stream:
                        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
                    counts['lfs_files_read'] += 1; counts['lfs_bytes_streamed'] += real_size
                    if actual != lfs_oid:
                        fact['hash_state'] = 'LFS_OBJECT_HASH_MISMATCH'
                    else:
                        fact['sha256'] = actual
            result[path] = by_oid[oid] = fact
    finally:
        proc.stdin.close()
        try:
            code = proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait(); raise RuntimeError('local_git_batch_did_not_exit')
        proc.stdout.close(); proc.stderr.close()
    if code:
        raise RuntimeError('local_git_batch_failed')
    return result


def _read_json(path, expected_sha=None):
    if path.stat().st_size > 32 * 1024 * 1024:
        raise RuntimeError('control_json_budget_exceeded')
    raw = path.read_bytes()
    if expected_sha and sha(raw) != expected_sha:
        raise RuntimeError('fixed_baseline_or_plan_hash_changed')
    return json.loads(raw)


def plan_bindings(plan):
    bindings = []
    for source, pin in plan.get('source_artifact_pins', {}).items():
        resource, kind = _resource('game', source, {})
        if not resource or kind != 'author':
            continue
        inputs = [dict(repo='game', path=source, sha256=pin['git_blob']['sha256'])]
        mirror = pin.get('content_mirror')
        if mirror:
            inputs.append(dict(repo='content', path=mirror['path'], sha256=mirror['sha256']))
        bindings.append(dict(resource=resource, output=dict(repo='game', path=resource), inputs=inputs,
                             artifact_sha256=pin['compiled_artifact_sha256']))
    return bindings


def _registered_path(path):
    return (isinstance(path, str) and path.startswith('output/') and path.endswith('.json')
            and '\\' not in path and ':' not in path
            and all(part not in ('', '.', '..') for part in path.split('/')))


def _registered_json(root, relative, digest):
    if not _registered_path(relative) or not SHA256.fullmatch(str(digest or '')):
        raise RuntimeError('registered_baseline_reference_invalid')
    target = root / relative
    if not target.resolve().is_relative_to((root/'output').resolve()):
        raise RuntimeError('registered_control_outside_output')
    for item in (target, *target.parents):
        if item == root:
            break
        if item.is_symlink() or (hasattr(item, 'is_junction') and item.is_junction()):
            raise RuntimeError('registered_control_reparse_point_refused')
    return _read_json(target, digest)


def _verify_sparse_rollforward(previous, baseline, report):
    """Ensure a registered partial delivery did not silently replace all HEAD."""
    def need(value, code):
        if not value:
            raise RuntimeError(code)
    lineage = report.get('git_runtime_lineage', {})
    need(report.get('baseline_release_sequence') == previous.get('parent_sequence')
         and report.get('baseline_content_sha256') == previous.get('parent_content_sha256')
         and report.get('authenticated_parent_manifest_sha256') == previous.get('parent_manifest_sha256'),
         'registered_previous_baseline_differs')
    need(baseline.get('source_anchors') == previous.get('source_anchors'), 'partial_baseline_cannot_replace_source_anchors')
    origins = lineage.get('resource_origins', {})
    old_origins = previous.get('resource_origins', {})
    changed = set(report.get('changed_runtime_paths', ()))
    removed = set(report.get('removed_runtime_paths', ()))
    need(isinstance(origins, dict) and origins == baseline.get('resource_origins'), 'registered_resource_origins_not_published_origins')
    need(changed == {p for p, row in origins.items() if p not in old_origins or
         (row.get('resource_sha256'), row.get('resource_bytes')) !=
         (old_origins[p].get('resource_sha256'), old_origins[p].get('resource_bytes'))}
         and removed == set(old_origins) - set(origins), 'registered_runtime_change_set_differs')
    covered, removed_sources = set(), set()
    pins = report.get('source_artifact_pins', {})
    consumed = set()
    for path in changed:
        origin = origins[path]; covered.add('game:' + path)
        if origin.get('kind') == 'IMMUTABLE_GIT_RUNTIME_BLOB':
            need(origin.get('source_path') == path, 'registered_identity_source_differs')
        elif origin.get('kind') == 'BOUND_OFFICIAL_COMPILER_ARTIFACT':
            source = origin.get('source_path'); pin = pins.get(source, {})
            mirror = pin.get('content_mirror', {})
            need(pin and origin.get('compilation_binding') == pin
                 and pin.get('compiled_artifact_sha256') == origin.get('resource_sha256')
                 and isinstance(mirror.get('path'), str), 'registered_compiler_source_mapping_invalid')
            covered.update(('game:' + source, 'content:' + mirror['path'])); consumed.add(source)
        else:
            raise RuntimeError('registered_runtime_origin_requires_review')
    need(consumed == set(pins), 'registered_compiler_binding_not_delivered')
    removal_bindings = report.get('removed_source_bindings', {})
    need(set(removal_bindings) == removed, 'registered_removal_bindings_missing')
    for resource, sources in removal_bindings.items():
        need(dict(repo='game', path=resource) in sources, 'registered_runtime_removal_unknown')
        for source in sources:
            need(source.get('repo') in ('game', 'content') and isinstance(source.get('path'), str), 'registered_removed_source_invalid')
            removed_sources.add(source['repo'] + ':' + source['path'])
    old_inventory, inventory = previous.get('source_inventory', {}), baseline.get('source_inventory', {})
    need(set(old_inventory) == set(inventory) == {'game', 'content'}, 'registered_dual_source_inventory_missing')
    for role in ('game', 'content'):
        old, current = old_inventory[role], inventory[role]
        added_keys = {key.split(':', 1)[1] for key in covered if key.startswith(role + ':')}
        deleted_keys = {key.split(':', 1)[1] for key in removed_sources if key.startswith(role + ':')}
        need(set(current) == (set(old) | added_keys) - deleted_keys, 'partial_baseline_absorbed_unpublished_head_paths')
        need(all(current[path] == old[path] for path in set(old) - added_keys - deleted_keys),
             'partial_baseline_absorbed_unpublished_head_entries')
    deferred = json.loads(json.dumps(previous.get('deferred_sources', {})))
    for group in (lineage.get('deferred_sources'), lineage.get('deferred_unpublished0201_sources')):
        need(isinstance(group, dict), 'registered_deferred_history_missing')
        for key, value in group.items():
            need(key not in deferred or deferred[key] == value or key in covered or key in removed_sources,
                 'registered_unpublished_history_rewritten')
            deferred.setdefault(key, value)
    cleared = sorted(set(deferred).intersection(covered | removed_sources))
    for key in cleared:
        del deferred[key]
    need(deferred == baseline.get('deferred_sources'), 'registered_unpublished_history_lost')
    rollforward = baseline.get('rollforward', {})
    need(rollforward.get('updated_source_entries') == sorted(covered)
         and rollforward.get('removed_source_entries') == sorted(removed_sources)
         and rollforward.get('cleared_deferred_sources') == cleared,
         'registered_selective_rollforward_record_differs')


def load_registered_baseline(root, relative, expected_sha256, registry, *, read_json=None, _ancestry=()):
    """Read a hash-registered verified delivery; no writer or pointer advance.

    Registry schema: {schema:1, entries:{baseline_relative_path:{sha256,
    manifest_path,manifest_sha256,package_report_path,package_report_sha256,
    verified_delivery_path,verified_delivery_sha256,previous_baseline_path,
    previous_baseline_sha256}}}. All paths are exact ROOT/output JSONs. The
    registry's original bytes need a separate explicit CLI SHA256. This loader
    validates real SDK/download schemas and sparse history preservation, never
    a user-provided READY flag, and still grants no publication capability.
    """
    read = read_json or (lambda path, digest: _registered_json(root, path, digest))
    if len(_ancestry) >= 32:
        raise RuntimeError('registered_baseline_ancestry_limit')
    if expected_sha256 in _ancestry:
        raise RuntimeError('registered_baseline_ancestry_cycle')
    if not _registered_path(relative) or not SHA256.fullmatch(str(expected_sha256 or '')):
        raise RuntimeError('explicit_registered_baseline_path_and_sha_required')
    if not isinstance(registry, dict) or registry.get('schema') != 1 or not isinstance(registry.get('entries'), dict):
        raise RuntimeError('baseline_registry_schema_invalid')
    entry = registry['entries'].get(relative)
    if not isinstance(entry, dict) or entry.get('sha256') != expected_sha256:
        raise RuntimeError('baseline_not_registered_with_same_raw_sha')
    baseline = read(relative, expected_sha256)
    controls = {}
    for key in ('manifest', 'package_report', 'verified_delivery', 'previous_baseline'):
        path, digest = entry.get(key + '_path'), entry.get(key + '_sha256')
        if not _registered_path(path) or not SHA256.fullmatch(str(digest or '')):
            raise RuntimeError('registered_control_path_or_sha_invalid')
        controls[key] = read(path, digest)
    previous_path, previous_sha = entry['previous_baseline_path'], entry['previous_baseline_sha256']
    if previous_sha != BASELINE_SHA256:
        previous_entry = registry['entries'].get(previous_path)
        if not isinstance(previous_entry, dict) or previous_entry.get('sha256') != previous_sha:
            raise RuntimeError('previous_baseline_not_registered')
        # Registration alone is not a publication proof. Authenticate every
        # partial ancestor all the way back to the fixed signed0104 record.
        # The bound prevents unbounded file/manifest traversal; aliases with the
        # same raw digest cannot circumvent the cycle check.
        authenticated_previous, _, _ = load_registered_baseline(
            root, previous_path, previous_sha, registry, read_json=read,
            _ancestry=(*_ancestry, expected_sha256))
        if authenticated_previous != controls['previous_baseline']:
            raise RuntimeError('registered_previous_control_changed_during_validation')
    manifest, package, delivery, previous = (controls[k] for k in ('manifest', 'package_report', 'verified_delivery', 'previous_baseline'))
    spec = importlib.util.spec_from_file_location('pending_inventory_rollforward_checker', ROOT/'tools/release_baseline_rollforward.py')
    checker = importlib.util.module_from_spec(spec); spec.loader.exec_module(checker)
    checker._manifest_rows(manifest)
    checker._validate_delivery(manifest, package, delivery)
    if not (baseline.get('kind') == 'AUTHENTICATED_MIXED_PUBLICATION_BASELINE'
            and baseline.get('source_anchor_is_full_published_tree') is False
            and baseline.get('full_head_publication_claimed') is False
            and baseline.get('parent_sequence') == package.get('release_sequence')
            and baseline.get('parent_content_sha256') == manifest.get('content_sha256')
            and baseline.get('parent_manifest_sha256') == entry['manifest_sha256'] == delivery.get('manifest_sha256')
            and entry['package_report_sha256'] == delivery.get('package_report_sha256')
            and baseline.get('last_published_source_revisions') == package.get('source_revisions')
            and baseline.get('resource_origins_sha256') == checker.canonical_digest(baseline.get('resource_origins'))):
        raise RuntimeError('registered_baseline_is_not_same_verified_partial_delivery')
    origins, rows = baseline['resource_origins'], {r['path']: r for r in manifest['files']}
    if set(origins) != set(rows) or any((origins[p].get('resource_sha256'), origins[p].get('resource_bytes')) !=
                                      (rows[p]['sha256'], rows[p]['bytes']) for p in rows):
        raise RuntimeError('registered_origin_manifest_bytes_differ')
    advance = baseline.get('rollforward', {})
    if not (advance.get('sdk_and_full_official_download_verified') is True
            and advance.get('package_report_sha256') == delivery['package_report_sha256']
            and advance.get('canonical_journal_sha256') == delivery['journal_sha256']):
        raise RuntimeError('registered_rollforward_proof_binding_missing')
    _verify_sparse_rollforward(previous, baseline, package)
    return baseline, manifest, package


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--max-hash-bytes', type=int, default=256 * 1024 * 1024)
    parser.add_argument('--max-blob-bytes', type=int, default=64 * 1024 * 1024)
    parser.add_argument('--check', action='store_true', help='Exit 2 while any runtime item remains pending/dirty')
    parser.add_argument('--baseline', help='Explicit registered baseline JSON beneath ROOT/output')
    parser.add_argument('--baseline-sha256', help='SHA256 of original registered baseline bytes')
    parser.add_argument('--baseline-registry-sha256', help='SHA256 of fixed output/release_baselines/registry.json')
    args = parser.parse_args(argv)
    if not (1 <= args.max_blob_bytes <= args.max_hash_bytes <= 1024 * 1024 * 1024):
        parser.error('Byte budgets must satisfy 1 <= blob <= total <= 1GiB')
    explicit = (args.baseline, args.baseline_sha256, args.baseline_registry_sha256)
    if any(explicit) and not all(explicit):
        parser.error('--baseline, --baseline-sha256 and --baseline-registry-sha256 must be supplied together')
    if args.baseline:
        registry = _read_json(BASELINE_REGISTRY, args.baseline_registry_sha256)
        baseline, parent, plan = load_registered_baseline(ROOT, args.baseline, args.baseline_sha256, registry)
        baseline_mode = 'REGISTERED_SDK_AND_OFFICIAL_DOWNLOAD_VERIFIED_BASELINE'
    else:
        baseline = _read_json(BASELINE, BASELINE_SHA256)
        plan = _read_json(PLAN, PLAN_SHA256)
        parent = _read_json(PARENT_MANIFEST, baseline['parent_manifest_sha256'])
        if parent['content_sha256'] != baseline['parent_content_sha256'] or plan['baseline_content_sha256'] != parent['content_sha256']:
            raise RuntimeError('actual_signed_parent_identity_changed')
        baseline_mode = 'FIXED_0104_MIGRATION_BASELINE'
    counts = Counter(); trees, commits, dirty = {}, {}, []
    repositories = {'game': ROOT, 'content': CONTENT}
    for role, root in repositories.items():
        commits[role] = _git(root, 'rev-parse', 'HEAD', counts=counts).decode('ascii').strip()
        trees[role] = git_tree(root, counts, commits[role])
        dirty.extend(git_dirty(root, role, counts))
    historical = baseline['deferred_sources']
    unpublished = {} if args.baseline else plan['git_runtime_lineage']['deferred_unpublished0201_sources']
    protection = _read_json(ROOT/'tools/lua_protection_policy.json')
    production_resources = set(protection['business_modules'])
    for path in set(baseline['source_inventory']['game']) | set(trees['game']):
        if path.startswith(protection['generated_prefix']) and PurePosixPath(path).name not in protection['generated_exclusions']:
            production_resources.add(path)
    bindings = plan_bindings(plan)
    keys = pending_source_keys(baseline['source_inventory'], trees, historical, unpublished)
    for binding in bindings:
        keys.update((item['repo'], item['path']) for item in binding['inputs'] + [binding['output']])
    budget = HashBudget(args.max_hash_bytes, args.max_blob_bytes)
    facts = {}
    for role, root in repositories.items():
        values = read_git_facts(root, trees[role], {path for repo, path in keys if repo == role}, budget, counts)
        facts.update((role + ':' + path, value) for path, value in values.items())
    result = classify_inventory(baseline_inventory=baseline['source_inventory'], head_inventory=trees,
                                parent_manifest=parent, deferred_sources=historical,
                                deferred_unpublished_sources=unpublished, blob_facts=facts,
                                bindings=bindings, dirty=dirty, production_resources=production_resources)
    result.update(target_commits=commits, recorded_parent_sequence=baseline['parent_sequence'],
                  baseline_mode=baseline_mode,
                  baseline_control=dict(path=args.baseline, sha256=args.baseline_sha256, registry_sha256=args.baseline_registry_sha256) if args.baseline else None,
                  recorded_parent_manifest_sha256=baseline['parent_manifest_sha256'],
                  recorded_parent_content_sha256=parent['content_sha256'],
                  recorded_parent_steam_manifest=baseline['official_parent_manifest'],
                  call_counts=dict(counts), hash_budget=dict(max_total=budget.total, max_blob=budget.per_blob, reserved=budget.used),
                  official_remote_queried=False, bytes_written=0, git_mutations=0, sdk_calls=0, network_calls=0)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 2 if args.check and (result['counts']['pending'] or result['counts']['dirty_runtime']) else 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(json.dumps(dict(status='PENDING_INVENTORY_REFUSED_NO_PUBLICATION_CLAIM', error_type=type(error).__name__), ensure_ascii=True))
        raise SystemExit(2)
