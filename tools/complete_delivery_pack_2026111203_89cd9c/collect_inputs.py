"""Collect immutable complete-release inputs and optionally prepare a fresh unsigned tree.

One offline invocation, no watcher/SDK/key/journal/install/delete. Source Git
trees are indexed once; each needed blob is read once by a bounded batch reader.
Every pending/historical source and every rebuilt derived output is reviewed.
Receipt producers keep their original commits; current target facts are separate.
"""
from __future__ import annotations
import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import importlib
import json
import os
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from complete_delivery_pack_2026111203_89cd9c import parent_pending as pending
import release_compile_scope as compiler
from complete_delivery_pack_2026111203_89cd9c import build_release as build, ledger, localization_projection
TOOL = 'tools/complete_delivery_pack_2026111203_89cd9c/collect_inputs.py'
LOADED_SHA = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
MAX_TOTAL = 1024 ** 3

def loaded_dependencies():
    result = {}
    for module, field in ((pending, 'EXECUTED_SOURCE_LF_SHA256'), (compiler, 'EXECUTED_TOOL_LF_SHA256'), (compiler.inventory, 'EXECUTED_SOURCE_LF_SHA256'), (build, 'EXECUTED_SOURCE_LF_SHA256'), (ledger, 'EXECUTED_SOURCE_LF_SHA256'), (localization_projection, 'EXECUTED_SOURCE_LF_SHA256')):
        path = build._plain(module.__file__, directory=False)
        ledger.need(path.is_relative_to(ROOT), 'collector_dependency_outside_operator_tree')
        raw = path.read_bytes()
        actual = ledger.sha(raw.replace(b'\r\n', b'\n'))
        ledger.need(getattr(module, field, None) == actual, 'collector_dependency_changed_after_import:' + path.relative_to(ROOT).as_posix())
        result[path.relative_to(ROOT).as_posix()] = actual
    return result

def checked(spec):
    ledger.need(isinstance(spec, dict) and set(spec) >= {'path', 'sha256'}, 'explicit_original_document_path_and_sha_required')
    path = Path(spec['path'])
    if not path.is_absolute():
        ledger.need(not path.drive and '..' not in path.parts, 'canonical_relative_document_path_required')
        path = ROOT / path
    path = build._plain(path, directory=False)
    ledger.need(path.stat().st_size <= ledger.MAX_DOCUMENT, 'bounded_original_control_document_required')
    raw = path.read_bytes()
    return (ledger.document(raw, spec['sha256']), raw)

def raw_file(path):
    path = build._plain(path, directory=False)
    ledger.need(path.stat().st_size <= ledger.MAX_DOCUMENT, 'bounded_actual_artifact_required')
    return path.read_bytes()

class Sources:

    def __init__(self, pins, *, diagnostic=False):
        ledger.need(set(pins) == {'game', 'content', 'operator'}, 'explicit_target_source_triple_required')
        self.pins, self.counts = (pins.copy(), Counter())
        dependencies = loaded_dependencies()
        self.roots = {'game': ROOT, 'content': pending.CONTENT}
        for role, commit in pins.items():
            ledger.revision(commit)
            root = self.roots.get(role, ROOT)
            ledger.need(pending._git(root, 'rev-parse', '--verify', commit + '^{commit}', counts=self.counts).decode().strip() == commit, 'exact_target_commit_required')
        actual = Path(__file__).read_bytes().replace(b'\r\n', b'\n')
        ledger.need(ledger.sha(actual) == LOADED_SHA, 'collector_changed_after_import')
        try:
            declared = self.operator_blob(pins['operator'], TOOL)
        except RuntimeError:
            declared = None
        self.diagnostic = declared is None or declared.replace(b'\r\n', b'\n') != actual
        for name, loaded in dependencies.items():
            source = self.operator_blob(pins['operator'], name)
            if ledger.sha(source.replace(b'\r\n', b'\n')) != loaded:
                self.diagnostic = True
        ledger.need(not self.diagnostic or diagnostic, 'collector_not_in_frozen_operator_commit')
        self.trees = {role: pending.git_tree(root, self.counts, pins[role]) for role, root in self.roots.items()}
        self.reader = compiler.Reader(self.roots, self.trees)
        self.values, self.facts, self.original_tools = ({}, {}, {})
        self.semantic_evidence = {'compiler': []}

    def operator_blob(self, revision, name):
        ledger.revision(revision)
        ledger.path(name)
        key = (revision, name)
        if hasattr(self, 'original_tools') and key in self.original_tools:
            return self.original_tools[key]
        raw = pending._git(ROOT, 'show', revision + ':' + name, counts=self.counts)
        ledger.byte_fingerprint(raw)
        if hasattr(self, 'original_tools'):
            self.original_tools[key] = raw
        return raw

    def get(self, key):
        ledger.source_id(key)
        if key not in self.values:
            role, name = key.split(':', 1)
            value = self.reader.get(role, name)
            self.values[key] = value
            self.facts[key] = {'commit': self.pins[role], 'git_oid': value['oid'], **value['content'], 'lfs': value['lfs'], 'lfs_content_verified': value['lfs'], 'git_blob_sha256': value['git_blob']['sha256']}
        return self.values[key]

    def content(self, key):
        return self.get(key)['raw']

    def original_bytes(self, key):
        value = self.get(key)
        if not value['lfs']:
            return value['raw']
        role = key.split(':', 1)[0]
        pointer = pending._git(self.roots[role], 'cat-file', 'blob', value['oid'], counts=self.counts)
        return {'git_blob': pointer, 'content': value['raw']}

    def close(self):
        self.reader.close()

