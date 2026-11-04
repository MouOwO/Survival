"""Exact immutable standalone-JSON review; never a release authority.

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
import release_pending_inventory as pending
import release_compile_scope as compiler

TOOL = 'tools/complete_delivery_release_20261103/exact_review.py'
EXECUTED_SHA = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
MANIFEST = 'data/ui/ui_static_catalog_manifest.json'
REGISTRY = 'data/ui/ui_static_catalog_registry.json'
ATLAS = 'data/ui/grid_static_atlas_candidate_20261103.json'
JS = 'panorama/src/scripts/custom_game/common/ui_static_catalog.js'
CONTENT_JS = 'panorama/scripts/custom_game/common/ui_static_catalog.js'
LUA = 'scripts/vscripts/config/generated/ui_static_catalog_lookup.lua'
TARGETS = ['panorama/scripts/custom_game/common/ui_static_catalog.vjs_c', LUA]
EVIDENCE = {
 'data/ui/network50_dev05_evidence_20261103.json': ('status', 'LOCAL_TOOLS_NATIVE_PARTIAL_EVIDENCE_NOT_FPS_OR_WORKSHOP_ACCEPTANCE'),
 'data/ui/network50_dev06_fps_reclassification_20261103.json': ('status', 'RECLASSIFIED_INVALID_GAMEPLAY_CAPTURE_ORIGINAL_RETAINED'),
 'data/ui/network50_dev07_evidence_20261103.json': ('status', 'LOCAL_TOOLS_NATIVE_AND_VALID_UNCOVERED_FPS_EVIDENCE_NOT_ORDINARY_OR_WORKSHOP_ACCEPTANCE'),
 'data/ui/ui_compact_native08_observation_20261104.json': ('kind', 'CLOSED_NATIVE08_WIRE_OBSERVATION_WITH_UNKNOWN_UI_INPUT_PROVENANCE_NOT_VISUAL_OR_TRANSACTION_ACCEPTANCE'),
 'data/ui/ui_compact_wire_native_evidence_20261103.json': ('kind', 'NATIVE_TOOLS_BIDIRECTIONAL_MESSAGE_CALIBRATION_NOT_ORDINARY_ACCEPTANCE'),
 'data/ui/ui_grid_bulk_native_evidence_20261103.json': ('kind', 'CLOSED_NATIVE_TOOLS_GB_SIZING_NOT_FULL_GRID_OR_FPS'),
}
LOADERS = {'LoadKeyValues', 'LoadKeyValuesFromString', 'LoadKVFile', 'LoadFile', 'loadfile', 'dofile',
           'require', 'readFileSync', 'readFile', 'read_text', 'read_bytes', 'open', 'fetch',
           'AsyncWebRequest', 'BLoadLayout', 'BLoadLayoutFromString', 'LoadLayout', 'LoadLayoutFromString'}
TOKEN_JS = re.compile(r'''(?P<comment>/\*.*?\*/|//[^\n]*)|(?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?P<id>[A-Za-z_$][\w$]*)|(?P<punct>[^\s])''', re.S)
TOKEN_LUA = re.compile(r'''(?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)|(?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?P<long>\[(?P<leq>=*)\[.*?\](?P=leq)\])|(?P<id>[A-Za-z_$][\w$]*)|(?P<punct>[^\s])''', re.S)


def need(value, reason):
    if not value: raise ValueError(reason)


def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(value): return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'), allow_nan=False)+'\n').encode('ascii')


def runtime_path(role, path):
    # These are actual mounted game-source roots, not a disposition of JSONs.
    return path.startswith(('scripts/', 'panorama/', 'cfg/', 'resource/')) and not path.startswith('scripts/vscripts/tests/')


def read_sites(text, paths, language='js'):
    """Ignore comments/string bodies as executable code; flag uncertain UI reads."""
    literal_paths = {p.replace('\\', '/') for p in paths}
    basenames = {Path(p).name for p in paths}
    namespace, sites, window, position, line_number = False, [], [], 0, 1
    # Stream a four-token window: large generated catalogues need O(1) lexer
    # workspace, not a token array or repeated prefix newline scans.
    tokenizer = TOKEN_LUA if language == 'lua' else TOKEN_JS
    for match in tokenizer.finditer(text):
        line_number += text.count('\n', position, match.start()); position = match.start()
        kind, token = match.lastgroup, match.group()
        if kind == 'comment': continue
        if kind in ('string', 'long') and ('data/ui' in token or 'data\\\\ui' in token): namespace = True
        window.append((kind, token, line_number))
        if len(window) > 4: window.pop(0)
        if len(window) != 4: continue
        (kind, name, line), opening, argument, following = window
        if kind != 'id' or name not in LOADERS or opening[1] != '(': continue
        argkind, arg, _ = argument
        static = argkind == 'string' and following[1] in (')', ',')
        value = arg[1:-1].replace('\\\\', '/') if argkind == 'string' else ''
        direct = static and (value in literal_paths or Path(value).name in basenames)
        sites.append({'api': name, 'line': line, 'literal_first_argument': static,
                      'candidate_json_read': bool(direct), 'uncertain_data_ui_read': 'data/ui' in value,
                      '_dynamic': not static})
    for site in sites:
        site['uncertain_data_ui_read'] = bool(site['uncertain_data_ui_read'] or (site.pop('_dynamic') and namespace))
    return sites


def validate_registry(document):
    need(document.get('format') == 1 and type(document.get('generation')) is int and document['generation'] > 0, 'registry_format_or_generation_invalid')
    for key, label, maximum in [('records', 'key', 65535), ('fields', 'name', 255)]:
        rows = document.get(key); need(isinstance(rows, list), 'registry_array_required')
        ids, names = set(), set()
        for row in rows:
            value, name = row.get('id'), row.get(label)
            need(type(value) is int and 1 <= value <= maximum and value not in ids and isinstance(name, str) and name and name not in names, 'registry_identity_invalid')
            ids.add(value); names.add(name)


def validate_lineage(registry_raw, manifest, histories):
    """All declared nodes are parsed, SHA-named and in the exact parent chain."""
    registry = json.loads(registry_raw); validate_registry(registry)
    current = sha(registry_raw)
    need(manifest.get('registry_sha256') == current, 'registry_manifest_sha_mismatch')
    declared = {p: v for p, v in manifest.get('source_hashes', {}).items() if p.startswith('data/ui/registry_history/')}
    need(set(declared) == set(histories), 'history_exact_declared_set_required')
    nodes = {}
    for path, raw in histories.items():
        digest = sha(raw)
        need(path == 'data/ui/registry_history/'+digest+'.json' and declared[path] == digest, 'history_filename_or_manifest_sha_mismatch')
        node = json.loads(raw); validate_registry(node); nodes[digest] = node
    seen, cursor, child = set(), current, None
    while cursor is not None:
        need(cursor in nodes and cursor not in seen, 'history_missing_node_or_cycle')
        node = nodes[cursor]; seen.add(cursor)
        if child is not None:
            need(node['generation']+1 == child['generation'], 'history_generation_gap')
            for collection, identity in [('records', 'key'), ('fields', 'name')]:
                newer = {r['id']: r for r in child[collection]}
                for old in node[collection]:
                    new = newer.get(old['id'])
                    need(new and new[identity] == old[identity], 'history_identity_reused_or_removed')
                    if collection == 'fields':
                        for k, v in old.items():
                            need((new.get(k, [])[:len(v)] == v if k == 'enum' and isinstance(v, list) else new.get(k) == v), 'history_field_semantics_changed')
                    else:
                        for k in ('domain', 'kind', 'business_id'):
                            need(new.get(k) == old.get(k), 'history_record_semantics_changed')
                        need(not old.get('tombstone') or new.get('tombstone'), 'history_tombstone_reused')
        child, cursor = node, node.get('parent_sha256')
    need(seen == set(nodes) and len(seen) == registry['generation'], 'history_unreachable_or_incomplete_nodes')
    need(nodes[current] == registry, 'current_registry_history_node_differs')
    return {'generation': registry['generation'], 'nodes_parsed': len(seen), 'records': len(registry['records']),
            'fields': len(registry['fields']), 'registry_sha256': current, 'exact_parent_chain': True,
            'append_only_identities_verified': True}


def validate_catalog(blobs):
    manifest = json.loads(blobs[MANIFEST]); registry = json.loads(blobs[REGISTRY])
    histories = {p: raw for p, raw in blobs.items() if p.startswith('data/ui/registry_history/')}
    checks = validate_lineage(blobs[REGISTRY], manifest, histories)
    need(checks['generation'] == 12 and checks['nodes_parsed'] == 12, 'review_requires_exact_twelve_history_nodes')
    for path in (REGISTRY, ATLAS): need(manifest['source_hashes'].get(path) == sha(blobs[path]), 'catalog_input_sha_mismatch:'+path)
    for path in (JS, LUA, REGISTRY): need(manifest['outputs'].get(path) == sha(blobs[path]), 'catalog_output_sha_mismatch:'+path)
    need(blobs['content:'+CONTENT_JS] == blobs[JS], 'catalog_content_mirror_differs')
    text = blobs[JS].decode('utf8'); start = re.search(r'var data\s*=\s*', text)
    need(start, 'generated_catalog_data_literal_missing')
    data, _ = json.JSONDecoder().raw_decode(text[start.end():])
    need(data['sha256'] == manifest['schema_sha256'] and data['registry_sha256'] == checks['registry_sha256'], 'generated_catalog_schema_mismatch')
    need(data['records'] == registry['records'] and data['fields'] == registry['fields'], 'generated_catalog_registry_semantics_mismatch')
    need(data['source_hashes'] == manifest['source_hashes'], 'generated_source_provenance_mismatch')
    need(re.search(r'\["sha256"\]="'+re.escape(manifest['schema_sha256'])+'"', blobs[LUA].decode('utf8')), 'lookup_schema_mismatch')
    source = json.loads(blobs[ATLAS]); embedded = data['auxiliary']['grid']['atlases']
    need(isinstance(source.get('atlases'), list) and len(source['atlases']) == len(embedded) > 0, 'atlas_count_mismatch')
    for old, new in zip(source['atlases'], embedded):
        for key in ('id', 'map', 'area', 'source_map_sha256'):
            need(old.get(key) == new.get(key), 'atlas_embedded_value_mismatch:'+key)
        need(new.get('authority') is False and new.get('requires_current_live_scan') is True, 'atlas_must_remain_non_authoritative')
    checks.update(schema_sha256=manifest['schema_sha256'], generated_js_lua_hashes_verified=True,
                  content_mirror_exact=True, atlas_embedded_and_non_authoritative=True)
    return checks


def make_reviews(scope, scope_sha256, pins, blobs, facts, scan, scan_sha256):
    need(scope.get('observed_commits') == {k: pins[k] for k in ('game', 'content')}, 'scope_source_revisions_mismatch')
    rows = [r for r in scope['decisions'] if r['inventory_status'] == 'UNMAPPED_SOURCE_PENDING']
    paths = {r['source']['path'] for r in rows}
    manifest = json.loads(blobs[MANIFEST]); histories = {p for p in manifest['source_hashes'] if p.startswith('data/ui/registry_history/')}
    need(len(rows) == len(paths) == 21 and paths == {ATLAS, MANIFEST, REGISTRY, *EVIDENCE, *histories}, 'unmapped_set_not_exact_reviewed_twenty_one')
    checks = validate_catalog(blobs)
    need(not scan['runtime_read_blockers'], 'runtime_reference_or_loader_requires_manual_review')
    reviews = []
    for row in sorted(rows, key=lambda r: r['source']['path']):
        path = row['source']['path']; key = 'game:'+path; raw = blobs[path]; fact = facts[key]
        need(row['source']['repo'] == 'game' and fact['git_oid'] == row['source']['head_oid'] and fact['sha256'] == row['candidate']['sha256'] == sha(raw), 'scope_git_source_fact_mismatch:'+path)
        value = json.loads(raw); extra = {}
        if path in EVIDENCE:
            field, expected = EVIDENCE[path]
            need(value.get(field) == expected, 'evidence_exact_semantic_type_mismatch:'+path)
            if path.endswith('dev06_fps_reclassification_20261103.json'): need(value.get('corrected_valid') is False, 'invalid_fps_reclassified_as_pass')
            if path.endswith('ui_grid_bulk_native_evidence_20261103.json'): need(value.get('actual_grid_payload_tested') is False and value.get('max_native_bytes') == 923, 'bulk_scope_or_measurement_changed')
            if path.endswith('ui_compact_native08_observation_20261104.json'): need(value.get('production7_visual_or_operation_acceptance') is False and value.get('fps_measured') is False, 'unknown_input_observation_overclaimed')
            classification = 'EXACT_PUBLIC_NUMERIC_OBSERVATION_NOT_RUNTIME_COMPONENT'
            reason = 'Parsed this exact public observation JSON and preserved its stated native/FPS/acceptance limitations. Immutable source-reference and executable read-API scans found no runtime read of this standalone path. Retain in Git as evidence; no UI/game state is loaded from it.'
            targets = []; extra = {'parsed_semantic_discriminator': {field: expected}, 'runtime_file_read_hits': 0}
        elif path == ATLAS:
            classification = 'PUBLIC_BUILD_INPUT_WITH_RUNTIME_DATA_EMBEDDED_IN_GENERATED_CATALOG'
            reason = 'Exact candidate atlas bytes are pinned by the generated manifest and its area/map values are embedded in verified JS/Lua outputs. Runtime consumes the generated catalogue and still requires live authoritative scans; exclude only the standalone JSON, not its generated targets.'
            targets = TARGETS; extra = checks
        elif path == MANIFEST:
            classification = 'EXACT_GENERATOR_SOURCE_OUTPUT_MANIFEST_NOT_RUNTIME_FILE'
            reason = 'Parsed manifest pins exact current registry, all twelve concrete history nodes, atlas and generated JS/Lua source bytes. It is build provenance rather than a runtime JSON loader; generated targets remain separately required.'
            targets = TARGETS; extra = checks
        else:
            classification = 'EXACT_APPEND_ONLY_REGISTRY_OR_HISTORY_BUILD_INPUT_NOT_RUNTIME_FILE'
            reason = 'Parsed and SHA-verified this concrete node in the exact twelve-generation parent chain, including append-only record/field semantics. Verified current generated IDs and schema against the catalogue. No history-directory prefix is ignored; generated targets remain separately required.'
            targets = TARGETS; extra = {**checks, 'this_node_generation': value['generation']}
        refs = []
        for refkey, source in scan['references'].items():
            if path in source['matches']: refs.append({'source_id': refkey, 'git_oid': source['git_oid'], 'sha256': source['sha256'], 'matches': source['matches'][path], 'reference_role': source['reference_role']})
        reviews.append({'source_id': key, 'source_revision': pins['game'], 'git_oid': fact['git_oid'], 'sha256': sha(raw), 'bytes': len(raw),
                        'classification': classification, 'checks': extra, 'reason': reason, 'references': refs,
                        'standalone_runtime_file_required': False, 'authority_granted': False, 'retained_in_git': True,
                        'scope_action_proposal': 'non_runtime_standalone_exact_path_review',
                        'semantic_or_build_dependency': bool(targets), 'runtime_targets_requiring_separate_generator_or_compiler_binding': targets})
    return {'schema': 1, 'kind': 'IMMUTABLE_DATA_UI_EXACT_PATH_REVIEW_NOT_RELEASE_AUTHORITY', 'source_revisions': pins,
            'inventory_sha256': scope_sha256, 'input_scope_sha256': scope_sha256, 'reference_scan_sha256': scan_sha256,
            'scope': {'actual_unmapped_count': len(rows), 'exact_paths': sorted(paths), 'directory_prefix_exclusions': False},
            'reviews': reviews, 'publication_ready': False,
            'limits': ['Exact-path immutable static audit, not a dynamic runtime file-access trace.',
                       'Direct loader calls and data/ui-dependent dynamic loader sites are checked; arbitrary computed external paths are not proven absent.',
                       'Unknown matched runtime references/read sites block instead of becoming automatic exclusions.',
                       'Generated targets still require their separate original generator/compiler/protection bindings.']}


class Sources:
    def __init__(self, pins):
        self.pins, self.counts = pins, Counter()
        self.roots = {'game': ROOT, 'content': pending.CONTENT}
        for role, revision in pins.items():
            compiler.immutable(self.roots.get(role, ROOT), revision)
        self.trees = {role: pending.git_tree(root, self.counts, pins[role]) for role, root in self.roots.items()}
        self.reader = compiler.Reader(self.roots, self.trees)
        self.facts = {}
    def get(self, role, path):
        result = self.reader.get(role, path)
        need(not result['lfs'], 'review_requires_exact_raw_text_git_blob:'+path)
        self.facts[role+':'+path] = {'source_revision': self.pins[role], 'git_oid': result['oid'],
                                   'raw_git_sha256': result['git_blob']['sha256'],
                                   'sha256': result['content']['sha256'], 'bytes': len(result['raw'])}
        return result['raw']
    def grep(self, role, patterns, fixed=True):
        argv = ['git', '--no-replace-objects', '-c', 'safe.directory='+self.roots[role].as_posix(), '-C', str(self.roots[role]), 'grep', '-l', '-I', '-F' if fixed else '-E']
        for pattern in patterns: argv += ['-e', pattern]
        argv += [self.pins[role], '--', 'tools', 'docs', 'scripts', 'panorama', 'data', 'cfg', 'resource']
        done = subprocess.run(argv, capture_output=True, timeout=60)
        need(done.returncode in (0, 1) and len(done.stdout) < 8*1024*1024, 'bounded_immutable_reference_search_failed')
        self.counts['git_reference_searches'] += 1
        prefix = self.pins[role]+':'
        names = []
        for line in done.stdout.decode('utf8').splitlines():
            need(line.startswith(prefix), 'reference_search_wrong_revision'); names.append(line[len(prefix):])
        return names
    def close(self): self.reader.close()


def reference_scan(sources, paths):
    patterns = sorted(set(paths) | {Path(p).name for p in paths})
    refs, blockers, scan = {}, [], []
    allowed_metadata = {('game', JS), ('game', LUA), ('content', CONTENT_JS)}
    for role in ('game', 'content'):
        matched = set(sources.grep(role, patterns))
        api = set(sources.grep(role, [r'LoadKeyValues|LoadKVFile|LoadFile|loadfile|dofile|readFile|read_text|read_bytes|io\.open|AsyncWebRequest|data/ui'], False))
        runtime_api_sites = 0
        for path in sorted(matched | {p for p in api if runtime_path(role, p)}):
            raw = sources.get(role, path); text = raw.decode('utf-8-sig'); key = role+':'+path
            hits = {candidate: [n for n, line in enumerate(text.split('\n'), 1) if candidate in line or Path(candidate).name in line] for candidate in paths}
            hits = {p: lines for p, lines in hits.items() if lines}
            sites = read_sites(text, paths, 'lua' if path.endswith('.lua') else 'js') if runtime_path(role, path) else []
            runtime_api_sites += len(sites)
            bad = [s for s in sites if s['candidate_json_read'] or s['uncertain_data_ui_read']]
            if bad: blockers.append({'source_id': key, 'reason': 'RUNTIME_JSON_READ_OR_UNCERTAIN_NAMESPACE', 'sites': bad})
            if hits and runtime_path(role, path) and (role, path) not in allowed_metadata:
                blockers.append({'source_id': key, 'reason': 'UNREVIEWED_RUNTIME_REFERENCE', 'paths': sorted(hits)})
            if hits:
                refs[key] = {**sources.facts[key], 'source_revision': sources.pins[role], 'matches': hits,
                             'reference_role': 'GENERATED_PROVENANCE_METADATA_NOT_FILE_READ' if (role, path) in allowed_metadata else
                             'BUILD_TOOL_TEST_DOCUMENT_OR_GENERATION_METADATA', 'runtime_read_api_sites': sites}
        scan.append({'repo': role, 'revision': sources.pins[role], 'exact_reference_files': len(matched),
                     'runtime_api_files_considered': sum(runtime_path(role, p) for p in api), 'runtime_api_sites': runtime_api_sites,
                     'method': 'immutable git grep file index plus batch raw-Git token-aware read-API audit'})
    return {'kind': 'IMMUTABLE_EXACT_DATA_UI_REFERENCE_SCAN_NOT_RUNTIME_DISPOSITION',
            'source_revisions': {k: sources.pins[k] for k in ('game', 'content')}, 'scan': scan,
            'references': refs, 'runtime_read_blockers': blockers, 'source_facts': sources.facts.copy(),
            'directory_prefix_dispositions': False, 'raw_source_or_private_payloads_disclosed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for role in ('game', 'content', 'operator'): parser.add_argument('--'+role+'-revision', required=True)
    parser.add_argument('--scope', required=True, type=Path); parser.add_argument('--scope-sha256', required=True)
    parser.add_argument('--output-prefix', required=True, type=Path)
    parser.add_argument('--diagnostic-uncommitted-tool', action='store_true'); args = parser.parse_args()
    pins = {role: getattr(args, role+'_revision') for role in ('game', 'content', 'operator')}
    scope_path = args.scope.resolve(); need(scope_path.is_relative_to((ROOT/'output').resolve()) and not scope_path.is_symlink(), 'scope_must_be_workspace_output')
    scope_raw = scope_path.read_bytes(); need(len(scope_raw) < 32*1024*1024 and sha(scope_raw) == args.scope_sha256, 'exact_scope_raw_sha_required')
    scope = json.loads(scope_raw); sources = Sources(pins)
    try:
        operator = {}
        for path in (TOOL, 'tools/release_pending_inventory.py', 'tools/release_compile_scope.py'):
            actual = (ROOT/path).read_bytes().replace(b'\r\n', b'\n')
            loaded = {TOOL: EXECUTED_SHA, 'tools/release_pending_inventory.py': pending.EXECUTED_SOURCE_LF_SHA256,
                      'tools/release_compile_scope.py': compiler.EXECUTED_TOOL_LF_SHA256}[path]
            need(sha(actual) == loaded, 'review_tool_or_dependency_changed_after_import')
            try: declared = compiler.run_git(ROOT, 'show', pins['operator']+':'+path).replace(b'\r\n', b'\n')
            except ValueError: declared = None
            operator[path] = {'executed_lf_sha256': sha(actual), 'declared_lf_sha256': sha(declared) if declared is not None else None, 'matches_operator_commit': declared == actual}
        committed = all(v['matches_operator_commit'] for v in operator.values())
        need(committed or args.diagnostic_uncommitted_tool, 'review_tool_not_in_exact_operator_commit')
        rows = [r for r in scope['decisions'] if r['inventory_status'] == 'UNMAPPED_SOURCE_PENDING']
        paths = {r['source']['path'] for r in rows}; blobs = {path: sources.get('game', path) for path in sorted(paths)}
        for path in (JS, LUA): blobs[path] = sources.get('game', path)
        blobs['content:'+CONTENT_JS] = sources.get('content', CONTENT_JS)
        scan = reference_scan(sources, paths); scan['operator_binding'] = {'revision': pins['operator'], 'tools': operator, 'committed': committed}
        scan_raw = canonical(scan)
        review = make_reviews(scope, sha(scope_raw), pins, blobs, sources.facts, scan, sha(scan_raw))
        review['operator_binding'] = scan['operator_binding']; review['diagnostic_only_uncommitted_tool'] = not committed
        review['read_costs'] = {**sources.counts, 'batch_blob_requests': sources.reader.requests, 'batch_source_bytes': sources.reader.used}
        prefix = args.output_prefix.resolve(); need(prefix.is_relative_to((ROOT/'output/compact_delivery_scope_20261103').resolve()) and not prefix.is_symlink(), 'fixed_scope_output_prefix_required')
        documents = [(Path(str(prefix)+'_reference_scan.json'), scan_raw), (Path(str(prefix)+'_path_review.json'), canonical(review))]
        for path, _ in documents: need(not path.exists(), 'fresh_exact_review_outputs_required')
        for path, raw in documents:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream: stream.write(raw)
        print(json.dumps({'kind': 'EXACT_REVIEW_GENERATED_NOT_RELEASE_AUTHORITY', 'reviews': len(review['reviews']), 'diagnostic': not committed,
                          'reference_scan': {'path': str(documents[0][0]), 'sha256': sha(documents[0][1])},
                          'exact_review': {'path': str(documents[1][0]), 'sha256': sha(documents[1][1])}, 'runtime_read_blockers': len(scan['runtime_read_blockers'])}))
    finally: sources.close()


if __name__ == '__main__': main()
