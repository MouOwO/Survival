"""Pure complete-source coverage ledger; not signing/publication authority.

All documents are supplied as exact pinned bytes. The inventory must be freshly
recomputed from the chosen dual Git trees and authenticated signed parent by
the eventual authority. This module validates its exhaustive declared coverage;
it cannot authenticate a caller's compiler/protection/review receipt by itself.
There is deliberately no SDK, journal, process, filesystem or deletion API.
"""
from __future__ import annotations
import hashlib
import json
import re
import struct
from pathlib import Path, PurePosixPath
from complete_delivery_pack_2026111008_c0a4f5 import localization_projection
EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
MAX_DOCUMENT = 32 * 1024 * 1024
KINDS = frozenset(('identity', 'compiled', 'generated', 'protected', 'production_override', 'localization_projection'))
RUNTIME_ROOTS = frozenset(('scripts', 'panorama', 'maps', 'materials', 'models', 'particles', 'resource', 'sounds', 'soundevents', 'cfg'))
REMOVED = frozenset(('RUNTIME_REMOVAL_PENDING', 'SOURCE_REMOVED_REQUIRES_RUNTIME_DECISION'))
STATUSES = REMOVED | frozenset(('PARENT_BYTES_MATCH', 'HISTORICAL_REVIEW_REQUIRED_PARENT_BYTES_MATCH', 'PENDING_RUNTIME_UPDATE', 'PENDING_RUNTIME_ADD', 'PRODUCTION_TRANSFORM_REQUIRED', 'GENERATED_BINDING_REQUIRED', 'UNCOMPILED_BINDING_REQUIRED', 'UNBOUND_COMPILED_ARTIFACT', 'UNMAPPED_SOURCE_PENDING'))

def need(value, reason):
    if not value:
        raise ValueError(reason)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':'), allow_nan=False) + '\n').encode('ascii')

def digest(value):
    need(isinstance(value, str) and re.fullmatch('[a-f0-9]{64}', value), 'sha256_required')
    return value

def revision(value):
    need(isinstance(value, str) and re.fullmatch('[a-f0-9]{40}', value), 'immutable_git_commit_required')
    return value

def path(value):
    need(isinstance(value, str) and value and ('\\' not in value) and (':' not in value) and ('\x00' not in value), 'canonical_relative_posix_path_required')
    p = PurePosixPath(value)
    need(not p.is_absolute() and str(p) == value and all((v not in ('', '.', '..') for v in p.parts)), 'canonical_relative_posix_path_required')
    return value

def source_id(value):
    need(isinstance(value, str) and ':' in value, 'source_id_required')
    role, name = value.split(':', 1)
    need(role in ('game', 'content'), 'unknown_source_repository')
    return role + ':' + path(name)

def document(raw, pin):
    need(type(raw) is bytes and len(raw) <= MAX_DOCUMENT and (sha(raw) == digest(pin)), 'exact_bounded_document_bytes_required')

    def pairs(items):
        value = {}
        for key, item in items:
            need(key not in value, 'duplicate_json_key')
            value[key] = item
        return value

    def invalid(_):
        raise ValueError('nonfinite_json_value')
    value = json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)
    need(isinstance(value, dict), 'json_object_required')
    return value

def fingerprint(row):
    need(isinstance(row, dict), 'resource_fingerprint_required')
    digest(row.get('sha256'))
    need(type(row.get('bytes')) is int and 0 <= row['bytes'] <= 2 ** 40, 'resource_byte_count_required')
    need(isinstance(row.get('md5'), str) and re.fullmatch('[a-f0-9]{32}', row['md5']), 'resource_md5_required')
    return {key: row[key] for key in ('bytes', 'sha256', 'md5')}

def parent_rows(parent):
    need(isinstance(parent.get('files'), list), 'complete_parent_resource_rows_required')
    result, casefold = ({}, set())
    for row in parent['files']:
        need(set(row) == {'path', 'bytes', 'sha256', 'md5'}, 'parent_resource_row_schema_requires_explicit_adapter')
        name = path(row.get('path'))
        fingerprint(row)
        need(name not in result and name.casefold() not in casefold, 'duplicate_or_case_colliding_parent_resource')
        result[name] = row.copy()
        casefold.add(name.casefold())
    need(parent.get('file_count') == len(result), 'parent_file_count_mismatch')
    need(parent.get('bytes') == sum((row['bytes'] for row in result.values())), 'parent_byte_count_mismatch')
    digest(parent.get('content_sha256'))
    return result

def byte_fingerprint(raw):
    need(type(raw) is bytes and len(raw) <= MAX_DOCUMENT, 'bounded_original_artifact_bytes_required')
    return {'bytes': len(raw), 'sha256': sha(raw), 'md5': hashlib.md5(raw, usedforsecurity=False).hexdigest()}

def _unique(rows, key, reason):
    need(isinstance(rows, list), reason)
    result = {}
    for row in rows:
        need(isinstance(row, dict) and row.get(key) not in result, reason)
        result[row.get(key)] = row
    return result

def _compiled_data(raw, texture=False):
    """Recheck the actual Valve resource blocks, never trust receipt DATA flags."""
    need(28 <= len(raw) <= MAX_DOCUMENT, 'bounded_compiled_resource_required')
    size, version, _, offset, count = struct.unpack_from('<IHHII', raw)
    start = 8 + offset
    need((16 <= size <= len(raw) if texture else size == len(raw)) and version == 12 and (1 <= count <= 64) and (16 <= start <= size - count * 12), 'compiled_resource_header_invalid')
    result, ranges = ({}, [])
    for index in range(count):
        entry = start + index * 12
        tag, displacement, length = struct.unpack_from('<4sII', raw, entry)
        begin = entry + 4 + displacement
        end = begin + length
        need(all((32 <= v <= 126 for v in tag)) and tag not in result and (begin >= start + count * 12) and (end <= size) and (not any((begin < prior_end and prior_begin < end for prior_begin, prior_end in ranges))), 'compiled_resource_block_invalid')
        result[tag] = raw[begin:end]
        ranges.append((begin, end))
    need(b'DATA' in result, 'compiled_resource_data_missing')
    return (result, size)