def inventory(ctx):
    """Reuse the fixed authenticated migration inventory, without using HEAD."""
    baseline = pending._read_json(pending.BASELINE, pending.BASELINE_SHA256)
    previous = {'baseline_content_sha256': baseline['parent_content_sha256']}
    parent_raw = pending.PARENT_MANIFEST.read_bytes()
    parent = ledger.document(parent_raw, baseline['parent_manifest_sha256'])
    ledger.need(parent['content_sha256'] == baseline['parent_content_sha256'] == previous['baseline_content_sha256'], 'actual_parent_identity_changed')
    history = baseline['deferred_sources']
    unpublished = []
    keys = pending.pending_source_keys(baseline['source_inventory'], ctx.trees, history, unpublished)
    bindings = []
    for binding in bindings:
        keys.update(((v['repo'], v['path']) for v in [*binding['inputs'], binding['output']]))
    facts = {}
    for role, name in sorted(keys):
        if name not in ctx.trees[role]:
            continue
        value = ctx.get(role + ':' + name)
        facts[role + ':' + name] = {'hash_state': 'VERIFIED', **value['content'], 'git_sha256': value['git_blob']['sha256'], 'lfs': value['lfs']}
    policy = json.loads(ctx.operator_blob(ctx.pins['operator'], 'tools/lua_protection_policy.json'))
    production = set(policy['business_modules'])
    production.update((name for name in ctx.trees['game'] if name.startswith(policy['generated_prefix']) and Path(name).name not in policy['generated_exclusions']))
    dirty = []
    for role, root in ctx.roots.items():
        dirty.extend(pending.git_dirty(root, role, ctx.counts))
    result = pending.classify_inventory(baseline_inventory=baseline['source_inventory'], head_inventory=ctx.trees, parent_manifest=parent, deferred_sources=history, deferred_unpublished_sources=unpublished, blob_facts=facts, bindings=bindings, dirty=dirty, production_resources=production)
    result.update(target_commits={k: ctx.pins[k] for k in ('game', 'content')}, recorded_parent_manifest_sha256=baseline['parent_manifest_sha256'], recorded_parent_content_sha256=parent['content_sha256'], recorded_parent_sequence=baseline['parent_sequence'], recorded_parent_steam_manifest=baseline['official_parent_manifest'])
    return (parent_raw, baseline['parent_manifest_sha256'], result)

