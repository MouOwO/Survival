"""Exact immutable standalone build-input review; never a release authority.

Indexes the two selected Git trees once, batch-reads local blobs, verifies the
actual catalogue/12-node lineage, and audits direct runtime read sites. No
prefix exclusion, working-tree runtime input, SDK, network, install or journal.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from complete_delivery_pack_2026111002_e1fa24 import parent_pending as pending
import release_compile_scope as compiler
from complete_delivery_pack_2026111002_e1fa24 import localization_projection as localization
TOOL = 'tools/complete_delivery_pack_2026111002_e1fa24/exact_review.py'
EXECUTED_SHA = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
MANIFEST = 'data/ui/ui_static_catalog_manifest.json'
REGISTRY = 'data/ui/ui_static_catalog_registry.json'
ATLAS = 'data/ui/grid_static_atlas_candidate_20261103.json'
LOTTERY_SEED = 'data/ui/lottery_catalog.json'
JS = 'panorama/src/scripts/custom_game/common/ui_static_catalog.js'
CONTENT_JS = 'panorama/scripts/custom_game/common/ui_static_catalog.js'
LUA = 'scripts/vscripts/config/generated/ui_static_catalog_lookup.lua'
TARGETS = ['panorama/scripts/custom_game/common/ui_static_catalog.vjs_c', LUA]
CSV_GENERATOR = 'tools/build_configs.py'
LOCALIZATION_TOOL = 'tools/complete_delivery_pack_2026111002_e1fa24/localization_projection.py'
CSV_GENERATOR_LF_SHA256 = '5ca74b5a7b0b61bc9140a4941c373f5ca2ae31baac18a2a3cf1d0f4ad3dc5efd'
CSV_OUTPUTS = {'data/csv/英雄系统/' + name + '.csv': 'scripts/vscripts/config/generated/' + name + '.lua' for name in ('blademaster_exclusive_runtime', 'hero_skill_definitions', 'monkey_king_exclusive_runtime')}
CSV_OUTPUTS.update({'data/csv/公共规则/tooltip_definitions.csv': 'scripts/vscripts/config/generated/tooltip_definitions.lua', 'data/csv/挑战与奖励系统/challenge_definitions.csv': 'scripts/vscripts/config/generated/challenge_definitions.lua', 'data/csv/英雄系统/hero_attack_projectiles.csv': 'scripts/vscripts/config/generated/hero_attack_projectiles.lua', 'data/csv/资源系统/asset_catalog.csv': 'scripts/vscripts/config/generated/asset_catalog.lua', 'data/csv/商店系统/altar_actions.csv': 'scripts/vscripts/config/generated/altar_actions.lua'})
CSV_OUTPUTS.update({'data/csv/存档系统/archive_challenge_definitions.csv': 'scripts/vscripts/config/generated/archive_challenge_definitions.lua', 'data/csv/挑战与奖励系统/encounter_members.csv': 'scripts/vscripts/config/generated/encounter_members.lua', 'data/csv/怪物与波次系统/monster_encounters.csv': 'scripts/vscripts/config/generated/monster_encounters.lua'})
KEEPER_MANIFEST = 'art/effects/keeper_attack/manifest.json'
KEEPER_AUTHORS = compiler.KEEPER_PARTICLES
KEEPER_INPUTS = {KEEPER_MANIFEST, *KEEPER_AUTHORS.values()}
EVIDENCE = {'data/ui/network50_dev05_evidence_20261103.json': ('status', 'LOCAL_TOOLS_NATIVE_PARTIAL_EVIDENCE_NOT_FPS_OR_WORKSHOP_ACCEPTANCE'), 'data/ui/network50_dev06_fps_reclassification_20261103.json': ('status', 'RECLASSIFIED_INVALID_GAMEPLAY_CAPTURE_ORIGINAL_RETAINED'), 'data/ui/network50_dev07_evidence_20261103.json': ('status', 'LOCAL_TOOLS_NATIVE_AND_VALID_UNCOVERED_FPS_EVIDENCE_NOT_ORDINARY_OR_WORKSHOP_ACCEPTANCE'), 'data/ui/ui_compact_native08_observation_20261104.json': ('kind', 'CLOSED_NATIVE08_WIRE_OBSERVATION_WITH_UNKNOWN_UI_INPUT_PROVENANCE_NOT_VISUAL_OR_TRANSACTION_ACCEPTANCE'), 'data/ui/ui_compact_wire_native_evidence_20261103.json': ('kind', 'NATIVE_TOOLS_BIDIRECTIONAL_MESSAGE_CALIBRATION_NOT_ORDINARY_ACCEPTANCE'), 'data/ui/ui_grid_bulk_native_evidence_20261103.json': ('kind', 'CLOSED_NATIVE_TOOLS_GB_SIZING_NOT_FULL_GRID_OR_FPS')}
LOADERS = {'LoadKeyValues', 'LoadKeyValuesFromString', 'LoadKVFile', 'LoadFile', 'loadfile', 'dofile', 'require', 'readFileSync', 'readFile', 'read_text', 'read_bytes', 'open', 'fetch', 'AsyncWebRequest', 'BLoadLayout', 'BLoadLayoutFromString', 'LoadLayout', 'LoadLayoutFromString'}
TOKEN_JS = re.compile('(?P<comment>/\\*.*?\\*/|//[^\\n]*)|(?P<string>"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')|(?P<id>[A-Za-z_$][\\w$]*)|(?P<punct>[^\\s])', re.S)
TOKEN_LUA = re.compile('(?P<comment>--\\[(?P<eq>=*)\\[.*?\\](?P=eq)\\]|--[^\\n]*)|(?P<string>"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')|(?P<long>\\[(?P<leq>=*)\\[.*?\\](?P=leq)\\])|(?P<id>[A-Za-z_$][\\w$]*)|(?P<punct>[^\\s])', re.S)

def need(value, reason):
    if not value:
        raise ValueError(reason)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n').encode('ascii')

def runtime_path(role, path):
    return path.startswith(('scripts/', 'panorama/', 'cfg/', 'resource/')) and (not path.startswith('scripts/vscripts/tests/'))

def read_sites(text, paths, language='js'):
    """Ignore comments/string bodies as executable code; flag uncertain UI reads."""
    literal_paths = {p.replace('\\', '/') for p in paths}
    basenames = {Path(p).name for p in paths}
    namespace, sites, window, position, line_number = (False, [], [], 0, 1)
    tokenizer = TOKEN_LUA if language == 'lua' else TOKEN_JS
    for match in tokenizer.finditer(text):
        line_number += text.count('\n', position, match.start())
        position = match.start()
        kind, token = (match.lastgroup, match.group())
        if kind == 'comment':
            continue
        if kind in ('string', 'long') and any((p in token for p in ('data/ui', 'data\\\\ui', 'data/csv', 'data\\\\csv'))):
            namespace = True
        window.append((kind, token, line_number))
        if len(window) > 4:
            window.pop(0)
        if len(window) != 4:
            continue
        (kind, name, line), opening, argument, following = window
        if kind != 'id' or name not in LOADERS or opening[1] != '(':
            continue
        argkind, arg, _ = argument
        static = argkind == 'string' and following[1] in (')', ',')
        value = arg[1:-1].replace('\\\\', '/') if argkind == 'string' else ''
        direct = static and (value in literal_paths or Path(value).name in basenames)
        sites.append({'api': name, 'line': line, 'literal_first_argument': static, 'candidate_json_read': bool(direct), 'uncertain_data_ui_read': any((p in value for p in ('data/ui', 'data/csv'))), '_dynamic': not static})
    for site in sites:
        site['uncertain_data_ui_read'] = bool(site['uncertain_data_ui_read'] or (site.pop('_dynamic') and namespace))
    return sites

def validate_registry(document):
    need(document.get('format') == 1 and type(document.get('generation')) is int and (document['generation'] > 0), 'registry_format_or_generation_invalid')
    for key, label, maximum in [('records', 'key', 65535), ('fields', 'name', 255)]:
        rows = document.get(key)
        need(isinstance(rows, list), 'registry_array_required')
        ids, names = (set(), set())
        for row in rows:
            value, name = (row.get('id'), row.get(label))
            need(type(value) is int and 1 <= value <= maximum and (value not in ids) and isinstance(name, str) and name and (name not in names), 'registry_identity_invalid')
            ids.add(value)
            names.add(name)

def validate_lineage(registry_raw, manifest, histories):
    """Declared input nodes plus the exact generated node form one full chain."""
    registry = json.loads(registry_raw)
    validate_registry(registry)
    current = sha(registry_raw)
    need(manifest.get('registry_sha256') == current, 'registry_manifest_sha_mismatch')
    declared = {p: v for p, v in manifest.get('source_hashes', {}).items() if p.startswith('data/ui/registry_history/')}
    current_path = 'data/ui/registry_history/' + current + '.json'
    need(set(declared) | {current_path} == set(histories), 'history_exact_declared_set_required')
    nodes = {}
    for path, raw in histories.items():
        digest = sha(raw)
        expected = declared.get(path, current if path == current_path else None)
        need(path == 'data/ui/registry_history/' + digest + '.json' and expected == digest, 'history_filename_or_manifest_sha_mismatch')
        node = json.loads(raw)
        validate_registry(node)
        nodes[digest] = node
    seen, cursor, child = (set(), current, None)
    while cursor is not None:
        need(cursor in nodes and cursor not in seen, 'history_missing_node_or_cycle')
        node = nodes[cursor]
        seen.add(cursor)
        if child is not None:
            need(node['generation'] + 1 == child['generation'], 'history_generation_gap')
            for collection, identity in [('records', 'key'), ('fields', 'name')]:
                newer = {r['id']: r for r in child[collection]}
                for old in node[collection]:
                    new = newer.get(old['id'])
                    need(new and new[identity] == old[identity], 'history_identity_reused_or_removed')
                    if collection == 'fields':
                        for k, v in old.items():
                            need(new.get(k, [])[:len(v)] == v if k == 'enum' and isinstance(v, list) else new.get(k) == v, 'history_field_semantics_changed')
                    else:
                        for k in ('domain', 'kind', 'business_id'):
                            need(new.get(k) == old.get(k), 'history_record_semantics_changed')
                        need(not old.get('tombstone') or new.get('tombstone'), 'history_tombstone_reused')
        child, cursor = (node, node.get('parent_sha256'))
    need(seen == set(nodes) and len(seen) == registry['generation'], 'history_unreachable_or_incomplete_nodes')
    need(nodes[current] == registry, 'current_registry_history_node_differs')
    return {'generation': registry['generation'], 'nodes_parsed': len(seen), 'records': len(registry['records']), 'fields': len(registry['fields']), 'registry_sha256': current, 'exact_parent_chain': True, 'declared_input_history_nodes': len(declared), 'current_history_is_generated_output': current_path not in declared, 'append_only_identities_verified': True}

def validate_catalog(blobs):
    manifest = json.loads(blobs[MANIFEST])
    registry = json.loads(blobs[REGISTRY])
    histories = {p: raw for p, raw in blobs.items() if p.startswith('data/ui/registry_history/')}
    checks = validate_lineage(blobs[REGISTRY], manifest, histories)
    input_registry = manifest['source_hashes'].get(REGISTRY)
    need(input_registry in {checks['registry_sha256'], registry.get('parent_sha256')} and isinstance(input_registry, str) and (manifest['source_hashes'].get('data/ui/registry_history/' + input_registry + '.json') == input_registry), 'catalog_input_registry_not_current_or_direct_parent')
    need(manifest['source_hashes'].get(ATLAS) == sha(blobs[ATLAS]), 'catalog_input_sha_mismatch:' + ATLAS)
    for path in (JS, LUA, REGISTRY):
        need(manifest['outputs'].get(path) == sha(blobs[path]), 'catalog_output_sha_mismatch:' + path)
    need(blobs['content:' + CONTENT_JS] == blobs[JS], 'catalog_content_mirror_differs')
    text = blobs[JS].decode('utf8')
    start = re.search('var data\\s*=\\s*', text)
    need(start, 'generated_catalog_data_literal_missing')
    data, _ = json.JSONDecoder().raw_decode(text[start.end():])
    need(data['sha256'] == manifest['schema_sha256'] and data['registry_sha256'] == checks['registry_sha256'], 'generated_catalog_schema_mismatch')
    need(data['records'] == registry['records'] and data['fields'] == registry['fields'], 'generated_catalog_registry_semantics_mismatch')
    need(data['source_hashes'] == manifest['source_hashes'], 'generated_source_provenance_mismatch')
    need(re.search('\\["sha256"\\]="' + re.escape(manifest['schema_sha256']) + '"', blobs[LUA].decode('utf8')), 'lookup_schema_mismatch')
    source = json.loads(blobs[ATLAS])
    embedded = data['auxiliary']['grid']['atlases']
    need(isinstance(source.get('atlases'), list) and len(source['atlases']) == len(embedded) > 0, 'atlas_count_mismatch')
    for old, new in zip(source['atlases'], embedded):
        for key in ('id', 'map', 'area', 'source_map_sha256'):
            need(old.get(key) == new.get(key), 'atlas_embedded_value_mismatch:' + key)
        need(new.get('authority') is False and new.get('requires_current_live_scan') is True, 'atlas_must_remain_non_authoritative')
    checks.update(schema_sha256=manifest['schema_sha256'], generated_js_lua_hashes_verified=True, content_mirror_exact=True, atlas_embedded_and_non_authoritative=True)
    if LOTTERY_SEED in blobs:
        checks.update(validate_lottery_seed(blobs[LOTTERY_SEED], manifest, data))
    return checks

def validate_lottery_seed(raw, manifest, data):
    """Prove this exact build input is embedded in the generated public data."""
    need(manifest.get('source_hashes', {}).get(LOTTERY_SEED) == sha(raw), 'lottery_seed_source_manifest_sha_mismatch')
    seed = json.loads(raw)
    need(set(seed) == {'md5', 'config_hash', 'catalog_json'} and re.fullmatch('[a-f0-9]{64}', str(seed['config_hash'])) and isinstance(seed['catalog_json'], str) and (hashlib.md5(seed['catalog_json'].encode('utf8')).hexdigest() == seed['md5']), 'lottery_seed_public_document_md5_invalid')
    public = json.loads(seed['catalog_json'])
    need(public.get('schema') == 1 and isinstance(public.get('snapshots'), list) and (len(public['snapshots']) == 4) and ({row.get('selected_pool_id') for row in public['snapshots']} == {'map', 'cultivation', 'dragon_knight', 'summer'}), 'lottery_seed_four_public_pools_required')
    auxiliary = data.get('auxiliary', {})
    need(auxiliary.get('lottery_public') == public and auxiliary.get('lottery_config_hash') == seed['config_hash'], 'lottery_seed_not_exact_generated_runtime_data')
    return {'lottery_seed_md5': seed['md5'], 'lottery_config_hash': seed['config_hash'], 'public_seed_embedded_exactly': True, 'public_snapshot_count': 4, 'probabilities_or_rewards_modified_by_review': False}

def validate_csv_build_inputs(blobs, pins):
    """Execute the selected immutable generator with memory-only path adapters.

    No handwritten CSV-to-Lua serializer and no working-tree import. Calling
    build(), rather than main(), cannot rebuild unrelated tables/tooltip files.
    Cost is one generator load plus O(total selected CSV/output bytes), once.
    """
    paths = sorted(set(blobs) & set(CSV_OUTPUTS))
    if not paths:
        return {}
    generator = blobs[CSV_GENERATOR]
    need(generator == blobs['operator:' + CSV_GENERATOR], 'csv_generator_source_operator_bytes_differ')
    need(sha(generator.replace(b'\r\n', b'\n')) == CSV_GENERATOR_LF_SHA256, 'csv_generator_readset_not_reviewed')
    namespace = {'__name__': '_immutable_exact_csv_generator', '__file__': str(ROOT / CSV_GENERATOR)}
    exec(compile(generator, CSV_GENERATOR, 'exec'), namespace)
    build = namespace.get('build')
    need(callable(build), 'csv_generator_build_entry_missing')

    class Input:

        def __init__(self, path, raw):
            self.name, self.raw, self.reads = (Path(path).name, raw, 0)

        def read_bytes(self):
            self.reads += 1
            need(self.reads == 1, 'csv_generator_input_read_contract_changed')
            return self.raw

        def __str__(self):
            return self.name

    class Output:

        def __init__(self):
            self.raw = None

        def write_text(self, text, *, encoding, newline):
            need(self.raw is None and encoding == 'utf-8' and (newline == '\n'), 'csv_generator_output_contract_changed')
            self.raw = text.encode('utf8')
            return len(text)
    checks = {}
    for path in paths:
        source = Input(path, blobs[path])
        output = Output()
        build(source, output)
        target = CSV_OUTPUTS[path]
        need(source.reads == 1 and output.raw is not None and (output.raw == blobs[target]), 'csv_generated_lua_bytes_differ:' + path)
        checks[path] = {'generator_path': CSV_GENERATOR, 'generator_entry': 'build', 'generator_source_revision': pins['game'], 'generator_operator_revision': pins['operator'], 'generator_sha256': sha(generator), 'input_sha256': sha(blobs[path]), 'reviewed_generator_lf_sha256': CSV_GENERATOR_LF_SHA256, 'complete_readset': [{'repo': 'game', 'path': path, 'sha256': sha(blobs[path])}, {'repo': 'game', 'path': CSV_GENERATOR, 'sha256': sha(generator)}], 'generated_lua_path': target, 'generated_lua_source_revision': pins['game'], 'generated_lua_sha256': sha(output.raw), 'generated_lua_bytes': len(output.raw), 'complete_generated_bytes_equal': True, 'all_emitted_values_equal': True, 'working_tree_generator_used': False, 'runtime_files_written': 0, 'csv_read_count': source.reads, 'other_csv_or_template_reads': 0, 'derived_unified_tooltip_rebuilt': False}
    return checks

def load_review_blobs(sources, rows, pins):
    """Read the declared repository, including both immutable localization inputs."""
    blobs = {}
    for row in rows:
        role, path = (row['source']['repo'], row['source']['path'])
        need(role in ('game', 'content'), 'review_source_repository_invalid')
        key = path if role == 'game' else role + ':' + path
        blobs[key] = sources.get(role, path)
        if role == 'content' and path in localization.PATHS:
            blobs[path] = sources.get('game', path)
    for path in (JS, LUA):
        blobs[path] = sources.get('game', path)
    for path in (MANIFEST, REGISTRY, ATLAS):
        if path not in blobs:
            blobs[path] = sources.get('game', path)
    catalog_manifest = json.loads(blobs[MANIFEST])
    history_paths = {path for path in catalog_manifest['source_hashes'] if path.startswith('data/ui/registry_history/')}
    history_paths.add('data/ui/registry_history/' + catalog_manifest['registry_sha256'] + '.json')
    for path in sorted(history_paths):
        if path not in blobs:
            blobs[path] = sources.get('game', path)
    csv_paths = {r['source']['path'] for r in rows if r['source']['repo'] == 'game'} & set(CSV_OUTPUTS)
    if csv_paths:
        blobs[CSV_GENERATOR] = sources.get('game', CSV_GENERATOR)
        blobs['operator:' + CSV_GENERATOR] = compiler.run_git(ROOT, 'show', pins['operator'] + ':' + CSV_GENERATOR)
        for path in sorted(csv_paths):
            blobs[CSV_OUTPUTS[path]] = sources.get('game', CSV_OUTPUTS[path])
    blobs['content:' + CONTENT_JS] = sources.get('content', CONTENT_JS)
    if set(blobs) & KEEPER_INPUTS:
        for resource, author in KEEPER_AUTHORS.items():
            blobs[author] = sources.get('game', author)
            blobs['content:' + resource[:-2]] = sources.get('content', resource[:-2])
        blobs[KEEPER_MANIFEST] = sources.get('game', KEEPER_MANIFEST)
    return blobs

def validate_keeper_build_inputs(blobs):
    """Bind these two exact authored particles; official compile remains required."""
    manifest = json.loads(blobs[KEEPER_MANIFEST])
    rows = manifest.get('outputs', [])
    expected = {resource[:-2]: author for resource, author in KEEPER_AUTHORS.items()}
    need(manifest.get('format') == 1 and len(rows) == len(expected) and ({row.get('resource') for row in rows} == set(expected)) and (manifest.get('root') == 'particles/survival/heroes/keeper/keeper_of_the_light_base_attack.vpcf'), 'keeper_exact_particle_manifest_required')
    checks = {}
    for row in rows:
        source = row['resource']
        author = expected[source]
        raw = blobs[author]
        need(raw == blobs['content:' + source] and sha(raw) == row.get('source_sha256') and (row.get('native_resource') == 'particles/units/heroes/hero_keeper_of_the_light/' + Path(source).name) and re.fullmatch('[0-9a-f]{64}', row.get('native_data_sha256', '')), 'keeper_particle_manifest_or_dual_author_mismatch')
        checks[author] = {'source_sha256': sha(raw), 'content_source': source, 'required_compiled_resource': source + '_c', 'native_visual_acceptance': False}
    return checks

def runtime_mapping_reviews(rows, pins, blobs, facts):
    """Only a verified typed runtime projection can leave the standalone audit."""
    result, seen = ([], set())
    for row in rows:
        source = row['source']
        path = source['path']
        if source.get('repo') != 'content' or path not in localization.PATHS:
            continue
        key = 'content:' + path
        need(key not in seen, 'duplicate_runtime_projection_source')
        seen.add(key)
        content, game = (blobs[key], blobs[path])
        proof = localization.verify_projection(path, content, game)
        inputs = {}
        for role, raw in (('content', content), ('game', game)):
            fact = facts[role + ':' + path]
            need(fact.get('source_revision') == pins[role] and isinstance(fact.get('git_oid'), str) and re.fullmatch('[0-9a-f]{40}', fact['git_oid']) and (fact.get('sha256') == sha(raw)) and (fact.get('bytes') == len(raw)), 'runtime_projection_git_source_fact_mismatch:' + role + ':' + path)
            inputs[role + ':' + path] = dict(source_revision=pins[role], **{k: fact[k] for k in ('git_oid', 'sha256', 'bytes')})
        need(facts[key]['git_oid'] == source.get('head_oid') and facts[key]['sha256'] == row['candidate']['sha256'], 'runtime_projection_scope_source_mismatch:' + key)
        result.append({'source_id': key, 'source_revision': pins['content'], 'git_oid': facts[key]['git_oid'], 'sha256': sha(content), 'bytes': len(content), 'kind': 'localization_projection', 'resource': path, 'sources': inputs, 'localization_projection': proof, 'standalone_runtime_file_required': True, 'non_runtime_exclusion': False, 'authority_granted': False, 'scope_action_proposal': 'typed_runtime_projection_required', 'runtime_targets_requiring_separate_generator_or_compiler_binding': [path]})
    return sorted(result, key=lambda row: row['source_id'])

def make_reviews(scope, scope_sha256, pins, blobs, facts, scan, scan_sha256):
    need(scope.get('observed_commits') == {k: pins[k] for k in ('game', 'content')}, 'scope_source_revisions_mismatch')
    all_rows = [r for r in scope['decisions'] if r['inventory_status'] == 'UNMAPPED_SOURCE_PENDING']
    mappings = runtime_mapping_reviews(all_rows, pins, blobs, facts)
    mapped = {row['source_id'] for row in mappings}
    rows = [row for row in all_rows if row['source'].get('repo', '') + ':' + row['source']['path'] not in mapped]
    paths = {r['source']['path'] for r in rows}
    manifest = json.loads(blobs[MANIFEST])
    histories = {p for p in manifest['source_hashes'] if p.startswith('data/ui/registry_history/')}
    current = manifest.get('registry_sha256')
    if isinstance(current, str) and re.fullmatch('[a-f0-9]{64}', current):
        histories.add('data/ui/registry_history/' + current + '.json')
    known = {ATLAS, MANIFEST, REGISTRY, LOTTERY_SEED, *EVIDENCE, *histories, *CSV_OUTPUTS, *KEEPER_INPUTS}
    expected = paths & known
    need(len(rows) == len(paths) == len(expected) and paths == expected, 'unmapped_set_not_exact_reviewed_paths')
    checks = validate_catalog(blobs)
    csv_checks = validate_csv_build_inputs(blobs, pins)
    keeper_checks = validate_keeper_build_inputs(blobs) if paths & KEEPER_INPUTS else {}
    need(not scan['runtime_read_blockers'], 'runtime_reference_or_loader_requires_manual_review')
    reviews = []
    for row in sorted(rows, key=lambda r: r['source']['path']):
        path = row['source']['path']
        key = 'game:' + path
        raw = blobs[path]
        fact = facts[key]
        need(row['source']['repo'] == 'game' and fact['git_oid'] == row['source']['head_oid'] and (fact['sha256'] == row['candidate']['sha256'] == sha(raw)), 'scope_git_source_fact_mismatch:' + path)
        value = json.loads(raw) if path not in CSV_OUTPUTS and path not in KEEPER_AUTHORS.values() else None
        extra = {}
        if path in CSV_OUTPUTS:
            classification = 'EXACT_CSV_BUILD_INPUT_REPRODUCED_BY_IMMUTABLE_GENERATOR'
            reason = 'Executed the exact selected Git generator build() in memory on this immutable CSV and verified the entire generated Lua byte-for-byte, including every emitted value. The CSV is a build input; its generated Lua still requires the separate production/protection binding. No directory or filename alone grants exclusion.'
            targets = [CSV_OUTPUTS[path]]
            extra = csv_checks[path]
        elif path in KEEPER_INPUTS:
            classification = 'EXACT_PARTICLE_BUILD_INPUT_REQUIRING_OFFICIAL_COMPILER_BINDING'
            reason = 'Verified the two exact manifest resources, immutable game/content author bytes and source hashes. These source/provenance files remain in Git; each resulting particle requires a separate original official compiler receipt. This is not native appearance acceptance.'
            targets = sorted(KEEPER_AUTHORS) if path == KEEPER_MANIFEST else [keeper_checks[path]['required_compiled_resource']]
            extra = keeper_checks if path == KEEPER_MANIFEST else keeper_checks[path]
        elif path in EVIDENCE:
            field, expected = EVIDENCE[path]
            need(value.get(field) == expected, 'evidence_exact_semantic_type_mismatch:' + path)
            if path.endswith('dev06_fps_reclassification_20261103.json'):
                need(value.get('corrected_valid') is False, 'invalid_fps_reclassified_as_pass')
            if path.endswith('ui_grid_bulk_native_evidence_20261103.json'):
                need(value.get('actual_grid_payload_tested') is False and value.get('max_native_bytes') == 923, 'bulk_scope_or_measurement_changed')
            if path.endswith('ui_compact_native08_observation_20261104.json'):
                need(value.get('production7_visual_or_operation_acceptance') is False and value.get('fps_measured') is False, 'unknown_input_observation_overclaimed')
            classification = 'EXACT_PUBLIC_NUMERIC_OBSERVATION_NOT_RUNTIME_COMPONENT'
            reason = 'Parsed this exact public observation JSON and preserved its stated native/FPS/acceptance limitations. Immutable source-reference and executable read-API scans found no runtime read of this standalone path. Retain in Git as evidence; no UI/game state is loaded from it.'
            targets = []
            extra = {'parsed_semantic_discriminator': {field: expected}, 'runtime_file_read_hits': 0}
        elif path == ATLAS:
            classification = 'PUBLIC_BUILD_INPUT_WITH_RUNTIME_DATA_EMBEDDED_IN_GENERATED_CATALOG'
            reason = 'Exact candidate atlas bytes are pinned by the generated manifest and its area/map values are embedded in verified JS/Lua outputs. Runtime consumes the generated catalogue and still requires live authoritative scans; exclude only the standalone JSON, not its generated targets.'
            targets = TARGETS
            extra = checks
        elif path == LOTTERY_SEED:
            classification = 'EXACT_PUBLIC_LOTTERY_BUILD_INPUT_EMBEDDED_IN_GENERATED_RUNTIME'
            reason = 'Parsed this exact seed, verified its public-document MD5 and manifest source SHA, and compared all public fields with the generated runtime catalogue. Runtime reads generated Lua/compiled JS; the standalone JSON is a build input, not a replacement for those resources. The original bundle projection and generated seed contract require separate verification.'
            targets = [*TARGETS, 'panorama/scripts/custom_game/lottery_catalog_seed.vjs_c', 'scripts/vscripts/config/generated/lottery_catalog_manifest.lua']
            extra = checks
        elif path == MANIFEST:
            classification = 'EXACT_GENERATOR_SOURCE_OUTPUT_MANIFEST_NOT_RUNTIME_FILE'
            reason = 'Parsed manifest pins the exact current output registry, its complete concrete input/output history chain, atlas and generated JS/Lua source bytes. It is build provenance rather than a runtime JSON loader; generated targets remain separately required.'
            targets = TARGETS
            extra = checks
        else:
            classification = 'EXACT_APPEND_ONLY_REGISTRY_OR_HISTORY_BUILD_INPUT_NOT_RUNTIME_FILE'
            reason = 'Parsed and SHA-verified this concrete node in the complete exact parent chain, including append-only record/field semantics. The sole possible new output node is bound to the current registry SHA. Verified current generated IDs and schema against the catalogue. No history-directory prefix is ignored; generated targets remain separately required.'
            targets = TARGETS
            extra = {**checks, 'this_node_generation': value['generation']}
        refs = []
        for refkey, source in scan['references'].items():
            if path in source['matches']:
                refs.append({'source_id': refkey, 'git_oid': source['git_oid'], 'sha256': source['sha256'], 'matches': source['matches'][path], 'reference_role': source['reference_role']})
        reviews.append({'source_id': key, 'source_revision': pins['game'], 'git_oid': fact['git_oid'], 'sha256': sha(raw), 'bytes': len(raw), 'classification': classification, 'checks': extra, 'reason': reason, 'references': refs, 'standalone_runtime_file_required': False, 'authority_granted': False, 'retained_in_git': True, 'scope_action_proposal': 'non_runtime_standalone_exact_path_review', 'semantic_or_build_dependency': bool(targets), 'runtime_targets_requiring_separate_generator_or_compiler_binding': targets})
    return {'schema': 1, 'kind': 'IMMUTABLE_DATA_UI_EXACT_PATH_REVIEW_NOT_RELEASE_AUTHORITY', 'source_revisions': pins, 'inventory_sha256': scope_sha256, 'input_scope_sha256': scope_sha256, 'reference_scan_sha256': scan_sha256, 'scope': {'actual_unmapped_count': len(all_rows), 'standalone_review_count': len(rows), 'typed_runtime_mapping_count': len(mappings), 'exact_paths': sorted(paths), 'directory_prefix_exclusions': False}, 'reviews': reviews, 'runtime_mapping_reviews': mappings, 'publication_ready': False, 'limits': ['Exact-path immutable static audit, not a dynamic runtime file-access trace.', 'Direct loader calls and data/ui-dependent dynamic loader sites are checked; arbitrary computed external paths are not proven absent.', 'Unknown matched runtime references/read sites block instead of becoming automatic exclusions.', 'Generated targets still require their separate original generator/compiler/protection bindings.']}

class Sources:

    def __init__(self, pins):
        self.pins, self.counts = (pins, Counter())
        self.roots = {'game': ROOT, 'content': pending.CONTENT}
        for role, revision in pins.items():
            compiler.immutable(self.roots.get(role, ROOT), revision)
        self.trees = {role: pending.git_tree(root, self.counts, pins[role]) for role, root in self.roots.items()}
        self.reader = compiler.Reader(self.roots, self.trees)
        self.facts = {}

    def get(self, role, path):
        result = self.reader.get(role, path)
        need(not result['lfs'], 'review_requires_exact_raw_text_git_blob:' + path)
        self.facts[role + ':' + path] = {'source_revision': self.pins[role], 'git_oid': result['oid'], 'raw_git_sha256': result['git_blob']['sha256'], 'sha256': result['content']['sha256'], 'bytes': len(result['raw'])}
        return result['raw']

    def grep(self, role, patterns, fixed=True):
        argv = ['git', '--no-replace-objects', '-c', 'safe.directory=' + self.roots[role].as_posix(), '-C', str(self.roots[role]), 'grep', '-l', '-z', '-I', '-F' if fixed else '-E']
        for pattern in patterns:
            argv += ['-e', pattern]
        argv += [self.pins[role], '--', 'tools', 'docs', 'scripts', 'panorama', 'data', 'cfg', 'resource']
        done = subprocess.run(argv, capture_output=True, timeout=60)
        need(done.returncode in (0, 1) and len(done.stdout) < 8 * 1024 * 1024, 'bounded_immutable_reference_search_failed')
        self.counts['git_reference_searches'] += 1
        prefix = self.pins[role] + ':'
        names = []
        for line in done.stdout.decode('utf8').split('\x00'):
            if not line:
                continue
            need(line.startswith(prefix), 'reference_search_wrong_revision')
            names.append(line[len(prefix):])
        return names

    def close(self):
        self.reader.close()

def reference_scan(sources, paths):
    patterns = sorted(set(paths) | {Path(p).name for p in paths})
    mentions = {p: re.compile('(?<![\\w.-])(?:' + re.escape(p) + ('' if p == KEEPER_MANIFEST else '|' + re.escape(Path(p).name)) + ')(?![\\w.-])') for p in paths}
    refs, blockers, scan = ({}, [], [])
    allowed_metadata = {('game', JS), ('game', LUA), ('content', CONTENT_JS)}
    allowed_metadata.update((('game', CSV_OUTPUTS[p]) for p in paths if p in CSV_OUTPUTS))
    for role in ('game', 'content'):
        matched = set(sources.grep(role, patterns))
        api = set(sources.grep(role, ['LoadKeyValues|LoadKVFile|LoadFile|loadfile|dofile|readFile|read_text|read_bytes|io\\.open|AsyncWebRequest|data[/\\\\]+(ui|csv)'], False))
        runtime_api_sites = 0
        for path in sorted(matched | {p for p in api if runtime_path(role, p)}):
            raw = sources.get(role, path)
            text = raw.decode('utf-8-sig')
            key = role + ':' + path
            hits = {candidate: [n for n, line in enumerate(text.split('\n'), 1) if mentions[candidate].search(line)] for candidate in paths}
            hits = {p: lines for p, lines in hits.items() if lines}
            sites = read_sites(text, paths, 'lua' if path.endswith('.lua') else 'js') if runtime_path(role, path) else []
            runtime_api_sites += len(sites)
            bad = [s for s in sites if s['candidate_json_read'] or s['uncertain_data_ui_read']]
            if bad:
                blockers.append({'source_id': key, 'reason': 'RUNTIME_JSON_READ_OR_UNCERTAIN_NAMESPACE', 'sites': bad})
            if hits and runtime_path(role, path) and ((role, path) not in allowed_metadata):
                unreviewed = set(hits)
                for resource, author in KEEPER_AUTHORS.items():
                    if author not in unreviewed or author in text:
                        continue
                    logical = resource[:-2]
                    remainder = text.replace('"' + logical + '"', '').replace("'" + logical + "'", '')
                    if not mentions[author].search(remainder):
                        unreviewed.remove(author)
                if unreviewed:
                    blockers.append({'source_id': key, 'reason': 'UNREVIEWED_RUNTIME_REFERENCE', 'paths': sorted(unreviewed)})
            if hits:
                refs[key] = {**sources.facts[key], 'source_revision': sources.pins[role], 'matches': hits, 'reference_role': 'GENERATED_PROVENANCE_METADATA_NOT_FILE_READ' if (role, path) in allowed_metadata else 'BUILD_TOOL_TEST_DOCUMENT_OR_GENERATION_METADATA', 'runtime_read_api_sites': sites}
        scan.append({'repo': role, 'revision': sources.pins[role], 'exact_reference_files': len(matched), 'runtime_api_files_considered': sum((runtime_path(role, p) for p in api)), 'runtime_api_sites': runtime_api_sites, 'method': 'immutable git grep file index plus batch raw-Git token-aware read-API audit'})
    return {'kind': 'IMMUTABLE_EXACT_DATA_UI_REFERENCE_SCAN_NOT_RUNTIME_DISPOSITION', 'source_revisions': {k: sources.pins[k] for k in ('game', 'content')}, 'scan': scan, 'references': refs, 'runtime_read_blockers': blockers, 'source_facts': sources.facts.copy(), 'directory_prefix_dispositions': False, 'raw_source_or_private_payloads_disclosed': False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for role in ('game', 'content', 'operator'):
        parser.add_argument('--' + role + '-revision', required=True)
    parser.add_argument('--scope', required=True, type=Path)
    parser.add_argument('--scope-sha256', required=True)
    parser.add_argument('--output-prefix', required=True, type=Path)
    parser.add_argument('--diagnostic-uncommitted-tool', action='store_true')
    args = parser.parse_args()
    pins = {role: getattr(args, role + '_revision') for role in ('game', 'content', 'operator')}
    scope_path = args.scope.resolve()
    need(scope_path.is_relative_to((ROOT / 'output').resolve()) and (not scope_path.is_symlink()), 'scope_must_be_workspace_output')
    scope_raw = scope_path.read_bytes()
    need(len(scope_raw) < 32 * 1024 * 1024 and sha(scope_raw) == args.scope_sha256, 'exact_scope_raw_sha_required')
    scope = json.loads(scope_raw)
    sources = Sources(pins)
    try:
        operator = {}
        for path in (TOOL, 'tools/complete_delivery_pack_2026111002_e1fa24/parent_pending.py', 'tools/release_pending_inventory.py', 'tools/release_compile_scope.py', LOCALIZATION_TOOL):
            actual = (ROOT / path).read_bytes().replace(b'\r\n', b'\n')
            loaded = {TOOL: EXECUTED_SHA, 'tools/complete_delivery_pack_2026111002_e1fa24/parent_pending.py': pending.EXECUTED_SOURCE_LF_SHA256, 'tools/release_pending_inventory.py': pending.legacy.EXECUTED_SOURCE_LF_SHA256, 'tools/release_compile_scope.py': compiler.EXECUTED_TOOL_LF_SHA256, LOCALIZATION_TOOL: localization.EXECUTED_SOURCE_LF_SHA256}[path]
            need(sha(actual) == loaded, 'review_tool_or_dependency_changed_after_import:' + path)
            try:
                declared = compiler.run_git(ROOT, 'show', pins['operator'] + ':' + path).replace(b'\r\n', b'\n')
            except ValueError:
                declared = None
            operator[path] = {'executed_lf_sha256': sha(actual), 'declared_lf_sha256': sha(declared) if declared is not None else None, 'matches_operator_commit': declared == actual}
        committed = all((v['matches_operator_commit'] for v in operator.values()))
        need(committed or args.diagnostic_uncommitted_tool, 'review_tool_not_in_exact_operator_commit')
        rows = [r for r in scope['decisions'] if r['inventory_status'] == 'UNMAPPED_SOURCE_PENDING']
        blobs = load_review_blobs(sources, rows, pins)
        mappings = runtime_mapping_reviews(rows, pins, blobs, sources.facts)
        mapped = {row['source_id'] for row in mappings}
        paths = {r['source']['path'] for r in rows if r['source']['repo'] + ':' + r['source']['path'] not in mapped}
        scan = reference_scan(sources, paths)
        scan['operator_binding'] = {'revision': pins['operator'], 'tools': operator, 'committed': committed}
        scan['typed_runtime_mapping_source_ids'] = sorted(mapped)
        scan_raw = canonical(scan)
        review = make_reviews(scope, sha(scope_raw), pins, blobs, sources.facts, scan, sha(scan_raw))
        review['operator_binding'] = scan['operator_binding']
        review['diagnostic_only_uncommitted_tool'] = not committed
        review['read_costs'] = {**sources.counts, 'batch_blob_requests': sources.reader.requests, 'batch_source_bytes': sources.reader.used}
        prefix = args.output_prefix.resolve()
        need(prefix.is_relative_to((ROOT / 'output/packager/pack_2026111002_98e1fa24/scope').resolve()) and (not prefix.is_symlink()), 'fixed_scope_output_prefix_required')
        documents = [(Path(str(prefix) + '_reference_scan.json'), scan_raw), (Path(str(prefix) + '_path_review.json'), canonical(review))]
        for path, _ in documents:
            need(not path.exists(), 'fresh_exact_review_outputs_required')
        for path, raw in documents:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream:
                stream.write(raw)
        print(json.dumps({'kind': 'EXACT_REVIEW_GENERATED_NOT_RELEASE_AUTHORITY', 'reviews': len(review['reviews']), 'diagnostic': not committed, 'reference_scan': {'path': str(documents[0][0]), 'sha256': sha(documents[0][1])}, 'exact_review': {'path': str(documents[1][0]), 'sha256': sha(documents[1][1])}, 'runtime_read_blockers': len(scan['runtime_read_blockers'])}))
    finally:
        sources.close()
if __name__ == '__main__':
    main()