def _resolved_git_bytes(value):
    """An LFS pointer and its payload are separate, explicitly supplied bytes."""
    if type(value) is bytes:
        byte_fingerprint(value)
        need(not value.startswith(b'version https://git-lfs.github.com/spec/v1'), 'unresolved_lfs_pointer_bytes_refused')
        return (value, value, False)
    need(isinstance(value, dict) and set(value) == {'git_blob', 'content'}, 'explicit_git_blob_and_resolved_lfs_bytes_required')
    git_raw, content = (value['git_blob'], value['content'])
    byte_fingerprint(git_raw)
    byte_fingerprint(content)
    pointer = re.fullmatch(b'version https://git-lfs.github.com/spec/v1\\noid sha256:([a-f0-9]{64})\\nsize ([0-9]+)\\n?', git_raw)
    need(pointer and sha(content) == pointer[1].decode() and (len(content) == int(pointer[2])), 'resolved_lfs_pointer_identity_mismatch')
    return (git_raw, content, True)

def verify_compiler_receipt(*, plan_raw, plan_sha256, proof_raw, proof_sha256, source_revisions, compiler_sha256, operator_tools, source_bytes, artifacts, compiler_logs):
    """Verify the real release_compile_scope.py plan/proof and actual bytes.

    Source revisions here are the receipt's ORIGINAL explicit triple. Importing
    an older receipt requires a separate current-input equivalence binding;
    this function never relabels historical commits as current. source_bytes is
    keyed game:/content: and contains original Git blobs, or explicit
    {git_blob:pointer_bytes,content:resolved_bytes}. No filesystem fallback. All
    operator_tools/compiler SHA expectations come from the immutable operator
    authority, not fields copied out of the untrusted proof.
    """
    need(set(source_revisions) == {'game', 'content', 'operator'}, 'compiler_original_source_triple_required')
    for pin in source_revisions.values():
        revision(pin)
    plan = document(plan_raw, plan_sha256)
    proof = document(proof_raw, proof_sha256)
    dual = {key: source_revisions[key] for key in ('game', 'content')}
    need(plan.get('kind') == 'IMMUTABLE_ISOLATED_OFFICIAL_COMPILE_PLAN' and proof.get('kind') == 'ISOLATED_OFFICIAL_COMPILER_PROOF' and (proof.get('plan_sha256') == plan_sha256) and (plan.get('source_revisions') == proof.get('source_revisions') == dual), 'compiler_plan_proof_source_binding_mismatch')
    need(proof.get('compiler_sha256') == digest(compiler_sha256) and proof.get('scope_sha256') == plan.get('scope_sha256'), 'official_compiler_or_scope_binding_mismatch')
    digest(plan.get('scope_sha256'))
    operator = plan.get('operator_binding', {})
    need(operator == proof.get('operator_binding') and operator.get('revision') == source_revisions['operator'], 'compiler_operator_revision_mismatch')
    tools = operator.get('tools_lf_sha256')
    need(isinstance(tools, dict) and tools and (set(operator_tools) == set(tools)), 'exact_compiler_operator_tools_required')
    for name, pin in tools.items():
        path(name)
        need(sha(operator_tools[name].replace(b'\r\n', b'\n')) == digest(pin), 'compiler_operator_tool_bytes_changed')
    tool_pin = tools.get('tools/release_compile_scope.py')
    actual_tool = operator_tools.get('tools/release_compile_scope.py', b'')
    need(tool_pin and plan.get('tool_sha256') == proof.get('tool_sha256') == sha(actual_tool), 'compiler_executed_tool_sha_mismatch')
    need(proof.get('complete') is True and proof.get('sdk_calls') == proof.get('git_mutations') == proof.get('project_worktree_writes') == 0, 'incomplete_or_effectful_compiler_receipt')
    expected = _unique(plan.get('resources'), 'resource', 'unique_compile_plan_resources_required')
    results = _unique(proof.get('results'), 'resource', 'unique_compiler_results_required')
    need(expected and set(expected) == set(results) == set(artifacts), 'complete_compiler_artifact_set_required')
    outputs, used_sources, used_git_sources, used_logs = ({}, {}, {}, set())
    for name, row in expected.items():
        path(name)
        result = results[name]
        need(row.get('status') == 'READY_FOR_ISOLATED_OFFICIAL_COMPILE' and result.get('status') == 'OFFICIALLY_COMPILED_AND_SOURCE_BOUND' and (type(result.get('compiler_exit_code')) is int) and (result['compiler_exit_code'] == 0) and (result.get('inputs') == row.get('sources')) and (result.get('primary_source') == row.get('primary_source')) and (result.get('engine_references') == row.get('engine_references')), 'original_compiler_resource_result_mismatch')
        log_sha = digest(result.get('compiler_log_sha256'))
        need(log_sha in compiler_logs, 'original_compiler_log_missing')
        log = compiler_logs[log_sha]
        need(type(log) is bytes and len(log) <= MAX_DOCUMENT and (sha(log) == log_sha) and re.search(b'(?<![0-9])0 failed(?![0-9])', log), 'compiler_success_log_bytes_required')
        used_logs.add(log_sha)
        local = {}
        source_pins = _unique(row.get('sources'), 'path', 'unique_compiler_closure_inputs_required')
        need(row.get('primary_source') in source_pins, 'compiler_primary_input_missing')
        for source_name, pin in source_pins.items():
            path(source_name)
            key = 'content:' + source_name
            need(pin.get('repo') == 'content' and pin.get('mode') in ('100644', '100755') and (pin.get('source_revision') == source_revisions['content']), 'immutable_content_compiler_input_required')
            need(key in source_bytes, 'compiler_original_git_blob_or_explicit_lfs_binding_required')
            git_raw, raw, lfs = _resolved_git_bytes(source_bytes[key])
            actual = byte_fingerprint(raw)
            need(pin.get('lfs') is lfs and pin.get('git_blob') == byte_fingerprint(git_raw) and (pin.get('content') == actual) and (hashlib.sha1(b'blob ' + str(len(git_raw)).encode() + b'\x00' + git_raw).hexdigest() == revision(pin.get('oid'))), 'compiler_git_blob_identity_mismatch')
            if source_name.endswith(('.js', '.css', '.xml', '.vtex', '.svg')):
                normalized = raw.replace(b'\r\n', b'\n')
                need(b'\r' not in normalized, 'compiler_source_lone_cr_requires_review')
                payload = normalized.replace(b'\n', b'\r\n')
                normalization = 'GIT_IDENTITY' if payload == raw else 'IMMUTABLE_GIT_TEXT_TO_COMPILER_CRLF_ONLY'
            else:
                payload, normalization = (raw, 'BINARY_GIT_IDENTITY')
            need(pin.get('compiler_input') == byte_fingerprint(payload) and pin.get('normalization') == normalization and (plan.get('inputs', {}).get(source_name) == pin), 'compiler_checkout_or_global_input_binding_mismatch')
            author = pin.get('game_author')
            if source_name in {'particles/survival/heroes/keeper/' + name + '.vpcf' for name in ('keeper_of_the_light_base_attack', 'keeper_base_attack')}:
                need(isinstance(author, dict) and author.get('path') == 'art/effects/keeper_attack/source/' + source_name, 'compiler_keeper_particle_dual_author_required')
            cover_author = {'panorama/images/custom_game/loading/dawnward_citadel_background.png': 'art/ui/sources/custom_game/loading/dawnward_citadel_background.png', 'panorama/images/custom_game/loading/dawnward_citadel_background_png.vtex': 'art/ui/sources/custom_game/loading/dawnward_citadel_background_png.vtex'}.get(source_name)
            if cover_author is not None:
                need(isinstance(author, dict) and author.get('path') == cover_author, 'compiler_loading_cover_dual_author_required')
            if source_name.startswith('panorama/videos/') and source_name.endswith('.webm'):
                need(isinstance(author, dict) and author.get('path') == source_name, 'compiler_raw_movie_dual_author_required')
            if author is not None:
                author_name = path(author.get('path'))
                author_key = 'game:' + author_name
                need(author_key in source_bytes, 'compiler_dual_author_blob_missing')
                a_git, a_raw, a_lfs = _resolved_git_bytes(source_bytes[author_key])
                need(author_key in source_bytes and author.get('repo') == 'game' and (author.get('source_revision') == source_revisions['game']) and (author.get('lfs') is a_lfs) and (author.get('git_blob') == byte_fingerprint(a_git)) and (author.get('content') == byte_fingerprint(a_raw)) and (hashlib.sha1(b'blob ' + str(len(a_git)).encode() + b'\x00' + a_git).hexdigest() == author.get('oid')), 'compiler_dual_author_blob_mismatch')
                a = a_raw
                if source_name.endswith(('.js', '.css', '.xml', '.vtex', '.svg')):
                    a = a.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
                need(a == payload, 'compiler_game_content_authors_differ')
                used_sources[author_key] = sha(a_raw)
                used_git_sources[author_key] = sha(a_git)
            local[source_name] = payload
            used_sources[key] = sha(raw)
            used_git_sources[key] = sha(git_raw)
        runtime_raw = {key: byte_fingerprint(raw) for key, raw in local.items() if key.startswith('panorama/videos/') and key.endswith('.webm')}
        if runtime_raw or 'runtime_raw_dependencies' in result:
            need(result.get('runtime_raw_dependencies') == runtime_raw, 'compiler_raw_movie_runtime_binding_mismatch')
        artifact = artifacts[name]
        actual = byte_fingerprint(artifact)
        need(result.get('artifact') == actual, 'actual_compiler_artifact_hash_mismatch')
        texture = name.endswith('.vtex_c')
        blocks, metadata_bytes = _compiled_data(artifact, texture)
        if name.endswith('.vjs_c'):
            need(blocks[b'DATA'] == local[row['primary_source']] and result.get('compiled_js_DATA_equals_input') is True, 'compiled_js_data_not_actual_immutable_input')
        block_rows = [{'tag': tag.decode('ascii'), 'bytes': len(value), 'sha256': sha(value)} for tag, value in blocks.items()]
        need(result.get('blocks') == block_rows and result.get('rerl_bytes') == len(blocks.get(b'RERL', b'')) and (result.get('resource_metadata_bytes') == metadata_bytes) and (result.get('texture_external_payload_bytes') == (len(artifact) - metadata_bytes if texture else 0)) and (result.get('texture_external_payload_sha256') == (sha(artifact[metadata_bytes:]) if texture and len(artifact) > metadata_bytes else None)), 'compiler_native_block_or_external_texture_receipt_mismatch')
        outputs[name] = actual
    need(set(compiler_logs) == used_logs and set(plan.get('inputs', {})) == {key.split(':', 1)[1] for key in used_sources if key.startswith('content:')}, 'unrelated_compiler_logs_or_closure_inputs_refused')
    need(plan.get('counts') == {'READY_FOR_ISOLATED_OFFICIAL_COMPILE': len(expected)} and proof.get('counts') == {'OFFICIALLY_COMPILED_AND_SOURCE_BOUND': len(results)}, 'compiler_result_counts_mismatch')
    return {'kind': 'ORIGINAL_COMPILER_RECEIPT_AND_ARTIFACT_BYTES_VERIFIED_NOT_PACKAGE_AUTHORITY', 'source_revisions': source_revisions.copy(), 'plan_sha256': plan_sha256, 'proof_sha256': proof_sha256, 'compiler_sha256': compiler_sha256, 'source_sha256s': used_sources, 'source_git_sha256s': used_git_sources, 'outputs': outputs, 'publication_ready': False, 'remaining_checks': ['REEXECUTE_DEPENDENCY_CLOSURE_FROM_IMMUTABLE_GIT', 'AUTHENTICATE_PACKAGE_AND_NATIVE_ADMISSION']}