def assemble(*, pins, parent_raw, parent_sha256, base_inventory, facts, targets, review, review_sha256, reference_scan_sha256, originals=()):
    """Pure complete decision assembly; no prefix exclusions or default unknowns."""
    parent = ledger.document(parent_raw, parent_sha256)
    old = ledger.parent_rows(parent)
    inv = deepcopy(base_inventory)
    source_rows = {}
    for row in inv['rows']:
        key = row['source']['repo'] + ':' + row['source']['path']
        ledger.need(key not in source_rows, 'duplicate_base_inventory_source')
        source_rows[key] = row
    original_source_ids = set(source_rows)
    reviewed = {row['source_id']: row for row in review.get('reviews', [])}
    ledger.need(len(review.get('reviews', [])) == len(reviewed) and review.get('reference_scan_sha256') == reference_scan_sha256, 'exact_review_scan_or_source_set_mismatch')
    base_sha = ledger.sha(ledger.canonical(inv))
    bindings, artifacts, source_targets = ({}, {}, {})
    for name, target in sorted(targets.items()):
        ledger.path(name)
        kind, raw = (target['kind'], target['raw'])
        ledger.need(kind in ledger.KINDS and target.get('sources'), 'typed_verified_target_and_sources_required')
        inputs = []
        for key in sorted(set(target['sources'])):
            ledger.need(key in facts, 'target_source_facts_missing:' + key)
            inputs.append({'source_id': key, 'sha256': facts[key]['sha256'], 'git_oid': facts[key]['git_oid']})
            source_targets.setdefault(key, []).append(name)
        bindings[name] = {'resource': name, 'kind': kind, 'inputs': inputs, 'output': ledger.byte_fingerprint(raw), 'original_evidence': deepcopy(target.get('evidence', [])), 'original_receipts': [{'kind': v['kind'], 'original_receipt_sha256': v['sha256'], 'original_source_revisions': v['source_revisions']} for v in target.get('evidence', []) if 'sha256' in v]}
        if kind == 'localization_projection':
            bindings[name]['localization_projection'] = deepcopy(target['localization_projection'])
        artifacts[name] = raw
        own = 'game:' + name
        if own in facts and kind != 'identity':
            if own not in source_rows:
                role, source_name = own.split(':', 1)
                row = {'source': {'repo': role, 'path': source_name, 'head_oid': facts[own]['git_oid']}, 'resource': name, 'status': 'PRODUCTION_TRANSFORM_REQUIRED' if kind in ('protected', 'production_override') else 'UNBOUND_COMPILED_ARTIFACT' if kind == 'compiled' else 'GENERATED_BINDING_REQUIRED', 'history': [], 'blocking': True}
                inv['rows'].append(row)
                source_rows[own] = row
            row = source_rows[own]
            if row['status'] == 'PARENT_BYTES_MATCH':
                row['original_status'] = row['status']
                row['status'] = 'PRODUCTION_TRANSFORM_REQUIRED' if kind in ('protected', 'production_override') else 'UNBOUND_COMPILED_ARTIFACT' if kind == 'compiled' else 'GENERATED_BINDING_REQUIRED'
            row['derived_output_review'] = {'target_sha256': bindings[name]['output']['sha256'], 'parent_sha256': old.get(name, {}).get('sha256'), 'source_oid_unchanged_does_not_imply_published_output': True}
    normalized = {'kind': 'COMPLETE_RUNTIME_BINDING_RECEIPT', 'source_revisions': pins.copy(), 'bindings': {name: {'kind': row['kind'], 'inputs': {v['source_id']: v['sha256'] for v in row['inputs']}, 'output': row['output'], 'original_receipts': row['original_receipts'], **({'localization_projection': row['localization_projection']} if row['kind'] == 'localization_projection' else {})} for name, row in bindings.items() if row['kind'] != 'identity'}, 'original_receipts': list(originals), 'declaration_is_not_package_authority': True}
    raw = ledger.canonical(normalized)
    receipts = {ledger.sha(raw): raw}
    for row in bindings.values():
        if row['kind'] != 'identity':
            row['receipt_sha256'] = ledger.sha(raw)
    decisions, errors = ([], [])
    for key, row in sorted(source_rows.items()):
        if row['status'] == 'PARENT_BYTES_MATCH':
            continue
        if row['source'].get('head_oid') is None:
            if row.get('resource') in old and row['resource'] not in bindings:
                decisions.append({'source_id': key, 'action': 'remove', 'resource': row['resource']})
            else:
                errors.append({'source_id': key, 'reason': 'DELETED_SOURCE_WITHOUT_EXACT_REMOVABLE_PARENT_RESOURCE'})
            continue
        options = source_targets.get(key, [])
        chosen = row.get('resource') if row.get('resource') in options else sorted(options)[0] if row.get('resource') is None and options else None
        if chosen:
            decisions.append({'source_id': key, 'action': 'publish', 'resource': chosen})
            continue
        proof = reviewed.get(key)
        if proof and row.get('resource') is None and (key in facts):
            valid = proof.get('sha256') == facts[key]['sha256'] and proof.get('git_oid') == facts[key]['git_oid'] and (proof.get('standalone_runtime_file_required') is False) and (proof.get('authority_granted') is False) and (proof.get('scope_action_proposal') == 'non_runtime_standalone_exact_path_review') and isinstance(proof.get('reason'), str) and bool(proof['reason'].strip()) and all((name in bindings for name in proof.get('runtime_targets_requiring_separate_generator_or_compiler_binding', [])))
            if valid:
                value = {'kind': 'NON_RUNTIME_EXACT_PATH_REVIEW', 'source_revisions': pins.copy(), 'source_id': key, 'source_sha256': facts[key]['sha256'], 'reason': proof['reason'], 'reference_scan_sha256': reference_scan_sha256, 'original_review_sha256': review_sha256, 'original_review_source_revision': proof.get('source_revision')}
                raw = ledger.canonical(value)
                pin = ledger.sha(raw)
                receipts[pin] = raw
                decisions.append({'source_id': key, 'action': 'non_runtime', 'receipt_sha256': pin})
                continue
        errors.append({'source_id': key, 'reason': 'UNRESOLVED_EXACT_SOURCE_BINDING_OR_REVIEW', 'resource': row.get('resource'), 'status': row['status']})
    derived = {'protected_outputs': sum((v['kind'] == 'protected' for v in targets.values())), 'protected_outputs_changed_from_parent': sum((v['kind'] == 'protected' and ledger.byte_fingerprint(v['raw']) != (ledger.fingerprint(old[name]) if name in old else None) for name, v in targets.items())), 'protected_sources_absent_from_git_pending_inventory': sum((v['kind'] == 'protected' and 'game:' + name not in original_source_ids for name, v in targets.items())), 'protected_changed_sources_absent_from_git_pending_inventory': sum((v['kind'] == 'protected' and 'game:' + name not in original_source_ids and (ledger.byte_fingerprint(v['raw']) != (ledger.fingerprint(old[name]) if name in old else None)) for name, v in targets.items()))}
    if errors:
        return {'status': 'COMPLETE_COLLECTION_BLOCKED_UNRESOLVED_SOURCES', 'blockers': errors, 'publication_ready': False, 'derived_output_counts': derived, 'inventory': inv}
    inv.update(base_inventory_sha256=base_sha, derived_output_rows=sum(('derived_output_review' in r for r in inv['rows'])))
    inv['counts'] = {**inv.get('counts', {}), 'rows': len(inv['rows']), 'pending': sum((r['status'] != 'PARENT_BYTES_MATCH' for r in inv['rows'])), 'by_status': dict(sorted(Counter((r['status'] for r in inv['rows'])).items()))}
    facts_doc = {'source_revisions': pins.copy(), 'sources': facts}
    facts_raw = ledger.canonical(facts_doc)
    inv_raw = ledger.canonical(inv)
    scope = {'source_revisions': pins.copy(), 'parent_manifest_sha256': parent_sha256, 'inventory_sha256': ledger.sha(inv_raw), 'source_facts_sha256': ledger.sha(facts_raw), 'decisions': decisions, 'bindings': list(bindings.values()), 'original_receipts': list(originals), 'exact_review_sha256': review_sha256}
    scope_raw = ledger.canonical(scope)
    inputs = dict(parent_raw=parent_raw, parent_sha256=parent_sha256, inventory_raw=inv_raw, inventory_sha256=ledger.sha(inv_raw), facts_raw=facts_raw, facts_sha256=ledger.sha(facts_raw), scope_raw=scope_raw, scope_sha256=ledger.sha(scope_raw), receipts=receipts)
    projection = build.project(**inputs)
    projection_raw = ledger.canonical(projection)
    return {'status': 'COMPLETE_IMMUTABLE_INPUTS_COLLECTED_NOT_SIGNED', 'inputs': inputs, 'projection': projection, 'projection_raw': projection_raw, 'projection_sha256': ledger.sha(projection_raw), 'artifact_bytes': artifacts, 'original_receipts': list(originals), 'derived_output_counts': derived, 'blockers': [], 'publication_ready': False}

def _target(ctx, targets, name, kind, raw, sources, evidence):
    ledger.path(name)
    sources = set(sources)
    if name in ctx.trees['game']:
        sources.add('game:' + name)
    for key in sources:
        ctx.get(key)
    ledger.need(name not in targets, 'ambiguous_duplicate_runtime_producer:' + name)
    targets[name] = {'kind': kind, 'raw': raw, 'sources': sorted(sources), 'evidence': [evidence]}

def _identity_target(ctx, targets, name):
    key = 'game:' + name
    ledger.need(name in ctx.trees['game'], 'identity_game_source_required:' + name)
    raw = ctx.content(key)
    sources = [key]
    if name.startswith('panorama/videos/') and name.endswith('.webm'):
        ledger.need(name in ctx.trees['content'], 'raw_video_content_source_required:' + name)
        mirror = 'content:' + name
        ledger.need(ctx.content(mirror) == raw, 'raw_video_game_content_bytes_differ:' + name)
        sources.append(mirror)
    _target(ctx, targets, name, 'identity', raw, sources, {'kind': 'EXACT_CURRENT_IMMUTABLE_GIT_BYTES', 'source_revision': ctx.pins['game']})

def _localization_target(ctx, targets, name):
    game, content = ('game:' + name, 'content:' + name)
    proof = localization_projection.verify_projection(name, ctx.content(content), ctx.content(game))
    _target(ctx, targets, name, 'localization_projection', ctx.content(game), [game, content], {'kind': localization_projection.KIND, 'proof_sha256': ledger.sha(ledger.canonical(proof))})
    targets[name]['localization_projection'] = proof

def load_compiler(ctx, spec, targets, originals):
    plan, plan_raw = checked(spec['plan'])
    proof, proof_raw = checked(spec['proof'])
    origins = spec['source_revisions']
    source_bytes, resource_sources, artifacts, logs = ({}, {}, {}, {})
    for row in plan['resources']:
        keys = set()
        for pin in row['sources']:
            keys.add('content:' + pin['path'])
            if pin.get('game_author'):
                keys.add('game:' + pin['game_author']['path'])
        for key in keys:
            source_bytes[key] = ctx.original_bytes(key)
        resource_sources[row['resource']] = keys
    proof_folder = Path(spec['proof']['path']).parent
    stage = build._plain(Path(proof['external_stage']) / 'game', directory=True)
    for row in proof['results']:
        artifact = build._plain(row['artifact_path'], directory=False)
        ledger.need(artifact.is_relative_to(stage), 'compiler_artifact_outside_original_stage')
        artifacts[row['resource']] = raw_file(artifact)
        log_name = ledger.path(row['compiler_log'])
        ledger.need(Path(log_name).name == log_name, 'compiler_log_must_be_one_original_leaf')
        logs[row['compiler_log_sha256']] = raw_file(proof_folder / 'logs' / log_name)
    tools = {}
    for name in plan['operator_binding']['tools_lf_sha256']:
        raw = ctx.operator_blob(origins['operator'], name)
        if name == 'tools/release_compile_scope.py' and ledger.sha(raw) != plan['tool_sha256']:
            ledger.need(b'\r' not in raw, 'compiler_original_physical_normalization_ambiguous')
            raw = raw.replace(b'\n', b'\r\n')
        tools[name] = raw
    with compiler.COMPILER.open('rb') as stream:
        compiler_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    kwargs = dict(plan_raw=plan_raw, plan_sha256=spec['plan']['sha256'], proof_raw=proof_raw, proof_sha256=spec['proof']['sha256'], source_revisions=origins, compiler_sha256=compiler_sha, operator_tools=tools, source_bytes=source_bytes, artifacts=artifacts, compiler_logs=logs)
    verified = ledger.verify_compiler_receipt(**kwargs)
    ctx.semantic_evidence['compiler'].append(kwargs)
    evidence = {'kind': proof['kind'], 'sha256': spec['proof']['sha256'], 'source_revisions': origins, 'plan_sha256': spec['plan']['sha256'], 'verification_sha256': ledger.sha(ledger.canonical(verified))}
    originals.append(evidence)
    for name, raw in artifacts.items():
        _target(ctx, targets, name, 'compiled', raw, resource_sources[name], evidence)