def verify_protection_receipt(*, production_raw, production_sha256, protection_raw, protection_sha256, policy_raw, policy_sha256, source_revisions, source_bytes, production_inputs, protected_outputs, operator_tools, dependency_files, lua_binaries):
    """Check original production.prepare/protect_runtime_lua evidence and bytes.

    No Lua, compiler, subprocess or receipt-supplied program is executed here.
    Original semantic probe flags are required AND bound to their entire exact
    output set; they do not replace rerunning the pinned probes/native gate.
    """
    need(set(source_revisions) == {'game', 'content', 'operator'}, 'production_explicit_source_triple_required')
    for value in source_revisions.values():
        revision(value)
    prep = document(production_raw, production_sha256)
    proof = document(protection_raw, protection_sha256)
    policy = document(policy_raw, policy_sha256)
    need(prep.get('kind') == 'COMPLETE0302_PRODUCTION_LUA_PREPARATION_NOT_RELEASE_AUTHORITY' and prep.get('source_revisions') == source_revisions and (prep.get('protection_verified') is True) and (prep.get('protection_report_sha256') == protection_sha256), 'original_production_protection_binding_required')
    need(prep.get('sdk_calls') == prep.get('git_mutations') == prep.get('installed_tree_writes') == 0, 'effectful_production_preparation_refused')
    digest(prep.get('baseline_manifest_sha256'))
    need(proof.get('kind') == 'offline_lua51_protection' and proof.get('status') == 'PASS_REQUIRES_NATIVE_SMOKE' and (proof.get('policy_sha256') == sha(canonical(policy)[:-1])) and (proof.get('source_modified') is False) and (proof.get('network_used_for_transform') is False) and (proof.get('workshop_upload_performed') is False), 'original_complete_offline_protection_proof_required')
    need(proof.get('generated_string_obfuscation', {}).get('enabled') is True and proof.get('generated_string_obfuscation', {}).get('private_rng') is True and (proof.get('generated_steps') == ['ConstantArray', 'EncryptStrings', 'NumbersToExpressions', 'WrapInFunction']) and (proof.get('steps') == policy.get('steps')), 'required_generated_string_protection_missing')
    dependency = policy.get('dependency', {})
    need(isinstance(dependency_files, dict) and len(dependency_files) == dependency.get('source_tree_files') and (len(dependency_files) <= 512) and ('LICENSE' in dependency_files) and ('cli.lua' in dependency_files), 'exact_pinned_prometheus_source_set_required')
    records, total = ([], 0)
    for name, raw in sorted(dependency_files.items(), key=lambda pair: tuple((p.lower() for p in PurePosixPath(pair[0]).parts))):
        path(name)
        need(name in ('LICENSE', 'cli.lua') or (name.startswith('src/') and name.endswith('.lua')), 'unreviewed_prometheus_dependency_file')
        value = byte_fingerprint(raw)
        total += len(raw)
        need(total <= 64 * 1024 * 1024, 'prometheus_dependency_budget_exceeded')
        records.append({'path': name, 'bytes': value['bytes'], 'sha256': value['sha256']})
    need(sha(canonical(records)[:-1]) == dependency.get('source_tree_sha256') and sha(dependency_files['LICENSE']) == dependency.get('license_sha256'), 'prometheus_source_tree_or_license_hash_mismatch')
    for reported in (prep.get('pinned_prometheus', {}), proof.get('dependency', {})):
        need(all((reported.get(key) == value for key, value in dependency.items())) and reported.get('verified_source_tree_sha256') == dependency['source_tree_sha256'], 'prometheus_original_identity_mismatch')
    tools = _unique(prep.get('executed_operator_inputs'), 'path', 'unique_production_operator_inputs_required')
    need(set(tools) == set(operator_tools) and {'tools/protect_runtime_lua.py', 'tools/complete_delivery_pack_2026111008_c0a4f5/production.py', 'tools/lua_protection_policy.json'} <= set(tools), 'exact_production_operator_tool_set_required')
    for name, row in tools.items():
        path(name)
        raw = operator_tools[name]
        need(row.get('revision') == source_revisions['operator'] and row.get('normalization') == 'CRLF_TO_LF' and (row.get('executed_lf_sha256') == sha(raw.replace(b'\r\n', b'\n'))) and (row.get('git_sha256') in (sha(raw), sha(raw.replace(b'\r\n', b'\n')))), 'production_operator_executed_bytes_mismatch')
    need(operator_tools['tools/lua_protection_policy.json'].replace(b'\r\n', b'\n') == policy_raw.replace(b'\r\n', b'\n'), 'production_policy_not_bound_to_operator')
    need(set(lua_binaries) == {'lua', 'luac'}, 'exact_lua_binaries_required')
    for name, raw in lua_binaries.items():
        need(prep.get('lua_binaries', {}).get(name, {}).get('sha256') == byte_fingerprint(raw)['sha256'], 'production_lua_binary_hash_mismatch')
    plain = _unique(prep.get('plain_inputs'), 'path', 'unique_original_plain_lua_inputs_required')
    reviews = _unique(prep.get('production_overrides'), 'path', 'unique_production_override_reviews_required')
    need(set(reviews) == {'addoninfo.txt', 'scripts/vscripts/addon_game_mode_client.lua', 'scripts/vscripts/config/commerce_payment_access.lua', 'scripts/vscripts/config/player_web_auth.lua', 'scripts/vscripts/config/release_profile.lua', 'scripts/vscripts/config/workshop_connection.lua', 'scripts/vscripts/core/test_access_policy.lua'}, 'exact_seven_production_override_reviews_required')
    probes = prep.get('behavior_probes', {})
    need(all((probes.get(key) is True for key in ('five_account_engine_io_simulation', 'four_configs_constant_policy_only', 'deleted_preview_dependency_absent', 'hosted_lobby_and_original_entry_engine_io_simulation'))) and probes.get('actual_steam_login') is False and (probes.get('native_acceptance') is False) and (probes.get('http_calls') == probes.get('sdk_calls') == 0), 'original_production_behavior_probes_required')
    need(set(production_inputs) == set(plain) | set(reviews) and set(source_bytes) == set(production_inputs), 'complete_original_and_production_input_sets_required')
    for name, row in plain.items():
        path(name)
        raw = source_bytes[name]
        need(row.get('source_revision') == source_revisions['game'] and row.get('source_sha256') == sha(raw) and (row.get('source_bytes') == len(raw)) and (row.get('git_oid') == hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\x00' + raw).hexdigest()), 'immutable_plain_protection_input_mismatch')
        if name not in reviews:
            need(production_inputs[name] == raw, 'unreviewed_plain_production_transform')
    for name, row in reviews.items():
        path(name)
        need(row.get('source_sha256') == sha(source_bytes[name]) and row.get('production_sha256') == sha(production_inputs[name]) and (row.get('production_bytes') == len(production_inputs[name])), 'production_override_actual_bytes_mismatch')
        digest(row.get('parent_sha256'))
    prefix, excluded = (policy.get('generated_prefix'), policy.get('generated_exclusions'))
    need(isinstance(prefix, str) and isinstance(excluded, dict) and isinstance(policy.get('business_modules'), list), 'known_protection_selection_policy_required')
    expected = {}
    for name in sorted(plain):
        if name.startswith(prefix) and PurePosixPath(name).name not in excluded:
            expected[name] = 'generated_table'
        elif name in policy['business_modules']:
            expected[name] = 'business'
    need(expected and set(policy['business_modules']) <= set(expected) and (not set(expected).intersection(policy.get('always_plaintext', ()))), 'complete_protection_policy_selection_required')
    selected = _unique(prep.get('protection_selected'), 'path', 'unique_selected_protection_inputs_required')
    rows = _unique(proof.get('files'), 'path', 'unique_protected_output_rows_required')
    bindings = _unique(prep.get('protected_bindings'), 'path', 'unique_protected_source_bindings_required')
    need(set(expected) == set(selected) == set(rows) == set(bindings) == set(protected_outputs) and proof.get('selected_files') == len(expected) and (proof.get('source_files') == len(plain)), 'complete_selected_protection_output_set_required')
    semantic = proof.get('semantic_verification', {})
    need(semantic.get('status') == 'PASS' and semantic.get('all_generated_values_exact') is True and (semantic.get('gameplay_rng_untouched_while_loading') is True) and (semantic.get('new_runtime_io_os_debug_dependency') is False) and (semantic.get('summary', {}).get('files') == len(expected)) and ({row.get('path') for row in semantic.get('files', [])} == set(expected)) and (len(semantic.get('files', [])) == len(expected)) and (semantic.get('business_probe_modules') == [name for name in sorted(expected) if expected[name] == 'business']) and (proof.get('syntax', {}).get('status') == 'PASS') and (proof.get('syntax', {}).get('all_lua_files') == len(plain)), 'complete_all_value_rng_and_syntax_probes_required')
    outputs = {}
    for name, kind in expected.items():
        row, binding = (rows[name], bindings[name])
        before = byte_fingerprint(production_inputs[name])
        after = byte_fingerprint(protected_outputs[name])
        need(selected[name].get('kind') == row.get('kind') == binding.get('kind') == kind and row.get('before') == before and (row.get('after') == after) and (before['sha256'] != after['sha256']) and (row.get('seed') == int(sha((name + before['sha256']).encode('ascii'))[:8], 16) % 2147483646 + 1) and (binding.get('source_revision') == source_revisions['game']) and (binding.get('source_sha256') == before['sha256']) and (binding.get('production_sha256') == after['sha256']) and (binding.get('production_bytes') == after['bytes']) and (binding.get('exact_values_and_rng_verified') is True), 'actual_protected_input_output_binding_mismatch')
        outputs[name] = after
    return {'kind': 'ORIGINAL_PROTECTION_RECEIPT_AND_FULL_SELECTED_BYTES_VERIFIED_NOT_PACKAGE_AUTHORITY', 'source_revisions': source_revisions.copy(), 'production_sha256': production_sha256, 'protection_sha256': protection_sha256, 'policy_sha256': policy_sha256, 'protected_outputs': outputs, 'production_overrides': {name: byte_fingerprint(production_inputs[name]) for name in reviews}, 'publication_ready': False, 'remaining_checks': ['REEXECUTE_SEVEN_PRODUCTION_OVERRIDE_RULES_AND_PINNED_BEHAVIOR_PROBES', 'AUTHENTICATE_PACKAGE_AND_NATIVE_ADMISSION']}

def verify_item_generator_receipt(*, proof_raw, proof_sha256, source_revisions, input_bytes, output_bytes, content_mirrors, operator_bytes, python_bytes):
    """Verify generator_binding.py's original exact replay receipt, not a claim wrapper."""
    proof = document(proof_raw, proof_sha256)
    need(set(source_revisions) == {'game', 'content', 'operator'}, 'generator_explicit_source_triple_required')
    for value in source_revisions.values():
        revision(value)
    need(proof.get('kind') == 'IMMUTABLE_ITEM_RESOURCE_GENERATOR_PROOF' and proof.get('source_revisions') == source_revisions and (type(proof.get('generator_exit_code')) is int) and (proof['generator_exit_code'] == 0) and (proof.get('immutable_rebuild_equals_target') is True) and (proof.get('sdk_calls') == proof.get('network_calls') == 0), 'original_immutable_generator_replay_required')

    def fact(value, raw, commit):
        need(isinstance(value, dict) and value.get('commit') == commit and (fingerprint(value) == byte_fingerprint(raw)) and (value.get('git_oid') == hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\x00' + raw).hexdigest()), 'generator_original_git_fact_mismatch')
    binding = proof.get('binding_tool', {})
    tool = path(binding.get('path'))
    generator = proof.get('generator', {})
    gen = path(generator.get('path'))
    need(set(operator_bytes) == {tool, gen} and tool == 'tools/complete_delivery_pack_2026111008_c0a4f5/generator_binding.py' and (gen == 'tools/build_item_resources.py') and (binding.get('operator_revision') == source_revisions['operator']) and (binding.get('exact_committed_tool') is True) and (binding.get('diagnostic_only') is False), 'committed_generator_binding_tool_required')
    fact(binding.get('operator_blob'), operator_bytes[tool], source_revisions['operator'])
    fact(generator, operator_bytes[gen], source_revisions['operator'])
    need(binding.get('loaded_lf_sha256') == sha(operator_bytes[tool].replace(b'\r\n', b'\n')), 'generator_loaded_operator_changed')
    tools = proof.get('executed_operator_inputs', {})
    need(set(tools) == {gen}, 'exact_generator_operator_input_required')
    entry = tools[gen]
    need(entry.get('revision') == source_revisions['operator'] and entry.get('normalization') == 'IDENTITY_EXACT_GIT_BYTES' and (entry.get('git_sha256') == entry.get('executed_sha256') == sha(operator_bytes[gen])) and (entry.get('executed_lf_sha256') == sha(operator_bytes[gen].replace(b'\r\n', b'\n'))), 'generator_operator_execution_binding_mismatch')
    inputs, outputs, mirrors = (proof.get('inputs', {}), proof.get('outputs', {}), proof.get('content_mirrors', {}))
    need(set(inputs) == set(input_bytes) and len(inputs) == 4 and (set(outputs) == set(output_bytes)) and (len(outputs) == 6) and (set(mirrors) == set(content_mirrors)) and (len(mirrors) == 5), 'exact_generator_input_output_and_mirror_sets_required')
    need(proof.get('runtime_files_modified') is False and proof.get('protected') is False and (proof.get('compiled') is False), 'generator_cannot_claim_protection_or_compilation')
    for key, value in inputs.items():
        source_id(key)
        need(key.startswith('game:'), 'generator_input_repository_mismatch')
        fact(value, input_bytes[key], source_revisions['game'])
    normalizations = proof.get('input_normalizations', {})
    need(set(normalizations) == {'data/ui/item_resources.json', 'data/presentation/approved_names_20261030.json'}, 'only_two_explicit_json_normalizations_allowed')
    for name, value in normalizations.items():
        raw = input_bytes['game:' + name]
        need(b'\r' not in raw and value.get('git_sha256') == sha(raw), 'generator_json_original_bytes_mismatch')
        mode = value.get('normalization')
        need(mode in ('IDENTITY_EXACT_GIT_BYTES', 'LF_TO_CRLF'), 'unknown_generator_json_normalization')
        transformed = raw if mode == 'IDENTITY_EXACT_GIT_BYTES' else raw.replace(b'\n', b'\r\n')
        need(value.get('executed') == byte_fingerprint(transformed), 'generator_json_execution_bytes_mismatch')
    for name, value in outputs.items():
        path(name)
        fact(value, output_bytes[name], source_revisions['game'])
        need(value.get('repo') == 'game' and value.get('path') == name and (value.get('inputs') == sorted(inputs)) and (value.get('generated_exact_git_bytes') is True), 'generator_output_input_binding_mismatch')
        need(value.get('kind') == ('executable_resolver_not_protected' if name == 'scripts/vscripts/config/generated/item_resources.lua' else 'authored_js_requires_official_compile'), 'generator_output_semantics_mismatch')
    for name, value in mirrors.items():
        path(name)
        fact(value, content_mirrors[name], source_revisions['content'])
        author = 'panorama/src/' + name[len('panorama/'):]
        normalized = content_mirrors[name].replace(b'\r\n', b'\n')
        need(name.startswith('panorama/') and author in outputs and (b'\r' not in normalized) and (value.get('normalization') == 'CRLF_TO_LF_ONLY') and (value.get('normalized_sha256') == sha(normalized)) and (normalized == output_bytes[author]), 'generator_actual_content_mirror_mismatch')
    execution = proof.get('execution', {})
    need(execution.get('python') == byte_fingerprint(python_bytes) and execution.get('isolated_python') is True and (execution.get('only_reviewed_inputs_exported') is True) and (execution.get('outputs_initially_absent_except_two_adapters') is True), 'isolated_generator_execution_and_binary_binding_required')
    commands = execution.get('commands', [])
    need(isinstance(commands, list) and len(commands) == 2, 'generate_then_check_original_receipts_required')
    for command, mode, status in zip(commands, ('generate', 'check'), ('GENERATED', 'CHECK_PASS')):
        digest(command.get('stdout_sha256'))
        result = command.get('result', {})
        need(command.get('mode') == mode and command.get('exit_code') == 0 and (result.get('status') == status) and (set(result.get('outputs', [])) == set(outputs)) and (len(result['outputs']) == len(outputs)), 'generator_command_result_mismatch')
    need(all((proof.get('checks', {}).get(key) is True for key in ('six_outputs_exact', 'five_content_mirrors_equal', 'generate_then_check', 'no_unreviewed_file_writes'))), 'complete_original_generator_checks_required')
    return {'kind': 'ORIGINAL_ITEM_GENERATOR_REPLAY_AND_BYTES_VERIFIED_NOT_PACKAGE_AUTHORITY', 'source_revisions': source_revisions.copy(), 'proof_sha256': proof_sha256, 'outputs': {name: byte_fingerprint(raw) for name, raw in output_bytes.items()}, 'publication_ready': False, 'remaining_checks': ['BIND_AUTHOR_JS_TO_ACTUAL_OFFICIAL_COMPILED_OUTPUTS', 'AUTHENTICATE_PACKAGE_AND_NATIVE_ADMISSION']}

def audit_complete(*, parent_raw, parent_sha256, inventory_raw, inventory_sha256, scope_raw, scope_sha256, facts_raw, facts_sha256, receipts):
    """Validate one exact decision for every pending/historical source.

    scope: source_revisions{game,content,operator}, inventory_sha256,
      parent_manifest_sha256, source_facts_sha256, decisions[], bindings[].
    A publish decision names a binding whose exact inputs include that source.
    A removal names an actual parent resource and a deleted source. Non-runtime
    decisions are allowed only for unmapped live sources, with a pinned exact
    path review and reference-scan digest. No prefix exclusion or deferral exists.
    Binding receipts are pinned JSON containing per-resource typed bindings;
    their authentic compiler/protection semantics remain an authority blocker.
    """
    parent = document(parent_raw, parent_sha256)
    old = parent_rows(parent)
    inventory = document(inventory_raw, inventory_sha256)
    scope = document(scope_raw, scope_sha256)
    facts_doc = document(facts_raw, facts_sha256)
    pins = scope.get('source_revisions', {})
    need(set(pins) == {'game', 'content', 'operator'}, 'explicit_dual_source_and_operator_commits_required')
    for pin in pins.values():
        revision(pin)
    need(scope.get('parent_manifest_sha256') == parent_sha256 and scope.get('inventory_sha256') == inventory_sha256 and (scope.get('source_facts_sha256') == facts_sha256), 'scope_document_binding_mismatch')
    need(inventory.get('kind') == 'READ_ONLY_ALL_PENDING_WORKSHOP_INVENTORY', 'fresh_full_pending_inventory_required')
    need(inventory.get('target_commits') == {key: pins[key] for key in ('game', 'content')}, 'inventory_source_commit_mismatch')
    need(inventory.get('recorded_parent_manifest_sha256') == parent_sha256 and inventory.get('recorded_parent_content_sha256') == parent['content_sha256'], 'inventory_authenticated_parent_mismatch')
    need(isinstance(inventory.get('dirty'), list), 'explicit_dirty_inventory_required')
    need(not any((row.get('runtime_related') is not False for row in inventory['dirty'])), 'dirty_or_unclassified_runtime_source')
    need(facts_doc.get('source_revisions') == pins and isinstance(facts_doc.get('sources'), dict), 'source_facts_commit_binding_mismatch')
    facts = facts_doc['sources']
    for key, fact in facts.items():
        source_id(key)
        role = key.split(':', 1)[0]
        need(fact.get('commit') == pins[role], 'source_fact_commit_mismatch')
        revision(fact.get('git_oid'))
        fingerprint(fact)
        need(fact.get('lfs') is not True or fact.get('lfs_content_verified') is True, 'unresolved_lfs_pointer_cannot_be_runtime')
    rows = {}
    need(isinstance(inventory.get('rows'), list), 'source_inventory_rows_required')
    for row in inventory['rows']:
        source = row.get('source', {})
        key = source_id(str(source.get('repo')) + ':' + str(source.get('path')))
        need(key not in rows, 'duplicate_inventory_source')
        need(isinstance(row.get('status'), str) and isinstance(row.get('history'), list), 'explicit_inventory_status_and_history_required')
        need(row['status'] in STATUSES, 'unknown_or_unverified_inventory_status')
        if source.get('head_oid') is not None:
            need(row['status'] not in REMOVED, 'live_source_marked_removed')
            need(key in facts and facts[key]['git_oid'] == source['head_oid'], 'immutable_source_fact_missing_or_changed:' + key)
        else:
            need(row['status'] in REMOVED and key not in facts, 'deleted_source_status_or_current_facts_contradict')
        rows[key] = row
    required = {key for key, row in rows.items() if row['status'] != 'PARENT_BYTES_MATCH'}
    need(isinstance(scope.get('decisions'), list) and isinstance(scope.get('bindings'), list), 'explicit_complete_decisions_and_bindings_required')
    decisions = {}
    for choice in scope['decisions']:
        key = source_id(choice.get('source_id'))
        need(key in required and key not in decisions, 'unknown_or_duplicate_source_decision')
        need(choice.get('action') in ('publish', 'remove', 'non_runtime'), 'no_deferred_or_unknown_source_disposition')
        decisions[key] = choice
    need(set(decisions) == required, 'complete_pending_source_coverage_required:' + ','.join(sorted(required - set(decisions))))
    need(isinstance(receipts, dict), 'pinned_receipt_bytes_required')
    decoded = {}

    def receipt(pin):
        digest(pin)
        if pin not in decoded:
            need(pin in receipts, 'binding_or_review_receipt_missing')
            decoded[pin] = document(receipts[pin], pin)
        return decoded[pin]
    bindings, input_index, cases = ({}, {}, set())
    for binding in scope['bindings']:
        name = path(binding.get('resource'))
        kind = binding.get('kind')
        need(name not in bindings and name.casefold() not in cases and (kind in KINDS), 'unique_typed_runtime_resource_binding_required')
        need(name == 'addoninfo.txt' or name.split('/', 1)[0] in RUNTIME_ROOTS, 'non_runtime_or_unknown_output_path')
        need(not name.casefold().startswith('panorama/src/') and (not {'.git', 'output', 'tests', '__pycache__', 'node_modules'}.intersection((p.casefold() for p in PurePosixPath(name).parts))), 'author_test_or_cache_files_cannot_be_runtime_outputs')
        need(not name.lower().endswith(('.pem', '.key', '.pfx', '.p12', '.env', '.log', '.tmp', '.bak', '.zip', '.7z', '.pyc', '.mdmp', '.dmp')), 'private_or_temporary_output_forbidden')
        if name.endswith('.vpk'):
            need(name.startswith('maps/') and (not re.search('(?:_dir|_[0-9]{3})\\.vpk$', name, re.I)), 'bare_package_volume_cannot_be_runtime_resource')
        need(not name.endswith(('_c', '.vpk')) or kind == 'compiled', 'compiled_resource_requires_compiler_receipt')
        output = fingerprint(binding.get('output'))
        need(isinstance(binding.get('inputs'), list) and binding['inputs'], 'nonempty_exact_resource_inputs_required')
        inputs = {}
        for item in binding['inputs']:
            key = source_id(item.get('source_id'))
            need(key not in inputs and key in facts, 'duplicate_or_unverified_binding_input')
            need(item.get('sha256') == facts[key]['sha256'] and item.get('git_oid') == facts[key]['git_oid'], 'resource_source_hash_or_oid_mismatch')
            inputs[key] = item['sha256']
            input_index.setdefault(key, set()).add(name)
        if kind == 'identity':
            expected_inputs = {'game:' + name}
            mirror = 'content:' + name
            if name.startswith('panorama/videos/') and name.endswith('.webm'):
                need(mirror in facts, 'raw_video_content_source_required:' + name)
                expected_inputs.add(mirror)
                need(output == fingerprint(facts[mirror]), 'raw_video_mirror_is_not_exact_current_git_bytes')
            need(set(inputs) == expected_inputs and output == fingerprint(facts['game:' + name]), 'identity_output_is_not_exact_current_git_bytes')
            need(binding.get('receipt_sha256') is None, 'identity_must_not_hide_a_transform')
        else:
            proof = receipt(binding.get('receipt_sha256'))
            need(proof.get('kind') == 'COMPLETE_RUNTIME_BINDING_RECEIPT' and proof.get('source_revisions') == pins, 'binding_receipt_source_or_schema_mismatch')
            entry = proof.get('bindings', {}).get(name, {})
            need(entry.get('kind') == kind and entry.get('inputs') == inputs and (entry.get('output') == output), 'typed_binding_receipt_output_or_inputs_mismatch')
            if kind == 'localization_projection':
                localization_projection.validate_metadata(name, entry.get('localization_projection'), inputs, output, {key: fingerprint(facts[key]) for key in inputs})
        bindings[name] = {'resource': name, 'kind': kind, 'inputs': inputs, 'output': output, 'receipt_sha256': binding.get('receipt_sha256')}
        cases.add(name.casefold())
    removals, non_runtime = (set(), [])
    for key, choice in decisions.items():
        row = rows[key]
        action = choice['action']
        if action == 'publish':
            name = path(choice.get('resource'))
            need(name in bindings and name in input_index.get(key, ()), 'published_source_not_bound_to_selected_output:' + key)
            need(row.get('resource') in (None, name), 'inventory_resource_mapping_changed_without_review')
            if row['status'] == 'PRODUCTION_TRANSFORM_REQUIRED':
                need(bindings[name]['kind'] in ('protected', 'production_override'), 'production_source_requires_typed_transform_receipt')
            elif row['status'] == 'GENERATED_BINDING_REQUIRED':
                need(bindings[name]['kind'] in ('generated', 'protected'), 'generated_source_requires_generator_or_protection_receipt')
            elif row['status'] in ('UNCOMPILED_BINDING_REQUIRED', 'UNBOUND_COMPILED_ARTIFACT'):
                need(bindings[name]['kind'] == 'compiled', 'compiled_source_requires_typed_compiler_receipt')
        elif action == 'remove':
            name = path(choice.get('resource'))
            need(row['source'].get('head_oid') is None and row.get('resource') == name and (name in old) and (name not in bindings) and (key not in input_index), 'runtime_removal_is_not_a_deleted_authenticated_resource')
            removals.add(name)
        else:
            need(row.get('resource') is None and row['source'].get('head_oid') is not None and (key not in input_index), 'runtime_or_deleted_source_cannot_be_excluded')
            proof = receipt(choice.get('receipt_sha256'))
            need(proof.get('kind') == 'NON_RUNTIME_EXACT_PATH_REVIEW' and proof.get('source_revisions') == pins and (proof.get('source_id') == key) and (proof.get('source_sha256') == facts[key]['sha256']) and isinstance(proof.get('reason'), str) and proof['reason'].strip(), 'exact_non_runtime_review_required')
            digest(proof.get('reference_scan_sha256'))
            non_runtime.append(key)
    need(all((any((key in required and decisions[key]['action'] == 'publish' and (decisions[key].get('resource') == name) for key in binding['inputs'])) for name, binding in bindings.items())), 'unrelated_runtime_payload_cannot_be_sneaked_into_scope')
    result = {'schema': 1, 'kind': 'COMPLETE_DECLARED_SOURCE_COVERAGE_NOT_BUILD_AUTHORITY', 'source_revisions': pins, 'parent_manifest_sha256': parent_sha256, 'inventory_sha256': inventory_sha256, 'scope_sha256': scope_sha256, 'source_facts_sha256': facts_sha256, 'pending_sources': sorted(required), 'covered_sources': sorted(decisions), 'historical_sources': sorted((key for key in required if rows[key]['history'])), 'resource_bindings': [bindings[key] for key in sorted(bindings)], 'removed_resources': sorted(removals), 'non_runtime_reviews': sorted(non_runtime), 'receipt_sha256s': sorted(decoded), 'coverage_complete': True, 'deferred_sources': [], 'unknown_sources': [], 'counts': {'sources': len(required), 'historical_sources': sum((bool(rows[key]['history']) for key in required)), 'runtime_bindings': len(bindings), 'runtime_removals': len(removals), 'non_runtime_reviews': len(non_runtime)}, 'build_ready': False, 'signing_ready': False, 'publication_ready': False, 'remaining_authority_checks': ['REEXECUTE_FULL_INVENTORY_AGAINST_AUTHENTICATED_PARENT_AND_EXACT_DUAL_GIT_TREES', 'VERIFY_ORIGINAL_COMPILER_GENERATOR_PROTECTION_AND_NON_RUNTIME_REVIEW_RECEIPT_SEMANTICS', 'VERIFY_IMMUTABLE_ARTIFACT_BYTES_AND_COMPLETE_SIGNED_PACKAGE_NATIVE_ADMISSION']}
    return {**result, 'ledger_sha256': sha(canonical(result))}