def load_production(ctx, spec, targets, originals):
    prep, prep_raw = checked(spec['receipt'])
    proof, proof_raw = checked(spec['proof'])
    origins = spec['source_revisions']
    policy_raw = ctx.operator_blob(origins['operator'], 'tools/lua_protection_policy.json')
    policy = json.loads(policy_raw)
    names = {row['path'] for row in prep['plain_inputs']} | {row['path'] for row in prep['production_overrides']}
    sources = {name: ctx.content('game:' + name) for name in names}
    exported = build._plain(proof['source_root'], directory=True)
    protected = build._plain(proof['destination'], directory=True)
    ledger.need(not exported.is_relative_to(ROOT.parents[2]) and (not protected.is_relative_to(ROOT.parents[2])), 'production_inputs_must_be_external')
    production = {name: raw_file(exported / ledger.path(name)) for name in names}
    outputs = {row['path']: raw_file(protected / ledger.path(row['path'])) for row in prep['protection_selected']}
    tools = {row['path']: ctx.operator_blob(origins['operator'], row['path']) for row in prep['executed_operator_inputs']}
    dependency = build._plain(spec['dependency_root'], directory=True)
    paths = [*dependency.glob('src/**/*.lua'), dependency / 'cli.lua', dependency / 'LICENSE']
    dependency_files = {p.relative_to(dependency).as_posix(): raw_file(p) for p in paths}
    binaries = {name: raw_file(row['path']) for name, row in prep['lua_binaries'].items()}
    kwargs = dict(production_raw=prep_raw, production_sha256=spec['receipt']['sha256'], protection_raw=proof_raw, protection_sha256=spec['proof']['sha256'], policy_raw=policy_raw, policy_sha256=ledger.sha(policy_raw), source_revisions=origins, source_bytes=sources, production_inputs=production, protected_outputs=outputs, operator_tools=tools, dependency_files=dependency_files, lua_binaries=binaries)
    verified = ledger.verify_protection_receipt(**kwargs)
    ctx.semantic_evidence['protection'] = kwargs
    evidence = {'kind': prep['kind'], 'sha256': spec['receipt']['sha256'], 'protection_sha256': spec['proof']['sha256'], 'source_revisions': origins, 'verification_sha256': ledger.sha(ledger.canonical(verified))}
    originals.append(evidence)
    for name, raw in outputs.items():
        _target(ctx, targets, name, 'protected', raw, ['game:' + name], evidence)
    for row in prep['production_overrides']:
        name = row['path']
        _target(ctx, targets, name, 'production_override', production[name], ['game:' + name], evidence)

def _attach_generation(ctx, targets, name, raw, sources, evidence):
    """A generated Lua/JS is a source of its protected/compiled runtime, never plaintext fallback."""
    if name.startswith('panorama/src/') and name.endswith('.js'):
        runtime = name.replace('panorama/src/', 'panorama/', 1)[:-3] + '.vjs_c'
    else:
        runtime = name
    if runtime in targets:
        ledger.need(ctx.content('game:' + name) == raw and targets[runtime]['kind'] in ('compiled', 'protected'), 'generator_transform_chain_mismatch')
        for key in sources:
            ctx.get(key)
        targets[runtime]['sources'] = sorted(set(targets[runtime]['sources']) | set(sources))
        targets[runtime]['evidence'].append(evidence)
    else:
        if name == 'scripts/vscripts/config/generated/item_resources.lua':
            _target(ctx, targets, name, 'generated', raw, sources, evidence)
            return
        row = ctx.parent_rows.get(runtime)
        ledger.need(runtime.endswith('.vjs_c') and row is not None, 'generated_runtime_missing_protection_or_official_compile:' + runtime)
        artifact = raw_file(pending.PARENT_MANIFEST.parent / runtime)
        ledger.need(ledger.byte_fingerprint(artifact) == ledger.fingerprint(row) and ledger.byte_fingerprint(ctx.content('game:' + runtime)) == ledger.fingerprint(row), 'parent_generated_js_artifact_not_identical')
        blocks, _ = ledger._compiled_data(artifact)
        normalized = raw.replace(b'\r\n', b'\n')
        ledger.need(b'\r' not in normalized, 'generated_js_lone_cr_requires_review')
        if blocks[b'DATA'] == raw:
            normalization = 'IDENTITY_EXACT_GENERATED_GIT_BYTES'
        else:
            ledger.need(b'\r' not in raw and blocks[b'DATA'] == raw.replace(b'\n', b'\r\n'), 'parent_generated_js_data_not_exact_current_source')
            normalization = 'GIT_LF_TO_COMPILER_CRLF_ONLY'
        parent_evidence = {'kind': 'ORIGINAL_SIGNED_RESOURCE_REBIND', 'resource': runtime, 'parent_manifest_sha256': ctx.parent_sha, 'parent_resource_sha256': row['sha256'], 'current_generated_source_sha256': ledger.sha(raw), 'normalization': normalization, 'invented_historical_source_revision': False}
        keys = [*sources, 'game:' + name]
        content_name = name.replace('panorama/src/', 'panorama/', 1)
        if content_name in ctx.trees['content']:
            keys.append('content:' + content_name)
        _target(ctx, targets, runtime, 'compiled', artifact, keys, evidence)
        targets[runtime]['evidence'].append(parent_evidence)

def load_item_generator(ctx, spec, targets, originals):
    proof, raw = checked(spec['proof'])
    origins = spec['source_revisions']
    sources = {key: ctx.content(key) for key in proof['inputs']}
    outputs = {name: ctx.content('game:' + name) for name in proof['outputs']}
    mirrors = {name: ctx.content('content:' + name) for name in proof['content_mirrors']}
    tool = proof['binding_tool']['path']
    gen = proof['generator']['path']
    operators = {name: ctx.operator_blob(origins['operator'], name) for name in (tool, gen)}
    kwargs = dict(proof_raw=raw, proof_sha256=spec['proof']['sha256'], source_revisions=origins, input_bytes=sources, output_bytes=outputs, content_mirrors=mirrors, operator_bytes=operators, python_bytes=raw_file(spec['python']))
    verified = ledger.verify_item_generator_receipt(**kwargs)
    ctx.semantic_evidence['item_generator'] = kwargs
    evidence = {'kind': proof['kind'], 'sha256': spec['proof']['sha256'], 'source_revisions': origins, 'verification_sha256': ledger.sha(ledger.canonical(verified))}
    originals.append(evidence)
    for name, value in outputs.items():
        _attach_generation(ctx, targets, name, value, list(sources), evidence)

def _catalog_sources(ctx, cat, manifest, previous_raw, registry_raw):
    """Bind original inputs; only the replayed registry may advance one generation."""
    sources, rebindings = ([], [])
    for name, expected in manifest['source_hashes'].items():
        key = 'game:' + name
        selected_raw = ctx.content(key)
        if ledger.sha(selected_raw) == expected:
            sources.append(key)
            continue
        ledger.need(name == cat.REGISTRY_PATH, 'catalog_input_changed_since_original_generation:' + name)
        ledger.need(ledger.sha(previous_raw) == expected, 'catalog_registry_rebinding_original_input_mismatch')
        ledger.need(selected_raw == registry_raw and ledger.sha(registry_raw) == manifest['registry_sha256'], 'catalog_registry_rebinding_output_mismatch')
        previous, current = (json.loads(previous_raw), json.loads(registry_raw))
        ledger.need(cat.canonical(previous) == previous_raw and cat.canonical(current) == registry_raw, 'catalog_registry_rebinding_noncanonical_bytes')
        ledger.need(type(previous.get('generation')) is int and type(current.get('generation')) is int and (current['generation'] == previous['generation'] + 1) and (current.get('parent_sha256') == expected), 'catalog_registry_rebinding_not_direct_successor')
        history_key = 'game:data/ui/registry_history/' + ledger.digest(expected) + '.json'
        ledger.need(ctx.content(history_key) == previous_raw, 'catalog_registry_rebinding_history_not_exact_input')
        history_sources = {}

        class SelectedHistory:

            def read(self, path):
                raw = ctx.content('game:' + path)
                ledger.need(raw == cat.canonical(json.loads(raw)), 'catalog_registry_rebinding_history_noncanonical')
                history_sources['game:' + path] = ledger.sha(raw)
                return raw
        cat.registry_history_git(current, SelectedHistory())
        sources.extend([key, *history_sources])
        rebindings.append({'original_path': name, 'original_input_sha256': expected, 'equivalent_selected_source_id': history_key, 'equivalent_selected_sha256': ledger.sha(previous_raw), 'selected_source_revision': ctx.pins['game'], 'selected_registry_output_source_id': key, 'selected_registry_output_sha256': ledger.sha(registry_raw), 'original_generation': previous['generation'], 'selected_generation': current['generation'], 'verified_history_sources': dict(sorted(history_sources.items()))})
    return (sorted(set(sources)), rebindings)

def load_catalog(ctx, spec, targets, originals):
    """Replay the immutable generator with its original previous registry and atlas reference."""
    manifest, manifest_raw = checked(spec['manifest'])
    origins = manifest['source_revisions']
    ledger.need(origins == spec['source_revisions'], 'explicit_original_catalog_source_revisions_required')
    cat = importlib.import_module('build_ui_static_catalog')
    original_tool = ctx.operator_blob(origins['operator'], 'tools/build_ui_static_catalog.py')
    ledger.need(original_tool.replace(b'\r\n', b'\n') == Path(cat.__file__).read_bytes().replace(b'\r\n', b'\n'), 'catalog_generator_not_exact_original_operator')
    game = cat.GitSource(ROOT, origins['game'])
    op = cat.GitSource(ROOT, origins['operator'])
    reference = cat.GitSource(ROOT, origins['atlas_reference'])
    registry_raw = ctx.content('game:' + cat.REGISTRY_PATH)
    registry = json.loads(registry_raw)
    parent_sha = ledger.digest(spec['previous_registry_sha256'])
    previous_raw = ctx.operator_blob(origins['game'], cat.REGISTRY_PATH)
    ledger.need(ledger.sha(previous_raw) == parent_sha, 'catalog_original_previous_registry_git_input_mismatch')
    for name, expected in manifest['source_hashes'].items():
        ledger.need(ledger.sha(game.read(name)) == expected, 'catalog_original_recorded_readset_mismatch:' + name)
    outputs, rebuilt_registry = cat.build(game, origins['content'], Path(spec['lua']), json.loads(previous_raw), op, reference)
    if not (outputs[cat.MANIFEST_PATH] == manifest_raw and outputs[cat.REGISTRY_PATH] == registry_raw and (rebuilt_registry == registry)):
        replay = json.loads(outputs[cat.MANIFEST_PATH])
        fields = sorted((k for k in set(replay) | set(manifest) if replay.get(k) != manifest.get(k)))
        extra = sorted(set(replay.get('source_hashes', {})) - set(manifest.get('source_hashes', {})))
        missing = sorted(set(manifest.get('source_hashes', {})) - set(replay.get('source_hashes', {})))
        changed = sorted((k for k in set(replay.get('source_hashes', {})) & set(manifest.get('source_hashes', {})) if replay['source_hashes'][k] != manifest['source_hashes'][k]))
        raise ValueError('catalog_original_replay_or_id_history_mismatch:registry=' + str(rebuilt_registry == registry) + ',manifest_fields=' + ','.join(fields) + ';source_extra=' + ','.join(extra) + ';source_missing=' + ','.join(missing) + ';source_changed=' + ','.join(changed))
    ledger.need(set(outputs) == {cat.MANIFEST_PATH, cat.REGISTRY_PATH, cat.LOOKUP_PATH, cat.CATALOG_PATH}, 'catalog_exact_four_outputs_required')
    for name, value in outputs.items():
        ledger.need(ctx.content('game:' + name) == value, 'generated_catalog_target_not_exact_current_git:' + name)
    sources, registry_rebindings = _catalog_sources(ctx, cat, manifest, previous_raw, registry_raw)
    for name, expected in manifest['operator_hashes'].items():
        ledger.need(ledger.sha(ctx.operator_blob(origins['operator'], name)) == expected, 'catalog_original_operator_input_mismatch')
    evidence = {'kind': 'IMMUTABLE_PUBLIC_UI_CATALOG_REPLAY', 'sha256': spec['manifest']['sha256'], 'source_revisions': origins, 'registry_sha256': manifest['registry_sha256'], 'schema_sha256': manifest['schema_sha256'], 'previous_registry_sha256': parent_sha, 'all_four_outputs_exact': True, 'registry_input_rebindings': registry_rebindings}
    originals.append(evidence)
    for name, value in outputs.items():
        if name in (cat.LOOKUP_PATH, cat.CATALOG_PATH):
            _attach_generation(ctx, targets, name, value, sources, evidence)

def collect(request):
    """Actual read-only collection from an explicit pinned request JSON object."""
    pins = request['source_revisions']
    ctx = Sources(pins, diagnostic=request.get('allow_uncommitted_collector_diagnostic') is True)
    try:
        parent_raw, parent_sha, base = inventory(ctx)
        ctx.parent_rows = ledger.parent_rows(ledger.document(parent_raw, parent_sha))
        ctx.parent_sha = parent_sha
        targets, originals = ({}, [])
        for spec in request['compiler_receipts']:
            load_compiler(ctx, spec, targets, originals)
        load_production(ctx, request['production'], targets, originals)
        load_item_generator(ctx, request['item_generator'], targets, originals)
        load_catalog(ctx, request['catalog'], targets, originals)
        for row in base['rows']:
            source = row['source']
            if source['repo'] == 'content' and source['path'] in localization_projection.PATHS and (source.get('head_oid') is not None) and (row['status'] != 'PARENT_BYTES_MATCH'):
                _localization_target(ctx, targets, source['path'])
        for row in base['rows']:
            source = row['source']
            key = source['repo'] + ':' + source['path']
            if source.get('head_oid') is not None:
                ctx.get(key)
            name = row.get('resource')
            identity_source = source['path'] == name and (source['repo'] == 'game' or (source['repo'] == 'content' and name.startswith('panorama/videos/') and name.endswith('.webm')))
            if name and name not in targets and identity_source and (row['status'] in ('PENDING_RUNTIME_UPDATE', 'PENDING_RUNTIME_ADD', 'HISTORICAL_REVIEW_REQUIRED_PARENT_BYTES_MATCH')):
                _identity_target(ctx, targets, name)
        for key in request.get('extra_sources', []):
            ctx.get(key)
        review, review_raw = checked(request['exact_review'])
        scan, scan_raw = checked(request['reference_scan'])
        ledger.need(review.get('kind') == 'IMMUTABLE_DATA_UI_EXACT_PATH_REVIEW_NOT_RELEASE_AUTHORITY', 'explicit_exact_path_review_required')
        result = assemble(pins=pins, parent_raw=parent_raw, parent_sha256=parent_sha, base_inventory=base, facts=ctx.facts, targets=targets, review=review, review_sha256=request['exact_review']['sha256'], reference_scan_sha256=request['reference_scan']['sha256'], originals=originals)
        result.update(diagnostic_only=ctx.diagnostic, source_facts=ctx.facts.copy(), source_raw={key: value['raw'] for key, value in ctx.values.items()}, semantic_evidence=ctx.semantic_evidence, call_counts=dict(ctx.counts), indexed_git_trees=2, native_calls=0, sdk_calls=0, git_mutations=0, backend_deployment_performed=False)
        return result
    finally:
        ctx.close()

def persist(result, *, report_directory, artifact_directory, allowed_artifact_root):
    """New local controls + external artifact files only. No raw VPK below addon."""
    ledger.need(result.get('status') == 'COMPLETE_IMMUTABLE_INPUTS_COLLECTED_NOT_SIGNED' and (not result.get('blockers')), 'unresolved_collection_cannot_materialize')
    report = build._plain(report_directory, exists=False)
    artifact = build._plain(artifact_directory, exists=False)
    allowed = build._plain(allowed_artifact_root, directory=True)
    ledger.need(report.is_relative_to(ROOT / 'output') and report != ROOT / 'output' and (artifact.parent == allowed) and (not artifact.is_relative_to(ROOT.parents[2])), 'fresh_external_artifacts_and_workspace_report_required')
    report.mkdir(parents=True, exist_ok=False)
    artifact.mkdir(exist_ok=False)
    build._write_new(artifact / build.MARKER, ledger.canonical({'status': 'UNSIGNED_COLLECTED_ARTIFACTS_NOT_INSTALLABLE', 'publication_ready': False}))
    paths = {}
    for name, raw in result['artifact_bytes'].items():
        target = artifact / ledger.path(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        build._write_new(target, raw)
        ledger.need(build._file_hash(target) == ledger.byte_fingerprint(raw), 'collected_artifact_write_hash_mismatch')
        paths[name] = str(target)
    for kind in ('parent', 'inventory', 'facts', 'scope'):
        build._write_new(report / (kind + '.json'), result['inputs'][kind + '_raw'])
    for pin, raw in result['inputs']['receipts'].items():
        (report / 'receipts').mkdir(exist_ok=True)
        build._write_new(report / 'receipts' / (pin + '.json'), raw)
    build._write_new(report / 'projection.json', result['projection_raw'])
    safe = {'status': result['status'], 'source_revisions': result['projection']['source_revisions'], 'projection_sha256': result['projection_sha256'], 'files': result['projection']['files'], 'bytes': result['projection']['bytes'], 'artifact_paths': paths, 'original_receipts': result['original_receipts'], 'diagnostic_only': result.get('diagnostic_only', False), 'publication_ready': False}
    build._write_new(report / 'collection.json', ledger.canonical(safe))
    return {'artifact_paths': paths, 'collection': safe}

def prepare(result, persisted, *, parent_root, destination, allowed_root, protected_paths=()):
    review = build.prepare_unsigned(inputs=result['inputs'], reviewed_projection_raw=result['projection_raw'], reviewed_projection_sha256=result['projection_sha256'], parent_root=parent_root, artifact_paths=persisted['artifact_paths'], destination=destination, allowed_root=allowed_root, protected_paths=protected_paths)
    raw = ledger.canonical(review)
    return {'unsigned_review': review, 'unsigned_review_raw': raw, 'unsigned_review_sha256': ledger.sha(raw)}

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    parser.add_argument('--request-sha256', required=True)
    parser.add_argument('--report-directory', type=Path)
    parser.add_argument('--artifact-directory', type=Path)
    parser.add_argument('--allowed-artifact-root', type=Path)
    parser.add_argument('--unsigned-directory', type=Path)
    args = parser.parse_args(argv)
    request, _ = checked({'path': str(args.request), 'sha256': args.request_sha256})
    result = collect(request)
    output = {key: result[key] for key in ('status', 'blockers', 'publication_ready', 'diagnostic_only', 'indexed_git_trees', 'derived_output_counts')}
    if args.report_directory or args.artifact_directory or args.unsigned_directory:
        ledger.need(args.report_directory and args.artifact_directory and args.allowed_artifact_root, 'explicit_new_collection_directories_required')
        saved = persist(result, report_directory=args.report_directory, artifact_directory=args.artifact_directory, allowed_artifact_root=args.allowed_artifact_root)
        output.update(saved['collection'])
        if args.unsigned_directory:
            prepared = prepare(result, saved, parent_root=pending.PARENT_MANIFEST.parent, destination=args.unsigned_directory, allowed_root=args.allowed_artifact_root)
            build._write_new(args.report_directory / 'unsigned_review.json', prepared['unsigned_review_raw'])
            output.update(unsigned_review_sha256=prepared['unsigned_review_sha256'], unsigned_status=prepared['unsigned_review']['status'])
    print(json.dumps(output, ensure_ascii=True))
    return 0 if not result['blockers'] else 2
import business_wire_binding as _business_wire_binding
_business_wire_binding.install(globals(), 'collector')
if __name__ == '__main__':
    raise SystemExit(main())
